#!/usr/bin/env bash
# Resolve the operator's current source IP and write a gitignored
# allowlist.auto.tfvars that populates var.allowed_web_cidrs.
#
# Phase 2 hybrid posture: code-server (:8080) and noVNC (:6080) ingress is
# restricted to var.allowed_web_cidrs (terraform/variables.tf, added in 02-01).
#
# Two modes:
#   1. Connected (default) — fetches public IP from https://checkip.amazonaws.com
#      and writes <ip>/32 to allowlist.auto.tfvars. Works when operator has
#      public-internet egress.
#   2. Airgapped — operator supplies CIDR(s) explicitly. Triggered by --cidr
#      flag (repeatable) or DEVBOX_OPERATOR_CIDR env var (comma-separated).
#      No outbound call is made. Required for GovCloud, isolated VPCs, direct-
#      connect-only networks, or anywhere checkip.amazonaws.com is blocked.
#
# Output:  ./allowlist.auto.tfvars (gitignored — see .gitignore Phase-2 stanza)
# Next:    make tf-apply

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Resolve operator source IP and write a gitignored allowlist.auto.tfvars
populating var.allowed_web_cidrs.

Connected mode (default):
  Resolves your current public IP from https://checkip.amazonaws.com.

Airgapped mode (--cidr or DEVBOX_OPERATOR_CIDR env):
  Skips the public lookup entirely; uses operator-supplied CIDRs only.
  Required when running in GovCloud, isolated VPCs, or any network
  without egress to checkip.amazonaws.com.

Options:
  --cidr CIDR         Operator-supplied CIDR (repeatable). When provided,
                      airgapped mode activates — no outbound HTTP call.
                      Example: --cidr 10.42.0.0/24 --cidr 10.43.5.7/32
  --extra-cidr CIDR   Additional CIDR appended to the auto-discovered /32
                      in connected mode. Ignored in airgapped mode (use
                      --cidr instead).
  --output PATH       Output path (default: ./allowlist.auto.tfvars)
  -h, --help          Show this help

Env vars:
  DEVBOX_OPERATOR_CIDR  Comma-separated CIDRs; equivalent to repeated --cidr.
                        If set and non-empty, airgapped mode activates.

Examples:
  $(basename "$0")                                  # connected: auto-discover /32
  $(basename "$0") --extra-cidr 10.0.0.0/24         # connected: /32 + office range
  $(basename "$0") --cidr 10.42.0.0/24              # airgapped: explicit only
  DEVBOX_OPERATOR_CIDR=10.0.0.0/8 $(basename "$0")  # airgapped via env

Behind a captive portal? Override manually:
  echo 'allowed_web_cidrs = ["YOUR.IP.HERE/32"]' > allowlist.auto.tfvars
EOF
  exit 0
}

TFVARS_PATH="${TFVARS_PATH:-./allowlist.auto.tfvars}"
OPERATOR_CIDRS=()
EXTRA_CIDRS=()

# Seed operator CIDRs from env var if present (comma-separated).
if [[ -n "${DEVBOX_OPERATOR_CIDR:-}" ]]; then
  IFS=',' read -ra _env_cidrs <<< "$DEVBOX_OPERATOR_CIDR"
  for c in "${_env_cidrs[@]}"; do
    c="${c// /}"  # strip whitespace
    [[ -n "$c" ]] && OPERATOR_CIDRS+=("$c")
  done
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --cidr)        OPERATOR_CIDRS+=("$2"); shift 2 ;;
    --extra-cidr)  EXTRA_CIDRS+=("$2"); shift 2 ;;
    --output)      TFVARS_PATH="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

CIDR_LIST=""
MODE=""
SOURCE_NOTE=""

if [[ ${#OPERATOR_CIDRS[@]} -gt 0 ]]; then
  # ----- Airgapped mode -----
  MODE="airgapped"
  for c in "${OPERATOR_CIDRS[@]}"; do
    # Sanity-check shape — Terraform's cidrhost() is the authoritative gate, but
    # catch obvious typos here so the operator sees a clearer error.
    if [[ ! "$c" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
      echo "ERROR: --cidr / DEVBOX_OPERATOR_CIDR value '$c' is not a valid CIDR (expected A.B.C.D or A.B.C.D/N)." >&2
      exit 1
    fi
    # Default to /32 if no prefix supplied (operator gave bare IP).
    [[ "$c" == */* ]] || c="${c}/32"
    [[ -z "$CIDR_LIST" ]] && CIDR_LIST="\"${c}\"" || CIDR_LIST="${CIDR_LIST}, \"${c}\""
  done
  SOURCE_NOTE="Source: operator-supplied (--cidr / DEVBOX_OPERATOR_CIDR). No public lookup."
  echo "Airgapped mode: skipping public IP lookup; using ${#OPERATOR_CIDRS[@]} operator-supplied CIDR(s)."
else
  # ----- Connected mode -----
  MODE="connected"
  echo "Resolving public IP from https://checkip.amazonaws.com ..."
  PUBLIC_IP=$(curl -sS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)

  if [[ -z "$PUBLIC_IP" ]]; then
    cat >&2 <<EOF
ERROR: checkip.amazonaws.com unreachable (timeout or network failure).

If you are in an airgapped network (GovCloud, isolated VPC, no egress), pass
the CIDR explicitly:

  $(basename "$0") --cidr YOUR.IP.HERE/32
  # or
  DEVBOX_OPERATOR_CIDR=YOUR.IP.HERE/32 $(basename "$0")

Or override manually:
  echo 'allowed_web_cidrs = ["YOUR.IP.HERE/32"]' > $TFVARS_PATH
EOF
    exit 1
  fi

  # Defense against captive-portal HTML: response must look exactly like IPv4.
  if [[ ! "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    cat >&2 <<EOF
ERROR: checkip.amazonaws.com returned unexpected payload: '$PUBLIC_IP'

Behind a captive portal, or in an airgapped network?
Use --cidr instead:
  $(basename "$0") --cidr YOUR.IP.HERE/32
Or override manually:
  echo 'allowed_web_cidrs = ["YOUR.IP.HERE/32"]' > $TFVARS_PATH
EOF
    exit 1
  fi

  CIDR_LIST="\"${PUBLIC_IP}/32\""
  for c in "${EXTRA_CIDRS[@]+"${EXTRA_CIDRS[@]}"}"; do
    CIDR_LIST="${CIDR_LIST}, \"${c}\""
  done
  SOURCE_NOTE="Source: checkip.amazonaws.com → ${PUBLIC_IP}/32"
fi

# Atomic write — write to a temp file, then mv into place.
TMP_FILE="${TFVARS_PATH}.tmp.$$"
cat > "$TMP_FILE" <<EOF
# AUTO-GENERATED by make devbox-allowlist-me on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Operator: ${USER:-unknown}
# Mode: ${MODE}
# ${SOURCE_NOTE}
# Refresh by re-running 'make devbox-allowlist-me' after IP changes.
# Gitignored — see .gitignore Phase-2 stanza.
allowed_web_cidrs = [${CIDR_LIST}]
EOF
mv "$TMP_FILE" "$TFVARS_PATH"

echo ""
echo "Wrote ${TFVARS_PATH}:"
echo "----------------------------------------"
cat "$TFVARS_PATH"
echo "----------------------------------------"
echo ""
echo "Next: make tf-apply"
