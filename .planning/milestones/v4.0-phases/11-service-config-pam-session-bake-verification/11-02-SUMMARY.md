---
phase: 11-service-config-pam-session-bake-verification
plan: "02"
subsystem: infra
tags: [xrdp, xorgxrdp, ansible, cis, selinux, polkit, systemd, fips, tls, pam]

# Dependency graph
requires:
  - phase: 11-01
    provides: "built+installed xrdp/xorgxrdp, TLS xrdp.ini, sesman.ini Xorg backend, PAM delegation, startwm.sh, systemd units, RDP-13 bake assert"
  - phase: 10
    provides: "from-source xrdp/xorgxrdp build, /usr/local install prefix, xorg module relabel"
provides:
  - "X server (xorg-x11-server-Xorg) + dbus-x11 installed from AL2023 core via dnf — the runtime xorgxrdp actually exec's"
  - "CIS rule 2.2.1 disabled (single accepted desktop deviation) so hardening does not delete the X server"
  - "post-hardening playbook assert that fails the bake if /usr/libexec/Xorg is gone after hardening (regression-proof against a CIS-role bump)"
  - "xrdp role gated on layers.xrdp AND layers.desktop (GNOME + ec2-user password always present first)"
  - "FIPS-safe self-signed TLS cert (RSA-2048, -sha256, subjectAltName=DNS:devbox)"
  - "full SELinux relabel of /usr/libexec/Xorg + /usr/local/{sbin,bin,lib} + /etc/xrdp before hardening enforces"
  - "non-racing sesman systemd unit (no StopWhenUnneeded, no BindsTo; WantedBy + xrdp.service one-directional Requires/After)"
  - "colord polkit allow-rule in AL2023 polkit-121 JS .rules format"
  - "extended RDP-13 bake assert covering X server, cert/key, startwm, PAM, and a cert-SAN proof"
affects: [phase-12-network-uat, hardening, desktop]

# Tech tracking
tech-stack:
  added: [xorg-x11-server-Xorg, dbus-x11, "polkit-121 JS .rules format"]
  patterns:
    - "Accepted CIS deviation = parent-role default override + inline justification + post-hardening regression assert"
    - "Bake assert proves the runtime, not just the role's own artifacts (stat the X server + cert SAN, not just the binary)"

key-files:
  created:
    - ansible/roles/xrdp/files/45-allow-colord.rules
  modified:
    - ansible/roles/xrdp/defaults/main.yml
    - ansible/roles/xrdp/tasks/main.yml
    - ansible/roles/hardening/defaults/main.yml
    - ansible/roles/xrdp/files/xrdp-sesman.service
    - ansible/playbook.yml
    - CLAUDE.md (on disk only — file is intentionally git-untracked)

key-decisions:
  - "Implemented the RESOLVED architecture decision: keep xorgxrdp/Xorg backend (option a), install the X server + disable CIS 2.2.1 — no Xvnc pivot, no post-hardening reinstall kludge"
  - "amzn2023cis_rule_2_2_1: false set at the parent-role default site only; vendored AMAZON2023-CIS default left at true (survives a role bump)"
  - "CLAUDE.md deviation doc written to disk but NOT force-committed — CLAUDE.md is deliberately gitignored/untracked (commit effde0f); the mechanically-authoritative deviation record is the inline comment in hardening/defaults/main.yml"
  - "sesman boot-race fix is the pinned W2 form: drop StopWhenUnneeded + BindsTo, keep WantedBy, rely on xrdp.service one-directional Requires/After"
  - "pam_loginuid kept `required` (redhat-standard); live-session effect deferred to the RDP-14 human UAT gate"

patterns-established:
  - "Regression-proof CIS deviation: every relaxed CIS control that a future role bump could silently re-impose gets a post-hardening post_task assert that turns the regression into a loud bake failure"
  - "RDP-13-style bake asserts must stat the actual runtime dependencies (X server, cert SAN), not only the role's own build outputs"

requirements-completed: [RDP-05, RDP-07, RDP-08, RDP-13]

# Metrics
duration: 8min
completed: 2026-06-16
---

# Phase 11 Plan 02: Service Config / PAM / Session Bake Verification (Gap Closure) Summary

**Closed all 4 CRITICAL + 3 HIGH + 3 RISK adversarial findings against the xorgxrdp backend: install the X server + dbus-x11, disable CIS 2.2.1 (with a post-hardening regression assert), fix the xrdp layer gate, FIPS-harden the TLS cert, full SELinux relabel, fix the sesman boot race, port colord polkit to .rules, and extend the RDP-13 bake assert to prove a real RDP+Xorg+PAM+GNOME stack survives hardening.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-16T00:19:45Z
- **Completed:** 2026-06-16T00:28:02Z
- **Tasks:** 3
- **Files modified:** 6 (5 tracked + CLAUDE.md on-disk-only)

## Accomplishments
- **CRITICAL #1** — `xorg-x11-server-Xorg` (provides `/usr/libexec/Xorg`) + `dbus-x11` (provides `dbus-launch`) now installed via `ansible.builtin.dnf` from the AL2023 core repo at the top of the Phase 11 block, with a success-assert gate. Airgap-compliant (no S3/mirror/get_url).
- **CRITICAL #2** — `amzn2023cis_rule_2_2_1: false` in `hardening/defaults/main.yml` (the proven parent-role override site) stops CIS from deleting `xorg-x11-server-common` (a dep of `-Xorg`). Vendored CIS default untouched.
- **CRITICAL #3** — xrdp role now gated on `(layers.xrdp) and (layers.desktop)`, guaranteeing GNOME + the secrets-role ec2-user password exist before xrdp configures auth.
- **CRITICAL #4** — RDP-13 in-role assert now stats `/usr/libexec/Xorg`, `/etc/xrdp/{cert,key}.pem`, `/etc/xrdp/startwm.sh`, `/etc/pam.d/xrdp-sesman` (plus the original binary/module/inis + is-enabled) and proves the cert carries `DNS:devbox`.
- **W1** — post-hardening `post_task` in `playbook.yml` stats `/usr/libexec/Xorg` AFTER the hardening role and fails the bake if it is gone, naming a CIS-2.2.1 re-enable as the cause — making the override regression-proof against a future CIS-role bump.
- **HIGH** — FIPS-safe cert (`-sha256` + `-addext subjectAltName=DNS:devbox` over RSA-2048); full `restorecon -RvF` over the X server + `/usr/local/{sbin,bin,lib}` + `/etc/xrdp` before hardening enforces SELinux.
- **HIGH/W2** — sesman unit boot-race fixed: removed `StopWhenUnneeded` + `BindsTo`, kept `WantedBy=multi-user.target`, ordered solely by xrdp.service's one-directional `Requires=`/`After=`.
- **RISK** — colord polkit allow-rule ported to AL2023 polkit-121 JS `.rules` format in `/etc/polkit-1/rules.d/`; dead `.pkla` no longer installed. dbus-x11 confirmed (CRITICAL #1). pam_loginuid `required` retained + justified (RDP-14 UAT).

## Task Commits

Each task was committed atomically:

1. **Task 1: Install X server + dbus-x11, disable CIS 2.2.1, fix layer gate, document deviation** - `ac3b3cb` (feat)
2. **Task 2: FIPS-safe cert, SELinux relabel, sesman boot-race fix, colord .rules, pam_loginuid** - `54740e8` (feat)
3. **Task 3: Extend RDP-13 bake assert + post-hardening X-server regression guard** - `a50abd1` (feat)

**Plan metadata:** _(final docs commit — this SUMMARY + STATE/ROADMAP/REQUIREMENTS)_

## Files Created/Modified
- `ansible/roles/xrdp/defaults/main.yml` - added `xrdp_runtime_deps` (xorg-x11-server-Xorg + dbus-x11, AL2023-core)
- `ansible/roles/xrdp/tasks/main.yml` - runtime-dep dnf install + assert; FIPS cert (-sha256 + SAN); restorecon over Xorg/usr-local/etc-xrdp; polkit .rules install; pam_loginuid comment; extended RDP-13 (5 new stats + cert-SAN assert; in-role X-server fail_msg blames the dep install, not CIS)
- `ansible/roles/hardening/defaults/main.yml` - `amzn2023cis_rule_2_2_1: false` with a desktop-exception comment
- `ansible/roles/xrdp/files/xrdp-sesman.service` - removed StopWhenUnneeded + BindsTo, kept WantedBy; documented the non-racing dependency
- `ansible/roles/xrdp/files/45-allow-colord.rules` - new polkit-121 JS rules file granting `org.freedesktop.color-manager.*`
- `ansible/playbook.yml` - xrdp `when:` gated on xrdp AND desktop; new post-hardening Xorg stat+assert as the first post_task
- `CLAUDE.md` - §8 accepted-CIS-deviation bullet (written on disk only; CLAUDE.md is git-untracked)

## Decisions Made
- Implemented the resolved option (a) — keep xorgxrdp; no Xvnc pivot, no post-hardening reinstall kludge.
- CIS override at the parent-role default site only; the vendored `AMAZON2023-CIS/defaults/main.yml` (line 258, `true`) is left untouched so it survives a role bump.
- The deviation's mechanically-authoritative record is the inline comment in `hardening/defaults/main.yml`; the CLAUDE.md bullet is a human-readable convenience that lives on the operator's local (untracked) copy.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] CLAUDE.md is git-untracked/ignored — could not be committed as a "files_modified" file**
- **Found during:** Task 1 (documenting the CIS deviation)
- **Issue:** The plan lists `CLAUDE.md` in `files_modified` and instructs documenting the accepted CIS deviation there. But `git add CLAUDE.md` failed — CLAUDE.md was deliberately untracked in commit `effde0f chore: untrack CLAUDE.md (local-only operator guide)` and is matched by `.gitignore:21`.
- **Fix:** Applied the documented deviation edit to CLAUDE.md on disk (so the operator's local guide carries it) but did NOT force-add it — force-adding would override a deliberate project policy. The deviation's authoritative, committed record is the inline comment in `ansible/roles/hardening/defaults/main.yml` plus this SUMMARY. All other Task 1 files committed normally.
- **Files modified:** CLAUDE.md (on disk only)
- **Verification:** `git check-ignore -v CLAUDE.md` → `.gitignore:21`; `git log --oneline -1 -- CLAUDE.md` → `effde0f` (untrack commit). The `grep -q 'amzn2023cis_rule_2_2_1' CLAUDE.md` Task-1 gate still passes against the on-disk file.
- **Committed in:** N/A (intentionally not committed; rationale documented here)

**2. [Rule 1 - Verify-gate bug] sesman-unit comment tripped the `! grep -q StopWhenUnneeded/BindsTo` gate**
- **Found during:** Task 2 (sesman boot-race fix)
- **Issue:** The first version of the explanatory comment in `xrdp-sesman.service` named the removed directives verbatim (`StopWhenUnneeded=true`, `BindsTo=xrdp.service`). The plan's acceptance gate is `! grep -q 'StopWhenUnneeded'` / `! grep -q 'BindsTo'`, which matched the comment substrings and would fail even though the actual `[Unit]` directives were gone.
- **Fix:** Reworded the comment to describe the removed directives descriptively ("the stop-when-unneeded directive", "the reciprocal binds-to-xrdp directive") without the literal tokens — preserving the plan-required rationale while letting the negative grep pass.
- **Files modified:** ansible/roles/xrdp/files/xrdp-sesman.service
- **Verification:** `grep -c 'StopWhenUnneeded'` → 0; `grep -c 'BindsTo'` → 0; `grep -c 'WantedBy=multi-user.target'` → 1.
- **Committed in:** `54740e8` (Task 2 commit)

---

**Total deviations:** 2 (1 blocking-policy, 1 verify-gate phrasing). Neither changes behavior.
**Impact on plan:** All functional acceptance criteria met exactly. The CLAUDE.md deviation is a tracking-location adjustment forced by a deliberate gitignore policy; the sesman one is a comment-wording adjustment to satisfy a literal grep gate. No scope creep, no weakened asserts.

## Issues Encountered
- The Bash environment's chained-command/no-verify hook intermittently truncated multi-line `&&`-joined verification scripts, suppressing the trailing `echo PASS`. Worked around by running each verify check as an individual single-purpose Bash call (per the project's "commit standalone / no-verify-hook" memory). All gate checks were confirmed individually.
- `ansible-lint` could not use the project `.ansible-lint` (pre-existing broken config: `parseable` is an unexpected property — noted in STATE.md and the plan's execution notes). Ran with `-c /dev/null`; the 345 production-profile findings are a pre-existing repo-wide baseline (FQCN, var-naming, Phase-10 `{{ version }}` task names). No NEW blocking finding was introduced by this plan's edits.

## User Setup Required
None - no external service configuration required. (The live RDP login, RDP-14, remains the Phase-12-close human UAT gate, as before.)

## Next Phase Readiness
- The bake is now config-correct AND runtime-honest: a GREEN bake means the X server, FIPS-safe cert, SELinux labels, non-racing units, and PAM/session files are all present and the X server survives hardening.
- Phase 12 (network) can open SG `:3389` and run the RDP-14 live UAT against a baked AMI with confidence the static + bake-time stack is complete.
- No blockers. The only un-bake-provable item (pam_loginuid live-session behavior) is explicitly the RDP-14 gate.

## Self-Check: PASSED

- FOUND: `.planning/phases/11-service-config-pam-session-bake-verification/11-02-SUMMARY.md`
- FOUND: `ansible/roles/xrdp/files/45-allow-colord.rules`
- FOUND commit `ac3b3cb` (Task 1)
- FOUND commit `54740e8` (Task 2)
- FOUND commit `a50abd1` (Task 3)

---
*Phase: 11-service-config-pam-session-bake-verification*
*Completed: 2026-06-16*
