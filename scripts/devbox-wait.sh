#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Wait for a freshly-provisioned devbox EC2 instance to finish building:
  running state -> EC2 status checks (system + instance reachability) -> SSM Online.

Intended to run right after 'tofu apply' (pipeline or local) so a subsequent
'status' (or a connect) is meaningful instead of racing a still-booting instance.

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

# 1. Pending -> running. (ec2:DescribeInstances — already held by anything that applied.)
echo "Waiting for instance to reach running state..."
aws ec2 wait instance-running \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

# 2. EC2 status checks: system + instance reachability = the OS booted and networking is up.
#    This is the "instance is built" signal (mirrors devbox-start.sh). Bounded by the AWS
#    waiter (~10m); exits non-zero on timeout so a stuck build fails loudly.
echo "Waiting for EC2 status checks (system + instance reachability)..."
aws ec2 wait instance-status-ok \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION"

# 3. Best-effort: SSM agent Online = cloud-init networking + the SSM agent are up (this box is
#    SSM-first). Warn-only — skips cleanly if ssm:DescribeInstanceInformation is not granted to
#    the caller, so it never blocks a pipeline on a missing IAM perm. EC2 status-ok above is the
#    hard gate; SSM Online is the nicer "manageable" signal when we are allowed to read it.
echo "Waiting for SSM agent to come Online (best-effort)..."
ssm_online=false
for _ in $(seq 1 40); do
  ping="$(aws ssm describe-instance-information \
    --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null || true)"
  if [[ "$ping" == "Online" ]]; then
    ssm_online=true
    break
  fi
  sleep 15
done
if [[ "$ssm_online" == true ]]; then
  echo "SSM agent Online."
else
  echo "WARNING: SSM agent not Online yet (or ssm:DescribeInstanceInformation not permitted)." >&2
  echo "         EC2 status checks already passed — the instance is built; SSM may need another minute." >&2
fi

echo ""
echo "Instance is built and reachable: $INSTANCE_ID ($REGION)"
