---
phase: 05-run-script-core
reviewed: 2026-05-27T12:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - run
findings:
  critical: 0
  warning: 3
  info: 1
  total: 4
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-05-27
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

The `./run` script is a well-structured Bash dispatcher that faithfully ports the Makefile's 20 commands to a standalone script. The code demonstrates strong defensive patterns: `set -euo pipefail`, a Bash 4+ version guard, `REPO_ROOT` anchoring via `BASH_SOURCE[0]`, subshell `cd` to prevent directory leaks, regex-validated `DEVBOX_USER`, and lazy `TF_STATE_BUCKET` derivation with an empty-guard. shellcheck passes clean. The `tf-ensure-init` auto-reinit logic is correctly ported.

Three warnings were found: a missing `tf-ensure-init` guard on `devbox-port-forward` that can cause it to read the wrong user's Terraform state, a help text that documents an invocation syntax that does not work, and AWS error suppression in `secrets-show` that hides permission errors from the operator.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: devbox-port-forward reads Terraform state without tf-ensure-init guard

**File:** `run:198-208`
**Issue:** `cmd_devbox_port_forward` calls `_require_devbox_user` (line 199) but does NOT call `cmd_tf_ensure_init` before reading Terraform output on lines 207-208. If an operator switches `DEVBOX_USER` between invocations without manually running `tf-init`, the `.terraform/` backend cache still points at the previous user's state key. The `tofu output -raw instance_id` call on line 207 will silently return the WRONG user's instance ID, and the operator's SSM port-forwarding session will connect to someone else's devbox.

This is a faithful port of the Makefile (line 175: `devbox-port-forward: _require-devbox-user` without `tf-ensure-init`), but the bug exists in both. The `devbox-ssm` command (line 192) correctly uses `cmd_tf_ensure_init`, making this an inconsistency within the script itself.

**Fix:**
```bash
cmd_devbox_port_forward() {
  cmd_tf_ensure_init   # <-- add this, replacing _require_devbox_user (tf_ensure_init calls it)
  if ! command -v session-manager-plugin >/dev/null 2>&1; then
```

### WR-02: Help text documents an invocation syntax the script does not support

**File:** `run:266`
**Issue:** The help output reads `Usage: ./run <command> [DEVBOX_USER=username]`, suggesting the operator can pass `DEVBOX_USER=username` as a trailing positional argument. The script does not parse positional `KEY=value` arguments -- the Bash shell only interprets `VAR=value` as environment assignment when it appears BEFORE the command (`DEVBOX_USER=jsmith ./run tf-apply`), not after it. When an operator runs `./run tf-apply DEVBOX_USER=jsmith`, the literal string `DEVBOX_USER=jsmith` becomes a positional arg in `$@`, which is silently ignored by `cmd_tf_apply` (it does not consume `$@`). The operator gets the "DEVBOX_USER is not set" error or, worse, picks up a stale `DEVBOX_USER` from the environment.

The Makefile equivalent (`make <target> DEVBOX_USER=jsmith`) works because Make has built-in variable-override syntax for trailing `KEY=value` arguments. Bash does not.

**Fix:** Update the help text to show the correct invocation syntax:
```bash
cat <<'EOF'
Usage: DEVBOX_USER=username ./run <command>
       (or: export DEVBOX_USER=username; ./run <command>)
EOF
```

### WR-03: secrets-show suppresses all AWS stderr, hiding permission-denied errors

**File:** `run:228-241`
**Issue:** Both `aws ssm get-parameter` calls on lines 228-230 and 236-238 use `2>/dev/null` to suppress AWS CLI stderr. When the parameter genuinely does not exist, this is fine -- the script provides its own error message. However, if the failure is due to IAM permission denial (`AccessDeniedException`), expired credentials, or a network error, the AWS CLI's diagnostic message is discarded and the operator sees only "code-server password not found at /devbox/..." which sends them down the wrong troubleshooting path ("Run './run build' first" when the real problem is their IAM policy).

**Fix:** Capture stderr and display it on failure:
```bash
local aws_err
cs_pwd="$(aws ssm get-parameter \
  --name "/devbox/${DEVBOX_USER}/code-server-password" \
  --with-decryption --query 'Parameter.Value' --output text 2>"$aws_err_file")" \
  || {
    echo "ERROR: could not retrieve code-server password at /devbox/${DEVBOX_USER}/code-server-password" >&2
    echo "       AWS error: $(cat "$aws_err_file")" >&2
    echo "       Run './run build' first to publish secrets, or check IAM permissions." >&2
    exit 1
  }
```
Or more simply, remove `2>/dev/null` and let AWS CLI's own error messages flow to stderr naturally, since the `|| { ... exit 1; }` block already handles the non-zero exit:
```bash
cs_pwd="$(aws ssm get-parameter \
  --name "/devbox/${DEVBOX_USER}/code-server-password" \
  --with-decryption --query 'Parameter.Value' --output text)" \
  || {
    echo "ERROR: code-server password not found at /devbox/${DEVBOX_USER}/code-server-password" >&2
    echo "       Run './run build' first to publish secrets to SSM, or check your DEVBOX_USER." >&2
    exit 1
  }
```

## Info

### IN-01: Redundant condition in _derive_tf_state_bucket guard

**File:** `run:54`
**Issue:** The guard `[[ -z "$account_id" ]] || [[ "devimage-tfstate-${account_id}" == "devimage-tfstate-" ]]` is redundant -- the second clause can only be true when `account_id` is empty, which the first clause already catches. Both branches produce the same outcome. This is belt-and-suspenders defensiveness and is not incorrect, but it could confuse future maintainers into thinking there's a case where `account_id` is non-empty yet the composed string still equals `"devimage-tfstate-"`.

**Fix:** Simplify to a single check (optional):
```bash
if [[ -z "$account_id" ]]; then
```

---

_Reviewed: 2026-05-27_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
