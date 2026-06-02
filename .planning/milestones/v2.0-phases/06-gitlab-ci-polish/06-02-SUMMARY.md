---
phase: 06-gitlab-ci-polish
plan: 02
subsystem: infra
tags: [gitlab-ci, pipeline, shellcheck, grep-gates, lockfile-readonly, ci-delegation]

requires:
  - phase: 06-gitlab-ci-polish
    plan: 01
    provides: "Color output helpers and doctor command in ./run"
  - phase: 05-run-script-core
    provides: "./run shell dispatcher with 20 commands"
provides:
  - "CI bake stage delegates to ./run build (no inline packer commands)"
  - "CI deploy stage delegates to ./run tf-init + ./run tf-auto-apply (no inline tofu commands)"
  - "CI shellcheck job lints run file alongside scripts/*.sh"
  - "CI grep-gates invariant #8 checks run executable bit (100755)"
  - "Pre-commit grep-gates parity with invariant #8"
  - "./run tf-init and tf-reinit add -lockfile=readonly when CI=true"
affects: [07-docs-cleanup]

tech-stack:
  added: []
  patterns: [CI-aware flag injection (CI=true -> lockfile=readonly), PKR_VAR_* env-var passthrough for Packer region]

key-files:
  created: []
  modified: [.gitlab-ci.yml, .pre-commit-config.yaml, run]

key-decisions:
  - "Plan-file workflow dropped from CI deploy in favour of ./run tf-auto-apply -- defense-in-depth (when:manual + protected branch + OIDC + DEVBOX_USER fail-fast) is sufficient without the plan artifact"
  - "PKR_VAR_aws_region set as CI job variable rather than modifying ./run build -- keeps ./run unchanged, uses Packer standard env-var convention"
  - "Deploy before_script DEVBOX_USER validation retained as defense-in-depth alongside ./run _require_devbox_user"

patterns-established:
  - "CI delegation: CI script blocks call ./run commands instead of inline shell"
  - "CI-aware init flags: ./run tf-init conditionally adds -lockfile=readonly when CI=true"
  - "Grep-gate parity: CI and pre-commit grep-gates both check the same invariants"

requirements-completed: [CI-01, CI-02, CI-03, CI-04]

duration: 4min
completed: 2026-05-27
---

# Phase 06 Plan 02: GitLab CI Pipeline Delegation Summary

**CI bake and deploy stages delegate to ./run, shellcheck and grep-gates extended to cover the run file**

## Performance

- **Duration:** 4 min
- **Started:** 2026-05-27T19:33:14Z
- **Completed:** 2026-05-27T19:37:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added CI-aware `-lockfile=readonly` flag to `./run tf-init` and `./run tf-reinit` (Phase 3 REP-01 enforcement in CI)
- Replaced inline `cd packer && packer init . && packer build -var ...` in CI bake job with `./run build` + `PKR_VAR_aws_region` env var
- Replaced inline `tofu init/plan/apply` in CI deploy job with `./run tf-init` + `./run tf-auto-apply`
- Removed deploy job `artifacts:` block (plan-file workflow dropped)
- Extended CI shellcheck job to lint `run` alongside `scripts/*.sh`
- Added grep-gates invariant #8 verifying `run` executable bit (`100755`) in both CI and pre-commit
- Updated invariant count from 7 to 8 in CI grep-gates echo

## Task Commits

Each task was committed atomically:

1. **Task 1: Add CI-aware lockfile flag to ./run tf-init** - `ab82dc5` (feat)
2. **Task 2: Wire GitLab CI bake, deploy, shellcheck, and grep-gates to use ./run** - `4ceadf3` (feat)

## Files Created/Modified
- `run` - Added `lockfile_flag` with CI-aware `-lockfile=readonly` to `cmd_tf_init` and `cmd_tf_reinit`
- `.gitlab-ci.yml` - Bake job: added `PKR_VAR_aws_region` variable, replaced inline packer commands with `./run build`. Deploy job: replaced inline tofu commands with `./run tf-init` + `./run tf-auto-apply`, removed `artifacts:` block, updated comment block. Shellcheck job: added `run` to shellcheck args. Grep-gates job: added invariant #8 (run executable bit), updated count to 8.
- `.pre-commit-config.yaml` - Grep-gates hook: added invariant #7 (run executable bit check) for CI parity

## Decisions Made
- Plan-file workflow (`tofu plan -out=tfplan && tofu apply tfplan`) dropped from CI deploy -- the `when: manual` gate + protected branch + OIDC + DEVBOX_USER validation provide sufficient defense-in-depth without the plan artifact (RESEARCH.md Open Question 1 / Pitfall 3)
- Deploy `before_script` DEVBOX_USER validation retained alongside `./run _require_devbox_user` as defense-in-depth -- the CI-side check saves an STS AssumeRole call on bad input (RESEARCH.md Open Question 3)
- `PKR_VAR_aws_region: ${AWS_REGION}` set as a CI job variable rather than modifying `./run build` -- uses Packer's standard `PKR_VAR_*` convention, keeps `./run` unchanged

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 06 (gitlab-ci-polish) is complete with all 4 CI requirements closed (CI-01 through CI-04) and both POL requirements from Plan 01 (POL-01, POL-02)
- Phase 07 (docs-cleanup) can proceed -- it will update CLAUDE.md and all docs from `make` to `./run`, then delete the Makefile

---
*Phase: 06-gitlab-ci-polish*
*Completed: 2026-05-27*
