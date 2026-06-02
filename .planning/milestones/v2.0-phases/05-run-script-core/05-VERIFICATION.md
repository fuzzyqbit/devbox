---
phase: 05-run-script-core
verified: 2026-05-27T14:30:00Z
status: human_needed
score: 8/8 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Install bash 4+ (brew install bash), run ./run help, and verify all 20 commands are listed in 6 groups"
    expected: "Grouped output with AMI (4 commands), Terraform (8 commands), Instance lifecycle (3), SSM (2), Secrets (1), Cleanup (1)"
    why_human: "macOS system bash is 3.2; the version guard blocks execution; runtime validation requires Homebrew bash"
  - test: "Run DEVBOX_USER= ./run tf-plan and DEVBOX_USER=INVALID ./run tf-plan"
    expected: "Both exit non-zero. First prints DEVBOX_USER not set with fix instructions. Second prints format validation error."
    why_human: "Requires bash 4+ runtime to exercise the guard functions"
  - test: "With valid AWS credentials and DEVBOX_USER, run ./run tf-init then ./run tf-plan and verify it passes through to tofu"
    expected: "tf-init resolves TF_STATE_BUCKET via STS, runs tofu init with backend-config flags. tf-plan calls tf-ensure-init then tofu plan."
    why_human: "Requires live AWS credentials and bash 4+ to verify end-to-end"
---

# Phase 5: Run Script Core Verification Report

**Phase Goal:** Operators can use `./run <command>` for all operations, with safety guards that fail fast on bad input
**Verified:** 2026-05-27T14:30:00Z
**Status:** human_needed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Operator can run ./run help and see grouped command reference with all 20 commands | VERIFIED | `cmd_help()` (lines 271-306) contains all 6 groups: AMI, Terraform/OpenTofu, Instance lifecycle, SSM access, Secrets, Cleanup. 19 commands listed in help text + help itself as dispatch target = 20. Case dispatch at lines 316-341 has 20 branches. |
| 2 | Operator can run ./run build and it executes packer init + packer build in packer/ directory | VERIFIED | `cmd_build()` (lines 94-97): calls `cmd_packer_init` then `(cd "$REPO_ROOT/packer" && packer build .)`. Subshell cd pattern prevents directory leakage. |
| 3 | Operator can run ./run tf-apply and it auto-reinitializes backend when cached state key mismatches DEVBOX_USER | VERIFIED | `cmd_tf_apply()` (line 142) calls `cmd_tf_ensure_init` first. `cmd_tf_ensure_init()` (lines 109-120) reads `.backend.config.key` via jq from `terraform/.terraform/terraform.tfstate`, compares to desired key, calls `cmd_tf_reinit` on mismatch. |
| 4 | Running ./run with unset DEVBOX_USER on a command that requires it prints actionable error and exits non-zero | VERIFIED | `_require_devbox_user()` (lines 33-45): empty check at line 34, prints "ERROR: DEVBOX_USER is not set." with fix instructions (`DEVBOX_USER=jsmith ./run <command>` or `export DEVBOX_USER=jsmith`), exits 1. |
| 5 | Running ./run with malformed DEVBOX_USER prints format error and exits non-zero | VERIFIED | `_require_devbox_user()` line 40: regex `^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$` rejects uppercase, leading/trailing dashes, >32 chars. Prints "ERROR: DEVBOX_USER='...' is invalid." with format requirements, exits 1. |
| 6 | Running ./run tf-init with invalid AWS credentials prints actionable TF_STATE_BUCKET error and exits non-zero | VERIFIED | `_derive_tf_state_bucket()` (lines 47-60): checks if account_id is empty or composed bucket equals `devimage-tfstate-`. Prints "ERROR: could not resolve AWS account ID..." with fix instructions, exits 1. |
| 7 | shellcheck ./run passes with zero errors | VERIFIED | `shellcheck run` exits 0. Seven SC2046 disables are intentional for word-splitting of `_tf_backend_args`/`_tf_var_args` output. |
| 8 | git ls-files -s run shows mode 100755 | VERIFIED | `git ls-files -s run` returns `100755 bbf00b53ffe246d323a83d33616fbb086e6af262 0 run`. |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `run` | Operator command dispatcher replacing Makefile, >250 lines | VERIFIED | 344 lines. Substantive: 20 command functions, 5 guard functions, case dispatch, help text, version guard. No stubs/placeholders. Wired: delegated scripts exist (`devbox-start.sh`, `devbox-stop.sh`, `devbox-status.sh`, `devbox-ssm.sh`). Not imported by other files (standalone entry point). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `run` | `scripts/devbox-start.sh` | exec delegation for start command | WIRED | Line 173: `"$REPO_ROOT/scripts/devbox-start.sh" "$@"`. Script exists (2268 bytes). |
| `run` | `scripts/devbox-stop.sh` | exec delegation for stop command | WIRED | Line 179: `"$REPO_ROOT/scripts/devbox-stop.sh" "$@"`. Script exists (1284 bytes). |
| `run` | `scripts/devbox-status.sh` | exec delegation for status command | WIRED | Line 185: `"$REPO_ROOT/scripts/devbox-status.sh" "$@"`. Script exists (2432 bytes). |
| `run` | `scripts/devbox-ssm.sh` | exec delegation for devbox-ssm command | WIRED | Line 195: `"$REPO_ROOT/scripts/devbox-ssm.sh" "$@"`. Script exists (2043 bytes). |
| `run` | `scripts/_common.sh` | NOT sourced -- run is standalone dispatcher | VERIFIED | Zero matches for `_common.sh` in `run`. Script defines its own DEVBOX_USER, INSTANCE_ID, REGION variables (lines 20-25). Lifecycle scripts source `_common.sh` themselves. |

### Data-Flow Trace (Level 4)

Not applicable -- `run` is a CLI dispatcher, not a UI component rendering dynamic data. Variable flow verified through static analysis of guard function call chains.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Version guard blocks bash 3.2 | `./run help` | "ERROR: Bash 4+ required. macOS: brew install bash" (exit 1) | PASS |
| shellcheck passes | `shellcheck run` | Exit 0, zero warnings | PASS |
| Executable bit in git | `git ls-files -s run` | `100755 bbf00b53...` | PASS |
| Help exits 0 on bash 4+ | N/A (bash 3.2 only) | Cannot test | SKIP (requires bash 4+) |
| DEVBOX_USER guard on bash 4+ | N/A | Cannot test | SKIP (requires bash 4+) |

### Probe Execution

Step 7c: SKIPPED (no probes defined for this phase)

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| RUN-01 | 05-01 | `./run` script with case-statement dispatcher handles all 20 commands | SATISFIED | 20 case branches (lines 316-341), one per Makefile PHONY target |
| RUN-02 | 05-01 | `./run help` prints grouped command reference | SATISFIED | `cmd_help()` lines 271-306, 6 groups matching Makefile help output |
| RUN-03 | 05-01 | Fails fast when DEVBOX_USER unset | SATISFIED | `_require_devbox_user()` line 34: empty check with actionable error |
| RUN-04 | 05-01 | Fails fast when TF_STATE_BUCKET derivation returns empty | SATISFIED | `_derive_tf_state_bucket()` lines 54-58: guards empty account_id |
| RUN-05 | 05-01 | Auto-reinitializes terraform backend on cached key mismatch | SATISFIED | `cmd_tf_ensure_init()` lines 109-120: jq key comparison + reinit |
| RUN-06 | 05-01 | `set -euo pipefail`, REPO_ROOT anchor, subshell cd | SATISFIED | Line 2: strict mode. Line 15: REPO_ROOT via BASH_SOURCE. 13 subshell cd patterns, zero bare cd. |
| RUN-07 | 05-01 | Executable bit committed to git | SATISFIED | `git ls-files -s run` shows 100755 |
| RUN-08 | 05-01 | DEVBOX_USER format validation (regex) | SATISFIED | Line 40: `^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$` with clear error message |

No orphaned requirements. All 8 IDs from REQUIREMENTS.md Phase 5 mapping are accounted for.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `run` | 125,132,138,144,150,156,162 | `shellcheck disable=SC2046` (7 instances) | INFO | Intentional: `_tf_backend_args` and `_tf_var_args` return space-separated flags that must word-split at call sites. Documented in SUMMARY key-decisions. |

No TBD, FIXME, XXX, TODO, HACK, or PLACEHOLDER markers found. No empty implementations. No hardcoded empty data. No placeholder text.

### Human Verification Required

### 1. End-to-end help output with bash 4+

**Test:** Install bash 4+ (`brew install bash`), run `./run help`, and verify all 20 commands are listed in 6 groups.
**Expected:** Grouped output with AMI (4 commands), Terraform/OpenTofu (8 commands), Instance lifecycle (3), SSM access (2), Secrets (1), Cleanup (1). Exit code 0.
**Why human:** macOS system bash is 3.2; the version guard correctly blocks execution. Runtime validation requires Homebrew bash 4+.

### 2. DEVBOX_USER guard end-to-end

**Test:** Run `DEVBOX_USER= ./run tf-plan` and `DEVBOX_USER=INVALID ./run tf-plan` with bash 4+.
**Expected:** Both exit non-zero. First prints "ERROR: DEVBOX_USER is not set." with fix instructions. Second prints "ERROR: DEVBOX_USER='INVALID' is invalid." with format requirements.
**Why human:** Requires bash 4+ runtime to exercise the guard functions end-to-end.

### 3. Live AWS integration

**Test:** With valid AWS credentials and DEVBOX_USER, run `./run tf-init` then `./run tf-plan`.
**Expected:** tf-init resolves TF_STATE_BUCKET via STS, runs tofu init with backend-config flags. tf-plan calls tf-ensure-init then tofu plan.
**Why human:** Requires live AWS credentials and bash 4+ to verify AWS STS derivation and tofu integration end-to-end.

### Observations

**Code review fix (WR-01):** `cmd_devbox_port_forward` was intentionally changed post-review to call `cmd_tf_ensure_init` instead of `_require_devbox_user`, deviating from the original plan but improving correctness (prevents stale instance ID after DEVBOX_USER switch). The Makefile has the same bug; the `./run` script is now more correct than the Makefile. This is documented in commit `fc2a871` and the code review report.

---

_Verified: 2026-05-27T14:30:00Z_
_Verifier: Claude (gsd-verifier)_
