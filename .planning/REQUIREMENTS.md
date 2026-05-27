# Requirements: devbox v2.0

**Defined:** 2026-05-27
**Core Value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one command — without leaking credentials or exposing a vulnerable host to the public internet.

## v2.0 Requirements

### Run Script Core

- [x] **RUN-01**: `./run` script with case-statement dispatcher handles all 20 commands previously in Makefile
- [x] **RUN-02**: `./run help` prints grouped command reference (AMI / Terraform / Lifecycle / SSM / Secrets / Cleanup)
- [x] **RUN-03**: `./run` fails fast with actionable error when DEVBOX_USER is unset for commands that require it
- [x] **RUN-04**: `./run` fails fast with actionable error when TF_STATE_BUCKET derivation returns empty account ID
- [x] **RUN-05**: `./run` auto-reinitializes terraform backend when cached state key mismatches current DEVBOX_USER (tf-ensure-init port)
- [x] **RUN-06**: `./run` uses `set -euo pipefail`, anchors REPO_ROOT via script location, wraps `cd` in subshells
- [x] **RUN-07**: `./run` executable bit committed to git (`git update-index --chmod=+x`)
- [x] **RUN-08**: `./run` validates DEVBOX_USER format (lowercase, alphanumeric + dash, 2-32 chars) with clear error message

### Run Script Polish

- [x] **POL-01**: `./run` outputs colored status/error messages with NO_COLOR and CI environment guards
- [x] **POL-02**: `./run doctor` checks all required dependencies (aws, packer, tofu, ansible, jq, shellcheck, gitleaks, pre-commit, session-manager-plugin) and reports missing/version issues

### GitLab CI Integration

- [x] **CI-01**: GitLab CI bake stage calls `./run build` instead of inline packer commands
- [x] **CI-02**: GitLab CI deploy stage calls `./run tf-init` and `./run tf-apply` instead of inline tofu commands
- [x] **CI-03**: Validate shellcheck job includes `run` file alongside `scripts/*.sh`
- [x] **CI-04**: Grep-gate invariant verifies `run` file has executable bit in git

### Documentation + Cleanup

- [ ] **DOC-01**: CLAUDE.md updated — all `make` references replaced with `./run` equivalents
- [ ] **DOC-02**: Makefile deleted from repository

## Future Requirements

### Deferred from v1.0

- **OBS-01**: CloudWatch metrics + login event shipping
- **LIFE-01**: Idle auto-stop + scheduled nightly stop
- **IMG-01**: Old AMI deregistration + inventory
- **REP-01**: Pin Packer SSM parameter `:NN` version suffix

## Out of Scope

| Feature | Reason |
|---------|--------|
| Tab completion for `./run` | Complexity trap — 20 commands are easily discoverable via `./run help` |
| Config file for `./run` | Environment variables sufficient; config file adds a loading/precedence layer with no benefit |
| Plugin system / extensibility | Single-operator project with fixed command surface |
| Interactive menus / prompts | Must work in CI runners with no TTY |
| `./run` auto-update mechanism | Script lives in the repo; `git pull` is the update mechanism |
| Validate jobs routed through `./run` | Nine validate jobs run in single-binary images; routing through `./run` adds indirection with no benefit |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RUN-01 | Phase 5 | Complete |
| RUN-02 | Phase 5 | Complete |
| RUN-03 | Phase 5 | Complete |
| RUN-04 | Phase 5 | Complete |
| RUN-05 | Phase 5 | Complete |
| RUN-06 | Phase 5 | Complete |
| RUN-07 | Phase 5 | Complete |
| RUN-08 | Phase 5 | Complete |
| POL-01 | Phase 6 | Complete |
| POL-02 | Phase 6 | Complete |
| CI-01 | Phase 6 | Complete |
| CI-02 | Phase 6 | Complete |
| CI-03 | Phase 6 | Complete |
| CI-04 | Phase 6 | Complete |
| DOC-01 | Phase 7 | Pending |
| DOC-02 | Phase 7 | Pending |

**Coverage:**
- v2.0 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0 ✓

---
*Requirements defined: 2026-05-27*
*Last updated: 2026-05-27 after roadmap creation*
