#!/usr/bin/env bash
# kion-creds — fetch short-term AWS access keys (STAKs) from Kion.
# Installed to /usr/local/bin/kion-creds by ansible/roles/kion.
# Design: docs/superpowers/specs/2026-07-22-kion-creds-design.md
# shellcheck disable=SC2034  # REMOVED IN TASK 3 — constants below are consumed from Task 3 on
set -euo pipefail

# Env seams (tests point these at a tmpdir)
KION_CREDS_CONF="${KION_CREDS_CONF:-/etc/kion-creds.conf}"
KION_CREDS_USER_DIR="${KION_CREDS_USER_DIR:-${HOME}/.config/kion-creds}"
AWS_CREDS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-${HOME}/.aws/credentials}"
STATE_FILE="${KION_CREDS_USER_DIR}/state"

# Kion API (v3 family) — single source of truth for endpoint paths.
# [ASSUMED, confirmed-at-first-use]: verify each path and response shape against
# the org Kion instance's /swagger and correct HERE if they differ.
API_TOKEN_PATH="/api/v3/token"
API_ME_CARS_PATH="/api/v3/me/cloud-access-role"
API_PROJECT_ACCOUNTS_PATH="/api/v3/project/PROJECT_ID/accounts"
API_STAK_PATH="/api/v3/temporary-credentials/cloud-access-role"

CURL_CONNECT_TIMEOUT="${KION_CURL_CONNECT_TIMEOUT:-5}"
CURL_MAX_TIME="${KION_CURL_MAX_TIME:-30}"
CURL_5XX_RETRIES="${KION_CURL_5XX_RETRIES:-2}"

# Exit codes — stable contract; the login hook keys off EX_AUTH=3.
readonly EX_OK=0 EX_USAGE=2 EX_AUTH=3 EX_NETWORK=4
readonly EX_NOPROJECT=5 EX_NOCAR=6 EX_API=7 EX_NOTTY=8 EX_EXPIRED=9

# Config defaults — conf files override.
KION_URL="${KION_URL:-}"
KION_IDMS_ID="${KION_IDMS_ID:-1}"
KION_AWS_PROFILE="${KION_AWS_PROFILE:-default}"
KION_REFRESH_FUDGE_SECONDS="${KION_REFRESH_FUDGE_SECONDS:-300}"
KION_STAK_TTL_SECONDS="${KION_STAK_TTL_SECONDS:-3600}"
KION_USERNAME="${KION_USERNAME:-}"

ARG_ID="" ARG_CAR="" ARG_USER="" ARG_CHECK=0 ARG_PASSWORD_STDIN=0

err() { # err EXIT_CODE MESSAGE...
  local code="$1"; shift
  printf 'kion-creds: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  cat <<'EOF'
kion-creds — fetch short-term AWS credentials (STAK) from Kion

Usage:
  kion-creds [--id <project-number>] [--car <name>] [--user <name>]
             [--password-stdin] [--check]

Options:
  --id <n>          Kion project number (cached; later runs may omit it)
  --car <name>      pre-select the cloud access role by name
  --user <name>     Kion username (default: cached, then $USER)
  --password-stdin  read the Kion password from stdin line 1 (scripting/tests);
                    any picker input is read from the following lines
  --check           exit 0 if cached creds are still fresh, 9 if not (offline)
  -h, --help        this help
EOF
}

kc_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)   [[ $# -ge 2 ]] || err "$EX_USAGE" "--id needs a value";   ARG_ID="$2";   shift 2 ;;
      --car)  [[ $# -ge 2 ]] || err "$EX_USAGE" "--car needs a value";  ARG_CAR="$2";  shift 2 ;;
      --user) [[ $# -ge 2 ]] || err "$EX_USAGE" "--user needs a value"; ARG_USER="$2"; shift 2 ;;
      --password-stdin) ARG_PASSWORD_STDIN=1; shift ;;
      --check) ARG_CHECK=1; shift ;;
      -h|--help) usage; exit "$EX_OK" ;;
      *) usage >&2; err "$EX_USAGE" "unknown argument: $1" ;;
    esac
  done
  if [[ -n "$ARG_ID" && ! "$ARG_ID" =~ ^[0-9]+$ ]]; then
    err "$EX_USAGE" "--id must be a number, got: ${ARG_ID}"
  fi
}

kc_load_config() {
  # shellcheck disable=SC1090
  [[ -r "$KION_CREDS_CONF" ]] && . "$KION_CREDS_CONF"
  # shellcheck disable=SC1091
  [[ -r "${KION_CREDS_USER_DIR}/config" ]] && . "${KION_CREDS_USER_DIR}/config"
  return 0
}

kc_read_state() {
  KION_LAST_PROJECT_ID="" KION_LAST_USERNAME="" KION_CREDS_EXPIRY=0
  # shellcheck disable=SC1090
  [[ -r "$STATE_FILE" ]] && . "$STATE_FILE"
  return 0
}

# shellcheck disable=SC2329  # invoked from Task 3 on
kc_write_state() { # kc_write_state PROJECT_ID USERNAME EXPIRY_EPOCH
  mkdir -p "$KION_CREDS_USER_DIR"
  chmod 700 "$KION_CREDS_USER_DIR"
  local tmp
  tmp=$(mktemp "${KION_CREDS_USER_DIR}/.state.XXXXXX")
  {
    printf 'KION_LAST_PROJECT_ID=%q\n' "$1"
    printf 'KION_LAST_USERNAME=%q\n' "$2"
    printf 'KION_CREDS_EXPIRY=%q\n' "$3"
  } >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$STATE_FILE"
}

kc_creds_fresh() { # 0 = cached STAK still valid (refresh fudge applied)
  kc_read_state
  [[ "$KION_CREDS_EXPIRY" =~ ^[0-9]+$ ]] || return 1
  [[ -f "$AWS_CREDS_FILE" ]] || return 1
  local now
  now=$(date +%s)
  (( now < KION_CREDS_EXPIRY - KION_REFRESH_FUDGE_SECONDS ))
}

# shellcheck disable=SC2329  # invoked from Task 3 on
kc_has_tty() {
  ( : </dev/tty ) 2>/dev/null
}

main() {
  kc_parse_args "$@"
  kc_load_config
  if (( ARG_CHECK )); then
    if kc_creds_fresh; then exit "$EX_OK"; else exit "$EX_EXPIRED"; fi
  fi
  [[ -n "$KION_URL" ]] || err "$EX_USAGE" "KION_URL is not set (check ${KION_CREDS_CONF})"
  command -v jq >/dev/null 2>&1 || err "$EX_USAGE" "jq is required but not installed"
  kc_read_state
  KC_PROJECT_ID="${ARG_ID:-$KION_LAST_PROJECT_ID}"
  [[ -n "$KC_PROJECT_ID" ]] \
    || err "$EX_USAGE" "no project id — pass --id <project-number> (it is cached afterwards)"
  # Username chain (spec): --user flag → per-user/system config → cached → $USER
  KC_USERNAME="${ARG_USER:-${KION_USERNAME:-${KION_LAST_USERNAME:-$USER}}}"
  err "$EX_API" "not implemented yet"   # replaced in Task 3
}

main "$@"
