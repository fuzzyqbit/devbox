---
phase: 05-run-script-core
plan: 01
subsystem: infra
tags: [bash, shell-script, dispatcher, makefile-replacement, devbox]

# Dependency graph
requires:
  - phase: 04-ci-docs
    provides: Makefile with all 20 targets, scripts/devbox-*.sh helpers, _common.sh
provides:
  - "./run script: standalone bash dispatcher with all 20 commands, guards, and tf-ensure-init"
affects: [06-ci-integration, 07-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns: [case-dispatch, lazy-derivation, subshell-cd, bash-version-guard]

key-files:
  created: [run]
  modified: []

key-decisions:
  - "Standalone dispatcher (does not source _common.sh) — run is self-contained; lifecycle scripts source _common.sh themselves"
  - "Lazy TF_STATE_BUCKET derivation — aws sts call only when a command needs the backend, not at startup"
  - "Bash 4+ version guard as first executable block — exits cleanly on macOS system bash 3.2"
  - "DEVBOX_USER regex validation added (^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$) — matches CI deploy job regex"

patterns-established:
  - "case-dispatch: case $command in name) cmd_name ;; pattern for all commands"
  - "lazy-derivation: _derive_tf_state_bucket called only by backend-touching commands"
  - "subshell-cd: (cd dir && cmd) pattern prevents working directory leakage"
  - "guard-chain: commands call _require_devbox_user and/or cmd_tf_ensure_init explicitly"

requirements-completed: [RUN-01, RUN-02, RUN-03, RUN-04, RUN-05, RUN-06, RUN-07, RUN-08]

# Metrics
duration: 5min
completed: 2026-05-27
---

# Phase 5 Plan 1: Run Script Core Summary

**Standalone ./run bash dispatcher with all 20 Makefile commands, DEVBOX_USER validation + regex guard, lazy TF_STATE_BUCKET derivation, and tf-ensure-init auto-reinit — shellcheck clean at 337 lines**

## Performance

- **Duration:** 5 min
- **Started:** 2026-05-27T13:15:26Z
- **Completed:** 2026-05-27T13:20:23Z
- **Tasks:** 2
- **Files created:** 1

## Accomplishments
- Created `./run` script (337 lines) implementing all 20 Makefile commands via case-dispatch
- Ported DEVBOX_USER guard with added regex validation (format enforcement matching CI deploy job)
- Ported tf-ensure-init auto-reinit guard (jq-based backend cache key comparison)
- Lazy TF_STATE_BUCKET derivation prevents AWS STS call on non-backend commands (help, fmt, etc.)
- Executable bit committed to git index (100755)
- shellcheck 0.11.0 passes clean (zero warnings, zero errors)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ./run script with all 20 commands** - `8141c74` (feat)
2. **Task 2: Commit executable bit and validate command parity** - `8141c74` (verification only; executable bit was committed in Task 1)

## Files Created/Modified
- `run` - Standalone bash dispatcher replacing Makefile; 20 commands across 6 groups (AMI, Terraform, Lifecycle, SSM, Secrets, Cleanup)

## Decisions Made
- **Standalone script:** `./run` does NOT source `scripts/_common.sh`. It is a self-contained dispatcher. Lifecycle scripts (`devbox-start.sh`, `devbox-stop.sh`, etc.) source `_common.sh` themselves when delegated to.
- **Lazy derivation:** `TF_STATE_BUCKET` is computed only when needed (inside `_derive_tf_state_bucket`), not at script startup. This means `./run help`, `./run fmt`, and other non-backend commands work without AWS credentials.
- **Regex validation added:** `_require_devbox_user` now validates format with `^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$` in addition to the existing empty-string check. This is per RUN-08 and matches the CI deploy job regex.
- **shellcheck SC2046 disabled for word-splitting:** `_tf_backend_args` and `_tf_var_args` return space-separated flags that must be word-split by the caller. `# shellcheck disable=SC2046` is applied at each call site rather than globally.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- **Bash 3.2 on macOS prevents direct execution:** The development machine runs macOS with bash 3.2 (Apple's GPLv2 freeze). The Bash 4+ version guard correctly blocks execution. Smoke testing of guards and help output was done via function extraction and content analysis rather than direct `./run` invocation. This is expected behavior per PITFALLS.md M-1 and the operator prerequisite list in CLAUDE.md section 2.

## User Setup Required

None - no external service configuration required. Operators who don't have Homebrew bash 4+ will see the version guard error with clear installation instructions.

## Next Phase Readiness
- `./run` is ready for CI integration (Phase 6): CI jobs can call `./run build`, `./run tf-init`, `./run tf-apply`, etc.
- Makefile deletion is deferred to Phase 7 (after CI is verified working with `./run`)
- CLAUDE.md documentation update (`make` to `./run` references) will be Phase 7

---
*Phase: 05-run-script-core*
*Completed: 2026-05-27*
