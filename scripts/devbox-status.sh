#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

if [[ "$STATE" == "running" && "$PUBLIC_IP" != "N/A" ]]; then
  echo ""
  echo "=== Connection Info ==="
  echo "SSH:          ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
  echo "code-server:  https://${PUBLIC_IP}:8080"
  echo "noVNC:        https://${PUBLIC_IP}:6080"
fi
