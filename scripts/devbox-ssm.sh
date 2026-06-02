#!/usr/bin/env bash
# Open an AWS SSM Session Manager interactive shell to the operator's devbox.
# Replaces the old per-operator-key SSH-over-public-:22 flow now that Phase 2
# closed :22 ingress on the security group.
#
# See: .planning/phases/02-network-exposure-remediation/02-RESEARCH.md (Pattern 5)
# Requires: session-manager-plugin (https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Open an SSM Session Manager shell to the operator's devbox.

Options:
  --user USERNAME     Devbox owner (default: \$DEVBOX_USER or \$(whoami))
  --instance-id ID    EC2 instance ID (overrides Terraform state)
  --region REGION     AWS region (overrides Terraform state)
  -h, --help          Show this help

Requirements (operator workstation):
  aws CLI >= 1.16.12 (you already have this if './run build' works)
  session-manager-plugin (brew install --cask session-manager-plugin on macOS)
EOF
  exit 0
}

parse_args "$@"

# Pre-flight: session-manager-plugin must be installed on the operator workstation.
# The plugin is separate from the AWS CLI itself; aws ssm start-session shells out to it.
if ! command -v session-manager-plugin >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: session-manager-plugin is not installed on this workstation.

Install (macOS):
  brew install --cask session-manager-plugin

Install (Linux / other):
  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

Verify after install:
  session-manager-plugin
  # Expected: "The Session Manager plugin was installed successfully..."
EOF
  exit 1
fi

init_devbox

echo "Opening SSM session to ${INSTANCE_ID} in ${REGION}..."
echo "(Type 'exit' or Ctrl-D to end the session.)"
echo ""

exec aws ssm start-session \
  --target "$INSTANCE_ID" \
  --region "$REGION"
