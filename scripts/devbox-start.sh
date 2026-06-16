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

# Fetch connection info. Private-only — no PublicIpAddress query.
PRIVATE_IP="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)"

echo "=== Connection Info ($DEVBOX_USER) ==="
echo "Private IP:          $PRIVATE_IP"
echo "Shell (SSM):         aws ssm start-session --target $INSTANCE_ID --region $REGION"
echo "                     (or: DEVBOX_USER=$DEVBOX_USER ./run devbox-ssm)"
echo "code-server:         https://${PRIVATE_IP}:8080  (reachable from VPC; requires your CIDR in allowed_web_cidrs)"
echo "RDP desktop:         ${PRIVATE_IP}:3389  (native RDP client; reachable from VPC; requires your CIDR in allowed_web_cidrs)"
echo ""
echo "Off-VPC? Use './run devbox-port-forward' for code-server (:8080) or './run devbox-port-forward 3389' for RDP, or check var.allowed_web_cidrs."
