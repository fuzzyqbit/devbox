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
  # shellcheck disable=SC2030  # each @test runs in its own subshell — the export is intentionally test-local
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
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
  export STUB_CHECK_RC=9 STUB_RUN_RC=0
  source_hook
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kion-creds $' "$CALL_LOG")" -eq 1 ]
}

@test "auth failure retries 3 times then warns, shell survives" {
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
  export STUB_CHECK_RC=9 STUB_RUN_RC=3
  source_hook
  [ "$status" -eq 0 ]
  [ "$(grep -c '^kion-creds $' "$CALL_LOG")" -eq 3 ]
  [[ "$output" == *"3 failed password attempts"* ]]
}

@test "non-auth failure: single attempt, warn, shell survives" {
  # shellcheck disable=SC2030,SC2031  # each @test runs in its own subshell — the export is intentionally test-local
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

@test "hook sources cleanly under plain sh (non-interactive no-op)" {
  run sh -c ". '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALL_LOG" ]
}
