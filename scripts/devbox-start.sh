#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Start a user's devbox EC2 instance.

Options:
  --user USERNAME     Devbox owner (default: \$(whoami))
  --instance-id ID    EC2 instance ID (overrides Terraform state)
  --region REGION     AWS region (overrides Terraform state)
  -h, --help          Show this help message
EOF
  exit 0
}

parse_args "$@"
init_devbox

# Check current state
CURRENT_STATE="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)"

if [[ "$CURRENT_STATE" == "running" ]]; then
  echo "Instance is already running."
elif [[ "$CURRENT_STATE" == "stopped" ]]; then
  echo "Starting instance..."
  aws ec2 start-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --output text > /dev/null

  echo "Waiting for instance to reach running state..."
  aws ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION"

  echo "Waiting for status checks to pass..."
  aws ec2 wait instance-status-ok \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION"

  echo "Instance is running."
else
  echo "Instance is in '$CURRENT_STATE' state — cannot start." >&2
  exit 1
fi

echo ""

# Fetch connection info
PUBLIC_IP="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)"

# KEY_NAME query retained for parity with status.sh; no longer surfaced in the
# Phase 2 connection-info block (Phase 1 SSH path is closed). Pending cleanup.
# shellcheck disable=SC2034
KEY_NAME="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].KeyName' \
  --output text)"

echo "=== Connection Info ($DEVBOX_USER) ==="
echo "Public IP:           $PUBLIC_IP"
echo "Shell (SSM):         aws ssm start-session --target $INSTANCE_ID --region $REGION"
echo "                     (or: make devbox-ssm DEVBOX_USER=$DEVBOX_USER)"
echo "code-server:         https://${PUBLIC_IP}:8080   (requires your IP in allowed_web_cidrs)"
echo "noVNC:               https://${PUBLIC_IP}:6080   (requires your IP in allowed_web_cidrs)"
echo ""
echo "Browser access blocked? Check var.allowed_web_cidrs in your tfvars and re-run 'make tf-apply'."
