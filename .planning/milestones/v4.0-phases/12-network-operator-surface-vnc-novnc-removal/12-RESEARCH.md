# Phase 12: Network, Operator Surface + VNC/noVNC Removal - Research

**Researched:** 2026-06-15
**Domain:** Terraform EC2 security group, `./run` shell operator surface, Ansible role/playbook removal, AWS SSM port-forwarding, operator docs
**Confidence:** HIGH (entirely repo-internal evidence; every claim grounded in a read file:line, no external-version risk)

## Summary

Phase 12 is the irreversible-cleanup phase: open the SG to `:3389`, drop `:6080`, point the operator surface and docs at native RDP-over-SSM, and surgically excise every VNC/noVNC artifact now that Phase 11's xrdp uses the **xorgxrdp/Xorg backend** (no Xvnc). The single largest correctness risk is **deleting a VNC artifact that something surviving still needs** — and the research surfaced exactly one such trap: `tigervnc-server` is bundled into the **same `dnf` task** as `gnome-shell`, `gnome-session`, `dejavu-*` fonts and `mesa-dri-drivers` (`ansible/roles/desktop/tasks/main.yml:21-33`). Removal must drop only the `tigervnc-server` list item, not the task. A second, subtler trap is the **`vnc-password` SSM parameter is NOT a VNC artifact** — per the milestone credential model it is the `ec2-user` PAM password that xrdp authenticates against (`REQUIREMENTS.md:5`, applied via `chpasswd` in `devbox-secrets-bootstrap.sh.j2:55`). It MUST survive; only its noVNC-specific *labels/restart-targets* change.

Removal-safety is proven: `sesman.ini.j2:32-40` configures the `[Xorg]` backend (`param=/usr/libexec/Xorg`) and the xrdp role explicitly installs `xorg-x11-server-Xorg` as its own runtime dep (`xrdp/defaults/main.yml:32`). `grep -rn vnc` across the entire `xrdp` role returns **zero functional references** (only two comments citing the noVNC openssl pattern as prior art). GNOME comes from `@Desktop` + `gnome-shell`/`gnome-session` (`desktop/tasks/main.yml:16-32`), not pulled transitively by tigervnc. Therefore removing tigervnc-server, Xvnc, `/etc/pam.d/vnc`, the noVNC install, and the two systemd units strips nothing the RDP path needs.

The artifact inventory spans **three layers**: Ansible (desktop role VNC/noVNC blocks + the `novnc-plain-username-fix.yml` workaround + its playbook import + the secrets bootstrap's noVNC restart loop), Terraform (the `:6080` ingress block + `novnc_url` output + two variable/comment descriptions), and the operator surface (`./run` help + `secrets-show` label, `scripts/devbox-start.sh:70`, `scripts/devbox-status.sh:54,61`, and CLAUDE.md §1/§2/§5/§7). A pleasant side effect: removing the desktop role's `desktop_vnc_password != "changeme"` assert (`desktop/tasks/main.yml:7`) **eliminates one of three pre-existing `no-changeme` hook false-positives** (the other two stay, in the surviving secrets role).

**Primary recommendation:** Two-wave plan. **Wave A (additive/non-destructive, parallel-safe):** Terraform SG `:3389` ingress + drop `:6080` + outputs + var descriptions; `./run`/scripts/CLAUDE.md doc + label edits. **Wave B (destructive removal, depends on nothing in A but file-conflicts within itself):** desktop role VNC/noVNC excision, secrets-bootstrap restart-loop fix, `novnc-plain-username-fix.yml` deletion + import drop. **Recommendation on the network question: gate `:3389` on `var.allowed_web_cidrs` exactly like `:8080` (mirror the 8080 block), NOT SSM-only** — this is what RDP-09 literally requires ("exposes :3389 gated on var.allowed_web_cidrs"), preserves parity with code-server, and the SSM path (RDP-10) works regardless because SSM port-forwarding does not traverse the SG.

## User Constraints

> No `12-CONTEXT.md` exists (this is standalone/integrated research run before discuss-phase). Constraints below are derived from the **locked requirements** in `REQUIREMENTS.md` and `ROADMAP.md`, which bind this phase exactly as a CONTEXT.md would. Treat the requirement text as locked decisions.

### Locked Decisions (from REQUIREMENTS.md / ROADMAP.md Phase 12)
- **RDP-09**: SG exposes `:3389` **gated on `var.allowed_web_cidrs`**, drops `:6080`; SSM-first posture (no public `:22`) unchanged.
- **RDP-10**: `./run devbox-port-forward` tunnels `:3389`; CLAUDE.md documents connecting with a **native RDP client over SSM**.
- **RDP-11**: Remove the VNC/noVNC stack — vncserver/novnc systemd services, `SecurityTypes Plain`, `/etc/pam.d/vnc`, the noVNC install — no dead VNC config in the image.
- **RDP-12**: Revert/remove the noVNC username-injection workaround (`ansible/novnc-plain-username-fix.yml`, commit `29de35b`) and drop its import.
- **Credential model (REQUIREMENTS.md:5, locked):** the RDP login is the `ec2-user` PAM password the secrets role already generates and publishes to SSM at `/devbox/<user>/vnc-password`. **No new secret.** ⇒ the `vnc-password` SSM param is RETAINED (it is the RDP password), only re-labelled.

### Claude's Discretion
- Whether to *rename* the `vnc-password` SSM param to something RDP-flavoured, or retain the name and re-label in human-facing surfaces only. **Recommendation: retain the param name `/devbox/<user>/vnc-password`** (renaming is a cross-cutting break — IAM ARN is a wildcard so it would still work, but the bootstrap script, outputs, secrets-show, and any in-flight baked AMIs all hard-code the path; a rename buys nothing and risks an orphan). Re-label human-facing text to "desktop / RDP login password".
- Exact wording of CLAUDE.md daily-flow RDP step and troubleshooting entries.
- Whether to add a `DEVBOX_RDP_PORT`/default convenience or leave `./run devbox-port-forward 3389` explicit.

### Deferred Ideas (OUT OF SCOPE)
- Browser-based desktop (Guacamole RDP→HTML5 gateway) — explicitly out of scope (REQUIREMENTS.md:44).
- Migrating the host firewalld posture off the docker-zone workaround (separate retirement criteria; not triggered by this phase).
- Renaming the `vnc-password` SSM key (discretionary; recommend NOT doing it — see above).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RDP-09 | SG exposes `:3389` gated on `var.allowed_web_cidrs`, drops `:6080`; SSM-first unchanged | Exact edit mapped: mirror `main.tf:111-117` (8080 block) for 3389; delete `main.tf:119-125` (6080 block); update `main.tf:99-104` comment, `variables.tf:54` & `:66` descriptions. Recommendation: SG-gated (not SSM-only). |
| RDP-10 | `./run devbox-port-forward` tunnels `:3389`; docs describe native RDP client over SSM | `cmd_devbox_port_forward` (`run:379-435`) already accepts arbitrary `PORT`/`REMOTE:LOCAL` — `./run devbox-port-forward 3389` works with **no code change**; only help text (`run:392-394, 516-518`) + CLAUDE.md §5 need editing. |
| RDP-11 | Remove vncserver/novnc services, `SecurityTypes Plain`, `/etc/pam.d/vnc`, noVNC install | Complete inventory below; the tigervnc-server line is shared with GNOME (surgical removal required). xrdp proven independent of all of it. |
| RDP-12 | Revert/remove `novnc-plain-username-fix.yml` (commit `29de35b`) + drop import | Commit `29de35b` confirmed: added the file (86 LOC) + 6 LOC in playbook.yml. Delete file + remove `playbook.yml:118-122`. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| RDP perimeter ingress (:3389) | API/Infra (Terraform SG) | — | SG is the network boundary; RDP-09 locates it here, gated on `allowed_web_cidrs` (same as :8080) |
| RDP transport for off-VPC operator | Operator surface (`./run` over SSM) | AWS SSM service | SSM port-forward bypasses the SG entirely; RDP-10. Generic port logic already supports it |
| Desktop session backend | Image/Ansible (xrdp role, Xorg backend) | — | Already delivered Phase 11; Phase 12 only *removes the alternative* (VNC), does not touch xrdp |
| RDP login credential | Image/Ansible (secrets role → PAM via chpasswd) | SSM Parameter Store | Locked credential model: `vnc-password` param IS the ec2-user PAM password; survives |
| Dead-artifact removal | Image/Ansible (desktop role, playbook, secrets bootstrap) | — | The destructive core of the phase |
| Operator-facing labelling | Operator surface (`./run`, scripts) + Docs (CLAUDE.md) | — | Cosmetic-but-required: stop advertising :6080/noVNC, advertise RDP |

## Standard Stack

This phase installs **no new packages**. It removes packages/config and edits existing IaC. The "stack" is the existing toolchain (CLAUDE.md §2): `tofu`/OpenTofu, Ansible, the `./run` bash dispatcher, AWS SSM. No version verification, no registry lookups, no Package Legitimacy Audit required.

### Removal targets (packages no longer installed after this phase)
| Package | Installed by (current) | Safe to drop? | Evidence |
|---------|------------------------|---------------|----------|
| `tigervnc-server` | `desktop/tasks/main.yml:30` (shared dnf list) | YES — surgical (drop list item only) | No xrdp ref; GNOME from `@Desktop`+`gnome-shell` |
| `websockify` (pip) | `desktop/tasks/main.yml:128-131` | YES | noVNC-only proxy; nothing else uses it |
| noVNC v1.5.0 (tarball → `/usr/local/share/noVNC`) | `desktop/tasks/main.yml:134-163` | YES | noVNC-only |

> `python3-pip` (`desktop/tasks/main.yml:123-126`) is installed immediately before websockify but is a generic utility — **leave it** unless verified unused elsewhere. Conservative: keep it (KISS; removing it risks breaking some other pip consumer). Flag as a LOW-priority discretionary cleanup, not a requirement.

## Complete Removal Inventory

> Legend — **Action**: `DELETE` (whole file/block), `EDIT` (surgical), `KEEP` (do not touch — listed to prove it was considered). **Shared?**: YES = the artifact is co-located with a surviving feature; removal must be surgical.

### Ansible — desktop role (`ansible/roles/desktop/`)

| # | Artifact | Path : line | Action | Shared? / Risk |
|---|----------|-------------|--------|----------------|
| D1 | `desktop_vnc_password != "changeme"` assert (whole 3-line assert block) | `tasks/main.yml:1-12` | DELETE block | Removes 1 of 3 pre-existing `no-changeme` false-positives (see Hook Interactions). The password is still asserted in the secrets role. |
| D2 | `tigervnc-server` in the shared package list | `tasks/main.yml:30` | EDIT — remove **only** this list item | **YES — shared dnf task** with gnome-shell/gnome-session/fonts/mesa. Do NOT delete the task. |
| D3 | Create `~/.vnc` config dir | `tasks/main.yml:37-43` | DELETE task | VNC-only |
| D4 | "Set dev-user PAM password (TigerVNC ... auth)" | `tasks/main.yml:45-53` | **MOVE/RETAIN logic** — see note | **CRITICAL**: this task sets the ec2-user PAM password from `desktop_vnc_password`. It is functionally the RDP password setter at *bake time*. But the *runtime* password is (re)applied by the secrets bootstrap via chpasswd (`bootstrap.sh.j2:55`) on first boot, which overwrites it. So this bake-time task is **redundant at runtime** and tied to the VNC comment. **Recommend DELETE** (the bootstrap is the authoritative setter) — but verify the bootstrap always runs before first RDP login (it does: oneshot at boot). If any doubt, keep it but rewrite the comment to drop "TigerVNC". |
| D5 | Install `/etc/pam.d/vnc` PAM file | `tasks/main.yml:55-68` | DELETE task | VNC-only. xrdp uses `/etc/pam.d/xrdp-sesman` (`xrdp/files/xrdp-sesman.pam`), a separate file. |
| D6 | Install VNC xstartup script | `tasks/main.yml:70-76` | DELETE task | VNC-only. xrdp uses `startwm.sh` (`xrdp/templates/startwm.sh.j2`). |
| D7 | Install + enable `vncserver.service` (two tasks) | `tasks/main.yml:78-89` | DELETE both tasks | VNC-only systemd unit |
| D8 | GNOME screensaver/lock-disable via dconf (5 tasks) | `tasks/main.yml:91-119` | **KEEP** — but re-justify | The comment says "VNC keyboard input unreliable with lock". The *reason* is VNC-flavoured but disabling the GNOME lock screen is **also desirable for RDP** (a locked session over RDP is the same UX problem). **KEEP; rewrite the comment** to drop the VNC-specific rationale and reference RDP/headless. |
| D9 | noVNC: pip/websockify, get_url, extract, symlink, cert dir, openssl cert, perms (≈ tasks at 121-188) | `tasks/main.yml:121-201` | DELETE block | noVNC-only. Includes `/etc/novnc/` cert generation. |
| D10 | Install + enable `novnc.service` (two tasks) | `tasks/main.yml:190-202` | DELETE both tasks | noVNC-only systemd unit |
| D11 | ffmpeg static-build block | `tasks/main.yml:203-258` | **KEEP** | Media tooling — unrelated to VNC. (It sits between noVNC and VLC; do not over-delete.) |
| D12 | VLC flatpak block | `tasks/main.yml:260-274` | **KEEP** | Media tooling — unrelated to VNC. |
| D13 | `vncserver.service.j2` template | `templates/vncserver.service.j2` | DELETE file | VNC-only |
| D14 | `novnc.service.j2` template | `templates/novnc.service.j2` | DELETE file | noVNC-only |
| D15 | `xstartup.j2` template | `templates/xstartup.j2` | DELETE file | VNC-only (xrdp has its own startwm.sh) |
| D16 | desktop role defaults: `desktop_vnc_display/_port`, `desktop_novnc_port`, `desktop_vnc_resolution/_depth`, `desktop_novnc_version` | `defaults/main.yml:2-8` | DELETE these keys | VNC/noVNC-only. KEEP `dev_user`/`dev_home` (lines 10-11). |
| D17 | desktop role handler `reload systemd` | `handlers/main.yml:1-4` | **KEEP only if still notified** | The handler is notified by D7/D10 (now deleted). After D7/D10 removal, **check if any surviving desktop task still notifies it** — none do. So the handler becomes dead. **DELETE the handler** (or the whole handlers/main.yml if it's the only one). Verify no remaining `notify: reload systemd` in the role after edits. |

### Ansible — secrets role (`ansible/roles/secrets/`)

| # | Artifact | Path : line | Action | Shared? / Risk |
|---|----------|-------------|--------|----------------|
| S1 | Generate `desktop_vnc_password` (set_fact) | `tasks/generate.yml:9-14` | **KEEP** | This IS the RDP password (locked credential model). KEEP the generation; optionally rename the fact `desktop_vnc_password` → e.g. `rdp_password` only if you also chase every consumer (D4, publish.yml, bootstrap). **Recommend KEEP name** to avoid a rename cascade. |
| S2 | Assert `desktop_vnc_password != "changeme"` | `tasks/generate.yml:26-34` | **KEEP** | Surviving `no-changeme` false-positive (acceptable — see Hook Interactions). KEEP the assert (it guards the real RDP password). |
| S3 | Publish `vnc-password` to SSM | `tasks/publish.yml:39-51` | **KEEP** | Publishes the RDP password param. KEEP. Optionally rewrite the description string to drop "VNC" → "RDP/desktop login". |
| S4 | `secrets_vnc_password_length` / `secrets_ssm_vnc_param` defaults | `defaults/main.yml:5-6, 12` | **KEEP** | Param name `/devbox/<user>/vnc-password` retained (recommendation). Optionally rewrite the comment at lines 4-6 to drop "TigerVNC SecurityTypes=Plain" → "RDP PAM login". |
| S5 | secrets bootstrap: fetch `VNC_PWD` + apply via chpasswd | `templates/devbox-secrets-bootstrap.sh.j2:32-34, 52-55` | **KEEP** | This applies the RDP password to ec2-user. KEEP. Rewrite the comment block (lines 52-54) to drop "TigerVNC SecurityTypes=Plain ... /etc/pam.d/vnc". |
| S6 | secrets bootstrap: restart loop includes `vncserver.service novnc.service` | `templates/devbox-secrets-bootstrap.sh.j2:66` | **EDIT** | **Important**: after D7/D10 these units no longer exist. The loop is tolerant (`if systemctl list-unit-files "$svc"`), so it won't error — but leaving dead names is exactly the "no dead VNC config" RDP-11 violation. **EDIT line 66** to `for svc in code-server.service xrdp.service xrdp-sesman.service; do` (add xrdp so a password rotation restarts the RDP path; drop vncserver/novnc). Verify xrdp service names against `xrdp/files/xrdp.service` + `xrdp-sesman.service`. |

### Ansible — playbook + workaround (`ansible/`)

| # | Artifact | Path : line | Action | Shared? / Risk |
|---|----------|-------------|--------|----------------|
| P1 | `novnc-plain-username-fix.yml` (whole file, 86 LOC) | `ansible/novnc-plain-username-fix.yml` | DELETE file | RDP-12. Standalone workaround playbook (commit `29de35b`). |
| P2 | FIXME comment + `import_playbook: novnc-plain-username-fix.yml` | `playbook.yml:118-122` | DELETE these 5 lines | RDP-12. Keep the `firewalld-docker-fix.yml` import above it (lines 113-116). |
| P3 | firewalld-docker-fix.yml comment "(noVNC :6080, code-server :8080)" | `firewalld-docker-fix.yml:6` | EDIT comment | Cosmetic — drop noVNC :6080, can mention RDP :3389. The play body opens no specific port (sets zone=docker), so **no functional change**. |

### Terraform (`terraform/`)

| # | Artifact | Path : line | Action | Shared? / Risk |
|---|----------|-------------|--------|----------------|
| T1 | `:6080` noVNC ingress block | `main.tf:119-125` | DELETE block | noVNC-only |
| T2 | Add `:3389` RDP ingress block (mirror 8080) | `main.tf` (insert after :117) | ADD block | RDP-09 |
| T3 | SG comment "Web ports (:8080, :6080)" | `main.tf:99-104` | EDIT comment | Update to ":8080, :3389" |
| T4 | `novnc_url` output | `outputs.tf:21-24` | DELETE or REPLACE | Recommend DELETE the URL-style output and ADD an `rdp_endpoint`/note output: RDP is not a browser URL. E.g. `value = "${private_ip}:3389 — connect with a native RDP client (mstsc/FreeRDP/Remmina) or via ./run devbox-port-forward 3389 → localhost:3389"`. |
| T5 | `ssm_vnc_password_param` output | `outputs.tf:41-44` | **KEEP** (re-label) | Param retained. Rewrite description "VNC password" → "RDP/desktop login password". Optionally rename output key `ssm_vnc_password_param` → `ssm_rdp_password_param` (discretionary; the value path stays `/devbox/<user>/vnc-password`). |
| T6 | `private_ip` output description "...code-server/noVNC..." | `outputs.tf:6-9` | EDIT description | drop noVNC → RDP |
| T7 | `allowed_web_cidrs` description "code-server (:8080) and noVNC (:6080)" | `variables.tf:66` | EDIT description | → "code-server (:8080) and RDP (:3389)" |
| T8 | `associate_public_ip` description "...code-server/noVNC..." | `variables.tf:54` | EDIT description | drop noVNC → RDP |
| T9 | `allow_open_ingress` description "...:8080 / :6080..." | `variables.tf:82` | EDIT description | → ":8080 / :3389" |

> **Protocol note for T2:** RDP is TCP. The 8080 block uses `protocol = "tcp"` — mirror it exactly (`from_port = 3389`, `to_port = 3389`, `protocol = "tcp"`, `cidr_blocks = var.allowed_web_cidrs`). RDP also has a UDP transport (3389/udp) but xrdp's TLS config does not require it; **TCP-only is sufficient** and matches the existing pattern. Do not add UDP.

### Operator surface — `./run` + scripts

| # | Artifact | Path : line | Action | Shared? / Risk |
|---|----------|-------------|--------|----------------|
| R1 | `cmd_devbox_port_forward` generic port logic | `run:379-435` | **KEEP — no code change** | Already accepts `3389`. Verified: spec parser at `run:400-409` accepts any numeric PORT or REMOTE:LOCAL. |
| R2 | port-forward inline help comments "6080 -> noVNC" | `run:392-394` | EDIT comments | → `3389 -> RDP` examples |
| R3 | port-forward help block example "8080 6080 8888:18888" | `run:516-518` | EDIT help text | → mention 3389 |
| R4 | `cmd_secrets_show` label "VNC / noVNC (https://<host>:6080) password" | `run:470` | EDIT | → e.g. `RDP login (ec2-user@<host>:3389) password:` |
| R5 | `secrets-show` help "code-server and VNC passwords" | `run:522` | EDIT | → "code-server and RDP login passwords" |
| R6 | `secrets-show` SSM fetch of `/devbox/<user>/vnc-password` | `run:458-466` | **KEEP** (path unchanged) | Param retained; only the printed label (R4) changes. |
| R7 | `scripts/devbox-start.sh` "noVNC: https://...:6080" | `scripts/devbox-start.sh:70` | EDIT | → RDP :3389 line. (Wired via `./run start` → `cmd_start` at `run:345-348`.) |
| R8 | `scripts/devbox-status.sh` "noVNC (browser): ...:6080" | `scripts/devbox-status.sh:54` | EDIT | → RDP :3389. (Wired via `./run status` → `cmd_status` at `run:357-360`.) |
| R9 | `scripts/devbox-status.sh` "(and a second session for :6080)" | `scripts/devbox-status.sh:61` | EDIT | → "(and a second session for :3389)" |

### Docs — CLAUDE.md

| # | Artifact | Path : line | Action |
|---|----------|-------------|--------|
| C1 | §1 "code-server (browser VS Code) on :8080, noVNC on :6080" | `CLAUDE.md:9` | EDIT → "...code-server on :8080, RDP desktop on :3389" |
| C2 | §2 Step-2 heading "CIDR allowlist for code-server / noVNC" | `CLAUDE.md:87` | EDIT → "code-server / RDP" |
| C3 | §2 ":8080 (code-server) and :6080 (noVNC) are restricted..." | `CLAUDE.md:89` | EDIT → ":8080 (code-server) and :3389 (RDP)" |
| C4 | §5 daily-flow step 5 "tunnel :8080" + "browser at :8080" | `CLAUDE.md:120, 123` | EDIT — add RDP step: `./run devbox-port-forward 3389` then connect a native RDP client (mstsc/FreeRDP/Remmina) to `localhost:3389` as `ec2-user` |
| C5 | §5 step 6 comment "{code-server,vnc}-password" | `CLAUDE.md:126` | KEEP path or relabel comment (param name unchanged) |
| C6 | §7 troubleshooting — add an RDP-connect entry; review the firewalld-blocking entry | `CLAUDE.md:~175-185` (firewalld entry references the fix) | EDIT/ADD — add "RDP client can't connect → check var.allowed_web_cidrs / SG :3389 / use ./run devbox-port-forward 3389" |
| C7 | §8 invariants — review (no functional change) | `CLAUDE.md:204-218` | KEEP (see Invariant Interactions) |

## Removal-Safety Proof

**Claim: nothing that survives depends on tigervnc-server, Xvnc, `/etc/pam.d/vnc`, the VNC xstartup, or the VNC/noVNC systemd units.**

1. **xrdp uses Xorg, not Xvnc.** `sesman.ini.j2:32-40` defines an `[Xorg]` section with `param=/usr/libexec/Xorg`; there is **no `[Xvnc]` section**. The header comment (`sesman.ini.j2:2`) states "xorgxrdp (Xorg) backend only; no Xvnc backend." `[CITED: ansible/roles/xrdp/templates/sesman.ini.j2]`
2. **xrdp installs its own X server.** `xrdp/defaults/main.yml:32` lists `xorg-x11-server-Xorg` in `xrdp_runtime_deps` — the X server is pulled by the xrdp role, independent of tigervnc. `[CITED: ansible/roles/xrdp/defaults/main.yml:32]`
3. **No VNC references anywhere in the xrdp role.** `grep -rn -i 'vnc'` over `ansible/roles/xrdp/` returns only two comment lines that cite the noVNC openssl cert pattern as prior art (`tasks/main.yml:199`, `sesman.ini.j2:2`) — zero functional dependency. `[VERIFIED: grep over xrdp role]`
4. **GNOME is installed independently of tigervnc.** `desktop/tasks/main.yml:16` installs `@Desktop`; lines 22-23 install `gnome-shell` + `gnome-session` explicitly. tigervnc (line 30) is a sibling list item, not a parent. Removing it cannot strip GNOME. `[CITED: ansible/roles/desktop/tasks/main.yml:16-33]`
5. **Fonts/mesa are explicit siblings, not tigervnc deps.** `dejavu-sans-fonts`, `dejavu-sans-mono-fonts`, `mesa-dri-drivers` are their own list items (`desktop/tasks/main.yml:31-33`) — they survive the tigervnc-server line removal. `[CITED]`
6. **xrdp PAM is a separate file.** xrdp authenticates via `/etc/pam.d/xrdp-sesman` (`xrdp/files/xrdp-sesman.pam`, installed by the xrdp role), NOT `/etc/pam.d/vnc`. Deleting `/etc/pam.d/vnc` cannot affect RDP auth. `[CITED: ansible/roles/xrdp/files/xrdp-sesman.pam]`
7. **xrdp session launcher is separate.** xrdp uses `startwm.sh` (`xrdp/templates/startwm.sh.j2`); the VNC `xstartup.j2` is unused by xrdp. `[CITED]`

**Conclusion:** All seven checks pass. Removing the VNC/noVNC artifacts (D2-D7, D9-D10, D13-D16, T1) strips nothing the surviving RDP/GNOME/code-server/jupyter paths require. **HIGH confidence.**

## vnc-password SSM Orphan Decision

**Verdict: NOT an orphan — KEEP. The `/devbox/<user>/vnc-password` SSM parameter is the RDP login password, re-labelled only.**

Evidence chain:
- `REQUIREMENTS.md:5` (locked credential model): *"the RDP login is the `ec2-user` PAM password the `secrets` role already generates per build, publishes to SSM (`/devbox/<user>/vnc-password`), and the boot bootstrap applies via `chpasswd`. No new secret."*
- `devbox-secrets-bootstrap.sh.j2:32-34` fetches `/devbox/$DEVBOX_USER/vnc-password`; line 55 applies it: `printf '%s:%s' 'ec2-user' "$VNC_PWD" | chpasswd`. This sets the `ec2-user` PAM password that xrdp's `password-auth` PAM stack validates. `[CITED]`
- `secrets-show` (`run:458-470`) reads the same param and prints it for the operator — this is precisely the password the RDP-14 UAT instructs the operator to use (`11-HUMAN-UAT.md:23`).

**What changes (re-labelling, not removal):**
- KEEP: generation (`generate.yml:9-14`), assert (`generate.yml:26-34`), publish (`publish.yml:39-51`), defaults (`defaults/main.yml:5-6,12`), bootstrap fetch+chpasswd (`bootstrap.sh.j2:32-34,52-55`), SSM param path, IAM ARN wildcard, `secrets-show` fetch, `ssm_vnc_password_param` output.
- EDIT (human labels / comments only): `run:470` label (R4), `run:522` help (R5), `outputs.tf:42` description (T5), `generate.yml` / `publish.yml` / `defaults/main.yml` / `bootstrap.sh.j2` comments that say "TigerVNC"/"SecurityTypes=Plain"/"/etc/pam.d/vnc" → reword to "RDP PAM login".
- EDIT (functional): bootstrap restart loop `bootstrap.sh.j2:66` — drop `vncserver.service novnc.service`, add `xrdp.service xrdp-sesman.service` (S6).

**Rename recommendation:** Do NOT rename the SSM param key. The IAM policy uses a wildcard (`main.tf:64`: `parameter/devbox/${var.devbox_user}/*`) so a rename would still be authorized, but the path is hard-coded in 4+ places and any AMI baked before the rename would read the old key — a classic orphan-creation move for zero benefit. The param name being "vnc-password" is a cosmetic wart, not a correctness issue. (Discretionary: if the planner wants cosmetic purity, the rename must be a single atomic task touching generate/publish/defaults/bootstrap/outputs/secrets-show together — call it out as all-or-nothing.)

**Post-removal `secrets-show` output should print exactly two lines:**
```
code-server (https://<host>:8080) password:  <cs_pwd>
RDP login (ec2-user @ <host>:3389) password:  <rdp_pwd>
```

## Network Question: SG-gated :3389 vs SSM-only

**Recommendation: gate `:3389` on `var.allowed_web_cidrs` (mirror the :8080 block). NOT SSM-only.**

Reasoning:
1. **RDP-09 text is explicit and locked:** "The Terraform security group **exposes `:3389` (gated on `var.allowed_web_cidrs`)**". This is not ambiguous — the SG opens 3389 to the allowlist. `[CITED: REQUIREMENTS.md:27]`
2. **Parity with code-server:** :8080 is SG-gated on the same allowlist (`main.tf:111-117`); RDP gets the identical treatment, so an operator inside the VPC (or whose CIDR is allowlisted) reaches RDP directly, exactly like code-server.
3. **SSM path (RDP-10) is orthogonal and always works:** `AWS-StartPortForwardingSession` tunnels to the instance's *local* port over the SSM data channel — it does **not** traverse the security group. So an off-VPC operator with no allowlisted CIDR still connects via `./run devbox-port-forward 3389`. The SG gate and the SSM path are complementary, not exclusive. The default allowlist `["10.0.0.0/8"]` (`variables.tf:65`) means the out-of-box posture is "RFC1918-only" — appropriately closed.
4. **No security regression:** this exactly mirrors the existing, Phase-2-approved posture for :8080/:6080. We are swapping one allowlist-gated port (6080) for another (3389). The `allow_open_ingress` escape hatch and the empty-list refusal validation (`variables.tf:68-71`) continue to apply unchanged.

If the planner or operator later wants RDP to be **SSM-only** (more closed), they set `allowed_web_cidrs = []` + `allow_open_ingress = true` (the documented Pattern 5 / Example 3 posture in `variables.tf:82`) and rely solely on `./run devbox-port-forward 3389`. That is a per-operator runtime choice — the *code* should ship the SG-gated ingress per RDP-09.

## Host firewall (firewalld) — already handled in the default build; one edge case

- The hardening role **disables all CIS host-firewall rules** (`hardening/defaults/main.yml:4-13`, rules `3_4_1_1`…`3_4_2_7` = false): "EC2 security groups provide perimeter security." `[CITED]`
- `firewalld-docker-fix.yml` sets the default firewalld zone to `docker` (target=ACCEPT) when the `containers` layer is on (default build: `layer_config.yml` containers implied; the workaround runs as a top-level import). This makes the host firewall **permissive** — :3389 is reachable host-side with no extra rule, identically to how :6080/:8080 work today. `[CITED: ansible/firewalld-docker-fix.yml:53-86]`
- **Edge case (flagged by Phase 11, 11-VERIFICATION.md:66):** if an operator bakes with `containers: false` AND `desktop/xrdp: true`, the stock `public` zone would drop 3389. The 11-03 SUMMARY (line 142) explicitly assigns "firewalld host allow for `:3389`" to **Phase 12**. **Recommendation:** add a small, idempotent firewalld `--add-port=3389/tcp` task **in the xrdp role** (not the desktop role being gutted), guarded so it no-ops when firewalld is absent — OR explicitly accept the default-build coverage and document the `containers:false` caveat. Given KISS and that the default build is permissive, the **minimum** for RDP-09/RDP-14 is the SG; the host-firewall task is a robustness nicety. **Flag as a planner decision** — call it RDP-09-adjacent, low-risk, ~5 lines.

## RDP-12 Workaround Revert — Exact Steps

Commit `29de35b` confirmed via `git show --stat 29de35b`:
```
fix(desktop): inject fixed VNC username into noVNC client (VeNCrypt Plain)
 ansible/novnc-plain-username-fix.yml | 86 ++++++++++++++++++++++++++++++++++++
 ansible/playbook.yml                 |  6 +++
```
Author Quantum Koala, 2026-06-15 11:25. `[VERIFIED: git show --stat 29de35b]`

**Revert (clean, per the "kludge in its own named playbook" convention in reverse):**
1. `git rm ansible/novnc-plain-username-fix.yml` (delete the 86-LOC file — P1).
2. Remove `playbook.yml:118-122` — the FIXME comment block + `- import_playbook: novnc-plain-username-fix.yml` (P2). Leave the `firewalld-docker-fix.yml` import (lines 113-116) intact.

This is the entire RDP-12 surface — the workaround touched only those two files. No other consumer references it.

## Hook / Invariant / Grep-Gate Interactions

### `no-changeme` pre-commit hook (`.pre-commit-config.yaml:43`)
The hook runs `git grep -nIE "changeme" -- ":!*.md" ":!.planning/**" ":!.pre-commit-config.yaml"` and `exit 1` if it matches. **Reproduced: it currently matches THREE lines** (all `... != "changeme"` asserts — the *opposite* of a weak default):
- `ansible/roles/desktop/tasks/main.yml:7` → **REMOVED by D1** (this assert block is deleted)
- `ansible/roles/secrets/tasks/generate.yml:21` → KEPT (code-server assert; surviving)
- `ansible/roles/secrets/tasks/generate.yml:31` → KEPT (vnc/RDP-password assert; surviving)

**Interaction:** This is a **pre-existing false positive** (the hook's regex matches the literal `changeme` even inside `!= "changeme"`). It is unrelated to Phase 12 *per se*, but Phase 12's D1 deletion **removes one of the three matches**. This does NOT fix the hook (two matches remain) — but the planner should be aware that:
  - Removing D1 reduces, but does not eliminate, the false positives. Do not let a verifier flag "the no-changeme hook still fails" as a Phase-12 regression — it was already failing/false-positive before, and the two remaining matches are legitimate `!= "changeme"` guards on the surviving secrets role.
  - **Out of scope for this phase** (CLAUDE.md §8 lists the `changeme` invariant; the *intent* is "no weak `changeme` *default*", which these asserts honor). Note it as a pre-existing wart in the research; do not expand scope to "fix the hook regex" unless the planner explicitly wants a drive-by.

### `grep-gates` (CI `.github/workflows/ci.yml:171-246` + pre-commit `:96`)
Reviewed all 10 invariants. **None reference 6080 / novnc / vnc / tigervnc.** The relevant ones for Phase 12:
- **#9 hardening-is-last** (`ci.yml:234`): Phase 12 does NOT add/move roles — it edits within the desktop/secrets roles and deletes a *playbook import* (not a role). The role order in `playbook.yml` is untouched (xrdp before hardening, hardening last). **No interaction.** `[CITED: ci.yml:231-237]`
- **#8 no-`make`-targets** (`ci.yml:226`): editing `./run`/scripts/CLAUDE.md must not introduce a `make <target>` string. Trivially satisfied. `[CITED]`
- **#7 action SHA-pin**, **#1-6 REP invariants**, **#10 no-.mise.toml**: untouched by Phase 12.

**`.gitlab-ci.yml:239` `bridgecrew/checkov:3.2.527@sha256:22b308dd96e158b446c6080d19...`** — the `6080` is a coincidental substring of the image digest, NOT a noVNC reference. Do not touch. `[VERIFIED: grep context inspection]`

### CLAUDE.md §8 invariants (`CLAUDE.md:204-218`)
- The `changeme` invariant (line 204) — see no-changeme analysis above; no change needed.
- The CIS-2.2.1 X-server deviation (line 210-218) — **unaffected**; xrdp still needs Xorg, removing VNC does not change the X-server requirement. KEEP.
- hardening-last (the §8 grep-gate contract) — unaffected.
- **No §8 invariant references VNC/noVNC.** No invariant edits required.

## Runtime State Inventory

> This is a removal/cleanup phase touching baked-AMI artifacts + live SSM params + an SG. Runtime state matters.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data (SSM params) | `/devbox/<user>/vnc-password` SecureString — **IS the RDP password**, not VNC orphan. `/devbox/<user>/code-server-password` — unrelated, survives. | **KEEP both.** No data migration. Re-label human surfaces only. A rename would create an orphan (old AMIs read old key) — do NOT rename. |
| Live service config | vncserver.service + novnc.service are **enabled in the AMI** (`desktop/tasks/main.yml:85-89, 197-202`). On instances launched from a *future* (post-Phase-12) AMI they won't exist — clean. On instances still running the *current* AMI they're live until rebake. | No live-instance migration needed: the fix is "rebake + redeploy" (RDP-14 UAT does this). The removal is in the image source; existing instances are replaced, not patched. |
| OS-registered state | systemd units `vncserver.service`, `novnc.service` enabled at bake. The secrets-bootstrap oneshot restarts them by name (`bootstrap.sh.j2:66`). | Remove the units (D7/D10) AND fix the bootstrap restart loop (S6) so it does not name dead units. The bootstrap is tolerant (`list-unit-files` guard) so a stale name won't crash boot — but it IS "dead VNC config" (RDP-11 violation), so fix it. |
| Secrets / env vars | `desktop_vnc_password` Ansible fact (generated in secrets role) — survives as the RDP password (KEEP name to avoid rename cascade). No `.env`/SOPS keys involved. | None (KEEP fact name). Optionally re-label comments. |
| Build artifacts / installed packages | `/usr/local/share/noVNC/` (tarball extract), `/etc/novnc/` (cert dir), `~/.vnc/` (config dir), pip `websockify`, `tigervnc-server` rpm, `/etc/pam.d/vnc`, `/home/ec2-user/.vnc/xstartup` — all baked into the AMI by the current desktop role. | All disappear from the **next** bake once the role tasks are removed (they were created by tasks D3/D5/D6/D9). No explicit "absent" cleanup task needed — a fresh AMI simply never creates them. (If the planner wants belt-and-braces on a rebake-over-old-instance, that's out of scope: the model is rebake→replace, not in-place patch.) |

**The canonical question — after every repo file is updated, what runtime systems still have VNC cached/registered?** Answer: only instances still running a *pre-Phase-12 AMI*. Those are decommissioned by the normal rebake+`tf-apply` cycle (RDP-14 does exactly this). There is **no separate data-migration task** — the cleanup is purely source-side, realized on next bake. The one functional runtime edit is the bootstrap restart loop (S6).

## Common Pitfalls

### Pitfall 1: Deleting the shared GNOME/tigervnc dnf task
**What goes wrong:** Treating `desktop/tasks/main.yml:21-33` as "the VNC install task" and deleting it — which also removes gnome-shell, gnome-session, fonts, mesa → broken desktop, broken RDP.
**Why:** tigervnc-server is one line item in a 6-package shared list.
**How to avoid:** Surgically remove **only** the `- tigervnc-server` line (D2). Verify the other five list items remain.
**Warning sign:** A diff that removes more than one line from the `Install additional desktop packages` task.

### Pitfall 2: Deleting the vnc-password SSM param / generation as an "orphan"
**What goes wrong:** Concluding `vnc-password` is VNC-only and removing its generation/publish → the RDP login password vanishes → RDP-14 UAT fails with "Access denied".
**Why:** The param name is misleading; it is the RDP/PAM password (locked credential model).
**How to avoid:** KEEP all of S1-S5; re-label only. The vnc-password orphan section above is the authority.
**Warning sign:** A plan task titled "remove vnc-password generation" or "delete ssm_vnc_password_param".

### Pitfall 3: Leaving dead unit names in the bootstrap restart loop
**What goes wrong:** Removing vncserver/novnc units (D7/D10) but leaving `bootstrap.sh.j2:66` naming them → "dead VNC config in the image" (RDP-11 violation) even though it won't crash (guarded).
**How to avoid:** Edit the restart loop (S6) to `code-server.service xrdp.service xrdp-sesman.service`.
**Warning sign:** `git grep -n 'vncserver\|novnc' ansible/` returns hits after the removal plan executes.

### Pitfall 4: Forgetting the two shell scripts behind `./run start`/`status`
**What goes wrong:** Editing `./run` help but missing `scripts/devbox-start.sh:70` and `scripts/devbox-status.sh:54,61`, which print noVNC :6080 to the operator via `cmd_start`/`cmd_status`.
**How to avoid:** Inventory items R7-R9. These are *separate files* delegated to by `./run`.
**Warning sign:** `grep -rn 6080 scripts/` returns hits after the plan.

### Pitfall 5: Adding 3389 as a new role insertion / breaking hardening-last
**What goes wrong:** If the host-firewall :3389 task is added as a *new role* placed after hardening, it trips grep-gate #9.
**How to avoid:** If adding the (optional) firewalld 3389 task, put it **inside the existing xrdp role** (which is already before hardening), not as a new trailing role/import.

### Pitfall 6: "no dead VNC config" verification — completeness grep
**What goes wrong:** Declaring RDP-11 done while a stray `vnc`/`6080`/`novnc`/`SecurityTypes`/`tigervnc` reference remains.
**How to avoid:** Final verification grep (see Validation/verify steps below). The known-acceptable residuals are: the two `!= "changeme"` asserts in the surviving secrets role, the `vnc-password` SSM path (intentional), and the coincidental checkov digest in `.gitlab-ci.yml:239`.

## Code Examples

### T2 — :3389 ingress block (mirror of the :8080 block at main.tf:111-117)
```hcl
# Source: existing pattern at terraform/main.tf:111-117 (the :8080 block)
ingress {
  description = "RDP (xrdp/TLS) restricted to operator CIDR allowlist"
  from_port   = 3389
  to_port     = 3389
  protocol    = "tcp"
  cidr_blocks = var.allowed_web_cidrs
}
```

### S6 — bootstrap restart loop fix (devbox-secrets-bootstrap.sh.j2:66)
```bash
# Before:  for svc in code-server.service vncserver.service novnc.service; do
# After (xrdp replaces vnc/novnc so a password rotation restarts the RDP path):
for svc in code-server.service xrdp.service xrdp-sesman.service; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
        systemctl restart "$svc" || echo "WARN: failed to restart $svc" >&2
    fi
done
```

### R1 verification — no `./run` code change needed for 3389
```bash
# cmd_devbox_port_forward (run:400-409) parses any numeric PORT or REMOTE:LOCAL.
# Proof it already works:
./run devbox-port-forward 3389          # 3389 -> localhost:3389
./run devbox-port-forward 3389:13389    # remote 3389 -> localhost:13389
# Only the help-text comments (run:392-394, 516-518) need editing.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| noVNC :6080 browser desktop (VeNCrypt Plain + username-injection hack) | Native RDP client → xrdp :3389 (TLS, Xorg backend, PAM) | v3.2 (Phases 10-12) | Full-length PAM password auth (no 8-char DES cap); no browser gateway |
| tigervnc-server + websockify + noVNC tarball | xrdp + xorgxrdp from pinned source | Phase 10-11 | Airgap-safe, sha256-pinned build |
| `/etc/pam.d/vnc` | `/etc/pam.d/xrdp-sesman` → password-auth | Phase 11 | Same CIS PAM stack, different service file |

**Deprecated/removed by this phase:** vncserver.service, novnc.service, `/etc/pam.d/vnc`, `~/.vnc/xstartup`, `/usr/local/share/noVNC`, `/etc/novnc`, tigervnc-server, websockify, the noVNC username-injection workaround, the :6080 SG ingress.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | D4 (bake-time `user: password=desktop_vnc_password`) is redundant because the boot bootstrap re-applies the same password via chpasswd before first RDP login. | Inventory D4 | If the bootstrap somehow doesn't run before an RDP attempt, the ec2-user password could be unset between bake and first boot. Mitigation: keep D4 but reword its comment (safe fallback). Recommend the planner confirm bootstrap-before-login ordering or keep D4. |
| A2 | Removing the desktop role's `reload systemd` handler is safe because no surviving desktop task notifies it after D7/D10 removal. | Inventory D17 | If a kept task still notifies it, deleting the handler breaks the play. Mitigation: verify `grep notify ansible/roles/desktop/` after edits; only delete if zero notifiers remain. |
| A3 | Default build (`containers: true`) makes the host firewalld permissive (docker zone) so :3389 needs no host-firewall task for RDP-14. | Host firewall section | If a future operator bakes `containers:false`, host firewalld drops :3389. Mitigation: add the optional xrdp-role firewalld 3389 task, or document the caveat. Flagged as planner decision. |
| A4 | TCP-only :3389 SG ingress is sufficient (no UDP). | T2 note | xrdp's TLS path uses TCP; UDP 3389 is an optimization, not required. LOW risk. |
| A5 | The `vnc-password` SSM param should be retained un-renamed. | vnc-password section | Discretionary. If the planner/operator insists on a rename, it must be atomic across 4+ consumers. No correctness risk either way. |

## Open Questions

1. **Should the host-firewall :3389 task be added (xrdp role) or deferred?**
   - Known: default build is permissive (docker zone); 11-03 SUMMARY assigns "firewalld :3389" to Phase 12.
   - Unclear: whether the project wants the `containers:false` edge case covered now.
   - Recommendation: add a ~5-line idempotent `firewall-cmd --add-port=3389/tcp` task **in the xrdp role** guarded on firewalld presence; it's cheap robustness and matches the 11-03 assignment. If the planner prefers minimal scope, document the caveat instead.

2. **Delete D4 (bake-time password set) or keep with reworded comment?**
   - Recommendation: KEEP with a reworded comment (drop "TigerVNC"), since the bootstrap is the authoritative runtime setter but a bake-time fallback is harmless and de-risks A1. (Either is defensible; KEEP is the conservative call.)

3. **Rename `ssm_vnc_password_param` output key / SSM path?**
   - Recommendation: NO (orphan risk, zero benefit). Re-label descriptions only.

## Environment Availability

> This phase ships code/IaC edits + Ansible removals. The *implementation* (writing files, terraform fmt/validate, ansible-lint) needs no live AWS. The *verification* of RDP-09/RDP-14 needs a live bake — but that is the RDP-14 milestone-close gate, explicitly NOT a Phase-12 implementation task.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `tofu` (OpenTofu) | terraform fmt/validate of SG edits | Assumed (CLAUDE.md §2 floor ≥1.10) | — | `terraform` (drift per CLAUDE.md) |
| `ansible-lint` | desktop/secrets/playbook edits lint | Assumed (CLAUDE.md §2 floor ≥26) | — | skip lint; CI authoritative |
| `shellcheck` | `./run`/scripts edits | Assumed (CLAUDE.md §2 floor ≥0.10) | — | CI authoritative |
| `pre-commit` | grep-gates / no-changeme local run | Assumed (CLAUDE.md §2) | — | CI authoritative |
| AWS creds + live EC2 | RDP-14 UAT only (NOT Phase-12 impl) | N/A at plan time | — | RDP-14 is the human-UAT gate (`11-HUMAN-UAT.md`); recorded before milestone close |

**Missing dependencies with no fallback:** none for implementation. RDP-14's live AWS is a deliberate post-implementation gate, not a blocker for writing the Phase-12 changes.

## Validation Architecture

> `workflow.nyquist_validation` is **false** in `.planning/config.json`. Per the GSD protocol this section is normally skipped. Included below is a **lightweight verification checklist** (not a test framework) because this is a high-risk irreversible-removal phase and the planner needs concrete "prove removal is complete + safe" gates.

### Removal-completeness greps (run after Wave B)
```bash
# 1. No VNC/noVNC functional artifacts remain in ansible (allow the 2 secrets asserts + vnc-password path):
git grep -nE 'tigervnc|vncserver|novnc|/etc/pam\.d/vnc|SecurityTypes|6080|5901|websockify' -- ansible/ \
  | grep -vE 'vnc-password|secrets_ssm_vnc_param|!= "changeme"'
#   Expected: empty (or only intentional vnc-password/RDP-comment references).

# 2. No :6080 / noVNC in terraform, run, scripts, CLAUDE.md:
git grep -nE '6080|noVNC|novnc' -- terraform/ run scripts/ CLAUDE.md
#   Expected: empty.

# 3. The workaround file is gone and unimported:
test ! -f ansible/novnc-plain-username-fix.yml && ! git grep -q novnc-plain-username-fix ansible/playbook.yml && echo OK

# 4. :3389 ingress present, gated on allowed_web_cidrs:
grep -A5 'from_port   = 3389' terraform/main.tf | grep -q 'cidr_blocks = var.allowed_web_cidrs' && echo OK
```

### Safety / invariant gates (run after all waves)
```bash
# 5. hardening still last (grep-gate #9):
[ "$(grep -E '^[[:space:]]*-[[:space:]]*role:' ansible/playbook.yml | tail -1 | grep -c 'role:[[:space:]]*hardening')" -eq 1 ] && echo OK

# 6. xrdp role untouched / still has Xorg backend (removal didn't bleed into xrdp):
grep -q 'param=/usr/libexec/Xorg' ansible/roles/xrdp/templates/sesman.ini.j2 && echo OK

# 7. The RDP password param/path still exists end-to-end:
git grep -q '/devbox/.*/vnc-password\|secrets_ssm_vnc_param' run terraform/outputs.tf ansible/ && echo OK

# 8. GNOME packages survive the tigervnc line removal:
grep -A12 'Install additional desktop packages' ansible/roles/desktop/tasks/main.yml | grep -q gnome-shell && \
grep -A12 'Install additional desktop packages' ansible/roles/desktop/tasks/main.yml | grep -q mesa-dri-drivers && \
! grep -A12 'Install additional desktop packages' ansible/roles/desktop/tasks/main.yml | grep -q tigervnc && echo OK

# 9. terraform validate + ansible-lint + shellcheck + pre-commit (CI is authoritative):
(cd terraform && tofu fmt -check && tofu validate)
ansible-lint ansible/playbook.yml
shellcheck run scripts/devbox-start.sh scripts/devbox-status.sh
```

### Phase gate
All greps return their expected (empty / OK) result; `tofu validate` + `ansible-lint` + `shellcheck` pass; then `/gsd:verify-work`. RDP-14 live UAT is recorded separately at milestone close (`11-HUMAN-UAT.md`).

## Security Domain

`security_enforcement` not set to false → enabled. This is an infra/removal phase; relevant controls:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | Perimeter = EC2 SG (allowlist-gated :3389) + SSM-first (no public :22). Unchanged posture; swap :6080→:3389. |
| V2 Authentication | yes | RDP auth via PAM `password-auth` (CIS stack: pwquality, faillock) — delivered Phase 11; the password (vnc-password SSM SecureString) is retained. |
| V6 Cryptography | yes | RDP TLS (self-signed, RSA-2048+sha256) — Phase 11; SSM SecureString KMS-encrypted params — unchanged. Removing noVNC drops its separate self-signed cert (`/etc/novnc`) — no loss. |
| V9 Communications | yes | :3389 gated on allowed_web_cidrs (not 0.0.0.0/0); SSM channel for off-VPC. Empty-list refusal validation (`variables.tf:68-71`) preserved. |

| Threat Pattern | STRIDE | Mitigation |
|---------|--------|---------------------|
| Opening :3389 to 0.0.0.0/0 | Spoofing/Info-disclosure | Gate on `var.allowed_web_cidrs` (default RFC1918); `allow_open_ingress` validation prevents accidental empty-list open |
| Orphaned vnc-password param removal → RDP lockout | DoS | KEEP the param (it's the RDP password); proven via credential-model chain |
| Dead VNC service left enabled | Attack surface | RDP-11 removes the units + the bootstrap restart-loop reference (S6) |
| Stale noVNC cert/install on disk | Info-disclosure | D9 removes `/usr/local/share/noVNC` + `/etc/novnc` from the bake |

## Sources

### Primary (HIGH confidence — repo-internal, read directly)
- `ansible/roles/desktop/tasks/main.yml`, `defaults/main.yml`, `handlers/main.yml`, `templates/{vncserver.service,novnc.service,xstartup}.j2` — the VNC/noVNC install
- `ansible/roles/secrets/tasks/{generate,publish,main,install-oneshot}.yml`, `defaults/main.yml`, `templates/devbox-secrets-bootstrap.sh.j2` — the credential pipeline
- `ansible/roles/xrdp/templates/sesman.ini.j2`, `defaults/main.yml`, `files/xrdp-sesman.pam` — proof of Xorg backend / no Xvnc
- `ansible/playbook.yml`, `ansible/novnc-plain-username-fix.yml`, `ansible/firewalld-docker-fix.yml` — imports + workaround
- `terraform/main.tf`, `variables.tf`, `outputs.tf` — SG, vars, outputs
- `run`, `scripts/devbox-start.sh`, `scripts/devbox-status.sh` — operator surface
- `CLAUDE.md` — operator docs + §8 invariants
- `.pre-commit-config.yaml`, `.github/workflows/ci.yml`, `.gitlab-ci.yml` — hooks + grep-gates
- `.planning/REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `phases/11-.../11-VERIFICATION.md`, `11-HUMAN-UAT.md`, `11-03-SUMMARY.md`
- `git show --stat 29de35b` — workaround commit provenance

### Secondary / Tertiary
- None. No external sources needed; this phase is entirely repo-internal removal/edit work.

## Metadata

**Confidence breakdown:**
- Removal inventory: HIGH — every artifact located by direct read + grep, with file:line.
- Removal-safety proof: HIGH — 7 independent checks, all repo-verified (xrdp Xorg backend, GNOME independence, separate PAM file).
- vnc-password orphan decision: HIGH — locked credential model traced end-to-end (REQUIREMENTS → bootstrap chpasswd → secrets-show → RDP-14 UAT).
- Network recommendation: HIGH — RDP-09 text is explicit; SG-gated mirrors approved :8080 pattern.
- Hook interactions: HIGH — no-changeme false-positive reproduced; grep-gates reviewed line-by-line; 6080-in-checkov-digest confirmed coincidental.
- Host-firewall edge case: MEDIUM — default-build coverage is solid; the `containers:false` task is a flagged planner decision (A3).

**Research date:** 2026-06-15
**Valid until:** 2026-07-15 (stable — repo-internal; only invalidated by intervening edits to the named files)
