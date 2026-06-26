# Phase 14: Direct-Connect SG + xrdp/VNC Removal + CIS 2.2.1 Revert + Operator Surface — Research

**Researched:** 2026-06-19
**Domain:** AWS IaC cleanup — destructive removal of the xrdp/VNC remote-desktop stack, CIS 2.2.1 re-enablement, terraform SG flip (TCP+UDP :8443 direct connect, drop :3389), operator-surface relabel. Companion to the Phase 13 `dcv` role (already complete).
**Confidence:** HIGH on the removal inventory + SG + operator surface (all read at file:line); **MEDIUM-HIGH on the CIS 2.2.1 revert** (the RPM dependency cannot be proven independent at research time — no live box; gated to Phase-15 UAT with a code-in-now / assert mechanism).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DCV-06 | SG exposes `:8443` **TCP and UDP** gated on `var.allowed_web_cidrs` (UDP for QUIC, direct connect); drop xrdp `:3389`; `:22`/IMDSv2/egress unchanged | §4 SG edit — exact HCL for two ingress blocks mirroring the `:8080` block + the `:3389` deletion at `terraform/main.tf:119-125` |
| DCV-07 | Remove the `xrdp` role, its playbook wiring + layer toggle, the post-hardening Xorg `post_tasks` guard, `test-xrdp.yml`, the vendored `xorg.conf` | §2 removal inventory (X1–X8) with file:line + shared-with-DCV risk per artifact |
| DCV-08 | Revert the CIS 2.2.1 X-server exception — DCV virtual sessions use `Xdcv` not system Xorg — confirmed safe at the live UAT | §1 VERDICT + safe mechanism (code-revert-now + post-hardening Xdcv guard; UAT confirms) |
| DCV-09 | All VNC/noVNC/xrdp remnants removed across ansible/terraform/run/scripts/docs — repo-wide completeness check | §6 completeness grep (allowlisting the kept `vnc-password` identifiers) |
| DCV-10 | `secrets-show` + operator docs target **direct DCV `:8443` connect** (browser/native, within the CIDR) — no `./run` port-forward step for DCV; keep the `ec2-user` SSM credential, relabel RDP/noVNC→DCV | §5 operator-surface inventory (O1–O9) with file:line |
</phase_requirements>

## Summary

Phase 14 is the **irreversible-cleanup** half of the v4.0 DCV migration. Phase 13 already shipped a complete `dcv` role (install/config/virtual-session/cert/SELinux/bake-assert, DCV-01..05 verified). This phase tears out the xrdp stopgap, re-enables the one accepted CIS deviation, flips the security group from RDP `:3389` to **direct-connect DCV `:8443` (TCP + UDP)**, fixes the carried CRITICAL-1 secrets-bootstrap unit, and relabels the entire operator surface. The work is almost entirely **edit/delete against files read at file:line** — low novelty, high precision. The Phase-12 RDP-removal pattern (inventory table → surgical edits → repo-wide completeness grep) is the template; this milestone's `ARCHITECTURE.md` already drafted the inventory, which this research validates and corrects against the *current* tree.

The single load-bearing decision is **DCV-08: is reverting `amzn2023cis_rule_2_2_1: false` safe?** CIS 2.2.1 removes `xorg-x11-server-common` (which cascade-removes `xorg-x11-server-Xorg`). DCV uses a **virtual** session — its own bundled `Xdcv` server (`/usr/bin/Xdcv` from `nice-xdcv`), *not* `/usr/libexec/Xorg`. AWS docs confirm virtual sessions start Xdcv. **However**, the Phase-13 virtual-session init script runs `gnome-session` with `XDG_SESSION_TYPE=x11` *into* Xdcv, and the `desktop` role installs `@Desktop` which pulls in system Xorg + `xorg-x11-server-common`. The honest position: I **cannot prove independently** (no live box; `repoquery --requires nice-xdcv` / `rpm -qR` is the only authoritative test) that nothing DCV uses depends on `xorg-x11-server-common`. AWS's own Linux prereqs *list* `xorg-x11-server-Xorg` as recommended.

**Primary recommendation:** Revert the CIS 2.2.1 override **in code now** (DCV-08 is a code change this phase owns) BUT keep a **post-hardening assert** — repurpose the existing `playbook.yml:80-96` guard to stat **`/usr/bin/Xdcv`** (the DCV X server) instead of `/usr/libexec/Xorg`, gated on the `dcv`+`desktop` layers. This mirrors the v3.2 post-hardening Xorg-guard pattern: it makes a *wrong* revert a LOUD bake failure rather than a silent broken-desktop. Final confirmation that the Xdcv virtual session actually renders GNOME under enforcing belongs to the **Phase-15 live UAT (DCV-11)** — which the milestone already gates on. Do **not** delete the post-hardening guard outright (the ARCHITECTURE.md draft said "delete"); **retarget** it to Xdcv.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Network perimeter (`:8443` TCP+UDP ingress, drop `:3389`) | Terraform SG (`aws_security_group.devbox`) | — | The SG is the access boundary for direct connect; no SSM tunnel for DCV per v4.0 posture |
| X-server purge policy (CIS 2.2.1) | Ansible `hardening` role defaults | Ansible `playbook.yml` post_tasks (assert end-state) | Hardening runs last; the override + post-hardening assert are the only two places this is governed |
| xrdp install/config/service removal | Ansible `xrdp` role + `playbook.yml` wiring | `layer_config.yml` toggle | Self-contained role; nothing else imports it |
| Boot credential application + service ordering | Ansible `secrets` role (bootstrap unit + script) | systemd `Before=`/restart-loop | The unit orders/restarts the desktop service; must name `dcvserver`, not xrdp |
| Operator connect UX (labels, docs) | `run` + `scripts/devbox-*.sh` + `CLAUDE.md` | terraform `outputs.tf` descriptions | Human-facing surface; relabel RDP/noVNC→DCV, direct `:8443` |

---

## §1 — CIS 2.2.1 REVERT SAFETY: VERDICT + SAFE MECHANISM (gates DCV-08)

### The dependency chain (established facts)

- **CIS rule 2.2.1** (`amzn2023cis_rule_2_2_1`, default `true` in the vendored `AMAZON2023-CIS` role) **removes `xorg-x11-server-common`**. `-common` is a dependency of `xorg-x11-server-Xorg`, so removing `-common` cascade-removes the system Xorg. `[CITED: ansible/roles/hardening/defaults/main.yml:28-37]` `[CITED: playbook.yml:90-94]`
- The current override `amzn2023cis_rule_2_2_1: false` exists **solely** because xrdp's xorgxrdp backend exec'd the **system** `/usr/libexec/Xorg` (`sesman.ini param=/usr/libexec/Xorg`). `[CITED: ansible/roles/hardening/defaults/main.yml:28-37]`
- DCV's **virtual** session starts **`Xdcv`** — DCV's own bundled X server, shipped by `nice-xdcv` at `/usr/bin/Xdcv` — NOT `/usr/libexec/Xorg`. `[CITED: AWS docs — "With virtual sessions, Amazon DCV starts an X server instance, Xdcv"; ARCHITECTURE.md:244]` The Phase-13 bake assert already stats `/usr/bin/Xdcv`. `[CITED: ansible/roles/dcv/tasks/main.yml:268,310,322]`
- The Phase-13 virtual-session init script (`/etc/dcv/dcv-gnome-session.sh`) forces `XDG_SESSION_TYPE=x11` + software render (llvmpipe) + `gnome-session`, rendering GNOME **into Xdcv** (not system Xorg). `[CITED: ansible/roles/dcv/tasks/main.yml:110-125]`
- The `desktop` role installs `@Desktop` (the GNOME group), which on AL2023 pulls in `xorg-x11-server-Xorg` (+ its dep `xorg-x11-server-common`) as part of the group. `[CITED: ansible/roles/desktop/tasks/main.yml:4-7]`

### The unresolved question

Does **anything DCV needs** depend on `xorg-x11-server-common`? Two paths to worry about:
1. **`nice-xdcv` / `Xdcv` itself** — does its RPM `Requires:` pull `xorg-x11-server-common`? Xdcv is a self-contained X server fork; it should bundle its own server bits, but it commonly depends on the shared X data package (`/usr/share/X11`, `xkb`, `Xwrapper.config`) which lives in `-common`. **Cannot confirm without `repoquery --requires nice-xdcv` / `rpm -qR nice-xdcv` on a baked box.** `[ASSUMED]`
2. **GNOME-on-Xorg in the virtual session** — `gnome-session`/Mutter in X11 mode and `mesa-dri-drivers` (llvmpipe) may transitively want `-common`'s shared X11 files even when rendering into Xdcv rather than system Xorg. **Cannot confirm independently.** `[ASSUMED]`

AWS's Linux prerequisites **list `xorg-x11-server-Xorg` as a recommended package** for DCV servers. `[CITED: docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html]` That is a strong signal that removing the system X server family (which 2.2.1 does) is risky even for virtual sessions.

### VERDICT

**Revert in code this phase (DCV-08 owns the code change), but DO NOT trust the revert blind — keep a retargeted post-hardening assert, and gate final confirmation to the Phase-15 live UAT.**

Concretely:
- **EDIT** `ansible/roles/hardening/defaults/main.yml:28-37` — delete the `amzn2023cis_rule_2_2_1: false` line + its desktop-exception comment block, so the rule returns to its CIS default (`true`, removes `xorg-x11-server-common`). This re-closes the single accepted Level-2 deviation. `[CITED: file:line]`
- **DO NOT** delete the post-hardening guard at `playbook.yml:80-96` (the ARCHITECTURE.md draft X3 said "DELETE" — that is **wrong/over-removal**). Instead **RETARGET** it:
  - stat **`/usr/bin/Xdcv`** (was `/usr/libexec/Xorg`)
  - gate on `(layers.dcv | default(false)) and (layers.desktop | default(false))` (was `layers.xrdp ...`)
  - reword the `fail_msg` to: *"`/usr/bin/Xdcv` was DELETED after the dcv role configured it — the DCV X server is gone post-hardening. Most likely cause: CIS 2.2.1 (now re-enabled) removed `xorg-x11-server-common`, and Xdcv or the GNOME-on-Xorg virtual session depended on it. If this fires, re-add `amzn2023cis_rule_2_2_1: false` to hardening/defaults and confirm `rpm -qR nice-xdcv` at the Phase-15 UAT."*
- This mechanism is **strictly safer than either extreme**: if the revert IS safe, the bake stays green and the deviation is closed (security win); if the revert breaks Xdcv, the bake fails LOUDLY with the exact remediation, not a silent blank desktop discovered at the UAT.
- **Phase-15 UAT (DCV-11)** is the final gate: confirm the Xdcv virtual session renders GNOME under SELinux enforcing with 2.2.1 re-enabled. If it fails, the documented fallback is to re-add the override (keep `xorg-x11-server-common`).

> **Mandatory bake-verification step for the planner:** the *real* independent proof is one command on a baked box: `repoquery --requires nice-xdcv | grep -i xorg-x11-server-common` (and `rpm -qR nice-xdcv`). The plan should include this as a Phase-15 UAT assertion. At bake time, the retargeted `/usr/bin/Xdcv` stat IS the proof-by-survival.

**Confidence: MEDIUM-HIGH that the revert is correct.** The architecture (virtual session = Xdcv, not system Xorg) supports it; the residual risk is a transitive `-common` dependency that only `repoquery`/live-UAT can rule out. The retarget-the-guard mechanism converts that residual risk from "silent breakage" to "loud, self-documenting bake failure," which is the correct posture given we cannot prove it independent.

---

## §2 — COMPLETE xrdp REMOVAL INVENTORY (DCV-07 / DCV-09)

> Legend — **DELETE** (whole file/dir/block), **EDIT** (surgical), **KEEP** (listed to prove considered / shared with DCV).
> Verified against the **current** tree (the ARCHITECTURE.md draft had stale line numbers for the post_tasks guard and the wrong action for X3).

### Ansible — xrdp role + wiring

| # | Artifact | Path : line | Action | Shared-with-DCV risk |
|---|----------|-------------|--------|----------------------|
| X1 | Entire `xrdp` role (12 files) | `ansible/roles/xrdp/` — `defaults/main.yml`, `tasks/main.yml`, `handlers/main.yml`, `templates/{sesman.ini.j2,startwm.sh.j2,xrdp.ini.j2}`, `files/{45-allow-colord.pkla,45-allow-colord.rules,xorg.conf,xrdp-sesman.pam,xrdp-sesman.service,xrdp.service}` | **DELETE dir** | None — self-contained, nothing imports it. **NOTE:** the `dcv` role ships its OWN colord `.rules` + GNOME launcher; do NOT "migrate" xrdp's `45-allow-colord.rules` (verify the dcv role already has its equivalent before deleting — Phase-13 review mentioned colord). The vendored `xorg.conf` (XDummy) is xrdp-only; DCV virtual uses Xdcv, no XDummy. |
| X2 | `- role: xrdp` block + `when:` + comment | `ansible/playbook.yml:59-63` | **DELETE** | The `dcv` role (already at `playbook.yml:65-69`) replaces this slot. Removing the xrdp block does NOT disturb the dcv block or hardening-last. |
| X3 | post_tasks Xorg guard (stat + assert, 2 tasks) | `ansible/playbook.yml:80-96` | **EDIT → RETARGET to `/usr/bin/Xdcv`** (NOT delete — see §1) | This is the DCV-08 safety net. Retarget stat path + `when:` gate (xrdp→dcv) + `fail_msg`. **Over-removal risk if deleted.** |
| X4 | `xrdp: true` layer toggle + comment | `ansible/layer_config.yml:21-22` | **DELETE the two lines** | `dcv: true` already present at `layer_config.yml:23-24` — no add needed, just drop xrdp. |
| X5 | CIS 2.2.1 override + comment block | `ansible/roles/hardening/defaults/main.yml:28-37` | **DELETE (revert exception)** | See §1 VERDICT. The post-hardening Xdcv guard (X3) backstops it. |
| X6 | `test-xrdp.yml` top-level test playbook | `ansible/test-xrdp.yml` (whole file) | **DELETE** | xrdp-specific harness; no DCV equivalent referenced elsewhere. (Phase 13 did not ship a `test-dcv.yml`; the bake-assert lives in the role.) |
| X7 | secrets bootstrap **restart loop** names xrdp | `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:67` | **EDIT** `for svc in code-server.service xrdp.service xrdp-sesman.service` → `code-server.service dcvserver.service` (optionally `dcv-virtual-session.service`) | See §3. Dead unit names + DCV session won't restart on rotation otherwise. KEEP the `chpasswd` logic + the `vnc-password` SSM fetch. |
| X8 | secrets bootstrap **service `Before=`** + Description | `devbox-secrets-bootstrap.service.j2:2,5` | **EDIT** `Before=code-server.service xrdp.service xrdp-sesman.service` → `Before=code-server.service dcvserver.service`; Description "...code-server / RDP" → "...code-server / DCV" | See §3 / CRITICAL-1. Cosmetic-but-correct ordering. |
| X9 | secrets bootstrap **comment** at sh.j2:52-53 ("ec2-user RDP/PAM login... xrdp authenticates... /etc/pam.d/xrdp-sesman") + sh.j2:65 ("RDP units... desktop/xrdp layers") | `devbox-secrets-bootstrap.sh.j2:52-53,65` | **EDIT comments** → DCV / `authentication=system` PAM | KEEP all logic + the `vnc-password` param path. Reword "RDP/xrdp" → "DCV". |
| X10 | desktop role comments "GNOME-over-RDP" / "RDP" | `ansible/roles/desktop/tasks/main.yml:13-15,23` | **EDIT comments** (cosmetic) | The GNOME install + screensaver-disable all **KEEP** — DCV needs `@Desktop`/`gnome-session`/`mesa-dri-drivers`/fonts. Do NOT remove any desktop install task. |

> **VNC / noVNC remnants:** v3.2 Phase 12 already removed the VNC/noVNC functional stack (`tigervnc-server`, `vncserver.service`, `novnc.service`, `/etc/pam.d/vnc`, `xstartup`, `novnc-plain-username-fix.yml`, the `:6080` SG rule). This phase must only **prove** nothing VNC-functional survives (the §6 grep). The **intentional** residue to KEEP: the `vnc-password` SSM param name (renaming orphans it across bootstrap/outputs/secrets-show — Anti-Pattern; the IAM ARN is a wildcard but the path is hard-coded in 4+ places) and the `!= "changeme"` secrets asserts.

### Shared-with-DCV "do not over-remove" list (explicit)

- **`/devbox/<user>/vnc-password` SSM param** — KEEP (DCV `authentication=system` reads this `ec2-user` PAM password). Only relabel human text.
- **`secrets` role generate/publish/bootstrap chain** — KEEP all logic; edit only the xrdp unit names + comments (X7/X8/X9).
- **`desktop` role (`@Desktop`, `gnome-session`, `mesa-dri-drivers`, dejavu fonts, screensaver-disable)** — KEEP entirely; DCV's GNOME-on-Xorg virtual session needs every bit (X10 edits comments only).
- **colord polkit `.rules`** — verify the `dcv` role ships its own before deleting xrdp's; a remote GNOME session hangs on the colord polkit prompt without it (Pitfall 8). If the dcv role lacks it, that is a Phase-13 gap to flag, not a Phase-14 "keep xrdp's file" — but confirm before deleting `ansible/roles/xrdp/files/45-allow-colord.rules`.
- **The dcv role block (`playbook.yml:65-69`) and hardening-last** — KEEP untouched. Removing the xrdp block above it does not move hardening.

---

## §3 — secrets-bootstrap REWRITE (CRITICAL-1 carried from Phase 13)

The Phase-13 verification carried CRITICAL-1: the bootstrap unit orders `Before=…xrdp` and the restart loop names xrdp units — both dead after removal. Exact edits:

### `ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2`

```diff
- Description=Fetch devbox secrets from SSM and apply to code-server / RDP
+ Description=Fetch devbox secrets from SSM and apply to code-server / DCV
...
- Before=code-server.service xrdp.service xrdp-sesman.service
+ Before=code-server.service dcvserver.service
```
(line 2 Description; line 5 `Before=`)

### `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2`

```diff
  # Apply the credential as the ec2-user RDP/PAM login password. xrdp authenticates the
  # session via /etc/pam.d/xrdp-sesman -> password-auth, so this sets the password the RDP
  # client logs in with. printf is a bash builtin, so the cleartext never appears in the
- # process tree.
+ # Apply the credential as the ec2-user PAM login password. DCV authenticates the session
+ # via authentication=system (PAM -> system-auth), so this sets the password the DCV client
+ # logs in with. printf is a bash builtin, so the cleartext never appears in the process tree.
  printf '%s:%s' 'ec2-user' "$VNC_PWD" | chpasswd
...
- # Restart dependent services to pick up the new config. Tolerate units that aren't
- # installed (the RDP units are only present when the desktop/xrdp layers were enabled at
- # bake time). Jupyter is NOT here — it runs on demand on loopback, not as a service.
- for svc in code-server.service xrdp.service xrdp-sesman.service; do
+ # Restart dependent services to pick up the new config. Tolerate units that aren't
+ # installed (dcvserver is only present when the desktop/dcv layers were enabled at bake
+ # time). Jupyter is NOT here — it runs on demand on loopback, not as a service.
+ for svc in code-server.service dcvserver.service; do
```
(comment lines 52-53; restart-loop line 67; comment line 65)

**Functional note (from Phase-13 review):** DCV `authentication=system` reads the **live** OS password via PAM at connect time, so a `dcvserver` restart is not strictly required for the password to take effect (low severity). The edits are still correct: (a) `Before=dcvserver.service` removes the negligible first-boot race and the dead xrdp ordering; (b) the restart loop drops dead unit names. `dcv-virtual-session.service` is **optional** in the loop — a password change does not require recreating the session, so `dcvserver.service` alone is sufficient and simplest (KISS). If the planner wants belt-and-braces, adding `dcv-virtual-session.service` to the loop is harmless (the `systemctl list-unit-files` guard tolerates absent units).

---

## §4 — SECURITY GROUP: `:8443` TCP+UDP, DROP `:3389` (DCV-06)

Current SG at `terraform/main.tf:106-142`: `:8080` TCP ingress (KEEP), `:3389` TCP ingress at **lines 119-125** (DELETE), egress-all (KEEP). `:22` absent (KEEP). `[CITED: terraform/main.tf:106-142]`

### Exact edit

**1. Delete** the `:3389` block (`main.tf:119-125`):
```hcl
  ingress {
    description = "RDP (xrdp/TLS) restricted to operator CIDR allowlist"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }
```

**2. Add** two `:8443` blocks (mirror the `:8080` block at `main.tf:111-117`), e.g. after the `:8080` ingress:
```hcl
  ingress {
    description = "Amazon DCV (HTTPS/WebSocket) restricted to operator CIDR allowlist — direct connect"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  ingress {
    description = "Amazon DCV QUIC (UDP) restricted to operator CIDR allowlist — direct connect, no SSM tunnel"
    from_port   = 8443
    to_port     = 8443
    protocol    = "udp"
    cidr_blocks = var.allowed_web_cidrs
  }
```

**3. Edit** the SG comment header (`main.tf:102`): `Web ports (:8080, :3389)` → `Web ports (:8080 code-server, :8443 DCV TCP+UDP)`.

> **Posture note (v4.0 CHANGE — important):** This is **DIRECT connect**, not SSM-tunneled. The milestone-research `ARCHITECTURE.md` (drafted earlier in the milestone) recommended **TCP-only + NOT adding UDP** because it assumed the *SSM-port-forward* posture (SSM can't tunnel UDP, so QUIC was disabled). **That recommendation is SUPERSEDED by REQUIREMENTS.md DCV-06**, which mandates **both TCP and UDP** because v4.0 access is direct (CIDR allowlist is the perimeter) and QUIC is **enabled** (`enable-quic-frontend=true`, confirmed in the Phase-13 dcv.conf — `[CITED: 13-VERIFICATION.md DCV-02]`). Direct UDP path is viable precisely because there is no SSM tunnel. **Follow REQUIREMENTS.md: add both.** Flag this supersession to the planner so the older ARCHITECTURE.md TCP-only line is not mistakenly applied.

### Variables / outputs (descriptions only — no logic change)

| # | Artifact | Path : line | Action |
|---|----------|-------------|--------|
| V1 | `associate_public_ip` desc "...code-server/RDP..." | `variables.tf:54` | EDIT → "code-server/DCV" |
| V2 | `allowed_web_cidrs` desc "code-server (:8080) and RDP (:3389)" | `variables.tf:66` | EDIT → "code-server (:8080) and DCV (:8443 TCP+UDP)" |
| V3 | `allow_open_ingress` desc "no inbound :8080 / :3389" | `variables.tf:82` | EDIT → ":8080 / :8443" |
| T5 | `rdp_endpoint` output | `outputs.tf:21-24` | **EDIT → rename `dcv_endpoint`**, value `"https://${private_ip}:8443 — Amazon DCV web client (browser) or native DCV client, within the allowed CIDR"`; description "Amazon DCV endpoint (TLS :8443, TCP+UDP/QUIC) — direct connect within var.allowed_web_cidrs; browser or native DCV client". **Drop the `./run devbox-port-forward 3389` mention.** |
| T6 | `ssm_vnc_password_param` desc "RDP/desktop login" | `outputs.tf:42` | EDIT desc → "DCV login password (the ec2-user PAM password)"; KEEP the key + `vnc-password` value path |
| T7 | `private_ip` desc "...code-server/RDP..." | `outputs.tf:7` | EDIT → "code-server/DCV" |

SSM-first shell, no-`:22`, IMDSv2-only metadata, egress — all **unchanged** (DCV-06 explicit). No IAM / S3-endpoint changes in this phase — those are Phase-B (license infra) scope per the roadmap and are **out of scope here** (this phase is SG + removal + CIS-revert + operator surface).

---

## §5 — OPERATOR SURFACE: RDP→DCV, DIRECT `:8443` (DCV-10)

DCV-10 mandates **direct** connect (`https://<host>:8443`, browser or native client, within the CIDR) — **NO `./run` port-forward step for DCV**. This DIFFERS from the older ARCHITECTURE.md draft (O1), which kept a `devbox-port-forward 8443` example (it assumed the SSM posture). **Follow REQUIREMENTS.md DCV-10: remove/relabel the RDP port-forward guidance for DCV.**

| # | Artifact | Path : line | Action |
|---|----------|-------------|--------|
| O1 | `run` port-forward inline examples + help: `3389 -> RDP`, `8080 3389` | `run:392-395,404,518` | **EDIT** — drop the `3389`/RDP examples. The `cmd_devbox_port_forward` *function* stays (it still serves code-server :8080 / jupyter); just remove the RDP example lines. Do NOT add an `8443` port-forward example (DCV is direct connect). |
| O2 | `cmd_secrets_show` label "RDP login (ec2-user @ <host>:3389)" | `run:470` | **EDIT** → "DCV login (ec2-user @ <host>:8443) password:" |
| O3 | `cmd_secrets_show` error "RDP login password not found" | `run:462` | **EDIT** → "DCV login password not found at /devbox/${DEVBOX_USER}/vnc-password" |
| O4 | `secrets-show` help "code-server and RDP login passwords" | `run:522` | **EDIT** → "code-server and DCV login passwords" |
| O5 | `secrets-show` SSM fetch of `/devbox/<u>/vnc-password` | `run:458-460` | **KEEP path**; only labels (O2/O3) change |
| O6 | `scripts/devbox-start.sh` "RDP desktop ...:3389 (native RDP client...)" + the port-forward-3389 hint | `scripts/devbox-start.sh:70,72` | **EDIT** → "DCV desktop: https://${PRIVATE_IP}:8443 (browser or native DCV client; reachable from VPC; requires your CIDR in allowed_web_cidrs)"; drop the `devbox-port-forward 3389` hint (line 72 — keep the :8080 port-forward hint for code-server) |
| O7 | `scripts/devbox-status.sh` "RDP desktop ...:3389" + the port-forward-3389 hint | `scripts/devbox-status.sh:54,61` | **EDIT** → DCV `:8443` direct; drop the `devbox-port-forward 3389` RDP hint (keep :8080) |
| O8 | `firewalld-docker-fix.yml` comment "(code-server :8080, RDP :3389)" | `ansible/firewalld-docker-fix.yml:6` | **EDIT comment** → "(code-server :8080, DCV :8443)"; body unchanged (sets zone=docker; no per-port rule) |
| O9 | `CLAUDE.md` RDP/:3389/xrdp references | `CLAUDE.md:9,87,89,120-122,125-126,129-130,167,189-193,220-227` | **EDIT** (see breakdown below) |

### CLAUDE.md breakdown (O9)

- `:9` — "...an RDP desktop on `:3389`" → "...an Amazon DCV remote desktop on `:8443`"
- `:87,89` — §4 Step 2 header + body "code-server / RDP" + "`:3389` (RDP)" → "code-server / DCV" + "`:8443` (DCV, TCP+UDP)"
- `:120-122` — §5 daily-flow `./run devbox-port-forward 3389 # tunnel RDP...` block → **DELETE** (DCV is direct connect). Keep the :8080 port-forward line above it (code-server).
- `:125-126` — "browser at https://<host>:8080 (code-server) and a native RDP client at <host>:3389" → "...and the Amazon DCV web client (browser) or a native DCV client at `https://<host>:8443`"
- `:129-130` — `secrets-show` comment "the vnc-password param is the RDP/PAM login password" → "the vnc-password param is the DCV/PAM login password"
- `:189-193` — §7 troubleshooting "**RDP client can't connect to `:3389`**" entry → rewrite as "**DCV client can't connect to `:8443`**": confirm CIDR in `var.allowed_web_cidrs`, the `:8443` TCP **and** UDP ingress applied (`./run tf-apply`), browse `https://<host>:8443` or use a native DCV client, log in as `ec2-user` with the password from `./run secrets-show`. (No SSM port-forward — direct connect.)
- `:220-227` — §8/§7 invariant note "X server (xrdp/xorgxrdp → xorg-x11-server-Xorg); CIS rule 2.2.1..." → rewrite: CIS 2.2.1 is now **re-enabled** (the exception is reverted in v4.0). DCV uses its own `Xdcv` virtual X server, not the system Xorg, so the exception is no longer needed. A post-hardening assert stats `/usr/bin/Xdcv` to make a regression loud. **This is a CLAUDE.md §8 invariant edit — see §7.**

> **`/etc/pam.d/xrdp-sesman` reference (O9 `:189-193` / X9):** any doc text pointing the operator at the xrdp PAM file must change to DCV `authentication=system` (system-auth/password-auth). No physical `docs/` directory exists in the repo (verified — `ls docs/` empty); the operator docs live in `CLAUDE.md` + the inline `./run help` + the script banners. The `<files_to_read>` reference to "docs/ files" maps to these.

---

## §6 — REPO-WIDE COMPLETENESS GATE (DCV-09)

Mirror the Phase-12 RDP-11 completeness-gate pattern. Run **after** all removals. Exclude `.planning/**` (history) and **allowlist the intentionally-kept `vnc-password` identifiers** + the `!= "changeme"` secrets asserts.

```bash
# 1. No xrdp / xorgxrdp / :3389 functional artifacts remain
#    (allowlist: the kept vnc-password SSM path + the secrets != "changeme" asserts):
git grep -nIE 'xrdp|xorgxrdp|3389' -- ':!.planning/**' | grep -vE 'vnc-password|!= "changeme"'
#    expect: EMPTY

# 2. No VNC / noVNC functional artifacts remain
#    (allowlist: vnc-password SSM param name + ssm_vnc_password_param output + VNC_PWD/vnc_pwd vars):
git grep -nIE 'tigervnc|vncserver|novnc|noVNC|/etc/pam\.d/vnc|6080' -- ':!.planning/**' \
  | grep -vE 'vnc-password|ssm_vnc_password_param|VNC_PWD|vnc_pwd'
#    expect: EMPTY

# 3. The xrdp role directory is gone:
test ! -d ansible/roles/xrdp && echo "OK: xrdp role removed"

# 4. test-xrdp.yml is gone:
test ! -f ansible/test-xrdp.yml && echo "OK: test-xrdp.yml removed"

# 5. hardening still LAST (CLAUDE.md §8 grep-gate #1 / invariant):
[ "$(grep -E '^[[:space:]]*-[[:space:]]*role:' ansible/playbook.yml | tail -1 | grep -c 'hardening')" -eq 1 ] \
  && echo "OK: hardening last"

# 6. :8443 TCP+UDP ingress gated on the allowlist; :8080 kept; :3389 gone:
grep -A5 'from_port   = 8443' terraform/main.tf | grep -q 'var.allowed_web_cidrs' && echo "OK: 8443 gated"
grep -cE 'protocol    = "(tcp|udp)"' terraform/main.tf   # expect >=3 (8080 tcp, 8443 tcp, 8443 udp)
! grep -q '3389' terraform/main.tf && echo "OK: 3389 gone from terraform"

# 7. CIS 2.2.1 override reverted (no false override left):
! grep -q 'amzn2023cis_rule_2_2_1' ansible/roles/hardening/defaults/main.yml \
  && echo "OK: 2.2.1 exception reverted"

# 8. The post-hardening guard retargeted to Xdcv (not deleted, not still Xorg):
grep -q '/usr/bin/Xdcv' ansible/playbook.yml && echo "OK: post-hardening guard targets Xdcv"
```

> **Allowlist rationale:** `vnc-password` is the locked SSM param name (Anti-Pattern to rename — orphans bootstrap/outputs/secrets-show); `ssm_vnc_password_param`, `VNC_PWD`, `vnc_pwd` are the variable/output identifiers built on it. These are the ONLY VNC-string survivors and they are credential-path identifiers, not remote-desktop config. Everything else (functional xrdp/VNC/noVNC) must be zero.

---

## §7 — PHASE ORDER / WAVE BREAKDOWN + INVARIANT

### Hardening-last invariant (CLAUDE.md §8)

- Deleting the `- role: xrdp` block (`playbook.yml:59-63`) leaves `dcv` (lines 65-69) then `hardening` (line 71) as the last role — invariant **preserved**. Verify with grep-gate #5 (§6).
- The post_tasks Xorg guard edit (X3) **does not** add or move a role — `post_tasks` run after all roles regardless. Retargeting it to `/usr/bin/Xdcv` does not disturb hardening-last.
- **CLAUDE.md §8 invariant text** itself references "X server (xrdp/xorgxrdp)" and CIS 2.2.1 (CLAUDE.md:220-227). Reverting the exception means the §8 narrative + the §7 troubleshooting entry must be updated (O9). The mechanical grep-gates in §8 are about hardening-last, lockfile, SHA-pin, changeme, no-`make` — **none of those grep-gates reference xrdp/3389**, so removing xrdp does NOT trip an existing gate. (Double-check: the §8 "no retired `make` target" gate matches former Makefile target names — none collide with xrdp/dcv terms.)

### Recommended wave grouping (coarse granularity per config)

Split into **additive** (safe, reversible) vs **destructive** (irreversible) so a failure in the destructive wave doesn't strand a half-renamed operator surface:

- **Wave 1 — ADDITIVE: SG flip + operator-surface relabel + secrets-bootstrap rewrite.**
  - terraform SG (`:8443` TCP+UDP add, `:3389` delete) + var/output descriptions (§4)
  - operator surface relabel: `run`, `scripts/devbox-{start,status}.sh`, `firewalld-docker-fix.yml` comment, `CLAUDE.md` (§5)
  - secrets-bootstrap `.service.j2` + `.sh.j2` (§3, CRITICAL-1)
  - *Rationale:* these are independent of the role-removal and of each other; they make the surface DCV-correct while xrdp files still exist. `terraform validate` + a no-op bake-config check verify it. The SG `:3389` delete is technically destructive at the AWS layer but is a one-line config revertible via git + `tf-apply`.

- **Wave 2 — DESTRUCTIVE: xrdp role/wiring removal + CIS 2.2.1 revert + post-hardening guard retarget.**
  - delete `ansible/roles/xrdp/` (X1), `playbook.yml:59-63` (X2), `layer_config.yml:21-22` (X4), `ansible/test-xrdp.yml` (X6)
  - revert CIS 2.2.1 (X5) + retarget the post-hardening guard to `/usr/bin/Xdcv` (X3)
  - *Rationale:* this is the irreversible cleanup. Doing it after Wave 1 means the operator surface is already DCV-correct, so if the CIS-revert needs the Phase-15 UAT to confirm, the box is otherwise fully migrated. The retargeted guard makes a bad revert a loud bake failure.

- **Wave 3 — VERIFY: the §6 completeness grep battery + `ansible-lint` + `terraform validate` + `pre-commit run --all-files`.**
  - *Rationale:* DCV-09 is a verification requirement; run the full grep gate + the project's lint/format gates as the phase-close check. (`nyquist_validation: false` in config — no automated test-framework section needed; the grep battery + lint IS the validation here.)

> **Dependency:** Wave 1 and Wave 2 are independent enough to run in either order, but **Wave 1 first** is safer (surface correct before the irreversible delete). Wave 3 must be last. The bake itself (live render under enforcing) is **Phase-15 (DCV-11)**, not this phase — this phase closes at "bakes green + grep-clean + lint-clean."

---

## Common Pitfalls (Phase-14-specific)

### Pitfall A: Deleting the post-hardening guard instead of retargeting it
**What goes wrong:** Following the ARCHITECTURE.md draft (X3 "DELETE") removes the only post-hardening proof that the X server survived CIS. Combined with reverting 2.2.1, a transitive `xorg-x11-server-common` dependency would silently delete Xdcv's prerequisites → blank desktop discovered only at the Phase-15 UAT.
**Avoid:** RETARGET to `/usr/bin/Xdcv` (§1). The guard is the safety net for the revert.

### Pitfall B: Renaming the `vnc-password` SSM param "for cleanliness"
**What goes wrong:** Orphans the bootstrap fetch, the `ssm_vnc_password_param` output, `secrets-show`, and any in-flight AMIs.
**Avoid:** KEEP the param name; relabel only human-facing text. Allowlist it in the §6 grep.

### Pitfall C: Applying the older ARCHITECTURE.md "TCP-only, no UDP, port-forward 8443" guidance
**What goes wrong:** That guidance assumed the SSM-port-forward posture. v4.0 REQUIREMENTS.md DCV-06/DCV-10 changed to **direct connect** — UDP **is** required (QUIC enabled) and there is **no** DCV port-forward step.
**Avoid:** Follow REQUIREMENTS.md, not the milestone-draft ARCHITECTURE.md, where they conflict (both flagged inline in §4/§5).

### Pitfall D: Over-removing the colord `.rules` shared by GNOME-over-remote
**What goes wrong:** Deleting `ansible/roles/xrdp/files/45-allow-colord.rules` without confirming the `dcv` role ships its own → DCV's GNOME session hangs on the colord polkit prompt.
**Avoid:** Confirm the dcv role's colord handling before deleting the whole xrdp dir; if missing, flag as a Phase-13 gap (do not keep xrdp's file as a crutch).

---

## Project Constraints (from CLAUDE.md)

- **`hardening` MUST remain the last role in `ansible/playbook.yml`** (§8 invariant + grep-gate). Removing the xrdp block preserves this; verify with grep-gate #5.
- **`changeme` literal MUST NOT appear in any tracked code file** (`no-changeme` hook). The kept `!= "changeme"` secrets asserts are a known acceptable false-positive carried from the secrets role.
- **Action SHA-pin / lockfile / Packer-SSM-pin invariants** — untouched by this phase.
- **No retired `make <target>` invocations** — unaffected (xrdp/dcv terms don't collide with the gated Makefile target names).
- **Coding-style (user rules):** immutable edits, KISS — the secrets-bootstrap restart loop should stay minimal (`code-server.service dcvserver.service`), not speculatively add units (YAGNI).
- **Commit standalone** (MEMORY): run any `git commit` as its own Bash call (block-no-verify hook false-positives on chained commits).
- **Verify subagent commits** (MEMORY): spot-check claimed git hashes via `git rev-parse` after executor returns.
- **Workaround layout** (MEMORY): the firewalld-docker-fix stays its own named playbook (only its comment changes here).

## Environment Availability

Code/config-only phase (terraform + ansible + shell edits). No new external tooling beyond the existing floor (`tofu`/`terraform validate`, `ansible-lint`, `pre-commit`, `git grep`). The live bake/instance is **Phase-15**, out of scope. No environment probe needed for this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `nice-xdcv` / `Xdcv` does NOT hard-`Requires` `xorg-x11-server-common` such that the 2.2.1 revert breaks it | §1 | DCV virtual session loses its X prerequisites → blank desktop. **Mitigated** by the retargeted `/usr/bin/Xdcv` post-hardening guard (loud bake failure) + the Phase-15 `repoquery --requires nice-xdcv` UAT assertion. |
| A2 | GNOME-on-Xorg in the Xdcv virtual session does not transitively need `xorg-x11-server-common` once 2.2.1 removes it | §1 | Same as A1; same mitigation. |
| A3 | The `dcv` role ships its own colord polkit `.rules` (so deleting xrdp's is safe) | §2 / Pitfall D | GNOME session hangs on colord prompt. Confirm in the dcv role before deleting the xrdp dir. |
| A4 | `dcv-virtual-session.service` does NOT need restarting on password rotation (PAM reads live) | §3 | Negligible — `dcvserver.service` alone in the restart loop is sufficient; password takes effect at next connect regardless. |

## Open Questions

1. **Does `nice-xdcv` depend on `xorg-x11-server-common`?**
   - Known: virtual session uses `/usr/bin/Xdcv`, not `/usr/libexec/Xorg`; AWS lists `xorg-x11-server-Xorg` as a recommended prereq.
   - Unclear: the transitive RPM `Requires:` — only `repoquery --requires nice-xdcv` / `rpm -qR nice-xdcv` on a baked box answers it.
   - Recommendation: revert in code + retarget the guard to `/usr/bin/Xdcv` + assert `repoquery` at the Phase-15 UAT (§1 VERDICT). Documented fallback: re-add `amzn2023cis_rule_2_2_1: false`.

2. **Does the Phase-13 `dcv` role already ship a colord polkit `.rules`?**
   - If yes → delete xrdp's freely. If no → flag as a Phase-13 gap (Pitfall 8 colord-hang risk), do not retain xrdp's file as a workaround.

## Sources

### Primary (HIGH — repo-internal, read at file:line)
- `ansible/playbook.yml` (xrdp wiring :59-63; dcv :65-69; post_tasks Xorg guard :74-96; hardening-last :71)
- `ansible/layer_config.yml` (:21-24), `ansible/test-xrdp.yml` (exists), `ansible/firewalld-docker-fix.yml` (:6 comment)
- `ansible/roles/xrdp/` (full file tree — 12 files), `ansible/roles/desktop/tasks/main.yml` (:4-20 GNOME/mesa/fonts DCV reuses), `ansible/roles/hardening/defaults/main.yml` (:28-37 CIS 2.2.1 override)
- `ansible/roles/secrets/templates/devbox-secrets-bootstrap.{service.j2,sh.j2}` (the xrdp→dcv swap targets)
- `ansible/roles/dcv/tasks/main.yml` (:32-89 install; :110-125 GNOME-on-Xorg init; :268,310,322 `/usr/bin/Xdcv` bake-assert)
- `terraform/main.tf` (:97-142 SG, :3389 at 119-125), `terraform/variables.tf` (:54,66,82), `terraform/outputs.tf` (:6-9,21-24,41-44)
- `run` (:379-435 port-forward; :441-473 secrets-show; :516-522 help), `scripts/devbox-{start,status}.sh`, `CLAUDE.md` (:9,87-130,167,189-227)
- `.planning/REQUIREMENTS.md` (DCV-06..10, direct-connect/QUIC posture, Assumptions)
- `.planning/research/ARCHITECTURE.md` (removal-inventory draft + CIS-revert analysis — corrected here for X3 action + the superseded TCP-only SG line) + `PITFALLS.md` (CIS 2.2.1, colord, FIPS, SELinux)
- `.planning/phases/13-dcv-ansible-role/13-VERIFICATION.md` (CRITICAL-1 secrets-bootstrap; nice-xdcv-vs-2.2.1 carried; DCV-01..05 done)

### Secondary (HIGH — official AWS docs)
- [Prerequisites for Linux Amazon DCV servers](https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html) — lists `xorg-x11-server-Xorg` as a recommended prereq; virtual session uses Xdcv
- [Understanding / Starting Amazon DCV sessions](https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-intro.html) — "virtual sessions start an Xdcv X server"
- [Enabling QUIC](https://docs.aws.amazon.com/dcv/latest/adminguide/enable-quic.html) — QUIC = UDP 8443, viable on a direct (non-SSM) path

### Tertiary (LOW — WebSearch, unverified, flagged)
- WebSearch for `nice-xdcv` RPM dependencies returned no authoritative `Requires:` list — confirms the A1/A2 assumption can only be resolved by `repoquery`/live UAT. (re:Post AL2023 GUI articles, AWS DCV blog — context only.)

## Metadata

**Confidence breakdown:**
- Removal inventory (§2): HIGH — every artifact read at file:line in the current tree.
- SG + operator surface (§4/§5): HIGH — exact files/lines; the only nuance is the REQUIREMENTS-vs-ARCHITECTURE supersession (resolved in favor of REQUIREMENTS.md, flagged inline).
- CIS 2.2.1 revert (§1): MEDIUM-HIGH — architecture supports it; the residual transitive-dependency risk is unprovable without a live box, mitigated by the retargeted guard + Phase-15 UAT.
- Wave breakdown (§7): HIGH — additive/destructive split + invariant analysis grounded in the file structure.

**Research date:** 2026-06-19
**Valid until:** 2026-07-19 (stable repo-internal; the DCV RPM dependency question resolves at the Phase-15 bake regardless)
