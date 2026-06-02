#!/usr/bin/env bash
# Launch JupyterLab on demand on the operator's devbox, bound to loopback.
#
# Jupyter is NOT a baked systemd service. It is started here over an SSM
# interactive session, listening on 127.0.0.1:8888 only — never on a public
# interface. Because the listener is loopback-only, reachability is gated by
# AWS SSM + IAM (whoever can open this session already has shell access), so
# there is no Jupyter password and no TLS. (Phase 8: supersedes D-04/D-05.)
#
# Access: this command runs `jupyter lab` in the foreground and prints its URL.
# In a SECOND terminal, forward the port over SSM, then open the printed URL:
#
#   aws ssm start-session --target <instance-id> --region <region> \
#     --document-name AWS-StartPortForwardingSession \
#     --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'
#
# Then browse to the http://127.0.0.1:8888/lab?token=... URL Jupyter prints below.
#
# Requires: session-manager-plugin (same as ./run devbox-ssm).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh disable=SC1091
source "$SCRIPT_DIR/_common.sh"

JUPYTER_VENV="/opt/jupyter"
JUPYTER_NOTEBOOK_DIR="/home/ec2-user"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Launch JupyterLab on the devbox, bound to 127.0.0.1:8888, over SSM.

Options:
  --user USERNAME     Devbox owner (default: \$DEVBOX_USER or \$(whoami))
  --instance-id ID    EC2 instance ID (overrides Terraform state)
  --region REGION     AWS region (overrides Terraform state)
  -h, --help          Show this help

Access (loopback-only — no public exposure):
  1. Run this command; leave it running. Note the printed token URL.
  2. In another terminal, forward :8888 over SSM:
       aws ssm start-session --target <id> --region <region> \\
         --document-name AWS-StartPortForwardingSession \\
         --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'
  3. Open the http://127.0.0.1:8888/lab?token=... URL in your browser.

Requirements (operator workstation):
  aws CLI v2, session-manager-plugin (brew install --cask session-manager-plugin)
EOF
  exit 0
}

parse_args "$@"

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: session-manager-plugin is not installed on this workstation.

Install (macOS):
  brew install --cask session-manager-plugin

Install (Linux / other):
  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
EOF
  exit 1
fi

init_devbox

echo "Launching JupyterLab on ${INSTANCE_ID} (127.0.0.1:8888, loopback-only)..."
echo ""
echo "In a SECOND terminal, forward the port over SSM:"
echo "  aws ssm start-session --target ${INSTANCE_ID} --region ${REGION} \\"
echo "    --document-name AWS-StartPortForwardingSession \\"
echo "    --parameters '{\"portNumber\":[\"8888\"],\"localPortNumber\":[\"8888\"]}'"
echo ""
echo "Then open the http://127.0.0.1:8888/lab?token=... URL printed below."
echo "(Ctrl-C here stops JupyterLab.)"
echo ""

exec aws ssm start-session \
  --target "$INSTANCE_ID" \
  --region "$REGION" \
  --document-name AWS-StartInteractiveCommand \
  --parameters "{\"command\":[\"${JUPYTER_VENV}/bin/jupyter lab --ip=127.0.0.1 --port=8888 --no-browser --notebook-dir=${JUPYTER_NOTEBOOK_DIR}\"]}"
