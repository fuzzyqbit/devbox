---
phase: 07-docs-cleanup
plan: 01
subsystem: infra
tags: [docs, cleanup, makefile-retirement, grep-gates, run-dispatcher]

requires:
  - phase: 05-run-script-core
    provides: "./run shell dispatcher with 20 commands"
  - phase: 06-gitlab-ci-polish
    provides: "CI delegates to ./run; grep-gates parity across CI + pre-commit"
provides:
  - "Makefile deleted from the repository (./run is the sole operator surface)"
  - "All operator-facing `make <target>` hints converted to `./run` across docs, scripts, and Terraform strings"
  - "grep-gate invariant rejecting retired `make <target>` invocations in tracked files (pre-commit + GitLab CI + GitHub CI)"
affects: []

tech-stack:
  added: []
  patterns: [target-scoped grep gate to distinguish operator make-targets from genuine `make -j` build tool]

key-files:
  created: []
  modified: [CLAUDE.md, run, scripts/_common.sh, scripts/devbox-ssm.sh, scripts/devbox-start.sh, scripts/devbox-status.sh, scripts/devbox-stop.sh, ansible/firewalld-docker-fix.yml, terraform/main.tf, terraform/outputs.tf, terraform/backend.tf, terraform/terraform.tfvars, .pre-commit-config.yaml, .gitlab-ci.yml, .github/workflows/ci.yml]
  deleted: [Makefile]

key-decisions:
  - "grep-gate scoped to the former Makefile target names (build|validate|fmt|packer-init|tf-*|start|stop|status|devbox-*|secrets-show|clean|doctor|help) rather than a blanket `make ` match -- avoids false-positives on the genuine `make -j` C++/thrift build in ansible/roles/devtools and English prose (\"make changes\")"
  - "CLAUDE.md is .gitignored (local-only operator quickstart) -- its conversion is satisfied locally; the grep-gate enforces tracked content only"
  - "Added missing `# shellcheck source=_common.sh disable=SC1091` to devbox-stop.sh to match its three sibling scripts (fixed a pre-existing latent shellcheck gate failure surfaced during verification)"

patterns-established:
  - "Operator-surface invariant: no retired `make <target>` invocation may reappear in tracked files; enforced identically at pre-commit, GitLab CI, and GitHub CI"

requirements-completed: [DOC-01, DOC-02]

duration: ~20min
completed: 2026-06-02
---

# Phase 07 Plan 01: Docs + Cleanup Summary

**Makefile retired; `./run` is the sole operator surface, enforced by a new grep-gate across all three CI surfaces**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-06-02
- **Tasks:** 1 (direct execution — mechanical docs/cleanup phase)
- **Files modified:** 15 (+ Makefile deleted)

## Accomplishments
- Deleted the 219-line `Makefile`; `./run` is now the single operator entrypoint (verified via `git log --diff-filter=D -- Makefile`)
- Converted all operator-facing `make <target>` hints to `./run` form across CLAUDE.md, the `scripts/*.sh` runtime messages, and the Terraform output/comment strings; env-var prefix form adopted (`DEVBOX_USER=alice ./run tf-apply`)
- Added grep-gate invariant rejecting retired `make <target>` invocations in tracked files, wired identically into `.pre-commit-config.yaml`, `.gitlab-ci.yml`, and `.github/workflows/ci.yml`
- Fixed a pre-existing missing shellcheck source directive in `devbox-stop.sh` (SC1091) that would otherwise fail the shellcheck gate

## Success Criteria Verification
1. ✅ CLAUDE.md contains no `make` command references (local/.gitignored; converted in place)
2. ✅ Makefile no longer exists — confirmed in `git log --diff-filter=D` (commit `649ce1b`)
3. ✅ grep-gate confirms no retired `make <target>` invocations remain in tracked files (0 matches); gate present in pre-commit + GitLab CI + GitHub CI

## Task Commits
1. **Retire Makefile, make ./run the sole operator surface** — `649ce1b` (refactor)

## Verification Performed
- `git grep` for the former Makefile target names across tracked files (`:!.planning`) — 0 matches
- `shellcheck scripts/*.sh run` — exit 0
- `tofu fmt -check` in `terraform/` — exit 0
- `bash -n run` — syntax OK (full `./run help` requires bash 4+; macOS 3.2 hits the guard by design)

## Deviations from Plan
This phase was executed directly (no pre-written PLAN.md) at the operator's request during milestone close. Scope grew beyond CLAUDE.md once `git grep` surfaced stale `make` hints in scripts and Terraform strings — all operator-facing references were converted for correctness, not just the documentation.

## Issues Encountered
- Discovered CLAUDE.md is `.gitignore`d, so success criterion 1 cannot be enforced by a tracked-file grep-gate; satisfied locally and noted in the gate scope.
- `devbox-stop.sh` was missing the shellcheck source directive its three siblings have — added for gate parity.

## User Setup Required
None.

## Next Phase Readiness
- v2.0 milestone (Phases 5–7) complete; all RUN, CI, POL, and DOC requirements closed.
- Ready for milestone archival and the next milestone (jupyter notebook + mise).

---
*Phase: 07-docs-cleanup*
*Completed: 2026-06-02*
