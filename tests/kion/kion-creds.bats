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
  export MOCK_ARGV_LOG="${TEST_TMP}/curl-argv.log"
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

@test "non-numeric KION_REFRESH_FUDGE_SECONDS exits 2 on --check (no arith crash)" {
  mkdir -p "$KION_CREDS_USER_DIR"
  printf 'KION_REFRESH_FUDGE_SECONDS="soon"\n' >"${KION_CREDS_USER_DIR}/config"
  run "$SCRIPT" --check
  [ "$status" -eq 2 ]
  [[ "$output" == *"KION_REFRESH_FUDGE_SECONDS must be a number"* ]]
}

@test "non-numeric KION_STAK_TTL_SECONDS exits 2 on the fetch path" {
  mkdir -p "$KION_CREDS_USER_DIR"
  printf 'KION_STAK_TTL_SECONDS="soon"\n' >"${KION_CREDS_USER_DIR}/config"
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 2 ]
  [[ "$output" == *"KION_STAK_TTL_SECONDS must be a number"* ]]
}

@test "missing project id (no --id, no cache) exits 2 with hint" {
  run "$SCRIPT" --password-stdin <<<"pw"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--id"* ]]
}

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
  # shellcheck disable=SC2314  # negation is the last command in the test, so it fails the test correctly
  ! grep -q 'OLD' "$AWS_SHARED_CREDENTIALS_FILE"
}

@test "happy path: writes profile, caches state, password via body not argv" {
  run "$SCRIPT" --id 101 --password-stdin <<<"hunter2"
  [ "$status" -eq 0 ]
  grep -q '^\[default\]$' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q 'aws_access_key_id = ASIATESTKEY' "$AWS_SHARED_CREDENTIALS_FILE"
  grep -q 'KION_LAST_PROJECT_ID=101' "${KION_CREDS_USER_DIR}/state"
  grep -q 'KION_LAST_USERNAME=' "${KION_CREDS_USER_DIR}/state"
  grep -q 'hunter2' "$MOCK_LOG"           # password travelled in a request body
  # `run` + status (not bare `! grep`): a non-final `!` line never fails a bats
  # test (SC2314), so these must be status-checked to actually guard argv.
  run grep 'hunter2' "$MOCK_ARGV_LOG"
  [ "$status" -ne 0 ]                     # password never on curl argv
  run grep 'test-bearer-token' "$MOCK_ARGV_LOG"
  [ "$status" -ne 0 ]                     # bearer token never on curl argv
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
  # shellcheck disable=SC2030  # each @test runs in its own subshell — the export is intentionally test-local
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
  # shellcheck disable=SC2031  # each @test runs in its own subshell — no cross-test leakage intended
  export MOCK_STATUS__api_v3_token=500
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 7 ]
  [ "$(grep -c '^POST /api/v3/token$' "$MOCK_LOG")" -eq 3 ]  # 1 try + 2 retries
}

@test "empty accounts list exits 5" {
  # shellcheck disable=SC2030  # each @test runs in its own subshell — the export is intentionally test-local
  export MOCK_DIR="${TEST_TMP}/fx"
  mkdir -p "$MOCK_DIR"
  cp "${BATS_TEST_DIRNAME}/fixtures/happy/_api_v3_token.json" "$MOCK_DIR/"
  printf '{"data": []}' >"${MOCK_DIR}/_api_v3_project_101_accounts.json"
  run "$SCRIPT" --id 101 --password-stdin <<<"pw"
  [ "$status" -eq 5 ]
}

@test "--password-stdin accepts a password with no trailing newline" {
  printf '%s' "hunter2" >"${TEST_TMP}/pw"
  run "$SCRIPT" --id 101 --password-stdin <"${TEST_TMP}/pw"
  [ "$status" -eq 0 ]
  grep -q 'hunter2' "$MOCK_LOG"
}

@test "multi account + multi car: numbered picks from stdin" {
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
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
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --car admin --password-stdin <<EOF
pw
1
EOF
  [ "$status" -eq 0 ]
  grep -q '"cloud_access_role_name":"admin"' "$MOCK_LOG"
}

@test "--car with no matching role exits 6" {
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --car nope --password-stdin <<<"pw"
  [ "$status" -eq 6 ]
}

@test "invalid pick number exits 2" {
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --password-stdin <<EOF
pw
99
EOF
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid selection"* ]]
}

@test "octal-looking pick (08) is an invalid selection, not a bash error" {
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
  export MOCK_DIR="${BATS_TEST_DIRNAME}/fixtures/multi"
  run "$SCRIPT" --id 101 --password-stdin <<EOF
pw
08
EOF
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid selection"* ]]
  [[ "$output" != *"value too great"* ]]   # proves no bash octal-base error
}

@test "no tty and no --password-stdin exits 8" {
  command -v setsid >/dev/null 2>&1 || skip "needs setsid (linux/CI)"
  run setsid "$SCRIPT" --id 101 </dev/null
  [ "$status" -eq 8 ]
}
