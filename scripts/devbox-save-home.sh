#!/usr/bin/env bash
# Save /home/ec2-user -> /data on the devbox (over SSM). Run BEFORE an AMI refresh / instance
# replace so the home is preserved on the persistent /data volume; restore it on the new
# instance with `./run restore-home`. Manual by design.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Save /home/ec2-user into /data (the persistent EBS volume) on the devbox, over SSM.
Run this BEFORE replacing the instance (AMI refresh); restore after with restore-home.

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

echo "Saving /home/ec2-user -> /data on ${INSTANCE_ID} ..."
ssm_run_shell "sudo /usr/local/sbin/devbox-home-save.sh"
