#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Show the current status of a user's devbox EC2 instance.

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

# Fetch instance details
INFO="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].{State:State.Name,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,Type:InstanceType,LaunchTime:LaunchTime,KeyName:KeyName}' \
  --output json)"

STATE="$(echo "$INFO" | jq -r '.State')"
PUBLIC_IP="$(echo "$INFO" | jq -r '.PublicIp // "N/A"')"
PRIVATE_IP="$(echo "$INFO" | jq -r '.PrivateIp // "N/A"')"
INSTANCE_TYPE="$(echo "$INFO" | jq -r '.Type')"
LAUNCH_TIME="$(echo "$INFO" | jq -r '.LaunchTime // "N/A"')"
KEY_NAME="$(echo "$INFO" | jq -r '.KeyName // "N/A"')"

echo "=== Devbox Status ($DEVBOX_USER) ==="
echo "Instance ID:   $INSTANCE_ID"
echo "Region:        $REGION"
echo "State:         $STATE"
echo "Instance Type: $INSTANCE_TYPE"
echo "Public IP:     $PUBLIC_IP"
echo "Private IP:    $PRIVATE_IP"
echo "Key Name:      $KEY_NAME"
echo "Launch Time:   $LAUNCH_TIME"

if [[ "$STATE" == "running" ]]; then
  echo ""
  echo "=== Connection Info ==="
  # Shell access is brokered by SSM — no public IP needed.
  echo "Shell (SSM):          aws ssm start-session --target ${INSTANCE_ID} --region ${REGION}"
  echo "                      (or: make devbox-ssm DEVBOX_USER=${DEVBOX_USER})"
  if [[ "$PUBLIC_IP" != "N/A" ]]; then
    echo "code-server (browser): https://${PUBLIC_IP}:8080   (requires your IP in allowed_web_cidrs)"
    echo "noVNC (browser):       https://${PUBLIC_IP}:6080   (requires your IP in allowed_web_cidrs)"
    echo ""
    echo "Don't want public web ingress? Use SSM port forwarding:"
    echo "  make devbox-port-forward DEVBOX_USER=${DEVBOX_USER}"
    echo "  Then browse to https://localhost:8080 and https://localhost:6080"
  fi
  echo ""
  echo "If browser access fails: your public IP probably changed."
  echo "  make devbox-allowlist-me && make tg-apply"
fi
