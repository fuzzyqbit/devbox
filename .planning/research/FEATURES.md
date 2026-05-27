# Feature Landscape: ./run Task Runner Script

**Domain:** Shell-based task runner replacing a Makefile in a personal IaC project
**Researched:** 2026-05-27
**Scope:** Features for `./run <command>` that works identically locally and in GitLab CI runners

---

## Context: What Already Exists

The Makefile being replaced has these established behaviors that the `./run` script must preserve:

- 20 named commands across 5 groups: AMI/Packer, Terraform/OpenTofu, instance lifecycle, SSM access, secrets
- `DEVBOX_USER` guard that refuses to run state-touching commands without it
- `tf-ensure-init` auto-reinit guard (checks backend cache key vs current user, reinits if stale)
- `TF_BIN` override for tofu vs terraform
- `TF_STATE_BUCKET` derivation via `aws sts get-caller-identity`
- Per-operator backend config threading (`-backend-config` flags)
- A `help` target with grouped command listing

The scripts in `scripts/` already have: `parse_args` with `--user/--instance-id/--region` flags, `resolve_user`, `resolve_instance`, `init_devbox`, and individual `usage()` functions. The `_common.sh` pattern is solid infrastructure that `./run` should delegate to rather than replace.

---

## Table Stakes

Features that must exist or the `./run` script will frustrate operators more than the Makefile it replaces.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Subcommand dispatch** | Every modern CLI uses `tool <command>` not `tool-command` | Low | `case "$1" in` pattern; delegates to scripts or inline logic |
| **Help output — grouped** | Makefile already has this; regression if lost | Low | Must mirror Makefile's 5-group structure. `./run` or `./run help` both work |
| **DEVBOX_USER guard** | Already enforced by Makefile; removing it causes silent state corruption | Low | Port the existing `_require-devbox-user` guard exactly |
| **DEVBOX_USER env + arg** | Operators export it or pass per-invocation | Low | Accept via env var and via `--user` / positional (keep parity with scripts) |
| **tf-ensure-init guard** | The auto-backend-reinit is a genuine UX win; scripts that omit it break after user switching | Medium | Port the jq-based backend cache check from the Makefile |
| **Unrecognized command error** | Typos should produce `unknown command: foo` not silent no-op | Low | Default case in the dispatch with exit 1 |
| **Pass-through to scripts** | `scripts/*.sh` already exist and work; `./run` should delegate, not duplicate | Low | Exec or source with env vars threaded through |
| **CI-safe (no TTY requirement)** | GitLab CI runners have no TTY; the script must not hang on prompts | Low | `set -euo pipefail`; no `read` without `-t 0` guard; no interactive prompts |
| **Makefile target name parity** | All 20 existing command names must work as-is | Low | Operators will muscle-memory the names; a rename breaks CLAUDE.md and CI scripts |

## Differentiators

Features that improve operator experience meaningfully without adding accidental complexity.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Dependency preflight check** | Single `./run doctor` (or preflight on every run) that checks aws, jq, packer, tofu, ansible, session-manager-plugin, shellcheck are on PATH — surfaces clear "missing: session-manager-plugin, install: brew install --cask session-manager-plugin" before any command fails mid-way | Medium | `command -v` loop with per-tool install hints. Optionally triggered as `./run doctor` rather than blocking every invocation — fast commands (help, fmt) do not need AWS tools present |
| **Colored output — CI-aware** | `[OK]`, `[WARN]`, `[ERROR]` prefixes in color locally, plain text in CI | Low | Check `[[ -t 1 ]]` (stdout is a tty) AND respect `NO_COLOR` env var (no-color.org standard) AND detect `CI=true`. Three-condition guard: `color_enabled = tty AND NOT NO_COLOR AND NOT CI` |
| **Dry-run flag for destructive commands** | `./run tf-destroy --dry-run` prints what would happen without doing it; maps to `tofu plan -destroy` | Low | Only meaningful for: tf-destroy, tf-auto-destroy, tf-apply, tf-auto-apply. Other commands are already read-only or idempotent |
| **`./run` with no arguments shows help** | Common CLI convention; `./run` alone should not error | Low | If `$1` is empty, call help handler. Zero effort, high polish |
| **Version/env info command** | `./run env` prints: DEVBOX_USER, TF_BIN version, aws-cli version, tofu version, resolved TF_STATE_BUCKET — useful for debugging CI failures | Low | Pure read-only reporting; helps when CI fails with version mismatch |
| **Consistent error message format** | All errors follow: `ERROR: <what went wrong>. <how to fix it>.` — currently the Makefile mixes formats | Low | Adopt the pattern already used in `scripts/_common.sh` throughout `./run` itself |
| **Exit code discipline** | `./run` exits non-zero on any command failure; CI pipelines depend on this | Low | `set -euo pipefail` at top of script; any subshell failure propagates |
| **GitLab CI single-source alignment** | CI pipeline `script:` blocks call `./run <command>` instead of inline shell — the script IS the runbook | Low | This is the primary v2.0 goal; not a feature of the script per se but the design constraint that shapes everything |

## Anti-Features

Things to explicitly NOT build. Keeping `./run` a plain bash script is a feature.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Plugin/extension system** | One operator, one project, zero extensibility need | Hard-code the 20 commands; add new ones as case branches |
| **Configuration file (`run.toml`, `.runrc`)** | The Makefile already has all config as env vars; a new config file format adds a new mental model | Keep env vars + CLI args as the only configuration surface |
| **Tab completion script** | Low ROI for a single-operator project; adds a maintenance burden (completions must be sourced, vary by shell) | The 20 command names are short and memorable; `./run help` is the discovery mechanism |
| **Parallel task execution** | No current targets need to run in parallel; CI handles parallelism via separate jobs | Sequential execution is simpler, easier to debug, and matches the Makefile's behavior |
| **Dependency graph / task ordering engine** | The `tf-ensure-init` guard is already the only real dependency; generalizing it adds complexity | Keep the guard as an explicit check inside the commands that need it |
| **Built-in retry logic** | AWS CLI calls that fail should fail loudly so the operator understands the problem | Let failures propagate; add retry manually only if a specific command shows a real transient failure pattern |
| **Progress bars / spinners** | These require cursor control and break in CI logs | Print timestamped status lines instead (`echo "[$(date +%H:%M:%S)] Waiting for instance to reach running state..."`) |
| **Interactive menus / prompts** | CI runners have no TTY; interactive prompts break the CI use case entirely | All inputs via args or env vars only |
| **Automatic shell detection** | `#!/usr/bin/env bash` is sufficient; detecting zsh vs fish vs bash is complexity for zero gain | Bash only; document it |
| **Rewriting scripts/_common.sh** | The existing helper library is already solid and tested; `./run` should source and call it | Delegate lifecycle commands to the existing scripts; keep `./run` as a thin dispatcher |

---

## Feature Dependencies

```
Colored output → CI detection (must disable color in CI)
Colored output → NO_COLOR check (must honor the standard)
Dry-run flag  → tf-ensure-init guard (dry-run still needs backend initialized to plan)
./run doctor  → per-tool install hints (each missing tool needs a specific hint, not a generic "install it")
DEVBOX_USER guard → all tf-* and lifecycle commands (guard must be checked before any AWS call)
tf-ensure-init → tf-plan, tf-apply, tf-auto-apply, tf-destroy, tf-auto-destroy, start, stop, status, devbox-ssm
```

---

## MVP Recommendation

The v2.0 MVP `./run` script needs exactly:

1. **Subcommand dispatch** with all 20 existing Makefile command names
2. **Help grouped by category** (matches existing `make help` output, updated to `./run` syntax)
3. **DEVBOX_USER guard** (identical to Makefile's `_require-devbox-user`)
4. **tf-ensure-init guard** (identical logic, invoked by the same commands that invoke it today)
5. **`./run` with no args shows help** (convention; zero cost)
6. **CI-safe execution** (`set -euo pipefail`, no TTY requirements, no interactive prompts)
7. **Colored output with NO_COLOR + CI + tty guards** (low complexity, high polish, correct behavior in CI)

Defer to post-MVP:
- `./run doctor` preflight command — useful but not blocking; existing scripts already have per-tool hints on failure
- `./run env` info command — useful for debugging but not on the critical path
- Dry-run flag — only 4 commands benefit; tofu already has `tf-plan` as the dry-run equivalent for apply

---

## Sources

- NO_COLOR convention: https://no-color.org/
- FORCE_COLOR convention: https://force-color.org/
- Taskfile vs Just vs Make feature comparison: https://mylinux.work/guides/taskfile-vs-just-vs-make/
- Bash dependency checking patterns: https://gist.github.com/montanaflynn/e1e754784749fd2aaca7
- Bash colored output with tty detection: https://iifx.dev/en/articles/457712064/bash-scripting-how-to-reliably-use-color-output
- Preflight check patterns: https://samanpavel.medium.com/bash-fail-fast-on-missing-dependencies-b7560bf143e8
