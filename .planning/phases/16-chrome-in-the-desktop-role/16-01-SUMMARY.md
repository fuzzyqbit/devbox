---
phase: 16-chrome-in-the-desktop-role
plan: 01
subsystem: infra
tags: [ansible, dnf, rpm-gpg, google-chrome, packer-bake, al2023]

# Dependency graph
requires:
  - phase: 13-dcv-role (v4.0)
    provides: desktop role + GNOME session that Chrome renders into; rpm_key/dnf GPG idioms
provides:
  - google-chrome-stable baked into every layers.desktop bake from Google's official signed dnf repo
  - byte-canonical /etc/yum.repos.d/google-chrome.repo (gpgcheck=1) whose Chrome %post overwrite is a content no-op
  - Google Linux signing key pre-imported into the rpm db before install (active fingerprint documented in-task)
affects: [17-live-uat-gate, desktop, sbom]

# Tech tracking
tech-stack:
  added: [google-chrome-stable (Google dnf repo, latest-at-bake)]
  patterns: [byte-canonical vendor .repo via copy content (no yum_repository — spaces break Chrome's %post/cron grep), unconditional-in-role content gated only at role level]

key-files:
  created: []
  modified: [ansible/roles/desktop/tasks/main.yml]

key-decisions:
  - "Local pre-commit --all-files and repo-wide ansible-lint hook have pre-existing baseline failures (blame-proven, none in this phase's file); CI-authoritative scopes are green — logged to deferred-items.md, not fixed (scope boundary)"
  - "Hook auto-fix of trailing whitespace in an archived v4.0 research doc was reverted to keep the phase footprint at exactly one file"

patterns-established:
  - "Vendor repo with no release RPM: bake the .repo byte-identical to what the vendor's %post writes so self-management is a no-op"

requirements-completed: [CHROME-02]

# Metrics
duration: 6min
completed: 2026-07-24
---

# Phase 16 Plan 01: Chrome in the desktop role Summary

**google-chrome-stable baked into every desktop bake via rpm_key + byte-canonical google-chrome.repo (gpgcheck=1) + dnf, gated only by layers.desktop — GPG posture intact, all CI-authoritative gates green**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-07-24T13:10:39Z
- **Completed:** 2026-07-24T13:16:04Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- CHROME-02 delivered: three-task `# --- Google Chrome (CHROME-02) ---` block appended to
  `ansible/roles/desktop/tasks/main.yml` — `rpm_key` imports the Google signing-key bundle
  (active fingerprint `EB4C 1BFD 4F04 2F6D DDCC EC91 7721 F63B D38B 4796` documented in a
  task comment, no `fingerprint:` pin per Pitfall 3), `copy` bakes the six canonical
  `.repo` lines byte-identical to Chrome's `%post` heredoc (`gpgcheck=1`, no spaces around
  `=`), `dnf` installs `google-chrome-stable` with `state: present` +
  `disable_gpg_check: false`.
- No task-level gate: the block carries no `when:`/`block:` wrapper — gating comes solely
  from `role: desktop / when: layers.desktop | default(false)` in playbook.yml (locked
  decision), so a `layers.desktop: false` bake is unchanged for free.
- Static posture proven: playbook syntax check exits 0; grep-gates + gitleaks pass
  (hardening still last role, sbom.yml still last import); CI-equivalent
  `ansible-lint ansible/playbook.yml` (pinned v26.4.0 venv, production profile) exits 0
  with 0 warnings; comment-filtered GPG sweep finds zero `nogpgcheck` /
  `disable_gpg_check: true` occurrences.
- Change footprint exactly one file under `ansible/`; playbook.yml, layer_config.yml,
  sbom.yml, requirements.yml, desktop defaults, and the SPAL `chromium` entry untouched.

## Task Commits

Each task was committed atomically:

1. **Task 1: Append the Google Chrome block (CHROME-02) to the desktop role** - `f778b56` (feat)
2. **Task 2: Static verification sweep** - no commit (all checks green, no fixes required within the Chrome block — per plan, no commit needed)

## Files Created/Modified

- `ansible/roles/desktop/tasks/main.yml` - Google Chrome block appended after the VS Code
  block: rpm_key (Google key bundle) → copy (byte-canonical google-chrome.repo, root:root
  0644) → dnf (google-chrome-stable, present, GPG verification on)
- `.planning/phases/16-chrome-in-the-desktop-role/deferred-items.md` - out-of-scope
  pre-existing gate failures discovered during Task 2 (see Deferred Issues)

## Decisions Made

- Treated the repo-wide local hook failures as pre-existing baseline (blame/log-proven:
  2026-05-13 … 2026-07-24 archival commit, all predating this phase) and used the
  CI-authoritative scopes as the green gate — CI runs `ansible-lint ansible/playbook.yml`
  (scoped), not the whole repo. No fixes applied outside the plan footprint.
- Reverted the trailing-whitespace hook auto-fix to an archived v4.0 research doc
  (`git checkout -- <file>`, single-file) to keep the phase change footprint exact.

## Deviations from Plan

None in the delivered change - the Chrome block was implemented exactly as specified and
required zero lint/posture fixes.

Two of Task 2's literal acceptance criteria (`pre-commit run --all-files` exits 0;
`pre-commit run --hook-stage pre-push ansible-lint` exits 0) could not be met because the
plan's assumption of a green repo-wide baseline was wrong — both invocations fail on
pre-existing content unrelated to this phase (proven via git blame/log; details in
deferred-items.md). The intent of those criteria (this change introduces no violations;
invariant gates stay green) is met: grep-gates and gitleaks pass, and the pinned v26.4.0
production-profile lint of `ansible/playbook.yml` (the CI-authoritative form) exits 0 with
the Chrome block included. Fixing the unrelated files would have violated the plan's own
change-footprint success criterion and the executor scope boundary.

**Total deviations:** 0 auto-fixed in delivered code
**Impact on plan:** None - scope, footprint, and locked decisions all honored.

## Deferred Issues

Pre-existing, out-of-scope — logged in
[deferred-items.md](./deferred-items.md), not fixed:

1. `no-changeme` hook false-positives on the SEC-01/02 assertion guards in
   `ansible/roles/secrets/tasks/generate.yml` (since 2026-05-13).
2. `check-yaml` + ansible-lint `load-failure` on `.gitlab-ci.yml`'s GitLab `!reference`
   tag.
3. ansible-lint `yaml[line-length]` on `.pre-commit-config.yaml:43,126` and `role-name` on
   `ansible/roles/persistent-home` (repo-wide hook form only; outside CI scope).
4. Trailing whitespace in the archived
   `.planning/milestones/v4.0-phases/10-.../10-RESEARCH.md` (from the v4.1 archival move).
5. Git hooks not installed in this clone (`.git/hooks/` samples only) — operator should run
   the three `pre-commit install` commands from CLAUDE.md §2.

## Issues Encountered

None beyond the pre-existing baseline failures documented above - resolved by
proving them out-of-scope (blame/log) and gating on the CI-authoritative forms.

## Known Stubs

None - the Chrome block is fully wired; runtime launch proof (CHROME-01) is deliberately
Phase 17's live UAT, not a stub.

## Threat Flags

None - no security surface beyond the plan's threat model (T-16-01…T-16-SC all honored:
gpgcheck=1 baked, key pre-imported, canonical URLs, no GPG bypass anywhere in the diff).

## User Setup Required

None - no external service configuration required. (The bake itself needs AWS creds and is
the operator's live session, composing with the open live-UAT backlog.)

## Next Phase Readiness

- Phase 17 (live UAT gate, CHROME-01): ready — next `DEVBOX_USER=$(whoami) ./run build`
  bakes Chrome; verify launch from the GNOME desktop over DCV/xrdp, and optionally confirm
  the `%post` no-op (`cat /etc/yum.repos.d/google-chrome.repo` still canonical) per
  RESEARCH Open Question 2.
- Deferred: SPAL `chromium` coexistence question for the operator at UAT; CHROME-03/04
  remain deferred per re-scope.

## Self-Check: PASSED

- FOUND: ansible/roles/desktop/tasks/main.yml
- FOUND: .planning/phases/16-chrome-in-the-desktop-role/deferred-items.md
- FOUND commit: f778b56
- Stub scan: 0 hits; GPG sweep: 0 hits; footprint under ansible/: exactly 1 file

---
*Phase: 16-chrome-in-the-desktop-role*
*Completed: 2026-07-24*
