---
phase: 13-dcv-ansible-role
plan: 01
subsystem: infra
tags: [ansible, amazon-dcv, dcvserver, fips, selinux, pam, polkit, airgap, packer]

# Dependency graph
requires:
  - phase: 11-rdp-server-role (xrdp)
    provides: "FIPS cert recipe (rsa:2048/-sha256/SAN), colord polkit .rules, PAM-to-password-auth delegate, restorecon relabel pattern — all ported as the v4.0 deltas"
  - phase: secrets role (existing)
    provides: "desktop_vnc_password (ec2-user PAM password) consumed by authentication=system; the role asserts it is set"
  - phase: desktop role (existing)
    provides: "@Desktop + gnome-session + mesa-dri-drivers — the GNOME the DCV virtual session renders (consumed, never re-installed)"
provides:
  - "Complete ansible/roles/dcv/ role (defaults, handlers, 2 templates, 2 files, tasks core)"
  - "Airgap-compliant non-GPU DCV install: rpm_key NICE-GPG-KEY import + pinned get_url tarball + glob-install of nice-dcv-server / nice-xdcv / nice-dcv-web-viewer (disable_gpg_check:false) + policycoreutils-python-utils"
  - "dcv.conf: authentication=system, web-port=8443, enable-quic-frontend=true (no certificate key, no create-session=true)"
  - "FIPS-safe self-signed cert at /etc/dcv/dcv.{pem,key} owner dcv:dcv mode 0600, subjectAltName=DNS:devbox"
  - "Oneshot dcv-virtual-session.service (dcv create-session --type virtual --owner ec2-user) — the only auto-virtual mechanism"
  - "colord polkit allow rule + /etc/pam.d/dcv delegate + restorecon SELinux relabel"
affects: [13-02 (playbook wiring + RDP-13-grade bake assert), 14 (direct-connect SG + xrdp/VNC removal + CIS revert), 15 (live UAT)]

# Tech tracking
tech-stack:
  added: [amazon-dcv-2025.0, nice-dcv-server, nice-xdcv, nice-dcv-web-viewer]
  patterns:
    - "Port-plus-deltas: ~80% recovered verbatim from prior git role (51c5f1f), 20% ported from shipped xrdp role"
    - "Airgap install: rpm_key GPG import + pinned get_url + deferred-pin sha256 (GPG signature as integrity gate until filled)"
    - "Path-based DCV cert (hardcoded /etc/dcv/dcv.{pem,key}, dcv:dcv 0600) — NOT a dcv.conf key"
    - "Auto-virtual session via oneshot systemd unit (DCV has no auto-virtual config)"

key-files:
  created:
    - ansible/roles/dcv/defaults/main.yml
    - ansible/roles/dcv/handlers/main.yml
    - ansible/roles/dcv/tasks/main.yml
    - ansible/roles/dcv/templates/dcv.conf.j2
    - ansible/roles/dcv/templates/dcv-virtual-session.service.j2
    - ansible/roles/dcv/files/45-allow-colord.rules
    - ansible/roles/dcv/files/dcv.pam
  modified: []

key-decisions:
  - "Dropped the prior role's `desktop_vnc_password != \"changeme\"` assert clause; `is defined` + `length > 0` covers the intent without tripping the no-changeme hook (which scans ansible/ code files)"
  - "Split prior single dcv_build into dcv_build_server (20103, drives tarball URL) and dcv_build_xdcv (688, doc-only — RPM install globs by name to handle the build skew)"
  - "QUIC ON (enable-quic-frontend=true) per v4.0 direct-connect REQUIREMENTS — supersedes the research SUMMARY/PITFALLS SSM-era QUIC-OFF recommendation"
  - "Generated our own FIPS cert rather than relying on DCV's auto-cert (auto-cert may be CN-only/SHA-1 → FIPS handshake rejection)"
  - "restorecon-only SELinux relabel; no speculative fcontext type (DCV lands in distro paths with sane labels, unlike xrdp's /usr/local/sbin). audit2allow scoped module deferred to Phase 15 if AVCs appear"

patterns-established:
  - "DCV cert is delivered as files at hardcoded paths/names/owner/mode, never via config"
  - "Virtual session created by oneshot unit; create-session=true (console-only) deliberately unset in dcv.conf"

requirements-completed: [DCV-01, DCV-02, DCV-03, DCV-05]

# Metrics
duration: 5min
completed: 2026-06-19
---

# Phase 13 Plan 01: `dcv` Ansible Role Summary

**Complete airgap-compliant `dcv` role: GPG-verified non-GPU DCV install + dcv.conf (auth=system, :8443, QUIC on) + FIPS-safe cert at DCV's hardcoded path + oneshot virtual-session unit + colord/PAM + SELinux relabel — ported from git 51c5f1f and the shipped xrdp role.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-19T04:54:28Z
- **Completed:** 2026-06-19T05:00:01Z
- **Tasks:** 2
- **Files modified:** 7 (all created)

## Accomplishments
- Recovered the prior `dcv` role from git `51c5f1f` (the corrected commit — verified the NICE-GPG-KEY URL is the literal CloudFront URL, NOT the PII-mangled `<MRCLEAN…>` placeholder in 67faeb3/1d2f32e) and ported it as the spine.
- Airgap install: `rpm_key` import of `https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY`, pinned `get_url` of the 2025.0-20103 AL2023 tarball (deferred-pin sha256), glob+`dnf` install of the three non-GPU RPMs with `disable_gpg_check: false`, plus `policycoreutils-python-utils` from AL2023 core. No `--nogpgcheck`, no S3/mirror.
- `dcv.conf`: `authentication="system"`, `web-port=8443`, `enable-quic-frontend=true`; explicitly no `certificate=` key (path-based) and no `create-session=true` (console-only).
- FIPS-safe cert: `openssl req -x509 -newkey rsa:2048 -sha256 -addext subjectAltName=DNS:devbox` → `/etc/dcv/dcv.{pem,key}`, chowned `dcv:dcv` mode `0600` (NOT 0644).
- Oneshot `dcv-virtual-session.service` running `dcv create-session --type virtual --owner ec2-user`; both `dcvserver` and `dcv-virtual-session` enabled.
- colord polkit `.rules` (color-manager allow), `/etc/pam.d/dcv` delegating to `password-auth`, and `restorecon -RvF` over DCV install paths (permissive bake, before hardening).

## Task Commits

Each task was committed atomically:

1. **Task 1: Port the prior dcv role base (defaults, handlers, 2 templates, install + config + enable)** - `17b3a6b` (feat)
2. **Task 2: Add the FIPS cert, colord polkit rule, PAM delegate, and SELinux relabel** - `f98dd7a` (feat)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified
- `ansible/roles/dcv/defaults/main.yml` - Version pins (split server/xdcv build), web port, deferred sha256, runtime deps
- `ansible/roles/dcv/handlers/main.yml` - `reload systemd` (daemon_reload) handler
- `ansible/roles/dcv/tasks/main.yml` - PAM assert → GPG import → pinned download/extract → 3-RPM glob install → runtime deps → conf/unit templating → enable → FIPS cert → colord/PAM → SELinux relabel → cleanup
- `ansible/roles/dcv/templates/dcv.conf.j2` - auth=system, web-port, QUIC on; documented no-cert-key / no-console-session
- `ansible/roles/dcv/templates/dcv-virtual-session.service.j2` - Oneshot `dcv create-session --type virtual`
- `ansible/roles/dcv/files/45-allow-colord.rules` - polkit JS rule (GNOME-over-DCV hang prevention)
- `ansible/roles/dcv/files/dcv.pam` - `/etc/pam.d/dcv` delegating to `password-auth`

## Decisions Made
- **No-changeme handling:** the prior role's PAM assert had `desktop_vnc_password != "changeme"`; the no-changeme pre-commit hook scans all tracked code files except `*.md`/`.planning/**`, so the literal would fail in `ansible/`. Dropped the clause — `is defined` + `length > 0` covers the intent (per plan A4). Both commits passed the hook.
- **Build split:** prior single `dcv_build` was wrong for xdcv (688 ≠ 20103). Split into `dcv_build_server` (drives the tarball URL) and `dcv_build_xdcv` (documentation-only; the `find` glob installs the correct build regardless).
- **QUIC ON:** honored REQUIREMENTS.md / DCV-02 direct-connect posture over the superseded SSM-era QUIC-OFF research note.
- **restorecon-only SELinux:** no speculative `semanage fcontext` type; DCV's distro-path RPM gets sane default labels. Scoped `audit2allow` module is a Phase-15 escalation only if live AVCs appear.

## Deviations from Plan

None - plan executed exactly as written. (All deltas, file order, and the `!= "changeme"` drop were specified in the plan; no Rule 1-4 deviations were triggered.)

## Issues Encountered
- The bake-host shell ran with an inherited `errexit`-like option, so `grep`/`grep -q` no-match (rc=1) verification commands aborted mid-script with suppressed output. Resolved by running each verification grep as a standalone `grep -nE` (rc inspected separately) — every plan-specified gate pattern was confirmed present (rsa:2048, SAN, mode 0600, owner dcv, restorecon, password-auth, color-manager) and every antipattern absent (no quic-off, no auth-none, no real `--nogpgcheck` — the only match is a "NEVER add --nogpgcheck" comment, no `certificate=` key, no `changeme`). syntax-check + YAML parse both PASS.

## User Setup Required
None - no external service configuration required. (The `dcv_tarball_sha256` deferred-pin is filled after the first bake per CLAUDE.md §9; the GPG signature is the integrity gate until then.)

## Next Phase Readiness
- The `dcv` role is complete and self-consistent on disk (7 files), syntax-check clean, hooks green.
- **Plan 13-02 (wave 2)** wires `- role: dcv` before `hardening` (+ the `dcv: true` layer toggle) and adds the RDP-13-grade bake assert (binary/conf/cert-SAN/units/enablement). NOT done here by design.
- Binary paths in the SELinux relabel (`/usr/bin/dcv*`, `/usr/lib64/dcv*`) are confirmed-at-bake (annotated in tasks/main.yml); confirm with `rpm -ql nice-dcv-server nice-xdcv | grep /bin/` at first bake if they ever drift.
- Out of scope for Phase 13 (carried): S3 license VPC endpoint + IAM (Phase 14 if target env stops providing the license path), SG :8443 TCP+UDP ingress (Phase 14), live AVC/FIPS/QUIC/render proof (Phase 15 UAT).

## Self-Check: PASSED

- All 7 role files + SUMMARY.md exist on disk.
- Both task commits present in history: `17b3a6b` (Task 1), `f98dd7a` (Task 2).

---
*Phase: 13-dcv-ansible-role*
*Completed: 2026-06-19*
