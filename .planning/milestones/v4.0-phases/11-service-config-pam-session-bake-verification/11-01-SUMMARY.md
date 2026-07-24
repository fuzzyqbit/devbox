---
phase: 11-service-config-pam-session-bake-verification
plan: "01"
subsystem: ansible/roles/xrdp
tags: [xrdp, rdp, tls, pam, systemd, gnome, ansible, bake-assertion]
requires:
  - "Phase 10 (10-01): xrdp + xorgxrdp built/installed (/usr/local/sbin/xrdp, libxup.so, xrdpdev_drv.so)"
provides:
  - "TLS-enabled xrdp service on :3389 (config + cert)"
  - "xorgxrdp (Xorg) session backend via /usr/libexec/Xorg"
  - "PAM delegation to password-auth (CIS faillock + pwquality)"
  - "GNOME Xorg session launcher (startwm.sh) for ec2-user"
  - "enabled xrdp + xrdp-sesman systemd units"
  - "RDP-13 bake-time assertion (binary + module + ini files + service enablement)"
  - "layers.xrdp toggle; - role: xrdp wired before hardening"
affects:
  - ansible/playbook.yml
  - ansible/layer_config.yml
tech-stack:
  added: []
  patterns:
    - "self-signed openssl cert at bake (mirrors desktop role noVNC pattern)"
    - "static systemd unit files in files/ with hardcoded /usr/local/sbin exec paths"
    - "ld.so.conf.d entry + ldconfig for source-install /usr/local/lib"
    - "ansible.builtin.stat + assert + systemctl is-enabled bake gate"
key-files:
  created:
    - ansible/roles/xrdp/templates/xrdp.ini.j2
    - ansible/roles/xrdp/templates/sesman.ini.j2
    - ansible/roles/xrdp/templates/startwm.sh.j2
    - ansible/roles/xrdp/files/xrdp-sesman.pam
    - ansible/roles/xrdp/files/45-allow-colord.pkla
    - ansible/roles/xrdp/files/xrdp.service
    - ansible/roles/xrdp/files/xrdp-sesman.service
    - ansible/roles/xrdp/handlers/main.yml
  modified:
    - ansible/roles/xrdp/tasks/main.yml
    - ansible/playbook.yml
    - ansible/layer_config.yml
decisions:
  - "Dedicated layers.xrdp toggle (not reusing layers.desktop) so a future bake can decouple xrdp from GNOME."
  - "xrdp gets its OWN /etc/xrdp/cert.pem + key.pem (key 0600 root-only); does NOT reuse the noVNC cert (removed in Phase 12)."
  - "Static systemd units in files/ rather than templates — path substitution is deterministic (/usr/local prefix)."
  - "Added /etc/ld.so.conf.d/xrdp.conf + ldconfig proactively (RESEARCH Pitfall 5) since /usr/local/lib is not in the default linker path on AL2023."
metrics:
  duration: "~5 min"
  tasks_completed: 3
  files_created: 8
  files_modified: 3
  completed: 2026-06-15
---

# Phase 11 Plan 01: xrdp Service Config, PAM, Session + Bake Verification Summary

Configured the Phase-10-built xrdp into an enabled, TLS-protected systemd service on `:3389` that authenticates `ec2-user` against the CIS-hardened PAM stack and launches a GNOME Xorg session via the xorgxrdp backend — guarded by a loud bake-time assertion (RDP-13).

## What Was Built

**Task 1 — TLS config + Xorg backend (RDP-04/05)** — commit `f30fbc7`
- `templates/xrdp.ini.j2`: `[Globals]` with `port=3389`, `security_layer=tls` (no `negotiate` fallback), `crypt_level=high`, `certificate=/etc/xrdp/cert.pem`, `key_file=/etc/xrdp/key.pem`, `ssl_protocols=TLSv1.2, TLSv1.3`, `autorun=Xorg`; `[Channels]`; `[Xorg]` with literal `lib=libxup.so`.
- `templates/sesman.ini.j2`: `[Xorg]` backend with `param=/usr/libexec/Xorg` (full path — bare `Xorg` fails on AL2023), `AllowRootLogin=false`, `MaxLoginRetry=4`, `MaxSessions=1`, `DefaultWindowManager=startwm.sh`. No Xvnc backend.
- `tasks/main.yml` Phase 11 block: self-signed cert via `openssl req -x509` (`creates:` idempotent), cert/key perms (0644 / 0600 root:root), templates both ini files, `/etc/ld.so.conf.d/xrdp.conf` → `/usr/local/lib` + `ldconfig`.

**Task 2 — PAM + session + colord (RDP-06/07)** — commit `3a80ae6`
- `files/xrdp-sesman.pam`: verbatim redhat PAM stack delegating auth/account/session/password to `password-auth` (inherits faillock + pwquality); includes `pam_loginuid.so` + `pam_lastlog.so quiet`.
- `templates/startwm.sh.j2`: GNOME Xorg launcher — `XDG_SESSION_TYPE=x11` (prevents Wayland black screen), `GDK_BACKEND=x11`, `LIBGL_ALWAYS_SOFTWARE=1`/`GALLIUM_DRIVER=llvmpipe` (software rendering), `exec dbus-launch --exit-with-session gnome-session`. Mirrors the desktop role's proven `xstartup.j2`.
- `files/45-allow-colord.pkla`: polkit rule preventing the color-manager auth hang.
- `tasks/main.yml`: copy PAM → `/etc/pam.d/xrdp-sesman`, template startwm.sh → `/etc/xrdp/startwm.sh` (0755), ensure polkit dir + install the .pkla rule.

**Task 3 — systemd + wiring + bake assert (RDP-08/13)** — commit `e296d0b`
- `files/xrdp.service` + `files/xrdp-sesman.service`: units with `/usr/local/sbin/` exec paths (source-install prefix, NOT `/usr/sbin`), `Requires=`/`BindsTo=`, `WantedBy=multi-user.target`.
- `handlers/main.yml`: `reload systemd` (daemon_reload) handler.
- `tasks/main.yml`: copy both units to `/usr/lib/systemd/system/` (Pitfall 1 — make install may ship init.d instead), enable both (`enabled: true`, `daemon_reload: true` — no `started:`), then the RDP-13 assertion: stat the binary + xorgxrdp module + both ini files, assert all exist, run `systemctl is-enabled xrdp xrdp-sesman` (`failed_when: false`) and assert `rc == 0`. Fails the bake on any absence.
- `playbook.yml`: `- role: xrdp` (`when: layers.xrdp | default(false)`) inserted between `desktop` and `hardening` — **hardening stays last**.
- `layer_config.yml`: `layers.xrdp: true` (decoupled from `layers.desktop`).

## Requirement Coverage

| ID | Status | Evidence |
|----|--------|----------|
| RDP-04 | Satisfied | xrdp.ini.j2: `security_layer=tls`, cert/key paths, `ssl_protocols=TLSv1.2, TLSv1.3`, `port=3389`, `autorun=Xorg`; cert generated + perms set in tasks. |
| RDP-05 | Satisfied | sesman.ini.j2 `[Xorg]` with `param=/usr/libexec/Xorg`; no Xvnc backend. |
| RDP-06 | Satisfied | files/xrdp-sesman.pam delegates to `password-auth`; copied to `/etc/pam.d/xrdp-sesman`. |
| RDP-07 | Satisfied | startwm.sh.j2 GNOME Xorg session (no new secret — reuses the secrets-role ec2-user PAM password); colord polkit rule installed. |
| RDP-08 | Satisfied | Both units `/usr/local/sbin` exec, `enabled: true`; `- role: xrdp` before `hardening`; `layers.xrdp` toggle added. |
| RDP-13 | Satisfied | Bake assertion stats binary + xorgxrdp module + both ini files, then asserts `systemctl is-enabled xrdp xrdp-sesman` rc==0; fails bake on any absence. (Live RDP login is Phase-12 RDP-14 UAT, intentionally NOT done here.) |

## Deviations from Plan

None — plan executed exactly as written. All three tasks' `<verify>` checks passed; all phase-level checks passed.

Note (process, not scope): the plan's `<automated>` verify blocks use `cd ... && \`-continued multi-line shell. In this sandbox those continued commands produced empty output (a shell-output-capture quirk, not a content failure). Each verify was therefore executed via an equivalent `/tmp/verify_*.sh` script that runs the identical checks individually — all returned `RESULT: PASS`. No verify check was skipped or weakened.

## Threat Flags

None. No new security surface beyond the plan's `<threat_model>`. The configured `:3389` listener is a documented boundary (T-11-06): network exposure is gated by Phase 12 (SG/CIDR), not reachable at bake. TLS-only (`security_layer=tls`), `AllowRootLogin=false`, key.pem 0600 root-only, PAM → password-auth all align with the registered mitigations (T-11-01/03/04).

## Known Stubs

None. All artifacts are config templates / static files / systemd units with real values. No placeholder data, no `changeme`, no empty-value flows.

## Verification Results

- YAML validity: all edited/created YAML parses (tasks, handlers, playbook.yml, layer_config.yml).
- Jinja2: all three templates parse cleanly.
- `ansible-playbook --syntax-check` on playbook.yml: pass.
- Hardening grep-gate: `grep -E '^\s*-\s*role:' ansible/playbook.yml | tail -1 | grep -c 'role:\s*hardening'` → **1** (last role line is `- role: hardening`). INVARIANT PRESERVED.
- No `changeme` literal anywhere in `ansible/roles/xrdp/`.
- ansible-lint: not run — blocked by the pre-existing `.ansible-lint` config-parse error (`'parseable' was unexpected`, noted in STATE.md). This is pre-existing, not introduced by this plan.

## Self-Check: PASSED

Files created (all present + tracked):
- ansible/roles/xrdp/templates/{xrdp.ini.j2, sesman.ini.j2, startwm.sh.j2}
- ansible/roles/xrdp/files/{xrdp-sesman.pam, 45-allow-colord.pkla, xrdp.service, xrdp-sesman.service}
- ansible/roles/xrdp/handlers/main.yml

Commits verified via `git rev-parse`:
- f30fbc7 (Task 1) — present
- 3a80ae6 (Task 2) — present
- e296d0b (Task 3) — present

No file deletions across the three task commits.
