# kion-creds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake a `kion-creds` CLI + login-shell hook into the devbox AMI that prompts the operator for their Kion password and writes short-term AWS access keys (STAKs) to `~/.aws/credentials`.

**Architecture:** One bash script (`/usr/local/bin/kion-creds`, raw `curl` against the Kion v3 REST API) plus a POSIX-sh `/etc/profile.d/` hook that re-prompts when the cached STAK expires. Delivered by a new Ansible role `kion` (layer-gated `layers.kion`, wired before `hardening`), following the `ai_tools` role pattern including bake-asserts. Unit-tested with bats + a mocked `curl` on PATH.

**Tech Stack:** bash 5 (AL2023 target), POSIX sh (profile.d hook), jq, curl(-minimal), bats (bats-core), Ansible role, GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-07-22-kion-creds-design.md` — read it first.

## Global Constraints

- `hardening` MUST remain the last role in `ansible/playbook.yml` (grep-gate invariant). New role goes after `ai_tools`, before `secrets`.
- Every new `uses: org/repo@<ref>` in `.github/workflows/*` MUST pin a 40-char commit SHA — copy the existing checkout step verbatim from another job in `ci.yml`.
- No secrets on disk or argv: Kion password memory-only (`read -s`, request bodies via stdin, jq reads password from stdin — never `--arg`); no password/token in any file; `~/.aws/credentials` and the state file are `0600`.
- `layers.kion` defaults to **false** (org-specific `kion_url` required; role bake-asserts it non-empty).
- Kion API paths/response shapes carry the repo's `[ASSUMED, confirmed-at-first-use]` comment marker and live in one block at the top of the script.
- shellcheck-clean: all shell files pass `shellcheck` (CI job extended to cover them).
- ansible-lint clean: `ansible-lint ansible/playbook.yml` must pass (fqcn module names, named tasks — mirror `ai_tools` style).
- The login hook must NEVER fail or block the shell, and must be POSIX sh (profile.d is sourced by any sh).
- Conventional commit messages (`feat:`, `test:`, `ci:` …), no attribution footer.
- bats on macOS: tests need GNU bash ≥ 4.4 and `brew install bats-core`; CI (ubuntu) is authoritative.

## File Structure

| File | Responsibility |
|------|----------------|
| `ansible/roles/kion/files/kion-creds.sh` | The CLI. Installed as `/usr/local/bin/kion-creds`. |
| `ansible/roles/kion/files/kion-creds-login.sh` | POSIX login hook. Installed as `/etc/profile.d/kion-creds.sh`. |
| `ansible/roles/kion/templates/kion-creds.conf.j2` | System config rendered to `/etc/kion-creds.conf`. |
| `ansible/roles/kion/defaults/main.yml` | Role vars (`kion_url` etc.). |
| `ansible/roles/kion/tasks/main.yml` | Install + bake-asserts. |
| `tests/kion/kion-creds.bats` | CLI unit tests. |
| `tests/kion/login-hook.bats` | Hook unit tests. |
| `tests/kion/mocks/curl` | PATH-shim curl mock replaying fixtures. |
| `tests/kion/fixtures/{happy,multi}/*.json` | Canned Kion API responses. |
| `ansible/playbook.yml`, `ansible/layer_config.yml`, `.github/workflows/ci.yml` | Wiring (modify). |

Environment seams (how tests redirect everything; the script honors these):
`KION_CREDS_CONF` (default `/etc/kion-creds.conf`), `KION_CREDS_USER_DIR` (default `~/.config/kion-creds`), `AWS_SHARED_CREDENTIALS_FILE` (default `~/.aws/credentials`), `PATH` (curl mock), `KION_CREDS_HOOK_FORCE` (hook test seam).

---

### Task 1: CLI skeleton — args, config, state, `--check`

**Files:**
- Create: `ansible/roles/kion/files/kion-creds.sh`
- Test: `tests/kion/kion-creds.bats`

**Interfaces:**
- Consumes: nothing (first task).
- Produces (later tasks rely on these exact names):
  - Exit codes: `0` ok, `2` usage, `3` auth, `4` network, `5` unknown project, `6` no CAR, `7` API error, `8` no tty, `9` `--check` says expired.
  - Flags: `--id <n>`, `--car <name>`, `--user <name>`, `--password-stdin`, `--check`, `-h/--help`.
  - Functions: `err CODE MSG`, `usage`, `kc_parse_args`, `kc_load_config`, `kc_read_state`, `kc_write_state ID USER EXPIRY`, `kc_creds_fresh`, `kc_has_tty`, `main`.
  - Globals: `ARG_ID ARG_CAR ARG_USER ARG_CHECK ARG_PASSWORD_STDIN`, config vars `KION_URL KION_IDMS_ID KION_AWS_PROFILE KION_REFRESH_FUDGE_SECONDS KION_STAK_TTL_SECONDS`, state vars `KION_LAST_PROJECT_ID KION_LAST_USERNAME KION_CREDS_EXPIRY`, paths `KION_CREDS_CONF KION_CREDS_USER_DIR AWS_CREDS_FILE STATE_FILE`.

- [ ] **Step 1: Write the failing tests**

Create `tests/kion/kion-creds.bats`:

```bats
#!/usr/bin/env bats
# Unit tests for ansible/roles/kion/files/kion-creds.sh.
# Everything is redirected into a per-test tmpdir via the script's env seams;
# curl is a PATH mock (tests/kion/mocks/curl) — no network ever.

SCRIPT="${BATS_TEST_DIRNAME}/../../ansible/roles/kion/files/kion-creds.sh"

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="${TEST_TMP}/home"
  mkdir -p "$HOME"
  export KION_CREDS_CONF="${TEST_TMP}/kion-creds.conf"
  export KION_CREDS_USER_DIR="${HOME}/.config/kion-creds"
  export AWS_SHARED_CREDENTIALS_FILE="${HOME}/.aws/credentials"
  printf 'KION_URL="https://kion.test"\n' >"$KION_CREDS_CONF"
  export PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/happy"
  export MOCK_LOG="${TEST_TMP}/curl.log"
}

teardown() { rm -rf "$TEST_TMP"; }

seed_fresh_state() { # helper: state + creds file that pass --check
  mkdir -p "$KION_CREDS_USER_DIR" "$(dirname "$AWS_SHARED_CREDENTIALS_FILE")"
  touch "$AWS_SHARED_CREDENTIALS_FILE"
  printf 'KION_CREDS_EXPIRY=%s\n' "$(( $(date +%s) + 3600 ))" \
    >"${KION_CREDS_USER_DIR}/state"
}

@test "unknown flag exits 2 with usage" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "--id must be numeric" {
  run "$SCRIPT" --id abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"--id must be a number"* ]]
}

@test "--help exits 0 and shows flags" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--password-stdin"* ]]
}

@test "--check with no state exits 9" {
  run "$SCRIPT" --check
  [ "$status" -eq 9 ]
}

@test "--check with fresh state exits 0" {
  seed_fresh_state
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "--check inside the refresh fudge window exits 9" {
  seed_fresh_state
  printf 'KION_CREDS_EXPIRY=%s\n' "$(( $(date +%s) + 60 ))" \
    >"${KION_CREDS_USER_DIR}/state"   # 60s left < 300s fudge
  run "$SCRIPT" --check
  [ "$status" -eq 9 ]
}

@test "user config overrides system config" {
  seed_fresh_state
  # system fudge default 300 would say expired at +60s; user override 10 says fresh
  printf 'KION_REFRESH_FUDGE_SECONDS="10"\n' >"${KION_CREDS_USER_DIR}/config"
  printf 'KION_CREDS_EXPIRY=%s\n' "$(( $(date +%s) + 60 ))" \
    >"${KION_CREDS_USER_DIR}/state"
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "missing project id (no --id, no cache) exits 2 with hint" {
  run "$SCRIPT" --password-stdin <<<"pw"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--id"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/kion/kion-creds.bats`
Expected: all tests FAIL (script does not exist — status 127-style failures).

- [ ] **Step 3: Write the skeleton implementation**

Create `ansible/roles/kion/files/kion-creds.sh` (mode 755: `chmod 755` after writing):

```bash
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

kc_has_tty() { ( : </dev/tty ) 2>/dev/null; }

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
```

Then: `chmod 755 ansible/roles/kion/files/kion-creds.sh`

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/kion/kion-creds.bats`
Expected: all 8 PASS. (The "missing project id" test passes because the parse/config/state path runs before the `not implemented` stub.)

- [ ] **Step 5: Run shellcheck**

Run: `shellcheck ansible/roles/kion/files/kion-creds.sh tests/kion/kion-creds.bats`
Expected: no output, exit 0. (pre-commit's shellcheck hook is `types: [shell]` with no
path filter — it lints the `.bats` files and the extensionless curl mock on every
commit, so keep those shellcheck-clean locally as well.)

- [ ] **Step 6: Commit**

```bash
git add tests/kion/kion-creds.bats ansible/roles/kion/files/kion-creds.sh
git commit -m "feat(kion): kion-creds skeleton — args, config, state, --check (bats-tested)"
```

---

### Task 2: AWS credentials file writer

**Files:**
- Modify: `ansible/roles/kion/files/kion-creds.sh` (add one function before `main`)
- Test: `tests/kion/kion-creds.bats` (append)

**Interfaces:**
- Consumes: `AWS_CREDS_FILE` global from Task 1.
- Produces: `kc_write_aws_profile PROFILE AKID SECRET SESSION_TOKEN` — creates/updates one ini section in `$AWS_CREDS_FILE`, preserves foreign sections, leaves file `0600`. Task 3's `main` calls it.

- [ ] **Step 1: Write the failing tests** (append to `tests/kion/kion-creds.bats`)

The writer is exercised through a tiny driver so we can test it before the API
path exists (bash `-c` sources nothing; we invoke the script file with a
test-only subcommand is NOT added — instead the tests call the function via
`bash -c 'source …'`):

```bats
write_profile() { # helper: call kc_write_aws_profile in a throwaway shell
  bash -c '
    KION_CREDS_ALLOW_SOURCE=1 source "'"$SCRIPT"'"
    kc_write_aws_profile "$@"
  ' _ "$@"
}

@test "writer creates the creds file 0600 with the profile" {
  write_profile default AKIDXX secretXX tokenXX
  grep -q '^\[default\]$' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q '^aws_access_key_id = AKIDXX$' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q '^aws_session_token = tokenXX$' "$AWS_SHARED_CREDENTIALS_FILE"
  perms=$(python3 -c "import os,stat;print(oct(stat.S_IMODE(os.stat('$AWS_SHARED_CREDENTIALS_FILE').st_mode)))")
  [ "$perms" = "0o600" ]
}

@test "writer preserves foreign profiles and replaces its own" {
  mkdir -p "$(dirname "$AWS_SHARED_CREDENTIALS_FILE")"
  printf '[other]\naws_access_key_id = AKIAOTHER\n\n[default]\naws_access_key_id = OLD\n' \
    >"$AWS_SHARED_CREDENTIALS_FILE"
  write_profile default AKIDNEW s t
  grep -q '^\[other\]$' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q 'AKIAOTHER' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q 'AKIDNEW' "$AWS_SHARED_CREDENTIALS_FILE"
  ! grep -q 'OLD' "$AWS_SHARED_CREDENTIALS_FILE"
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bats tests/kion/kion-creds.bats`
Expected: 2 new FAIL (`kc_write_aws_profile: command not found` and the script's `main "$@"` firing on source), 8 old PASS.

- [ ] **Step 3: Implement**

In `kion-creds.sh`: make the file sourceable for tests by replacing the last line

```bash
main "$@"
```

with:

```bash
# Test seam: `KION_CREDS_ALLOW_SOURCE=1 source kion-creds.sh` loads functions
# without running main (bats function-level tests).
if [[ "${KION_CREDS_ALLOW_SOURCE:-0}" != "1" ]]; then
  main "$@"
fi
```

and add above `main`:

```bash
kc_write_aws_profile() { # kc_write_aws_profile PROFILE AKID SECRET SESSION_TOKEN
  local profile="$1" akid="$2" secret="$3" session="$4"
  local dir tmp
  dir=$(dirname "$AWS_CREDS_FILE")
  mkdir -p "$dir"
  tmp=$(mktemp "${dir}/.kion-creds.XXXXXX")
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
}
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `bats tests/kion/kion-creds.bats` — Expected: 10 PASS.
Run: `shellcheck ansible/roles/kion/files/kion-creds.sh` — Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add tests/kion/kion-creds.bats ansible/roles/kion/files/kion-creds.sh
git commit -m "feat(kion): aws credentials-file writer preserving foreign profiles"
```

---

### Task 3: Kion API client + happy path (token → resolve → STAK → write)

**Files:**
- Create: `tests/kion/mocks/curl`, `tests/kion/fixtures/happy/*.json`
- Modify: `ansible/roles/kion/files/kion-creds.sh`
- Test: `tests/kion/kion-creds.bats` (append)

**Interfaces:**
- Consumes: Task 1 exit codes/globals, Task 2 `kc_write_aws_profile`.
- Produces: `kc_api METHOD PATH [JSON_BODY] [CODE_ON_404]` (sets `KC_RESPONSE`), `kc_read_password` (sets `KC_PASSWORD`), `kc_login` (sets `KC_TOKEN`), `kc_resolve` (sets `KC_ACCOUNT_NUMBER`, `KC_CAR_NAME`; uses `kc_pick` — single-choice short-circuit only until Task 4), `kc_fetch_stak` (sets `KC_AKID KC_SECRET KC_SESSION`), completed `main`.
- Mock curl contract (login-hook tests do NOT use it; Task 4 does): env `MOCK_DIR` (fixtures), `MOCK_LOG` (append `METHOD PATH` + body per call), `MOCK_NETWORK_FAIL=1` (exit 6), `MOCK_STATUS_<sanitized_path>=NNN` (override HTTP status; sanitized = path with every non-alphanumeric → `_`, e.g. `MOCK_STATUS__api_v3_token`).

- [ ] **Step 1: Write the curl mock**

Create `tests/kion/mocks/curl` (then `chmod 755 tests/kion/mocks/curl`):

```bash
#!/usr/bin/env bash
# curl mock for kion-creds bats tests — replays fixtures, no network.
# Contract: see "Interfaces" in Task 3 of the plan.
set -euo pipefail

if [[ "${MOCK_NETWORK_FAIL:-0}" == "1" ]]; then
  echo "curl: (6) Could not resolve host" >&2
  exit 6
fi

method=GET url="" has_body=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -X) method="${args[i + 1]}"; i=$((i + 1)) ;;
    --data-binary) has_body=1; i=$((i + 1)) ;;
    -H|-w|--connect-timeout|--max-time) i=$((i + 1)) ;;
    http*://*) url="${args[i]}" ;;
  esac
done

path="/${url#*://*/}"
name=$(printf '%s' "$path" | tr -c 'A-Za-z0-9' '_')
body=""
[[ "$has_body" == "1" ]] && body=$(cat)
{ printf '%s %s\n' "$method" "$path"; printf '%s\n' "$body"; } >>"${MOCK_LOG:-/dev/null}"

status_var="MOCK_STATUS_${name}"
status="${!status_var:-200}"
fixture="${MOCK_DIR}/${name}.json"
if [[ -f "$fixture" ]]; then cat "$fixture"; else printf '{}'; fi
printf '\n%s' "$status"
```

Note: `tr -c 'A-Za-z0-9' '_'` maps `/api/v3/token` → `_api_v3_token` (env override name `MOCK_STATUS__api_v3_token` — double underscore).

- [ ] **Step 2: Write the happy fixtures**

Create `tests/kion/fixtures/happy/_api_v3_token.json`:

```json
{"data": {"access": {"token": "test-bearer-token"}}}
```

Create `tests/kion/fixtures/happy/_api_v3_project_101_accounts.json`:

```json
{"data": [{"account_number": "111122223333", "name": "dev-account"}]}
```

Create `tests/kion/fixtures/happy/_api_v3_me_cloud_access_role.json`:

```json
{"data": [{"id": 9, "name": "developer", "project_id": 101}]}
```

Create `tests/kion/fixtures/happy/_api_v3_temporary_credentials_cloud_access_role.json`:

```json
{"data": {"access_key": "ASIATESTKEY", "secret_access_key": "testsecret", "session_token": "testsession"}}
```

(Field names are the `[ASSUMED, confirmed-at-first-use]` shapes from the script header — fixtures and script must stay in lockstep. Every fixture file must end with a trailing newline or pre-commit's end-of-file-fixer rewrites it at commit time.)

- [ ] **Step 3: Write the failing tests** (append to `tests/kion/kion-creds.bats`)

```bats
@test "happy path: writes profile, caches state, password via body not argv" {
  run "$SCRIPT" --id 101 --password-stdin <<<"hunter2"
  [ "$status" -eq 0 ]
  grep -q '^\[default\]$' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q 'aws_access_key_id = ASIATESTKEY' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q 'KION_LAST_PROJECT_ID=101' "${KION_CREDS_USER_DIR}/state"
  grep -q 'KION_LAST_USERNAME=' "${KION_CREDS_USER_DIR}/state"
  grep -q 'hunter2' "$MOCK_LOG"           # password travelled in a request body
}

@test "cached project id reused when --id omitted" {
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 0 ]
  : >"$MOCK_LOG"
  run "$SCRIPT" --password-stdin <<<"pw"
  [ "$status" -eq 0 ]
  grep -q 'project/101/accounts' "$MOCK_LOG"
}

@test "per-user config username is used for the token request" {
  mkdir -p "$KION_CREDS_USER_DIR"
  printf 'KION_USERNAME="alice"\n' >"${KION_CREDS_USER_DIR}/config"
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 0 ]
  grep -q '"username":"alice"' "$MOCK_LOG"
}

@test "auth failure (401 on token) exits 3" {
  export MOCK_STATUS__api_v3_token=401
  run "$SCRIPT" --id 101 --password-stdin <<<"wrong"
  [ "$status" -eq 3 ]
}

@test "network failure exits 4 with a reach message" {
  export MOCK_NETWORK_FAIL=1
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot reach"* ]]
}

@test "unknown project (404 on accounts) exits 5" {
  export MOCK_STATUS__api_v3_project_999_accounts=404
  run "$SCRIPT" --id 999 --password-stdin <<<"pw"
  [ "$status" -eq 5 ]
}

@test "server 5xx retries then exits 7" {
  export MOCK_STATUS__api_v3_token=500
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 7 ]
  [ "$(grep -c '^POST /api/v3/token$' "$MOCK_LOG")" -eq 3 ]  # 1 try + 2 retries
}

@test "empty accounts list exits 5" {
  export MOCK_DIR="${TEST_TMP}/fx"
  mkdir -p "$MOCK_DIR"
  cp "${BATS_TEST_DIRNAME}/fixtures/happy/_api_v3_token.json" "$MOCK_DIR/"
  printf '{"data": []}' >"${MOCK_DIR}/_api_v3_project_101_accounts.json"
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 5 ]
}
```

- [ ] **Step 4: Run tests to verify the new ones fail**

Run: `bats tests/kion/kion-creds.bats`
Expected: the 8 new tests FAIL (main still exits `not implemented`, code 7 — the failure signature for most is wrong status/missing files), 10 old PASS.

- [ ] **Step 5: Implement the API client and full main**

First delete the file-wide `# shellcheck disable=SC2034` directive added in Task 1
(every constant is consumed from this task on). Then in `kion-creds.sh`, add above
`main` (order: after `kc_has_tty`):

```bash
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
    [[ -n "${KC_TOKEN:-}" ]] && curl_args+=(-H "authorization: Bearer ${KC_TOKEN}")
    [[ -n "$body" ]] && curl_args+=(--data-binary @-)
    set +e
    raw=$(printf '%s' "$body" | curl "${curl_args[@]}")
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
    IFS= read -r KC_PASSWORD || err "$EX_USAGE" "--password-stdin given but stdin is empty"
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

kc_pick() { # kc_pick LABEL CHOICE... — prints the selection (Task 4 adds >1)
  local label="$1"; shift
  if (( $# == 1 )); then printf '%s\n' "$1"; return 0; fi
  err "$EX_API" "multiple ${label}s found — picker lands in the next commit"
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
```

Replace the final `err "$EX_API" "not implemented yet"` line of `main` with:

```bash
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
```

- [ ] **Step 6: Run tests + shellcheck**

Run: `bats tests/kion/kion-creds.bats` — Expected: 18 PASS.
Run: `shellcheck ansible/roles/kion/files/kion-creds.sh tests/kion/kion-creds.bats tests/kion/mocks/curl` — Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add tests/kion ansible/roles/kion/files/kion-creds.sh
git commit -m "feat(kion): kion api client, auth, stak fetch — happy path with mocked curl"
```

---

### Task 4: Interactive picker, `--car` filter, tty guards

**Files:**
- Create: `tests/kion/fixtures/multi/*.json`
- Modify: `ansible/roles/kion/files/kion-creds.sh` (`kc_pick` only)
- Test: `tests/kion/kion-creds.bats` (append)

**Interfaces:**
- Consumes: `kc_pick LABEL CHOICE...` call sites from Task 3 (`kc_resolve`), `ARG_PASSWORD_STDIN`, `kc_has_tty`, `EX_NOTTY`, `EX_USAGE`.
- Produces: full `kc_pick` — single choice silent; multiple → numbered menu; input from stdin under `--password-stdin` (menu to stderr), else `/dev/tty`; no tty + no `--password-stdin` → exit 8.

- [ ] **Step 1: Write the multi fixtures**

`tests/kion/fixtures/multi/_api_v3_token.json` — same content as happy:

```json
{"data": {"access": {"token": "test-bearer-token"}}}
```

`tests/kion/fixtures/multi/_api_v3_project_101_accounts.json`:

```json
{"data": [
  {"account_number": "111122223333", "name": "dev-account"},
  {"account_number": "444455556666", "name": "prod-account"}
]}
```

`tests/kion/fixtures/multi/_api_v3_me_cloud_access_role.json`:

```json
{"data": [
  {"id": 9, "name": "developer", "project_id": 101},
  {"id": 10, "name": "admin", "project_id": 101},
  {"id": 11, "name": "developer", "project_id": 202}
]}
```

`tests/kion/fixtures/multi/_api_v3_temporary_credentials_cloud_access_role.json` — same as happy:

```json
{"data": {"access_key": "ASIATESTKEY", "secret_access_key": "testsecret", "session_token": "testsession"}}
```

- [ ] **Step 2: Write the failing tests** (append to `tests/kion/kion-creds.bats`)

```bats
@test "multi account + multi car: numbered picks from stdin" {
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --password-stdin <<EOF
pw
2
1
EOF
  [ "$status" -eq 0 ]
  grep -q '"account_number":"444455556666"' "$MOCK_LOG"   # picked account 2
  grep -q '"cloud_access_role_name":"developer"' "$MOCK_LOG"  # picked car 1
}

@test "--car narrows to one role: only the account pick is prompted" {
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --car admin --password-stdin <<EOF
pw
1
EOF
  [ "$status" -eq 0 ]
  grep -q '"cloud_access_role_name":"admin"' "$MOCK_LOG"
}

@test "--car with no matching role exits 6" {
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --car nope --password-stdin <<<"pw"
  [ "$status" -eq 6 ]
}

@test "invalid pick number exits 2" {
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --password-stdin <<EOF
pw
99
EOF
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid selection"* ]]
}

@test "no tty and no --password-stdin exits 8" {
  command -v setsid >/dev/null 2>&1 || skip "needs setsid (linux/CI)"
  run setsid "$SCRIPT" --id 101 </dev/null
  [ "$status" -eq 8 ]
}
```

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `bats tests/kion/kion-creds.bats`
Expected: 4 new FAIL (multi paths hit the Task-3 `kc_pick` stub, exit 7); the no-tty test already PASSes (`kc_read_password` fires EX_NOTTY before any picker runs) or SKIPs on macOS; 18 old PASS.

- [ ] **Step 4: Implement — replace the whole `kc_pick` stub**

```bash
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
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > $# )); then
    err "$EX_USAGE" "invalid selection: ${choice}"
  fi
  local choices=("$@")
  printf '%s\n' "${choices[choice - 1]}"
}
```

- [ ] **Step 5: Run tests + shellcheck**

Run: `bats tests/kion/kion-creds.bats` — Expected: 23 PASS (no-tty test may SKIP on macOS).
Run: `shellcheck ansible/roles/kion/files/kion-creds.sh` — Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add tests/kion ansible/roles/kion/files/kion-creds.sh
git commit -m "feat(kion): interactive account/car picker, --car filter, tty guards"
```

---

### Task 5: Login-shell hook

**Files:**
- Create: `ansible/roles/kion/files/kion-creds-login.sh`
- Test: `tests/kion/login-hook.bats`

**Interfaces:**
- Consumes: `kion-creds` exit-code contract (0 ok, 3 auth, 9 check-expired), `--check` flag, state file at `${KION_CREDS_USER_DIR:-~/.config/kion-creds}/state`.
- Produces: `/etc/profile.d/kion-creds.sh` payload. Sourced by login shells AND (via AL2023's `/etc/bashrc`, which sources `/etc/profile.d/*.sh` for interactive non-login shells) by code-server/DCV terminals. Test seam: `KION_CREDS_HOOK_FORCE=1` bypasses the interactive/tty guards.

- [ ] **Step 1: Write the failing tests**

Create `tests/kion/login-hook.bats`:

```bats
#!/usr/bin/env bats
# Tests for the profile.d login hook. kion-creds is stubbed on PATH; the hook
# is sourced in a throwaway bash with KION_CREDS_HOOK_FORCE=1 (guard seam).

HOOK="${BATS_TEST_DIRNAME}/../../ansible/roles/kion/files/kion-creds-login.sh"

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="${TEST_TMP}/home"
  mkdir -p "$HOME"
  export KION_CREDS_USER_DIR="${HOME}/.config/kion-creds"
  export CALL_LOG="${TEST_TMP}/calls.log"
  mkdir -p "${TEST_TMP}/bin" "$KION_CREDS_USER_DIR"
  cat >"${TEST_TMP}/bin/kion-creds" <<'STUB'
#!/usr/bin/env bash
echo "kion-creds $*" >>"$CALL_LOG"
case " $* " in
  *" --check "*) exit "${STUB_CHECK_RC:-9}" ;;
  *)             exit "${STUB_RUN_RC:-0}"   ;;
esac
STUB
  chmod 755 "${TEST_TMP}/bin/kion-creds"
  export PATH="${TEST_TMP}/bin:${PATH}"
  touch "${KION_CREDS_USER_DIR}/state"
}

teardown() { rm -rf "$TEST_TMP"; }

source_hook() {
  run bash -c "export KION_CREDS_HOOK_FORCE=1; . '$HOOK'"
}

@test "non-interactive shell without force: hook is a silent no-op" {
  run bash -c ". '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALL_LOG" ]
}

@test "fresh creds: only --check runs, silence" {
  export STUB_CHECK_RC=0
  source_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(grep -c 'kion-creds' "$CALL_LOG")" -eq 1 ]
  grep -q -- '--check' "$CALL_LOG"
}

@test "no state file: prints the first-run hint, no fetch" {
  rm -f "${KION_CREDS_USER_DIR}/state"
  source_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"no cached project"* ]]
  [ ! -s "$CALL_LOG" ]
}

@test "expired creds: fetch runs once on success" {
  export STUB_CHECK_RC=9 STUB_RUN_RC=0
  source_hook
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kion-creds $' "$CALL_LOG")" -eq 1 ]
}

@test "auth failure retries 3 times then warns, shell survives" {
  export STUB_CHECK_RC=9 STUB_RUN_RC=3
  source_hook
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kion-creds $' "$CALL_LOG")" -eq 3 ]
  [[ "$output" == *"3 failed password attempts"* ]]
}

@test "non-auth failure: single attempt, warn, shell survives" {
  export STUB_CHECK_RC=9 STUB_RUN_RC=4
  source_hook
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kion-creds $' "$CALL_LOG")" -eq 1 ]
  [[ "$output" == *"exit 4"* ]]
}

@test "kion-creds missing from PATH: silent no-op" {
  rm "${TEST_TMP}/bin/kion-creds"
  source_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/kion/login-hook.bats`
Expected: all FAIL (hook file missing).

- [ ] **Step 3: Implement the hook**

Create `ansible/roles/kion/files/kion-creds-login.sh`:

```sh
# shellcheck shell=sh
# kion-creds login hook — installed as /etc/profile.d/kion-creds.sh.
# Prompts for the Kion password when the cached STAK has expired.
# Sourced by login shells AND by interactive non-login shells (AL2023's
# /etc/bashrc sources /etc/profile.d/*.sh) — so code-server/DCV terminals
# are covered too. POSIX sh: profile.d is sourced by any /bin/sh.
# MUST NEVER fail or block the shell — every path ends in return 0.
# Design: docs/superpowers/specs/2026-07-22-kion-creds-design.md

_kion_hook() {
  command -v kion-creds >/dev/null 2>&1 || return 0
  _kion_state="${KION_CREDS_USER_DIR:-$HOME/.config/kion-creds}/state"
  if [ ! -f "$_kion_state" ]; then
    echo "kion: no cached project — run 'kion-creds --id <project>' to fetch AWS credentials"
    return 0
  fi
  kion-creds --check 2>/dev/null && return 0
  _kion_try=0
  while [ "$_kion_try" -lt 3 ]; do
    kion-creds
    _kion_rc=$?
    [ "$_kion_rc" -eq 0 ] && return 0
    if [ "$_kion_rc" -ne 3 ]; then
      echo "kion: credential fetch failed (exit $_kion_rc) — run 'kion-creds' manually" >&2
      return 0
    fi
    _kion_try=$((_kion_try + 1))
  done
  echo "kion: 3 failed password attempts — run 'kion-creds' manually" >&2
  return 0
}

_kion_guard_ok() {
  [ "${KION_CREDS_HOOK_FORCE:-0}" = "1" ] && return 0
  case $- in *i*) ;; *) return 1 ;; esac
  [ -t 0 ] || return 1
  return 0
}

# No run-once flag: nested/child interactive shells re-source this, and the
# `kion-creds --check` fast path (offline timestamp compare) keeps that silent
# and cheap. An exported guard would suppress the expired-creds prompt in tmux
# panes and child shells for the rest of the session.
if _kion_guard_ok; then
  _kion_hook || true
fi
unset -f _kion_hook _kion_guard_ok
unset _kion_state _kion_try _kion_rc 2>/dev/null || true
```

- [ ] **Step 4: Run tests + shellcheck**

Run: `bats tests/kion/login-hook.bats` — Expected: 7 PASS.
Run: `shellcheck ansible/roles/kion/files/kion-creds-login.sh` — Expected: clean.
Run: `bats tests/kion` — Expected: full suite PASS (no regressions).

- [ ] **Step 5: Commit**

```bash
git add tests/kion/login-hook.bats ansible/roles/kion/files/kion-creds-login.sh
git commit -m "feat(kion): posix login hook — expiry fast path, 3-try auth retry, never blocks shell"
```

---

### Task 6: Ansible role, playbook + layer wiring, CI

**Files:**
- Create: `ansible/roles/kion/defaults/main.yml`, `ansible/roles/kion/tasks/main.yml`, `ansible/roles/kion/templates/kion-creds.conf.j2`
- Modify: `ansible/playbook.yml` (insert role after `ai_tools`), `ansible/layer_config.yml` (add `kion: false`), `.github/workflows/ci.yml` (bats job + shellcheck paths)

**Interfaces:**
- Consumes: script + hook files from Tasks 1–5; `dev_user` playbook var; `layers.*` gating convention; existing `ci.yml` job structure and its SHA-pinned checkout step.
- Produces: baked image artifacts `/usr/local/bin/kion-creds` (0755), `/etc/profile.d/kion-creds.sh` (0644), `/etc/kion-creds.conf` (0644); role vars `kion_url kion_idms_id kion_aws_profile kion_refresh_fudge_seconds kion_stak_ttl_seconds`; CI jobs `bats` and extended `shellcheck`.

- [ ] **Step 1: Write the role defaults**

Create `ansible/roles/kion/defaults/main.yml`:

```yaml
---
# Kion STAK fetcher (design: docs/superpowers/specs/2026-07-22-kion-creds-design.md).
# kion_url is org-specific and REQUIRED when layers.kion is enabled — supply it
# via packer extra-vars or group_vars; the role bake-asserts it is non-empty.
# None of these are secrets: the operator's Kion password is prompted at runtime
# and never baked (CLAUDE.md §8 secrets invariant).
kion_url: ""
kion_idms_id: 1
kion_aws_profile: default
kion_refresh_fudge_seconds: 300
# STAK lifetime used to compute the cached expiry timestamp.
# [ASSUMED, confirmed-at-first-use]: match the org Kion's actual STAK TTL.
kion_stak_ttl_seconds: 3600
```

- [ ] **Step 2: Write the conf template**

Create `ansible/roles/kion/templates/kion-creds.conf.j2`:

```jinja
# Rendered by Ansible — role: kion. Do not edit by hand.
# Per-user overrides belong in ~/.config/kion-creds/config (same KEY="value"
# format; KION_USERNAME goes there too, never here).
# NOTE: the default profile "default" shadows the instance-role (IMDS)
# credentials for CLI/SDK calls on this box — intended. Set KION_AWS_PROFILE
# to a named profile to keep the IMDS default chain.
KION_URL="{{ kion_url }}"
KION_IDMS_ID="{{ kion_idms_id }}"
KION_AWS_PROFILE="{{ kion_aws_profile }}"
KION_REFRESH_FUDGE_SECONDS="{{ kion_refresh_fudge_seconds }}"
KION_STAK_TTL_SECONDS="{{ kion_stak_ttl_seconds }}"
```

- [ ] **Step 3: Write the role tasks**

Create `ansible/roles/kion/tasks/main.yml`:

```yaml
---
# Kion STAK fetcher — on-demand `kion-creds` CLI + login-shell hook.
# NO secrets baked (CLAUDE.md §8): the script prompts for the Kion password at
# runtime; only the org Kion URL and non-secret tuning knobs are rendered.
# curl: AL2023's preinstalled curl-minimal covers every flag the script uses
# (http/https, -sS -X -H -w --data-binary --connect-timeout --max-time), so
# only jq is installed here. The base role also lists jq — dnf is idempotent;
# installing here keeps the role self-contained (ai_tools precedent).

- name: Assert kion_url is configured (bake-assert)
  ansible.builtin.assert:
    that:
      - kion_url | length > 0
    fail_msg: >-
      layers.kion is enabled but kion_url is empty. Set kion_url (the org Kion
      base URL, e.g. https://kion.example.org) via packer extra-vars or
      group_vars — see ansible/roles/kion/defaults/main.yml.
    quiet: true

- name: Install kion-creds runtime dependency (jq)
  ansible.builtin.dnf:
    name: jq
    state: present

- name: Install the kion-creds script
  ansible.builtin.copy:
    src: kion-creds.sh
    dest: /usr/local/bin/kion-creds
    owner: root
    group: root
    mode: "0755"

- name: Install the login-shell hook
  ansible.builtin.copy:
    src: kion-creds-login.sh
    dest: /etc/profile.d/kion-creds.sh
    owner: root
    group: root
    mode: "0644"

- name: Render /etc/kion-creds.conf
  ansible.builtin.template:
    src: kion-creds.conf.j2
    dest: /etc/kion-creds.conf
    owner: root
    group: root
    mode: "0644"

# ── Bake-asserts (dcv/xrdp bake-green-but-broken pattern) ──
# --help proves the script parses and runs on the image's bash/jq;
# --check as the dev user proves the state/config path works unprivileged
# (rc 9 = "no cached creds yet" is the expected fresh-image answer).

- name: Run kion-creds --help (bake-assert)
  ansible.builtin.command:
    cmd: /usr/local/bin/kion-creds --help
  changed_when: false

- name: Run kion-creds --check as the dev user (bake-assert)
  ansible.builtin.command:
    cmd: /usr/local/bin/kion-creds --check
  become: true
  become_user: "{{ dev_user }}"
  register: kion_check
  changed_when: false
  failed_when: kion_check.rc not in [0, 9]

- name: Assert the rendered conf carries the org URL (bake-assert)
  ansible.builtin.command:
    cmd: grep -q "^KION_URL=.https" /etc/kion-creds.conf
  changed_when: false

- name: Stat the login hook (bake-assert)
  ansible.builtin.stat:
    path: /etc/profile.d/kion-creds.sh
  register: kion_hook_stat

- name: Assert the login hook landed with the right mode (bake-assert)
  ansible.builtin.assert:
    that:
      - kion_hook_stat.stat.exists
      - kion_hook_stat.stat.mode == "0644"
    fail_msg: >-
      /etc/profile.d/kion-creds.sh is missing or has the wrong mode — the login
      prompt would silently never fire.
    quiet: true

# The shell-startup design rests on AL2023's /etc/bashrc sourcing
# /etc/profile.d/*.sh for interactive non-login shells (code-server/DCV
# terminals). If a future AL2023 drops that, fail the bake here instead of the
# hook silently never running in those terminals.
- name: Assert /etc/bashrc sources profile.d for non-login shells (bake-assert)
  ansible.builtin.command:
    cmd: grep -q "profile\.d" /etc/bashrc
  changed_when: false
```

- [ ] **Step 4: Wire the playbook and layer config**

In `ansible/playbook.yml`, insert after the `ai_tools` role block (immediately before `- role: secrets`):

```yaml
    - role: kion
      when: layers.kion | default(false)
      # Kion STAK fetcher: /usr/local/bin/kion-creds + /etc/profile.d login hook.
      # Prompts for the operator's Kion password at login — NO secrets baked.
      # Requires the kion_url extra-var when enabled (role bake-asserts it).
      # MUST stay before hardening (last-role invariant).
```

In `ansible/layer_config.yml`, add after the `ai_tools: true` line:

```yaml
  # kion bakes the kion-creds STAK fetcher (login-prompted AWS creds via Kion).
  # Off by default: requires the org-specific kion_url extra-var to be set.
  kion: false
```

- [ ] **Step 5: Run ansible-lint**

Run: `ansible-lint ansible/playbook.yml`
Expected: exit 0, no new violations. (Fix any fqcn/naming nits it reports before continuing — mirror the `ai_tools` role style.)

- [ ] **Step 6: Extend CI**

In `.github/workflows/ci.yml`:

a) In the existing `shellcheck` job, replace the run line

```yaml
        run: shellcheck scripts/*.sh
```

with:

```yaml
        run: shellcheck scripts/*.sh ansible/roles/kion/files/*.sh tests/kion/mocks/curl tests/kion/*.bats
```

Also update the comment above that run line (it currently says shellcheck "covers all
scripts in scripts/") to mention the kion role files and tests.

b) Add a `bats` job at the end of the jobs map, matching house style (numbered
separator comment, two-line SHA-pinned checkout — the SHA below is the one every
existing job uses, verified against the file):

```yaml
  # ---- 9. bats — kion-creds unit tests -------------------------------------
  bats:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - name: Install bats
        run: sudo apt-get update && sudo apt-get install -y bats
      - name: Run kion unit tests
        run: bats tests/kion
```

c) Bump the stale bookkeeping comments: the header comment near the top of `ci.yml`
says "8 jobs, no needs: deps" — make it 9; keep the numbered `# ---- N.` separator
sequence consistent with the new job.

- [ ] **Step 7: Full local verification**

Run: `bats tests/kion` — Expected: full suite PASS.
Run: `shellcheck scripts/*.sh ansible/roles/kion/files/*.sh tests/kion/mocks/curl` — Expected: clean.
Run: `pre-commit run --all-files` — Expected: commit-stage hooks pass (shellcheck incl. the bats files and curl mock, grep-gates, gitleaks, formatters). Note: ansible-lint is a pre-push-stage hook and does NOT run in this command — it is covered by Step 5's direct run (or `pre-commit run --hook-stage pre-push --all-files`).

- [ ] **Step 8: Commit**

```bash
git add ansible/roles/kion ansible/playbook.yml ansible/layer_config.yml .github/workflows/ci.yml
git commit -m "feat(kion): ansible role, layer gating, bake-asserts, bats+shellcheck CI"
```

---

## Post-plan notes (not tasks)

- **First-bake verification (UAT, needs AWS + Kion access):** enable `layers.kion` with a real `kion_url`, `./run build`, then on the instance confirm the `[ASSUMED, confirmed-at-first-use]` items: the four endpoint paths + response shapes against `/swagger`, the real STAK TTL (update `kion_stak_ttl_seconds`), and IDMS id (update `kion_idms_id`). Correct the marked block in `kion-creds.sh` if the org's Kion differs, and update the fixtures to match.
- The spec's shell-startup caveat is handled by AL2023's `/etc/bashrc` sourcing `/etc/profile.d/*.sh` for interactive non-login shells; the role bake-asserts that sourcing line exists. Confirm end-to-end at UAT: open a fresh code-server terminal with absent/expired creds and expect the first-run hint or password prompt.
- Spec caveat 1 said the plan phase verifies endpoint paths against the org `/swagger` — no Kion instance is reachable from this workstation, so that verification is consciously deferred to first-bake UAT. The `[ASSUMED, confirmed-at-first-use]` block at the top of `kion-creds.sh` is the single place to correct paths and shapes (fixtures must be updated in lockstep).
- CLAUDE.md §5 daily-flow mention of `kion-creds` — leave to the doc-updater pass after UAT confirms the flow.
