#!/usr/bin/env bash
# Restore /data -> /home/ec2-user on the devbox (over SSM). Run AFTER a refreshed instance is up
# to lay your saved home back over the new AMI's /home (merge — keeps the new AMI defaults).
# Manual by design.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Restore /data/home back onto /home/ec2-user on the devbox, over SSM (merge — keeps the new
AMI's home defaults, lays your saved files on top). Run AFTER a refreshed instance is up.

Options:
  --user USERNAME     Devbox owner (default: \$DEVBOX_USER or \$(whoami))
  --instance-id ID    EC2 instance ID (overrides Terraform state)
  --region REGION     AWS region (overrides Terraform state)
  -h, --help          Show this help
EOF
  exit 0
}

parse_args "$@"
init_devbox

echo "Restoring /data -> /home/ec2-user on ${INSTANCE_ID} ..."
ssm_run_shell "sudo /usr/local/sbin/devbox-home-restore.sh"
