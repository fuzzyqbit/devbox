#!/usr/bin/env bash
# Shared helpers sourced by all devbox scripts.
# Sets: DEVBOX_USER, INSTANCE_ID, REGION, PROJECT_DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_DIR/terraform"
TG_DIR="$PROJECT_DIR"

DEVBOX_USER="${DEVBOX_USER:-}"
INSTANCE_ID=""
REGION=""

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

# Resolve instance ID and region from Terragrunt state
resolve_instance() {
  if [[ -z "$INSTANCE_ID" ]]; then
    INSTANCE_ID="$(cd "$TG_DIR" && DEVBOX_USER="$DEVBOX_USER" terragrunt output -raw instance_id 2>/dev/null)" || {
      echo "Error: Could not read instance_id from Terragrunt state for user '$DEVBOX_USER'." >&2
      echo "Run 'make tg-apply DEVBOX_USER=$DEVBOX_USER' first, or pass --instance-id." >&2
      exit 1
    }
  fi

  if [[ -z "$REGION" ]]; then
    REGION="$(cd "$TG_DIR" && DEVBOX_USER="$DEVBOX_USER" terragrunt output -raw aws_region 2>/dev/null)" \
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
