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
