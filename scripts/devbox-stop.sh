#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Stop a user's devbox EC2 instance.

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

if [[ "$CURRENT_STATE" == "stopped" ]]; then
  echo "Instance is already stopped."
  exit 0
elif [[ "$CURRENT_STATE" == "running" ]]; then
  echo "Stopping instance..."
  aws ec2 stop-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --output text > /dev/null

  echo "Waiting for instance to reach stopped state..."
  aws ec2 wait instance-stopped \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION"

  echo "Instance is stopped. You are no longer being charged for compute."
else
  echo "Instance is in '$CURRENT_STATE' state — cannot stop." >&2
  exit 1
fi
