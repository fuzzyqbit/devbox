#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

KEY_NAME="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].KeyName' \
  --output text)"

echo "=== Connection Info ($DEVBOX_USER) ==="
echo "Public IP:    $PUBLIC_IP"
echo "SSH:          ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
echo "code-server:  https://${PUBLIC_IP}:8080"
echo "noVNC:        https://${PUBLIC_IP}:6080"
