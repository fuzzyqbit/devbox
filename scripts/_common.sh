#!/usr/bin/env bash
# Shared helpers sourced by all devbox scripts.
# Sets: DEVBOX_USER, INSTANCE_ID, REGION, PROJECT_DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_DIR/terraform"

DEVBOX_USER="${DEVBOX_USER:-}"
INSTANCE_ID="${INSTANCE_ID:-}"
REGION="${REGION:-}"

# Parse common flags. Callers should invoke: parse_args "$@"
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --user)        DEVBOX_USER="$2"; shift 2 ;;
      --instance-id) INSTANCE_ID="$2"; shift 2 ;;
      --region)      REGION="$2"; shift 2 ;;
      -h|--help)     usage ;;
      *)             echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
}

# Resolve the user — explicit flag > env var > whoami
resolve_user() {
  if [[ -z "$DEVBOX_USER" ]]; then
    DEVBOX_USER="$(whoami)"
  fi
}

# Resolve instance ID and region from Terraform state.
# Requires `DEVBOX_USER=... ./run tf-init` to have run first (operator-scoped
# backend key — see the TF_STATE_KEY logic in ./run).
resolve_instance() {
  # TF_BIN: operator override (terraform vs tofu). Default matches ./run.
  local tfbin="${TF_BIN:-tofu}"

  if [[ -z "$INSTANCE_ID" ]]; then
    # Capture stderr to a temp var so the operator sees the real failure
    # (previously swallowed by 2>/dev/null which made every failure look the same).
    local tf_combined tf_rc
    tf_combined="$(cd "$TF_DIR" && "$tfbin" output -raw instance_id 2>&1)" && tf_rc=0 || tf_rc=$?
    if [[ "$tf_rc" -eq 0 ]] && [[ -n "$tf_combined" ]]; then
      INSTANCE_ID="$tf_combined"
    else
      echo "Error: Could not read instance_id from Terraform state for user '$DEVBOX_USER'." >&2
      echo "" >&2
      echo "Underlying $tfbin error (rc=$tf_rc):" >&2
      printf '    %s\n' "${tf_combined//$'\n'/$'\n'    }" >&2
      echo "" >&2
      echo "Common fixes:" >&2
      echo "  - First apply for this user:    DEVBOX_USER=$DEVBOX_USER ./run tf-apply" >&2
      echo "  - Backend stale / wrong key:    DEVBOX_USER=$DEVBOX_USER ./run tf-reinit" >&2
      echo "  - Bypass resolution from ./run: INSTANCE_ID=i-... REGION=us-east-1 ./run status" >&2
      echo "  - Direct script invocation:     $(basename "$0") --instance-id i-... --region us-east-1" >&2
      exit 1
    fi
  fi

  if [[ -z "$REGION" ]]; then
    REGION="$(cd "$TF_DIR" && "$tfbin" output -raw aws_region 2>/dev/null)" \
      || REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
  fi
}

# Full init sequence — call this after parse_args
init_devbox() {
  resolve_user
  resolve_instance

  echo "User:     $DEVBOX_USER"
  echo "Instance: $INSTANCE_ID"
  echo "Region:   $REGION"
  echo ""
}

# Run a one-shot shell command on the devbox over SSM (AWS-RunShellScript), wait for it to
# finish, print its stdout/stderr, and return its exit status. Uses INSTANCE_ID + REGION.
# Needs ssm:SendCommand + ssm:GetCommandInvocation on the operator's creds (no
# session-manager-plugin required — this is a pure API call, unlike `devbox-ssm`).
# Args: $1 = command string to run as root on the instance.
ssm_run_shell() {
  local cmd="$1" cmd_id status out err
  cmd_id="$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --document-name "AWS-RunShellScript" \
    --comment "devbox $(basename "$0")" \
    --parameters "$(jq -n --arg c "$cmd" '{commands: [$c]}')" \
    --query 'Command.CommandId' --output text)" || {
    echo "ERROR: ssm send-command failed (check ssm:SendCommand perms + SSM agent Online)" >&2
    return 1
  }
  echo "SSM command $cmd_id dispatched; waiting for completion..." >&2
  local waited=0
  while true; do
    status="$(aws ssm get-command-invocation \
      --command-id "$cmd_id" --instance-id "$INSTANCE_ID" --region "$REGION" \
      --query 'Status' --output text 2>/dev/null || echo Pending)"
    case "$status" in
      Success | Failed | Cancelled | TimedOut) break ;;
      *)
        sleep 3
        waited=$((waited + 3))
        if [[ "$waited" -ge 300 ]]; then
          echo "ERROR: SSM command never reached a terminal state within 300s — is the instance running and the SSM agent Online? Check: aws ssm describe-instance-information" >&2
          return 1
        fi
        ;;
    esac
  done
  out="$(aws ssm get-command-invocation --command-id "$cmd_id" \
    --instance-id "$INSTANCE_ID" --region "$REGION" \
    --query 'StandardOutputContent' --output text)"
  err="$(aws ssm get-command-invocation --command-id "$cmd_id" \
    --instance-id "$INSTANCE_ID" --region "$REGION" \
    --query 'StandardErrorContent' --output text)"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  [[ -n "$err" ]] && printf '%s\n' "$err" >&2
  echo "SSM command $status" >&2
  [[ "$status" == "Success" ]]
}
