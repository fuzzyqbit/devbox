---
phase: 13-dcv-ansible-role
plan: 02
subsystem: infra
tags: [ansible, amazon-dcv, playbook-wiring, bake-assert, fips, hardening-invariant, packer]

# Dependency graph
requires:
  - phase: 13-01 (dcv role)
    provides: "the complete dcv role + artifacts (dcvserver/dcv/Xdcv binaries, dcv.conf, FIPS cert at /etc/dcv/dcv.{pem,key}, dcv-virtual-session.service, colord .rules, /etc/pam.d/dcv) — the targets this plan wires and asserts"
  - phase: 11-rdp-server-role (xrdp)
    provides: "the RDP-13 bake-assert block structure (stat → existence assert → cert SAN → systemctl is-enabled) mirrored here; the playbook xrdp slot showing exactly where dcv goes before hardening"
provides:
  - "`- role: dcv` wired into ansible/playbook.yml strictly before `- role: hardening`, gated `when: layers.dcv and layers.desktop` (hardening-last grep-gate still prints 1)"
  - "`dcv: true` layer toggle in ansible/layer_config.yml (mirrors xrdp: true)"
  - "RDP-13-grade DCV bake assertion appended to ansible/roles/dcv/tasks/main.yml: stats binaries + conf + cert/key + session unit + colord + PAM; asserts existence (loud per-line fail_msg); cert/key dcv:dcv 0600; dcv.conf auth=system + web-port + QUIC-on and NOT auth=none; cert subjectAltName=DNS:devbox; dcvserver + dcv-virtual-session enabled (rc==0)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mirror-the-prior-bake-assert: retargeted the shipped xrdp RDP-13 block (stat → one big existence assert with loud per-line fail_msg → cert-owner/mode assert → slurp+content assert → openssl x509 SAN → systemctl is-enabled rc==0) onto the DCV artifact set"
    - "Stat-without-failed_when:false for binaries so a missing binary FAILS the bake loud (never silent-pass); openssl/systemctl probes use changed_when:false + failed_when:false and gate the verdict on the following assert"
    - "Role inserted between `desktop`/`xrdp` and `hardening` — the hardening-last invariant slot (CLAUDE.md §8 grep-gate)"

key-files:
  created:
    - .planning/phases/13-dcv-ansible-role/13-02-SUMMARY.md
  modified:
    - ansible/playbook.yml
    - ansible/layer_config.yml
    - ansible/roles/dcv/tasks/main.yml

key-decisions:
  - "Inserted `- role: dcv` immediately AFTER `- role: xrdp` and BEFORE `- role: hardening` — xrdp left intact because its removal is Phase 14 (scope fence); dcv co-deploys alongside it for now"
  - "web-port assertion uses the rendered variable (`'web-port=' ~ dcv_web_port`) rather than a hardcoded 8443 string, so an overridden dcv_web_port still asserts the value actually templated"
  - "Slurp + b64decode for the dcv.conf content checks (auth=system / web-port / QUIC-on present, auth=none / create-session=true absent) — the security-gate proof against the passwordless-desktop EoP"
  - "Binary stat paths (/usr/bin/dcvserver, /usr/bin/dcv, /usr/bin/Xdcv) annotated [ASSUMED] from vendor RPM convention — confirmed-at-first-bake via `rpm -ql nice-dcv-server nice-xdcv | grep /bin/`; design (loud-fail on absence) is what matters"

requirements-completed: [DCV-04, DCV-05]

# Metrics
duration: 3min
completed: 2026-06-19
---

# Phase 13 Plan 02: DCV Playbook Wiring + RDP-13-Grade Bake Assert Summary

**`- role: dcv` wired before hardening (hardening-last invariant intact) + `dcv: true` toggle + the load-bearing RDP-13-grade bake assertion that turns a green-but-DCV-dead AMI into a loud bake failure — binaries, dcv.conf keys (auth=system/web-port/QUIC, no auth=none/create-session), cert path/owner/0600/SAN, virtual-session unit, and both enabled services.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-06-19T05:04:13Z
- **Completed:** 2026-06-19T05:06:47Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- **Task 1 — playbook wiring + layer toggle.** Inserted `- role: dcv` into `ansible/playbook.yml` immediately after `- role: xrdp` and strictly before `- role: hardening`, gated `when: (layers.dcv | default(false)) and (layers.desktop | default(false))` with the desktop-gate comment (DCV needs GNOME + the ec2-user PAM password). `- role: hardening` remains the LAST `- role:` entry — the CLAUDE.md §8 hardening-last grep-gate prints `1`. Added `dcv: true` to `ansible/layer_config.yml` mirroring `xrdp: true`. xrdp wiring left untouched (Phase 14 owns its removal — scope fence).
- **Task 2 — RDP-13-grade bake assertion** appended to `ansible/roles/dcv/tasks/main.yml` after the cleanup tasks (runs last in the role, after every asserted artifact exists, before hardening). Mirrors the shipped xrdp RDP-13 block, retargeted to the DCV artifact set:
  - stat (no `failed_when:false`) of `/usr/bin/{dcvserver,dcv,Xdcv}`, `/etc/dcv/dcv.conf`, `/etc/dcv/dcv.{pem,key}`, `/etc/systemd/system/dcv-virtual-session.service`, `/etc/polkit-1/rules.d/45-allow-colord.rules`, `/etc/pam.d/dcv` → one existence assert with a loud per-line fail_msg naming each path;
  - cert/key assert: `pw_name == "dcv"` AND `mode == "0600"` for both files (Pitfall A — wrong perms → DCV silently ignores the cert);
  - slurp + b64decode of `dcv.conf`: assert `authentication="system"`, `web-port={{ dcv_web_port }}`, `enable-quic-frontend=true` present, and `authentication="none"` ABSENT (the passwordless-desktop EoP gate);
  - `openssl x509 -noout -text` SAN assert: `Subject Alternative Name` AND `DNS:devbox` (FIPS-strict handshake rejects CN-only certs);
  - `systemctl is-enabled dcvserver dcv-virtual-session` → assert `rc == 0` (boot enablement).
  - Explicitly NO live connect / create-session / FIPS-handshake / AVC check — those are the Phase-15 live UAT (DCV-11).

## Task Commits

Each task was committed atomically (hooks ran, no `--no-verify`):

1. **Task 1: Wire dcv role before hardening + dcv layer toggle** — `2b98793` (feat)
2. **Task 2: Append RDP-13-grade DCV bake assertion** — `e0f698a` (feat)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately.

## Files Modified

- `ansible/playbook.yml` — `- role: dcv` block (gated layers.dcv and layers.desktop) inserted between xrdp and hardening; hardening stays last; post_tasks untouched.
- `ansible/layer_config.yml` — `dcv: true` toggle + comment, near `xrdp: true`.
- `ansible/roles/dcv/tasks/main.yml` — DCV-04 bake-assert block (162 lines) appended after cleanup: 9 stats → existence assert → cert owner/mode assert → dcv.conf slurp/content assert → cert SAN assert → service-enablement assert.

## Verification Evidence (each gate printed PASS before its commit)

- **Task 1:** `ansible-playbook --syntax-check` PASS; `HARDENING-LAST=1 OK` (grep-gate = 1); `- role: dcv` at playbook line 65 (between xrdp@59 and hardening@71); `dcv: true` at layer_config.yml line 24.
- **Task 2:** `ansible-playbook --syntax-check` PASS; `python3 yaml.safe_load` → `YAML OK`; assert-block patterns present (`is-enabled`×2, `Subject Alternative Name`×1, `enable-quic-frontend=true`×2, `dcvserver`×14, `slurp`×1); `web-port=' ~ dcv_web_port` assert @328; `authentication="none" not in` assert @330; `create-session=true` count 0; no `changeme` literal in any touched file.

## Deviations from Plan

None — plan executed exactly as written. No Rule 1–4 deviations triggered.

## Issues Encountered

- The bake-host shell again ran with an inherited `errexit`-like option (documented in 13-01's SUMMARY): chained verification commands aborted after the first `grep` whose downstream peer returned rc=1, suppressing later output. Resolved exactly as 13-01 did — each verification grep re-run as a standalone Bash call with rc inspected separately. Every plan-specified gate pattern confirmed present and every antipattern confirmed absent. The only `--nogpgcheck` match is the pre-existing "NEVER add --nogpgcheck" comment (line 85, from 13-01), not a real invocation.

## Known Stubs

None. No hardcoded empty values, placeholder text, or unwired data sources introduced. The `dcv_tarball_sha256` deferred-pin (from 13-01) is unchanged and documented (CLAUDE.md §9); not introduced by this plan.

## Threat Surface

No new security surface beyond the plan's `<threat_model>`. This plan only wires + asserts; no package installs (T-13-SC n/a), no network endpoints, no new auth paths. The bake assert is the realization of mitigations T-13-08 (hardening-last order), T-13-09 (green-but-broken AMI), T-13-10 (CN-only cert), and T-13-11 (auth=none EoP).

## Next Phase Readiness

- Phase 13 is now fully executed: 13-01 (role) + 13-02 (wiring + bake assert). DCV-01…05 satisfied at the bake-artifact level.
- **Live properties remain Phase-15 UAT (DCV-11):** license resolves (`ORIGIN_OBJECT_MISSING` grace), GNOME renders over DCV, AVC-clean under enforcing, the FIPS handshake, and the QUIC data path. The bake assert proves the artifacts are in place, not that a live session connects.
- **Phase 14** owns: direct-connect SG (:8443 TCP+UDP), xrdp/VNC removal, CIS 2.2.1 revert + post-hardening Xorg-guard removal, operator surface. None touched here (scope fence).
- Binary stat paths in the assert are `[ASSUMED]` from vendor RPM convention — confirm at first bake with `rpm -ql nice-dcv-server nice-xdcv | grep /bin/` and adjust if the layout drifts.

## Self-Check: PASSED

- Both files exist on disk: `.planning/phases/13-dcv-ansible-role/13-02-SUMMARY.md`, `ansible/roles/dcv/tasks/main.yml`.
- Both task commits present in history: `2b98793` (Task 1), `e0f698a` (Task 2).

---
*Phase: 13-dcv-ansible-role*
*Completed: 2026-06-19*
</content>
</invoke>
