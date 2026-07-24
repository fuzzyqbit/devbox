---
phase: 11-service-config-pam-session-bake-verification
verified: 2026-06-15T00:00:00Z
status: human_needed
status_note: "BAKE-CONFIG CLEAR after 3 adversarial rounds. R1 (11-01): static 7/7 but adversarial found 4 CRITICAL + decision. R2 (11-02): decision (a) + closed all 4 CRITICAL/3 HIGH/3 RISK. R2 re-review found 2 more bake-fixable (xorg.conf, SELinux fcontext) + fragilities → R3 (11-03) closed them (xorg.conf vendored+asserted at /etc/X11/xrdp/xorg.conf, xrdp_exec_t fcontext, tsusers determinism, gnome-session). FINAL adversarial review = BAKE-CONFIG CLEAR; its one HIGH assert-gap (input-module stats) closed in 2236f0e. NO remaining bake-fixable green-but-broken blocker. Only RDP-14 live UAT residuals remain (AVC-clean enforcing boot, FIPS TLS handshake, firewalld :3389, GNOME render) — they REQUIRE ./run build + a live instance. Phase stays human_needed until RDP-14 passes."
score: bake-config CLEAR (3 adversarial rounds, 14 findings closed); 4 residuals are live-UAT-only (RDP-14)
overrides_applied: 0
human_verification:
  - test: "Live RDP login as ec2-user — connect from a native RDP client to the baked instance on :3389, authenticate with the password from `./run secrets-show`, and confirm the GNOME desktop renders"
    expected: "Desktop renders; no auth failure; no black screen; no color-manager auth popup"
    why_human: "Requires a baked AMI on a live EC2 instance with SG :3389 open (Phase 12). Cannot be verified at bake-config time. This is RDP-14, explicitly deferred to Phase-12-close UAT per ROADMAP.md."
---

# Phase 11: Service Config, PAM, Session + Bake Verification — Verification Report

**Phase Goal:** xrdp runs as an enabled, TLS-protected systemd service on `:3389`, authenticates `ec2-user` against the CIS-hardened PAM stack, launches the desktop session via the Xorg (xorgxrdp) backend, and a bake-time assertion proves the binaries/modules are present and the services are enabled — all with the `xrdp` role inserted before `hardening`.
**Verified:** 2026-06-15
**Status:** FAILED — static config verified 7/7, but adversarial runtime review found CRITICAL blockers (see addendum). Blocked on an architecture decision.
**Re-verification:** No — initial verification

---

## ⚠ ADVERSARIAL REVIEW ADDENDUM (2026-06-15, opus) — supersedes the "passed" verdict

The gsd-verifier confirmed the static config matches the plan (TLS, sesman keys, PAM, systemd paths, hardening-last). An independent adversarial review then found the phase, as built, **will not serve a working RDP session** — the bake is green but broken. Verified against the repo:

**CRITICAL (confirmed real):**
1. **No X server installed.** `sesman.ini` uses `param=/usr/libexec/Xorg`, but NO role installs `xorg-x11-server-Xorg`. Existing VNC survives only because it uses Xvnc (self-contained). xorgxrdp is the first thing needing real Xorg.
2. **CIS 2.2.1 deletes the X server.** `amzn2023cis_rule_2_2_1: true` (default, `ansible/roles/AMAZON2023-CIS/tasks/section_2/cis_2.2.x.yml:3`) removes `xorg-x11-server-common`; `hardening` runs AFTER xrdp; `xorg-x11-server-Xorg` depends on `-common` → X server gone at runtime.
3. **Layer gating bug.** `xrdp` gated on `layers.xrdp` ALONE (`playbook.yml:59`); `secrets` (sets ec2-user password) + GNOME (`desktop`) gate on `layers.desktop`. `xrdp=true, desktop=false` → no GNOME, no password, RDP dead. Fix: gate `when: layers.xrdp and layers.desktop`.
4. **RDP-13 assert is blind to all of the above** — stats only the xrdp binary/module/inis, never `/usr/libexec/Xorg`, cert/key, startwm, PAM. Bake passes while broken.

**HIGH:** SELinux-enforcing AVCs on unlabeled `/usr/local` binaries + `/etc/xrdp/key.pem` (restorecon only covered the xorg module dir); FIPS mode (hardening) may reject the rsa:2048/no-SAN self-signed cert in the RDP TLS handshake; sesman unit dual-enabled with `BindsTo`/`StopWhenUnneeded` can race at boot.

**RISK:** `.pkla` polkit format is ignored on AL2023 polkit 121+ (need a `.rules` file); `dbus-x11` (dbus-launch) may not be installed; `pam_loginuid.so required` may block the sesman session.

**De-risked (correct):** sesman `-config xrdp/xorg.conf` relative path; daemon_reload ordering; cert perms/idempotency (key 0600, xrdp runs as root).

**DECISION MADE (2026-06-15): Option (a) — keep xorgxrdp.** The xorgxrdp backend collides with CIS 2.2.1. Options were (a) keep xorgxrdp, install `xorg-x11-server-Xorg`+`dbus-x11`, set `amzn2023cis_rule_2_2_1=false`; (b) pivot to Xvnc backend; (c) reinstall X after hardening. **Operator chose (a)** — least rework, keeps Phases 10 & 11, best RDP quality; accepts one Level-2 CIS finding (rule 2.2.1) as a documented exception because this host is a desktop (X is required by purpose; NIST CM-7 "no X on a server" does not apply). The gap-closure plan must therefore implement, against the **Xorg backend**:

- **CRITICAL #1** — install `xorg-x11-server-Xorg` + `dbus-x11` in the xrdp build role.
- **CRITICAL #2** — set `amzn2023cis_rule_2_2_1: false` (CIS role default override) with an inline comment justifying the desktop exception; document it as the single accepted CIS deviation.
- **CRITICAL #3** — gate xrdp `when: layers.xrdp and layers.desktop` (needs GNOME + the secrets-role ec2-user password).
- **CRITICAL #4** — extend the RDP-13 bake assert to stat `/usr/libexec/Xorg`, `/etc/xrdp/{cert,key}.pem`, `/etc/xrdp/startwm.sh`, `/etc/pam.d/xrdp-sesman` — not just the role's own artifacts.
- **HIGH** — SELinux `restorecon` over the new X server + `/usr/local` (xrdp binaries) + `/etc/xrdp`; verify the self-signed cert survives FIPS in the RDP TLS handshake (add SAN, confirm key algo/size); resolve the sesman-unit dual-enable `BindsTo`/`StopWhenUnneeded` boot race.
- **RISK** — replace the `.pkla` colord polkit with a `.rules` file (AL2023 polkit 121+ ignores `.pkla`); confirm `dbus-x11` present (covered by #1); evaluate `pam_loginuid.so required` in the sesman PAM stack.

Next: `/gsd:plan-phase 11 --gaps`.

---

## ⚠ ADVERSARIAL REVIEW ADDENDUM #2 (2026-06-16, opus) — after gap-closure 11-02

Plan 11-02 closed all 10 round-1 findings (verified: X server installed, CIS 2.2.1 disabled at hardening/defaults, layer gate fixed, RDP-13 extended, post-hardening Xorg guard, FIPS cert, SELinux relabel, sesman race, polkit .rules, pam_loginuid). A fresh adversarial review of the **committed** code then found the bake can STILL go green while no RDP session starts:

**CRITICAL (bake-fixable now):**
1. **`/etc/xrdp/xorg.conf` is referenced but never verified.** `sesman.ini.j2` passes `param=xrdp/xorg.conf` (→ `/etc/xrdp/xorg.conf`), the Xorg config that loads the xrdpdev/xrdpkeyb/xrdpmouse driver modules. Nothing templates/copies it (assumed from `make install`) and the RDP-13 assert does NOT stat it. If absent → `/usr/libexec/Xorg -config xrdp/xorg.conf` exits non-zero, no X session, bake green. **Fix:** add `/etc/xrdp/xorg.conf` to the RDP-13 stat+assert; template+install it if `make install` doesn't place it under `--prefix=/usr/local`/`--sysconfdir=/etc`.
2. **SELinux: relabel ≠ policy for source-built daemons.** `restorecon` only applies EXISTING fcontext; xrdp/xrdp-sesman in `/usr/local/sbin` get `bin_t`, not `xrdp_exec_t` (no `semanage fcontext`/policy module in the repo). Under enforcing (hardening sets it; reboot enters it), the daemons run `init_t` and the sesman→Xorg exec + socket may hit AVC denials that silently kill the session while `xrdp.service` stays active. **Fix (bake):** `semanage fcontext -a -t xrdp_exec_t '/usr/local/sbin/(xrdp|xrdp-sesman)'` (+ libs) BEFORE restorecon. **Residual:** the actual AVC only appears at first boot under enforcing → confirmable only at RDP-14.

**HIGH (fragile, fix or document):**
- `TerminalServerUsers=tsusers` / `tsadmins` groups are never created and ec2-user is in neither; login works ONLY because `AlwaysGroupCheck=false` skips the gate when the group is absent. If anything ever creates `tsusers`, every login is silently denied. **Fix:** make login deterministic — either create `tsusers` + add ec2-user, or keep current + a bake assert that the group is absent + a comment.

**RISK (live-UAT only — needs ./run build):**
- `gnome-session` is assumed transitive via `@Desktop`; not installed by name → black-screen risk. **Fix (cheap):** add `gnome-session` to the desktop role dnf list.
- FIPS handshake depth: cert is well-formed (SAN/sha256/RSA-2048, generated pre-FIPS — idempotent on fresh bake) but the runtime TLS handshake under the kernel FIPS provider is unproven at bake.
- firewalld 3389: not dropped in the default build only because `containers: true` sets the docker zone (ACCEPT). If an operator runs `containers: false` with `desktop/xrdp: true`, the stock `public` zone drops 3389/8080/6080. **Fix (robust):** explicit `firewall-cmd --add-port=3389/tcp`.

**Confirmed mitigated:** host firewall (default build), other CIS rules (no X/GNOME/dbus/colord/faillock collision beyond 2.2.1), dnf ordering (Xorg installed before relabel), the W1 post-hardening guard (sound), cert idempotency (sound).

Round-3 gap-closure (11-03) implements the bake-fixable items (xorg.conf assert+template, semanage fcontext, tsusers determinism, gnome-session, firewalld 3389). The deep residuals (SELinux-under-enforcing, FIPS handshake, GNOME render) are signed off only by the live RDP-14 UAT.

---

## ✅ FINAL ADVERSARIAL VERDICT (2026-06-16, opus) — BAKE-CONFIG CLEAR

Round-3 (11-03, commits 3e0de34/d4a4eff) closed the ADDENDUM #2 bake-fixable findings. A final adversarial review of the **complete committed phase** (11-01 + 11-02 + 11-03) confirmed all four R3 fixes are correct in code and introduced no regression:

- **xorg.conf** — `files/xorg.conf` is byte-equivalent to upstream xorgxrdp 0.10.5; installed to `/etc/X11/xrdp/xorg.conf` (the path Xorg's relative `param=xrdp/xorg.conf` resolves to as root); stat-asserted in RDP-13. Vendoring matches what `make install` writes, so it cannot break a working session.
- **SELinux fcontext** — `semanage fcontext -a -t xrdp_exec_t '/usr/local/sbin/xrdp(-sesman)?'` runs idempotently BEFORE restorecon (verified line order); `semanage -a` persists to the policy store and survives the hardening reboot; `policycoreutils-python-utils` provides semanage (AL2023 dnf).
- **tsusers** — group created + ec2-user appended (`append: true`); positive login gating; runs after ec2-user exists.
- **gnome-session** — installed by name in the desktop role (AL2023 core); startwm.sh execs it directly (no gdm dependency).
- No CIS package-purge collision (only 2.2.1 touches X, disabled + W1 post-hardening guard); no-GPU DRMDevice falls back to software cleanly (xorgxrdp continues with glamor=FALSE; startwm forces llvmpipe); dead `.pkla` present but not installed.

The review's one HIGH assert-coverage gap — RDP-13 stat'd `xrdpdev_drv.so` (drivers/) but not the input modules `xrdpkeyb_drv.so`/`xrdpmouse_drv.so` (input/) the vendored xorg.conf loads — was closed in **2236f0e** (both now stat'd + asserted; bake fails loudly if a partial make install omitted them).

**No remaining BAKE-FIXABLE green-but-broken blocker.** Phase status = `human_needed`: the ONLY remaining gates are inherently live and require `./run build` + a running instance:

1. **AVC-clean boot under SELinux enforcing** — the `xrdp_exec_t` mapping + label are set at bake (permissive); the confined-domain boot is only observable live.
2. **FIPS TLS handshake** — cert is well-formed (SAN/sha256/RSA-2048); the FIPS-strict RDP handshake is live-only.
3. **firewalld :3389 ingress** — perimeter/runtime; routed to Phase 12 (SG :3389 + host firewall).
4. **Live GNOME-over-RDP render** — pam_loginuid, llvmpipe software render, colord polkit are all wired; a real interactive login is the only proof. This IS RDP-14.

**Verdict:** bake-config complete and runtime-honest. Do NOT close the phase (or the milestone) until RDP-14 (live RDP login as ec2-user → GNOME renders) is recorded. Phase 12 (network/operator surface + VNC/noVNC removal) can proceed in parallel; RDP-14 is the milestone-close gate.

---

## Commit Verification

All three commits claimed by SUMMARY.md are present and resolve correctly:

| Commit | SHA (full) | Description |
|--------|-----------|-------------|
| f30fbc7 | `f30fbc7f9e65e59681357a0ff63c32ca05b3e4df` | feat(11): xrdp.ini TLS config + sesman.ini Xorg backend + cert/ldconfig (RDP-04/05) |
| 3a80ae6 | `3a80ae67a5cc1d5e4e0fc8c68a8a1e00f63c3486` | feat(11): PAM delegation + GNOME session launcher + colord polkit (RDP-06/07) |
| e296d0b | `e296d0b5b304e5c85be6d7ea77c7d60c41e56b32` | feat(11): systemd units + enable, playbook wiring, RDP-13 bake assert (RDP-08/13) |

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | xrdp listens on :3389 with TLS (`security_layer=tls`, cert/key at `/etc/xrdp/cert.pem`/`key.pem`, `ssl_protocols`) | VERIFIED | `xrdp.ini.j2` lines 7,10,12,13,14 — `port=3389`, `security_layer=tls`, `certificate=/etc/xrdp/cert.pem`, `key_file=/etc/xrdp/key.pem`, `ssl_protocols=TLSv1.2, TLSv1.3`; cert generated in `tasks/main.yml` lines 177-184 |
| 2 | sesman.ini uses xorgxrdp (Xorg) backend via full `/usr/libexec/Xorg` path — no Xvnc | VERIFIED | `sesman.ini.j2` line 33 `param=/usr/libexec/Xorg`; comment on line 2 confirms "no Xvnc backend"; grep for `xvnc` returns no content lines |
| 3 | `/etc/pam.d/xrdp-sesman` delegates to `password-auth` (CIS PAM stack) | VERIFIED | `files/xrdp-sesman.pam` — all six lines delegate to `password-auth`; `pam_loginuid.so` + `pam_lastlog.so` present; `tasks/main.yml` line 234 copies it to `/etc/pam.d/xrdp-sesman` |
| 4 | `startwm.sh` launches GNOME Xorg session (`XDG_SESSION_TYPE=x11`); no new secret — reuses secrets-role ec2-user password | VERIFIED | `templates/startwm.sh.j2` line 8 `export XDG_SESSION_TYPE=x11`, line 14 `export GDK_BACKEND=x11`, line 20 `exec dbus-launch --exit-with-session gnome-session`; no new credential introduced |
| 5 | xrdp + xrdp-sesman enabled systemd services; ExecStart points at `/usr/local/sbin/` | VERIFIED | `files/xrdp.service` `ExecStart=/usr/local/sbin/xrdp $XRDP_OPTIONS --nodaemon`; `files/xrdp-sesman.service` `ExecStart=/usr/local/sbin/xrdp-sesman $SESMAN_OPTIONS --nodaemon`; `tasks/main.yml` lines 289-299 `enabled: true, daemon_reload: true` for both services |
| 6 | `- role: xrdp` wired in `ansible/playbook.yml` strictly before `- role: hardening` (hardening-stays-last invariant preserved) | VERIFIED | `playbook.yml` line 59 `- role: xrdp`, line 63 `- role: hardening`; hardening-last grep-gate returns `1` |
| 7 | Bake-time RDP-13 assertion fails the build if binary, xorgxrdp module, config files, or enabled services are absent | VERIFIED | `tasks/main.yml` lines 301-355 — stats `/usr/local/sbin/xrdp`, `/usr/lib64/xorg/modules/drivers/xrdpdev_drv.so`, `/etc/xrdp/xrdp.ini`, `/etc/xrdp/sesman.ini`; asserts all `.stat.exists`; runs `systemctl is-enabled xrdp xrdp-sesman` and asserts `rc == 0`; `failed_when: false` on the command + assert pattern ensures bake halts on any absence |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Evidence |
|----------|----------|--------|----------|
| `ansible/roles/xrdp/templates/xrdp.ini.j2` | TLS xrdp.ini (`security_layer=tls`, port 3389, cert/key, ssl_protocols, autorun=Xorg) | VERIFIED | File exists, 43 lines, all load-bearing keys present (lines 7,10,12-15) |
| `ansible/roles/xrdp/templates/sesman.ini.j2` | sesman.ini with `[Xorg]` backend, full `/usr/libexec/Xorg` path, no Xvnc | VERIFIED | File exists, 40 lines; `param=/usr/libexec/Xorg` at line 33; `AllowRootLogin=false`; `MaxSessions=1`; `DefaultWindowManager=startwm.sh` |
| `ansible/roles/xrdp/templates/startwm.sh.j2` | GNOME Xorg session launcher (`XDG_SESSION_TYPE=x11`) | VERIFIED | File exists, 21 lines; `XDG_SESSION_TYPE=x11`, `GDK_BACKEND=x11`, `dbus-launch --exit-with-session gnome-session` |
| `ansible/roles/xrdp/files/xrdp-sesman.pam` | PAM file delegating to `password-auth` | VERIFIED | File exists, 7 lines; all auth/account/session/password lines delegate to `password-auth`; `pam_loginuid.so` + `pam_lastlog.so` present |
| `ansible/roles/xrdp/files/xrdp.service` | systemd unit, ExecStart `/usr/local/sbin/xrdp` | VERIFIED | File exists; `ExecStart=/usr/local/sbin/xrdp $XRDP_OPTIONS --nodaemon`; `Requires=xrdp-sesman.service`; `WantedBy=multi-user.target` |
| `ansible/roles/xrdp/files/xrdp-sesman.service` | systemd unit, ExecStart `/usr/local/sbin/xrdp-sesman` | VERIFIED | File exists; `ExecStart=/usr/local/sbin/xrdp-sesman $SESMAN_OPTIONS --nodaemon`; `BindsTo=xrdp.service`; `WantedBy=multi-user.target` |
| `ansible/roles/xrdp/files/45-allow-colord.pkla` | colord polkit rule preventing GNOME session auth hang | VERIFIED | File exists; `[Allow colord for all users]`; `Action=org.freedesktop.color-manager.*`; all three Result keys set to `yes` |
| `ansible/roles/xrdp/handlers/main.yml` | `reload systemd` handler (`daemon_reload: true`) | VERIFIED | File exists; single handler `reload systemd` with `ansible.builtin.systemd: daemon_reload: true` |
| `ansible/roles/xrdp/tasks/main.yml` | Phase 11 block appended after Phase 10; contains `is-enabled` assert | VERIFIED | File exists, 356 lines; Phase 11 block begins at line 170 with banner comment; `systemctl is-enabled xrdp xrdp-sesman` at line 342 |
| `ansible/playbook.yml` | `- role: xrdp` wired before hardening | VERIFIED | Line 59 `- role: xrdp when: layers.xrdp | default(false)`; line 63 `- role: hardening`; hardening is the last `- role:` entry |
| `ansible/layer_config.yml` | `xrdp: true` toggle | VERIFIED | Line 22 `xrdp: true`; comment on line 21 explains the toggle |

---

### Key Link Verification

| From | To | Via | Status | Evidence |
|------|----|-----|--------|----------|
| `xrdp.ini.j2` | `/etc/xrdp/cert.pem` + `/etc/xrdp/key.pem` | `certificate=` / `key_file=` keys | WIRED | Lines 12-13 in template; cert generated by `openssl req` task in `tasks/main.yml` line 179 |
| `sesman.ini.j2` | `startwm.sh` | `DefaultWindowManager=startwm.sh` | WIRED | `sesman.ini.j2` line 7; `startwm.sh.j2` templated to `/etc/xrdp/startwm.sh` by `tasks/main.yml` line 244 |
| `playbook.yml` | `ansible/roles/xrdp` | `- role: xrdp` immediately before `- role: hardening` | WIRED | Line 59 `- role: xrdp`; line 63 `- role: hardening`; one role separates them (none) — xrdp is immediately before hardening |

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| RDP-04 | xrdp on :3389 with TLS (`security_layer`/`certificate`/`key_file`) | SATISFIED | `xrdp.ini.j2`: `port=3389`, `security_layer=tls`, `certificate=/etc/xrdp/cert.pem`, `key_file=/etc/xrdp/key.pem`, `ssl_protocols=TLSv1.2, TLSv1.3`; self-signed cert generated by tasks |
| RDP-05 | `sesman.ini` Xorg backend — no Xvnc | SATISFIED | `sesman.ini.j2` `[Xorg]` section, `param=/usr/libexec/Xorg` full path; no VNC backend section present |
| RDP-06 | `/etc/pam.d/xrdp-sesman` delegates to `password-auth` | SATISFIED | `files/xrdp-sesman.pam` — verbatim redhat PAM content; copied to target path in `tasks/main.yml` |
| RDP-07 | GNOME Xorg session reachable as ec2-user with existing secrets password; no new secret | SATISFIED (config delivered) | `startwm.sh.j2` forces `XDG_SESSION_TYPE=x11`; `GDK_BACKEND=x11`; `dbus-launch gnome-session`; no new credential introduced; live login proof is RDP-14 (Phase-12-close UAT) |
| RDP-08 | xrdp + xrdp-sesman enabled at boot; `- role: xrdp` before hardening; `layers.xrdp` toggle | SATISFIED | Units at `/usr/local/sbin/` paths; `enabled: true, daemon_reload: true` in tasks; playbook line 59 before line 63; `layer_config.yml` line 22 |
| RDP-13 | Bake assertion: binary + xorgxrdp module + ini files + service enablement | SATISFIED | `tasks/main.yml` lines 301-355; 4 stat+assert tasks + `systemctl is-enabled` assert; fails bake on any absence |

**Requirement RDP-14** (live RDP login UAT) is explicitly a milestone-close gate, not a Phase 11 deliverable, per ROADMAP.md ("tracked as a human-UAT gate that must be recorded before the milestone closes"). It is listed under Human Verification below.

---

### YAML Validity

All modified/created YAML files parse without error:

| File | Status |
|------|--------|
| `ansible/roles/xrdp/tasks/main.yml` | PASS |
| `ansible/roles/xrdp/handlers/main.yml` | PASS |
| `ansible/playbook.yml` | PASS |
| `ansible/layer_config.yml` | PASS |

---

### Hardening-Stays-Last Invariant (CLAUDE.md §8)

```
grep -E '^[[:space:]]*-[[:space:]]*role:' ansible/playbook.yml | tail -1 | grep -c 'role:[[:space:]]*hardening'
```

Result: **1** — INVARIANT PRESERVED.

The last `- role:` line in `ansible/playbook.yml` is `- role: hardening` (line 63). The `xrdp` role is at line 59, between `desktop` (line 56) and `hardening` (line 63).

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `ansible/playbook.yml` | 88, 93 | `# FIXME:` markers | INFO (pre-existing) | Both markers reference the firewalld and novnc workaround playbooks that predate Phase 11 (present before commit `e296d0b`); Phase 11 only added 4 lines to this file (the `- role: xrdp` block) and did not introduce these markers. Not a blocker. |

No debt markers (`FIXME`, `TBD`, `XXX`, `TODO`, `HACK`, `PLACEHOLDER`) exist anywhere in `ansible/roles/xrdp/` (confirmed by grep — zero matches).

No `changeme` literal in `ansible/roles/xrdp/` (confirmed — zero matches).

---

### Human Verification Required

#### 1. Live RDP Login — RDP-14 (Phase-12-close gate)

**Test:** After Phase 12 opens SG `:3389` and `./run devbox-port-forward` tunnels it, connect from a native RDP client (e.g. `mstsc`, FreeRDP, Remmina) to `localhost:3389`, authenticate as `ec2-user` with the password from `./run secrets-show`, and verify the GNOME desktop renders.

**Expected:** Desktop renders without a black screen; no auth failure ("Access denied"); no color-manager authentication popup hanging the session; `id` in a terminal shows `ec2-user`.

**Why human:** Requires a baked AMI deployed on a live EC2 instance with the Phase-12 SG `:3389` ingress configured. Cannot be verified by static code inspection or at bake-config time. Explicitly modelled in ROADMAP.md as "RDP-14 — milestone-close gate that must be recorded before the milestone closes."

---

### Gaps Summary

None. All 7 must-have truths are VERIFIED against the actual committed files. The three Phase 11 commits (`f30fbc7`, `3a80ae6`, `e296d0b`) are confirmed present in the git history. Every load-bearing configuration key, file, and wiring checked — no stubs, no placeholders, no orphaned artifacts found.

The single human-verification item (RDP-14 live RDP login) is not a Phase 11 gap — it is the Phase-12-close milestone gate, explicitly deferred in ROADMAP.md and REQUIREMENTS.md by design.

---

_Verified: 2026-06-15_
_Verifier: Claude (gsd-verifier)_
