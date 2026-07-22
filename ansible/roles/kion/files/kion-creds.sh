#!/usr/bin/env bash
# kion-creds — fetch short-term AWS access keys (STAKs) from Kion.
# Installed to /usr/local/bin/kion-creds by ansible/roles/kion.
# Design: docs/superpowers/specs/2026-07-22-kion-creds-design.md
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

# Cleanup for the mktemp files in kc_write_state / kc_write_aws_profile: an
# err/exit between mktemp and mv must not leave a stray dotfile behind.
KC_TMPFILE=""
# shellcheck disable=SC2064  # single-quoted deliberately — expanded at exit
trap '[[ -n "$KC_TMPFILE" ]] && rm -f "$KC_TMPFILE"' EXIT

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

kc_write_state() { # kc_write_state PROJECT_ID USERNAME EXPIRY_EPOCH
  mkdir -p "$KION_CREDS_USER_DIR"
  chmod 700 "$KION_CREDS_USER_DIR"
  local tmp
  tmp=$(mktemp "${KION_CREDS_USER_DIR}/.state.XXXXXX")
  KC_TMPFILE="$tmp"
  {
    printf 'KION_LAST_PROJECT_ID=%q\n' "$1"
    printf 'KION_LAST_USERNAME=%q\n' "$2"
    printf 'KION_CREDS_EXPIRY=%q\n' "$3"
  } >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$STATE_FILE"
  KC_TMPFILE=""
}

kc_creds_fresh() { # 0 = cached STAK still valid (refresh fudge applied)
  kc_read_state
  [[ "$KION_CREDS_EXPIRY" =~ ^[0-9]+$ ]] || return 1
  [[ -f "$AWS_CREDS_FILE" ]] || return 1
  local now
  now=$(date +%s)
  (( now < KION_CREDS_EXPIRY - KION_REFRESH_FUDGE_SECONDS ))
}

kc_has_tty() {
  ( : </dev/tty ) 2>/dev/null
}

kc_api() { # kc_api METHOD PATH [JSON_BODY] [CODE_ON_404] — sets KC_RESPONSE
  local method="$1" path="$2" body="${3:-}" code_on_404="${4:-$EX_API}"
  local url="${KION_URL%/}${path}"
  local attempt=0 raw rc http
  while :; do
    attempt=$((attempt + 1))
    local curl_args=(
      -sS -X "$method" "$url"
      --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME"
      -H "accept: application/json" -H "content-type: application/json"
      -w $'\n%{http_code}'
    )
    [[ -n "$body" ]] && curl_args+=(--data-binary @-)
    set +e
    if [[ -n "${KC_TOKEN:-}" ]]; then
      # Token via an fd-backed header file (-H @file, curl >= 7.55): never on
      # argv (/proc/cmdline is world-readable), never in the filesystem
      # namespace (bash herestrings use unlinked temp files).
      raw=$(printf '%s' "$body" | curl "${curl_args[@]}" -H "@/dev/fd/3" \
        3<<<"authorization: Bearer ${KC_TOKEN}")
    else
      raw=$(printf '%s' "$body" | curl "${curl_args[@]}")
    fi
    rc=$?
    set -e
    (( rc == 0 )) || err "$EX_NETWORK" "cannot reach Kion at ${KION_URL} (curl exit ${rc})"
    http="${raw##*$'\n'}"
    KC_RESPONSE="${raw%$'\n'*}"
    case "$http" in
      2??) return 0 ;;
      401|403) err "$EX_AUTH" "Kion rejected the request (HTTP ${http}): ${KC_RESPONSE}" ;;
      404) err "$code_on_404" "not found (HTTP 404) for ${method} ${path}: ${KC_RESPONSE}" ;;
      5??)
        if (( attempt <= CURL_5XX_RETRIES )); then sleep 1; continue; fi
        err "$EX_API" "Kion server error (HTTP ${http}) after ${attempt} attempts: ${KC_RESPONSE}"
        ;;
      *) err "$EX_API" "Kion API error (HTTP ${http}) for ${method} ${path}: ${KC_RESPONSE}" ;;
    esac
  done
}

kc_read_password() { # sets KC_PASSWORD; never echoes, never on argv
  if (( ARG_PASSWORD_STDIN )); then
    # read returns nonzero at EOF-without-newline even though it populated the
    # var — accept a non-empty password either way.
    IFS= read -r KC_PASSWORD || [[ -n "$KC_PASSWORD" ]] \
      || err "$EX_USAGE" "--password-stdin given but stdin is empty"
  elif kc_has_tty; then
    printf 'Kion password for %s: ' "$KC_USERNAME" >/dev/tty
    IFS= read -rs KC_PASSWORD </dev/tty
    printf '\n' >/dev/tty
  else
    err "$EX_NOTTY" "no tty for the password prompt (use --password-stdin)"
  fi
  [[ -n "$KC_PASSWORD" ]] || err "$EX_AUTH" "empty password"
}

kc_login() { # sets KC_TOKEN, wipes KC_PASSWORD
  local body
  # jq reads the password from stdin (-Rs) so it never appears on any argv.
  body=$(printf '%s' "$KC_PASSWORD" \
    | jq -Rsc --arg u "$KC_USERNAME" --argjson i "$KION_IDMS_ID" \
        '{idms_id: $i, username: $u, password: .}')
  kc_api POST "$API_TOKEN_PATH" "$body"
  KC_TOKEN=$(jq -er '.data.access.token' <<<"$KC_RESPONSE" 2>/dev/null) \
    || err "$EX_API" "unexpected token response shape: ${KC_RESPONSE}"
  KC_PASSWORD=""
}

kc_pick() { # kc_pick LABEL CHOICE... — prints the selected choice
  local label="$1"; shift
  if (( $# == 1 )); then printf '%s\n' "$1"; return 0; fi
  local menu choice i=1 c
  menu="Select ${label}:"$'\n'
  for c in "$@"; do
    menu+=$(printf '  %d) %s' "$i" "$c")$'\n'
    i=$((i + 1))
  done
  menu+="Choice [1-$#]: "
  if (( ARG_PASSWORD_STDIN )); then
    # Menu to stderr; selection read from fd 0 — the line AFTER the password.
    # Never reopen /dev/stdin here: with a regular-file stdin that reopens at
    # offset 0 and re-reads the password line as the selection.
    printf '%s' "$menu" >&2
    IFS= read -r choice || err "$EX_USAGE" "no selection input for ${label}"
  elif kc_has_tty; then
    printf '%s' "$menu" >/dev/tty
    IFS= read -r choice </dev/tty || err "$EX_USAGE" "no selection input for ${label}"
  else
    err "$EX_NOTTY" "multiple ${label}s but no tty to pick from (use --car or --password-stdin)"
  fi
  [[ "$choice" =~ ^[0-9]+$ ]] || err "$EX_USAGE" "invalid selection: ${choice}"
  # Force base 10: a leading zero ("08") would otherwise be read as octal and
  # blow up the arithmetic range check with "value too great for base".
  choice=$((10#$choice))
  if (( choice < 1 || choice > $# )); then
    err "$EX_USAGE" "invalid selection: ${choice}"
  fi
  local choices=("$@")
  printf '%s\n' "${choices[choice - 1]}"
}

kc_resolve() { # sets KC_ACCOUNT_NUMBER + KC_CAR_NAME for $KC_PROJECT_ID
  kc_api GET "${API_PROJECT_ACCOUNTS_PATH/PROJECT_ID/$KC_PROJECT_ID}" "" "$EX_NOPROJECT"
  local accounts=()
  mapfile -t accounts < <(jq -er '.data[] | "\(.account_number)\t\(.name)"' \
    <<<"$KC_RESPONSE" 2>/dev/null || true)
  (( ${#accounts[@]} > 0 )) \
    || err "$EX_NOPROJECT" "no accounts visible on project ${KC_PROJECT_ID} — check the id and your Kion access"

  kc_api GET "$API_ME_CARS_PATH"
  local cars=()
  mapfile -t cars < <(jq -er --argjson pid "$KC_PROJECT_ID" \
    '.data[] | select(.project_id == $pid) | .name' <<<"$KC_RESPONSE" 2>/dev/null || true)
  if [[ -n "$ARG_CAR" ]]; then
    local filtered=() c
    for c in "${cars[@]}"; do [[ "$c" == "$ARG_CAR" ]] && filtered+=("$c"); done
    cars=("${filtered[@]+"${filtered[@]}"}")
  fi
  (( ${#cars[@]} > 0 )) \
    || err "$EX_NOCAR" "no cloud access role for you on project ${KC_PROJECT_ID}${ARG_CAR:+ matching --car ${ARG_CAR}}"

  local acct_line
  acct_line=$(kc_pick "account" "${accounts[@]}")
  KC_ACCOUNT_NUMBER="${acct_line%%$'\t'*}"
  KC_CAR_NAME=$(kc_pick "cloud access role" "${cars[@]}")
}

kc_fetch_stak() { # sets KC_AKID / KC_SECRET / KC_SESSION
  local body
  body=$(jq -cn --arg a "$KC_ACCOUNT_NUMBER" --arg r "$KC_CAR_NAME" \
    '{account_number: $a, cloud_access_role_name: $r}')
  kc_api POST "$API_STAK_PATH" "$body"
  KC_AKID=$(jq -er '.data.access_key' <<<"$KC_RESPONSE" 2>/dev/null) \
    || err "$EX_API" "unexpected STAK response shape: ${KC_RESPONSE}"
  KC_SECRET=$(jq -er '.data.secret_access_key' <<<"$KC_RESPONSE")
  KC_SESSION=$(jq -er '.data.session_token' <<<"$KC_RESPONSE")
}

kc_write_aws_profile() { # kc_write_aws_profile PROFILE AKID SECRET SESSION_TOKEN
  local profile="$1" akid="$2" secret="$3" session="$4"
  local dir tmp
  dir=$(dirname "$AWS_CREDS_FILE")
  mkdir -p "$dir"
  tmp=$(mktemp "${dir}/.kion-creds.XXXXXX")
  KC_TMPFILE="$tmp"
  if [[ -f "$AWS_CREDS_FILE" ]]; then
    # Drop our own section (up to the next [section]); keep everything else.
    awk -v p="[${profile}]" '
      $0 == p { drop = 1; next }
      /^\[/   { drop = 0 }
      !drop   { print }
    ' "$AWS_CREDS_FILE" >"$tmp"
  fi
  {
    printf '[%s]\n' "$profile"
    printf 'aws_access_key_id = %s\n' "$akid"
    printf 'aws_secret_access_key = %s\n' "$secret"
    printf 'aws_session_token = %s\n' "$session"
  } >>"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$AWS_CREDS_FILE"
  KC_TMPFILE=""
}

main() {
  kc_parse_args "$@"
  kc_load_config
  [[ "$KION_REFRESH_FUDGE_SECONDS" =~ ^[0-9]+$ ]] \
    || err "$EX_USAGE" "KION_REFRESH_FUDGE_SECONDS must be a number, got: ${KION_REFRESH_FUDGE_SECONDS}"
  [[ "$KION_STAK_TTL_SECONDS" =~ ^[0-9]+$ ]] \
    || err "$EX_USAGE" "KION_STAK_TTL_SECONDS must be a number, got: ${KION_STAK_TTL_SECONDS}"
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
  kc_read_password
  kc_login
  kc_resolve
  kc_fetch_stak
  kc_write_aws_profile "$KION_AWS_PROFILE" "$KC_AKID" "$KC_SECRET" "$KC_SESSION"
  local expiry
  # [ASSUMED, confirmed-at-first-use]: the STAK response carries no expiry field
  # we rely on; the cache stamps now + KION_STAK_TTL_SECONDS. If the org's real
  # TTL is shorter, --check reports fresh on dead creds — fix the conf var at UAT.
  expiry=$(( $(date +%s) + KION_STAK_TTL_SECONDS ))
  kc_write_state "$KC_PROJECT_ID" "$KC_USERNAME" "$expiry"
  printf 'kion-creds: wrote profile [%s] — account %s / %s (expires in ~%dm)\n' \
    "$KION_AWS_PROFILE" "$KC_ACCOUNT_NUMBER" "$KC_CAR_NAME" \
    "$(( KION_STAK_TTL_SECONDS / 60 ))"
}

# Test seam: `KION_CREDS_ALLOW_SOURCE=1 source kion-creds.sh` loads functions
# without running main (bats function-level tests).
if [[ "${KION_CREDS_ALLOW_SOURCE:-0}" != "1" ]]; then
  main "$@"
fi
