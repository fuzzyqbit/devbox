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
