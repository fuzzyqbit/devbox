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
# Requires `make tf-init DEVBOX_USER=...` to have run first (operator-scoped
# backend key — see Makefile TF_STATE_KEY).
resolve_instance() {
  # TF_BIN: operator override (terraform vs tofu). Default matches Makefile.
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
      echo "  - First apply for this user:    make tf-apply  DEVBOX_USER=$DEVBOX_USER" >&2
      echo "  - Backend stale / wrong key:    make tf-reinit DEVBOX_USER=$DEVBOX_USER" >&2
      echo "  - Bypass resolution from make:  make status INSTANCE_ID=i-... REGION=us-east-1" >&2
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
