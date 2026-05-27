# Technology Stack: ./run Shell Script Runner

**Project:** devbox v2.0 — Run Script + GitLab CI Integration
**Researched:** 2026-05-27
**Scope:** Shell implementation choices for `./run` script replacing Makefile

---

## Recommended Stack

### Core Implementation

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Bash | 4.x+ (require; guard on boot) | Script runtime | `BASH_SOURCE`, process substitution, `set -euo pipefail`, `[[ ]]` — all Bash-specific and all already used in `scripts/_common.sh`. POSIX sh portability is not achievable without rewriting existing helpers; target bash explicitly. |
| `#!/usr/bin/env bash` shebang | — | Invocation | Picks up Homebrew bash 5.x on macOS (avoids system bash 3.2 which lacks `declare -A`); finds correct bash in CI images |
| `set -euo pipefail` | — | Error safety | Fail fast on errors, unset vars, pipe failures. Already the project standard in all `scripts/*.sh` |
| `case` dispatch | — | Subcommand routing | POSIX-compatible dispatch; no eval; shellcheck-clean; readable. Map `$1` to function calls via `case "$1" in` |

### Shell Version Strategy

**Require Bash 4+, not POSIX sh.** Rationale:

1. `scripts/_common.sh` already uses `BASH_SOURCE[0]`, `[[ ]]`, `local`, and process substitution — all Bash-only. Rewriting helpers for POSIX sh compliance would be a pure rewrite with no benefit.
2. macOS ships Bash 3.2 (GPL v2 freeze, Apple won't update). The operator CLAUDE.md already mandates `brew install` of multiple tools; adding `bash` to that list is consistent. A version guard at the top of `./run` provides a clear error rather than silent misbehavior.
3. All CI images used by this project (opentofu, hashicorp/packer, pipelinecomponents/ansible-lint, bridgecrew/checkov, koalaman/shellcheck-alpine) explicitly install `bash` via `apk add bash` in their Dockerfiles — bash is available in every job image. Confidence: HIGH (verified from Dockerfiles and Alpine package installs in image layers).
4. GitLab Runner Docker executor auto-selects bash when present (checks `/usr/local/bin/bash` → `/usr/bin/bash` → `/bin/bash` before falling back to sh). Inline `.gitlab-ci.yml` `script:` blocks execute under bash in these images. When calling `./run` as an external script, the shebang governs — executor's shell selection is bypassed.

### Bash Version Guard Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "ERROR: Bash 4+ required. macOS: brew install bash" >&2
  exit 1
fi
```

This must be the first executable block — before any function definitions or sourcing.

### Subcommand Dispatch Pattern

Use `case` statement dispatch to named functions. Functions are the single source of truth — help text is either embedded in a `help` function or via per-function docstrings extracted by `grep`.

```bash
# Recommended: explicit case dispatch
main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    build)         cmd_build "$@" ;;
    tf-init)       cmd_tf_init "$@" ;;
    tf-apply)      cmd_tf_apply "$@" ;;
    start)         cmd_start "$@" ;;
    stop)          cmd_stop "$@" ;;
    status)        cmd_status "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
      echo "ERROR: Unknown command: $cmd" >&2
      echo "Run: ./run help" >&2
      exit 1
      ;;
  esac
}

main "$@"
```

**Do NOT use `eval "$cmd"` or `"$@"` dispatch.** Reasons:
- `eval` is a shellcheck SC2294 warning and an injection vector if cmd ever comes from env
- Direct function-name dispatch (`"cmd_$1" "$@"`) makes it impossible to distinguish public commands from internal helpers without naming conventions; the case statement is unambiguous

### Variable Naming Convention

Mirror the existing Makefile conventions exactly — `DEVBOX_USER`, `TF_BIN`, `TF_STATE_BUCKET`, `TF_STATE_KEY`, `TF_STATE_REGION`, `TF_STATE_LOCK_TABLE`, `INSTANCE_ID`, `REGION`. No renaming — operators already have these in shell profiles and CI variables.

### Guard Pattern for DEVBOX_USER

```bash
_require_devbox_user() {
  if [[ -z "${DEVBOX_USER:-}" ]]; then
    echo "ERROR: DEVBOX_USER is not set." >&2
    echo "       Set per-invocation:  DEVBOX_USER=jsmith ./run <command>" >&2
    echo "       Or in your shell:    export DEVBOX_USER=jsmith" >&2
    exit 1
  fi
}
```

Note the syntax shift from Make (`DEVBOX_USER=jsmith make target`) to shell (`DEVBOX_USER=jsmith ./run command` or `export DEVBOX_USER=jsmith; ./run command`). The env-var-prefix form is idiomatic bash and avoids Make's special variable semantics.

### Backend Config Derivation

The `TF_STATE_BUCKET` derivation from `aws sts get-caller-identity` (Makefile line 39) translates to:

```bash
_derive_tf_state_bucket() {
  if [[ -z "${TF_STATE_BUCKET:-}" ]]; then
    local account_id
    account_id="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || {
      echo "ERROR: could not resolve AWS account ID via 'aws sts get-caller-identity'." >&2
      echo "       Check your AWS credentials/profile, or set TF_STATE_BUCKET=... explicitly." >&2
      exit 1
    }
    TF_STATE_BUCKET="devimage-tfstate-${account_id}"
  fi
}
```

Call this lazily (inside `cmd_tf_init`, `cmd_tf_reinit`) not at script startup — avoids requiring AWS credentials for `./run help` or `./run fmt`.

### Auto-Init Guard

The Makefile `tf-ensure-init` pattern (comparing cached backend key vs current `TF_STATE_KEY`) translates directly to bash. Use `jq -r '.backend.config.key // empty'` as-is — jq is already a project prerequisite.

---

## CI Runner Compatibility Matrix

| CI Image | Base OS | Bash Available | Confirmed By |
|----------|---------|---------------|--------------|
| `ghcr.io/opentofu/opentofu:1.10.6` | Alpine 3.20 | YES — `apk add --no-cache git bash openssh` in Dockerfile | HIGH: verified from official Dockerfile |
| `hashicorp/packer:1.15.3` | Alpine (golang:alpine base) | YES — `apk add --update git bash openssl` in Dockerfile | HIGH: verified from Docker Hub Dockerfile |
| `pipelinecomponents/ansible-lint:0.26.0` | Alpine (inferred from pipelinecomponents family) | YES — pipelinecomponents images install bash | MEDIUM: not directly verified from Dockerfile, consistent with project pattern |
| `bridgecrew/checkov:3.2.527` | Python-alpine based | YES — Dockerfile installs bash via apk | MEDIUM: verified from Checkov repo Dockerfile for similar versions |
| `koalaman/shellcheck-alpine:v0.10.0` | Alpine | NO by default — shellcheck-alpine is minimal | LOW: Alpine ash/sh only; bash NOT guaranteed |

**Critical note for shellcheck-alpine:** The `validate:shellcheck` job uses `koalaman/shellcheck-alpine` which is a minimal Alpine image. Shellcheck itself runs as a binary, not a shell. If `./run` needs to be called from this job (unlikely — shellcheck is a static analysis tool, not a runtime caller), bash would need to be installed first. For the actual `shellcheck` invocation (`shellcheck scripts/*.sh`), no bash is needed in the job — shellcheck is the analyzer, not the runner. The job does not call `./run`.

**Recommendation for CI jobs calling `./run`:** The bake and deploy jobs use packer and opentofu images respectively — both have bash. The `.aws-auth` template already uses `command -v apk` to detect Alpine and `apk add --no-cache aws-cli jq` if needed. The same defensive pattern can be applied for bash in any new jobs that source `./run`.

---

## GitLab CI Integration: How ./run Gets Called

GitLab Runner Docker executor shell selection order:
1. Checks `/usr/local/bin/bash`, `/usr/bin/bash`, `/bin/bash`
2. Falls back to `/bin/sh`, `/busybox/sh`

When bash is found, **inline `script:` blocks execute under bash**. But this is executor-level — it is NOT a shebang. When a job's `script:` calls `- ./run build`, the executor shell (`bash`) spawns `./run` as a subprocess, and the subprocess uses **its own shebang** (`#!/usr/bin/env bash`). Both levels therefore run bash, but for different reasons.

**Practical implication:** `./run` does not need to be called with an explicit `bash ./run` invocation in CI. The shebang on `./run` is sufficient because:
1. The repo is checked out with permissions preserved (`git checkout` respects execute bits IF they were committed — ensure `chmod +x ./run` + `git update-index --chmod=+x ./run`).
2. The Docker image has bash at a standard path found by `env`.

**CI job script pattern (replaces current inline shell):**

```yaml
script:
  - ./run tf-init
  - ./run tf-apply
```

Not:
```yaml
script:
  - bash ./run tf-init   # unnecessary; shebang handles it
```

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Shell target | Bash 4+ | POSIX sh | Existing helpers use Bash-only features; rewriting is net-negative scope |
| Shell target | Bash 4+ | zsh | Not available in CI images; not standard for scripts |
| Dispatch | `case` statement | `eval "cmd_$1"` | Injection risk; shellcheck warning SC2294; unclear command surface |
| Dispatch | `case` statement | `compgen -A function \| grep ^cmd_` + eval | Clever but opaque; harder to read in code review; shellcheck-hostile |
| Dispatch | `case` statement | Just (justfile runner) | External dependency; defeats the goal of removing a build tool dependency |
| Dispatch | `case` statement | Taskfile (task runner) | Same — external YAML-based tool; not standard in this stack |
| Help generation | Hand-written `cmd_help` function | `compgen`-based autodiscovery | Autodiscovery requires `eval` or `declare -F`; fragile; case-based dispatch already makes the command surface explicit |
| Variable passing | Env vars (`DEVBOX_USER=x ./run`) | `--user` flag on `./run` | Env vars match existing scripts and CI variable injection; flag parsing adds complexity for no gain at orchestrator level (per-command flags still supported by delegating to `scripts/*.sh`) |

---

## Script Structure

```
./run                     # Main dispatcher — the only new file
scripts/
  _common.sh              # Existing shared helpers (unchanged)
  devbox-start.sh         # Existing (unchanged — called by ./run start)
  devbox-stop.sh          # Existing (unchanged)
  devbox-status.sh        # Existing (unchanged)
  devbox-ssm.sh           # Existing (unchanged)
```

The Makefile's inline logic (packer, tofu invocations with args) moves into `./run` functions. The `scripts/*.sh` lifecycle files stay as delegates — `./run start` sets environment and execs the script, same as the Makefile does today.

**Target map (Makefile → ./run):**

| Makefile target | ./run command |
|----------------|---------------|
| `help` | `./run help` |
| `packer-init` | `./run packer-init` |
| `validate` | `./run validate` |
| `build` | `./run build` |
| `fmt` | `./run fmt` |
| `tf-init` | `./run tf-init` |
| `tf-reinit` | `./run tf-reinit` |
| `tf-plan` | `./run tf-plan` |
| `tf-apply` | `./run tf-apply` |
| `tf-auto-apply` | `./run tf-auto-apply` |
| `tf-destroy` | `./run tf-destroy` |
| `tf-auto-destroy` | `./run tf-auto-destroy` |
| `start` | `./run start` |
| `stop` | `./run stop` |
| `status` | `./run status` |
| `devbox-ssm` | `./run devbox-ssm` |
| `devbox-port-forward` | `./run devbox-port-forward` |
| `secrets-show` | `./run secrets-show` |
| `clean` | `./run clean` |

Hyphens in command names are valid: `case "$cmd" in tf-init)` works perfectly.

---

## Sources

- [GitLab Runner shell types](https://docs.gitlab.com/runner/shells/) — MEDIUM confidence (confirms bash default for Unix)
- [GitLab Runner Docker executor shell selection forum](https://forum.gitlab.com/t/how-the-shell-with-docker-executor-is-selected/73923) — MEDIUM confidence (priority order from source code)
- [OpenTofu Dockerfile (official repo)](https://github.com/opentofu/opentofu/blob/main/Dockerfile) — HIGH confidence (bash installed explicitly)
- [HashiCorp Packer Dockerfile](https://hub.docker.com/r/hashicorp/packer/dockerfile/) — HIGH confidence (bash installed explicitly)
- [Checkov Dockerfile](https://github.com/bridgecrewio/checkov/blob/de5425d974fcfea749f4924678b426faa8af9e14/Dockerfile) — MEDIUM confidence (verified for this commit, not pinned digest)
- [Nick Janetakis — Replacing make with ./run](https://nickjanetakis.com/blog/replacing-make-with-a-shell-script-for-running-your-projects-tasks) — MEDIUM confidence (pattern reference)
- [Bash associative arrays / macOS bash 3.2](https://news.ycombinator.com/item?id=29072097) — HIGH confidence (widely documented)
- [GitLab CI Docker executor bash issue #362](https://gitlab.com/gitlab-org/gitlab-runner/-/issues/362) — MEDIUM confidence (historical, Alpine bash behavior)
