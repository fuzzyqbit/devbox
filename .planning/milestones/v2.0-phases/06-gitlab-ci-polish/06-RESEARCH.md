# Phase 6: GitLab CI + Polish - Research

**Researched:** 2026-05-27
**Domain:** GitLab CI pipeline integration, bash shell scripting (color output, doctor command)
**Confidence:** HIGH

## Summary

Phase 6 wires the GitLab CI bake and deploy stages to call `./run` instead of inline shell commands, adds colored status output with NO_COLOR/CI suppression, adds a `./run doctor` dependency checker, extends the shellcheck CI job to lint the `run` file, and adds a grep-gate invariant verifying the `run` file's executable bit in git.

The core challenge is bridging the gap between `./run`'s interactive-first design and CI's specific requirements: the bake job passes explicit `-var` flags to packer, the deploy job uses `-lockfile=readonly` and a plan-file workflow (`tofu plan -out=tfplan && tofu apply tfplan`), and CI needs `PKR_VAR_*`/`TF_VAR_*` env vars to thread region and user values through. The research finds three specific mismatches between current `./run` commands and CI job behavior that must be resolved before the pipeline can delegate to `./run`.

**Primary recommendation:** Modify `./run build` and `./run tf-init`/`./run tf-apply` to accept env-var overrides that satisfy CI needs (e.g., `PACKER_ARGS` passthrough for bake, `-lockfile=readonly` when `CI=true` for init), while keeping the local interactive behavior unchanged. Add color output as helper functions gated on `NO_COLOR` and `CI` env vars. Implement `./run doctor` as a new command that checks each required tool with `command -v` and version comparisons.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CI-01 | GitLab CI bake stage calls `./run build` instead of inline packer commands | Bake job analysis (Section: CI Bake Integration), Packer var passthrough pattern |
| CI-02 | GitLab CI deploy stage calls `./run tf-init` and `./run tf-apply` instead of inline tofu commands | Deploy job analysis (Section: CI Deploy Integration), lockfile-readonly and plan-file patterns |
| CI-03 | Validate shellcheck job includes `run` file alongside `scripts/*.sh` | Shellcheck CI job analysis (Section: Shellcheck Integration) |
| CI-04 | Grep-gate invariant verifies `run` file has executable bit in git | Grep-gate analysis (Section: Grep-Gate Integration), `git ls-files -s` pattern |
| POL-01 | `./run` outputs colored status/error messages with NO_COLOR and CI environment guards | NO_COLOR convention research (Section: Color Output), CI env var detection |
| POL-02 | `./run doctor` checks all required dependencies and reports missing/version issues | Doctor command design (Section: Doctor Command), tool list and version floor |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- OpenTofu (`tofu`) is the canonical IaC binary; `terraform/.terraform.lock.hcl` is OpenTofu-flavoured (Phase 3 REP-01)
- Every `image:` line in `.gitlab-ci.yml` MUST be `name@sha256:<64-hex>` (digest-pin policy, grep-gate invariant #7)
- `hardening` MUST remain the last role in `ansible/playbook.yml`
- Action SHA-pin policy: every `uses:` in workflows MUST pin to 40-char hex SHA
- Validate jobs are NOT routed through `./run` (explicit Out of Scope in REQUIREMENTS.md)
- `set -euo pipefail` is the project bash convention; all `cd` wrapped in subshells
- Error messages: "ERROR: ..." on first line to stderr, fix instructions on subsequent lines
- Pre-commit shellcheck hook uses `types: [shell]` which already detects `run` as a shell file (verified locally)

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| CI pipeline orchestration | GitLab CI (`.gitlab-ci.yml`) | -- | Pipeline definition, stage ordering, image selection, rules/triggers |
| Build/deploy command execution | `./run` script | GitLab CI `script:` blocks | `./run` is the single source of truth; CI delegates to it |
| AWS authentication | GitLab CI (`.aws-auth` hidden job) | -- | OIDC federation happens before `./run` is invoked |
| Color output suppression | `./run` script | -- | Script checks env vars and decides whether to emit ANSI codes |
| Dependency validation | `./run doctor` command | -- | Runs locally on operator workstation; CI images are pre-built |
| Executable bit enforcement | GitLab CI grep-gate job | pre-commit grep-gates hook | CI is authoritative; pre-commit provides local feedback |
| Shell linting | GitLab CI shellcheck job | pre-commit shellcheck hook | CI is authoritative; pre-commit provides local feedback |

## Standard Stack

No new libraries or packages are installed in this phase. All changes are to existing bash scripts and YAML configuration files.

### Tools Used (already in project)
| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| shellcheck | v0.10.0 | Shell script linting | CI image: `koalaman/shellcheck-alpine:v0.10.0@sha256:7c6a5115...` |
| bash | 5.x (CI), 4+ (local) | Script runtime | CI Alpine images ship bash 5.x; macOS default is 3.2 |
| git | varies | Executable bit check | `git ls-files -s` works in all CI images used |
| packer | 1.15.3 | AMI bake | CI image: `hashicorp/packer:1.15.3@sha256:cb9c526a...` |
| tofu | 1.10.6 | Infrastructure deploy | CI image: `ghcr.io/opentofu/opentofu:1.10.6@sha256:43f73c1e...` |

## Package Legitimacy Audit

> No new packages are installed in this phase. All changes modify existing files in the repository.

## Architecture Patterns

### System Architecture: CI Pipeline Flow

```text
GitLab Web UI / Schedule trigger
        |
        | PIPELINE_KIND=bake | deploy
        v
.gitlab-ci.yml (workflow:rules gate)
        |
        +---> validate stage (9 parallel jobs, unchanged)
        |     [shellcheck now lints `run` + `scripts/*.sh`]
        |     [grep-gates now checks invariant #8: run executable bit]
        |
        +---> bake stage (PIPELINE_KIND=bake only)
        |     .aws-auth (OIDC) -> PKR_VAR_aws_region=$AWS_REGION
        |                      -> ./run build
        |
        +---> deploy stage (PIPELINE_KIND=deploy + manual)
              .aws-auth (OIDC) -> DEVBOX_USER, TF_STATE_BUCKET set
                               -> ./run tf-init
                               -> ./run tf-apply (or tf-auto-apply)
```

### Pattern 1: Color Output with Environment Guards

**What:** Colored status/error messages in `./run` that auto-suppress in CI and respect `NO_COLOR`.

**When to use:** Every user-facing message from `./run` (status lines, error prefixes, success indicators).

**Implementation pattern:**

```bash
# Color setup — placed after strict mode, before any output
# NO_COLOR spec: https://no-color.org/
# When present and non-empty, prevents ANSI color output.
# CI=true: GitLab CI sets this automatically; suppress color in CI.
if [[ -n "${NO_COLOR:-}" ]] || [[ "${CI:-}" == "true" ]]; then
  RED=""
  GREEN=""
  YELLOW=""
  BOLD=""
  RESET=""
else
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
fi
```

Source: NO_COLOR convention from https://no-color.org/ [CITED: no-color.org]

**Usage pattern — helper functions:**

```bash
_info()  { echo "${GREEN}[INFO]${RESET} $*"; }
_warn()  { echo "${YELLOW}[WARN]${RESET} $*" >&2; }
_error() { echo "${RED}ERROR:${RESET} $*" >&2; }
```

**Important:** The existing error messages in `./run` use plain `echo "ERROR: ..." >&2`. Phase 6 should update these to use the `_error` helper for consistency. The error message content and stderr routing must not change.

### Pattern 2: Doctor Command (Dependency Checker)

**What:** `./run doctor` iterates over required tools, checks presence via `command -v`, optionally checks version floors, and reports pass/fail for each.

**When to use:** After initial clone, or when troubleshooting "tool not found" errors.

**Implementation pattern:**

```bash
cmd_doctor() {
  local pass=0 fail=0 warn=0

  _check_cmd "aws" "brew install awscli" "2"
  _check_cmd "packer" "brew install packer" "1.12"
  _check_cmd "tofu" "brew install opentofu" "1.10"
  _check_cmd "ansible" "brew install ansible" ""
  _check_cmd "ansible-lint" "pip install ansible-lint" "26"
  _check_cmd "jq" "brew install jq" ""
  _check_cmd "shellcheck" "brew install shellcheck" "0.10"
  _check_cmd "gitleaks" "brew install gitleaks" "8.30"
  _check_cmd "pre-commit" "pip install pre-commit" "4.6"
  _check_cmd "session-manager-plugin" "brew install --cask session-manager-plugin" ""
  # Optional (CI is authoritative):
  _check_cmd_optional "checkov" "pip install checkov" ""

  echo ""
  echo "${BOLD}Summary:${RESET} ${pass} passed, ${fail} failed, ${warn} optional missing"
  [[ "$fail" -eq 0 ]] || exit 1
}
```

**Version extraction patterns** (tool-specific):

| Tool | Version command | Parse pattern |
|------|----------------|---------------|
| `aws` | `aws --version` | `aws-cli/2.x.y ...` — extract major from field 1 |
| `packer` | `packer --version` | Prints `Packer v1.15.3` or just `1.15.3` |
| `tofu` | `tofu --version` | `OpenTofu v1.10.6` — extract after `v` |
| `ansible` | `ansible --version` | First line: `ansible [core 2.18.x]` |
| `ansible-lint` | `ansible-lint --version` | `ansible-lint 26.x.y ...` |
| `shellcheck` | `shellcheck --version` | `version: 0.10.0` on a dedicated line |
| `gitleaks` | `gitleaks version` | `v8.30.x` |
| `pre-commit` | `pre-commit --version` | `pre-commit 4.6.0` |
| `session-manager-plugin` | `session-manager-plugin --version` | Prints version number |
| `checkov` | `checkov --version` | Prints version number |

[ASSUMED] — version output formats based on training data; should be verified against actual tool output during implementation.

**Version comparison:** Semantic version comparison in pure bash is fragile. The simplest reliable approach: extract the major version (or major.minor) and compare integers. For tools where only the major version matters (aws 2.x, packer 1.x, tofu 1.x), compare `major -ge floor`. For tools with important minor versions (shellcheck 0.10), compare `major.minor` as two integers.

### Pattern 3: CI-Aware Init Flags

**What:** `./run tf-init` adds `-lockfile=readonly` when running in CI, mirroring the existing deploy job's behavior that enforces Phase 3 REP-01.

**Why:** The `-lockfile=readonly` flag prevents CI from silently rewriting the committed lockfile. This is a CI-only concern; locally, the operator may need to update the lockfile during provider upgrades.

**Implementation option:**

```bash
cmd_tf_init() {
  _require_devbox_user
  _derive_tf_state_bucket
  local lockfile_flag=""
  if [[ "${CI:-}" == "true" ]]; then
    lockfile_flag="-lockfile=readonly"
  fi
  # shellcheck disable=SC2046
  (cd "$REPO_ROOT/terraform" && "$TF_BIN" init $lockfile_flag $(_tf_backend_args))
}
```

### Anti-Patterns to Avoid

- **Duplicating logic between `./run` and `.gitlab-ci.yml`:** The whole point of CI-01/CI-02 is to eliminate inline commands. If the CI job still has `cd packer && packer init .` alongside `./run build`, the dual maintenance problem persists.
- **Hardcoding CI-specific behavior:** Don't add `if CI=true then` branches for every CI difference. Use env var passthrough (e.g., `PKR_VAR_*`, `LOCKFILE_MODE`) so the same `./run` works in both contexts.
- **Color in doctor output that doesn't degrade:** If doctor runs on macOS bash 3.2 (before the version guard), it won't have the color variables. See Pitfall 1 below.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Semantic version comparison | Full `X.Y.Z` comparator in bash | Major-only integer comparison | Full semver parsing in bash is error-prone; major version floor is sufficient for all tools in this project |
| ANSI color code management | Complex `tput`-based color library | Direct `$'\033[...'` escape sequences | `tput` requires terminfo database, which may be absent in minimal CI images; raw escapes are simpler and sufficient |
| CI environment detection | Custom heuristic (check for runner PID, etc.) | `[[ "${CI:-}" == "true" ]]` | GitLab, GitHub Actions, and most CI systems set `CI=true` automatically [CITED: docs.gitlab.com/ee/ci/variables/predefined_variables.html] |

## Common Pitfalls

### Pitfall 1: Bash 3.2 and `./run doctor`

**What goes wrong:** The `run` script has a bash 4+ guard on line 7 that exits immediately if `BASH_VERSINFO[0] < 4`. On macOS with the system bash (3.2), `./run doctor` would exit before reaching the doctor logic, so the operator never sees the diagnostic output telling them to upgrade bash.

**Why it happens:** macOS ships bash 3.2 due to licensing (GPLv3 avoidance). The bash 4+ guard was added in Phase 5 to protect against bashisms in the rest of the script.

**How to avoid:** Move the `doctor` command dispatch BEFORE the bash 4+ guard, or restructure the guard to allow `doctor` to pass through. The doctor function itself should be written in bash 3.2-compatible syntax (no associative arrays, no `${var,,}` lowercase, no `|&` pipe, no `readarray`). Alternatively, have doctor check bash version as its first item and report it as a finding rather than an exit.

**Warning signs:** `./run doctor` exits with "ERROR: Bash 4+ required" instead of showing dependency status.

### Pitfall 2: CI Bake Job `-var` Passthrough

**What goes wrong:** The current CI bake job passes `-var "devbox_user=" -var "aws_region=${AWS_REGION}"` to packer. If `./run build` replaces the inline commands but doesn't pass these vars, the bake uses the defaults from `variables.pkr.hcl` (region defaults to `us-east-1`, which may match the CI `AWS_REGION` variable, but the explicit passthrough is the correct pattern).

**Why it happens:** `./run build` was designed for local use where the operator's AWS environment sets the region contextually. CI needs explicit var injection because the env var `AWS_REGION` is a GitLab CI/CD variable, not a Packer-recognized env var (Packer uses `PKR_VAR_*` prefix).

**How to avoid:** In the CI job, set `PKR_VAR_aws_region: ${AWS_REGION}` as an environment variable. Packer automatically reads `PKR_VAR_*` env vars. The `devbox_user=""` is already the default, so no action needed for that. This keeps `./run build` unchanged.

**Warning signs:** CI bake builds in the wrong region, or packer validate fails because it can't resolve the SSM parameter in a different region.

### Pitfall 3: CI Deploy Job Uses Plan-File Workflow

**What goes wrong:** The current CI deploy job runs `tofu plan -out=tfplan && tofu apply -auto-approve tfplan` (a plan-file workflow for auditability). But `./run tf-apply` runs `tofu apply` with var args directly (no plan file). If CI calls `./run tf-apply`, the plan-file audit trail is lost and the tfplan artifact (kept on failure) disappears.

**Why it happens:** `./run tf-apply` was ported from the Makefile's interactive flow, which prompts the user. CI uses `-auto-approve` on a saved plan for defense-in-depth.

**How to avoid:** Two options:
1. **Modify `./run`:** Add a `cmd_tf_plan_apply()` function (or modify `cmd_tf_auto_apply`) that does `tofu plan -out=tfplan && tofu apply -auto-approve tfplan`. CI calls this variant.
2. **CI calls `./run tf-auto-apply`:** Simpler, but loses the plan-file artifact. The manual `when: manual` gate and protected-branch requirement already provide defense-in-depth.

**Recommendation:** Option 2 is simpler and the plan-file artifact is a nice-to-have, not a security requirement. The `when: manual` gate + protected-branch + DEVBOX_USER fail-fast + OIDC auth provide sufficient defense-in-depth. If the plan-file is important, option 1 adds complexity to `./run` for a CI-only concern.

**Warning signs:** CI deploy job succeeds but terraform/tfplan artifact is no longer produced.

### Pitfall 4: `-lockfile=readonly` Missing from `./run tf-init`

**What goes wrong:** The current CI deploy job uses `tofu init -lockfile=readonly` to enforce REP-01 (lockfile must not be rewritten in CI). If CI calls `./run tf-init` without this flag, CI could silently rewrite the lockfile — violating the Phase 3 invariant.

**Why it happens:** `./run tf-init` was ported from the Makefile which doesn't use `-lockfile=readonly` (that was a CI-only safety measure).

**How to avoid:** Have `./run tf-init` auto-add `-lockfile=readonly` when `CI=true`. This is safe because CI should never modify the lockfile, and local operators who want to update it don't set `CI=true`.

**Warning signs:** CI pipeline silently rewrites `terraform/.terraform.lock.hcl` during deploy.

### Pitfall 5: Grep-Gate Invariant Numbering

**What goes wrong:** The existing grep-gate job has 7 invariants and ends with `echo "All 7 invariants pass."` Adding invariant #8 (run executable bit) requires updating this count.

**Why it happens:** The count is a human-readable summary, not a programmatic check. Easy to forget.

**How to avoid:** Update the echo to `"All 8 invariants pass."` when adding the new invariant.

**Warning signs:** CI says "All 7 invariants pass" but there are actually 8 checks.

### Pitfall 6: Pre-Commit Grep-Gates Parity

**What goes wrong:** The pre-commit `grep-gates` hook mirrors the CI grep-gates job. Adding invariant #8 to CI without adding it to the pre-commit hook means local pre-commit won't catch the regression.

**Why it happens:** Dual maintenance between `.gitlab-ci.yml` and `.pre-commit-config.yaml`.

**How to avoid:** Add the same `git ls-files -s run | grep -q '^100755'` check to the pre-commit grep-gates hook.

**Warning signs:** Local commits pass pre-commit but CI grep-gates fail.

## Code Examples

### CI Bake Job (CI-01)

```yaml
# Source: adapted from current .gitlab-ci.yml bake:packer-build
bake:packer-build:
  stage: bake
  extends: .aws-auth
  image: hashicorp/packer:1.15.3@sha256:cb9c526a6351c55f05430423a8b37139a04b0fb5ce541887d476e19860b5ed92
  variables:
    PKR_VAR_aws_region: ${AWS_REGION}
    # devbox_user defaults to "" in variables.pkr.hcl — no override needed
  script:
    - ./run build
  rules:
    - if: $CI_PIPELINE_SOURCE == "web" && $PIPELINE_KIND == "bake" && $CI_COMMIT_REF_PROTECTED == "true"
    - if: $CI_PIPELINE_SOURCE == "schedule" && $PIPELINE_KIND == "bake"
```

### CI Deploy Job (CI-02)

```yaml
# Source: adapted from current .gitlab-ci.yml deploy:tofu-apply
deploy:tofu-apply:
  stage: deploy
  extends: .aws-auth
  image: ghcr.io/opentofu/opentofu:1.10.6@sha256:43f73c1e01f21de343ca4428a7e1845a357790235c73758bd7dc3cc4d1324b49
  environment:
    name: devbox/${DEVBOX_USER}
  before_script:
    # DEVBOX_USER fail-fast preserved from current job
    - |
      if [ -z "${DEVBOX_USER:-}" ]; then
        echo "FATAL: DEVBOX_USER is required for PIPELINE_KIND=deploy." >&2
        exit 1
      fi
      if ! printf '%s' "$DEVBOX_USER" | grep -qE '^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$'; then
        echo "FATAL: DEVBOX_USER='${DEVBOX_USER}' violates naming convention." >&2
        exit 1
      fi
    - !reference [.aws-auth, before_script]
  script:
    - ./run tf-init
    - ./run tf-auto-apply
  rules:
    - if: $CI_PIPELINE_SOURCE == "web" && $PIPELINE_KIND == "deploy" && $CI_COMMIT_REF_PROTECTED == "true"
      when: manual
      allow_failure: false
  artifacts:
    paths:
      - terraform/tfplan
    expire_in: 1 month
    when: on_failure
```

**Note:** The `before_script` DEVBOX_USER validation is retained as defense-in-depth. The `./run tf-init` will also validate DEVBOX_USER via `_require_devbox_user`, but the early CI-side check prevents wasting an STS AssumeRole on bad input. The `tfplan` artifact path is preserved for compatibility but will only be produced if `./run` is modified to use plan-file workflow; otherwise it can be removed.

### Shellcheck Job (CI-03)

```yaml
# Source: adapted from current .gitlab-ci.yml validate:shellcheck
validate:shellcheck:
  stage: validate
  image: koalaman/shellcheck-alpine:v0.10.0@sha256:7c6a5115899d99323b22fc84b29e924aef5b6fa985612e450a8c356969ebb577
  script:
    - shellcheck scripts/*.sh run
```

### Grep-Gate Invariant #8 (CI-04)

```bash
# 8. run file must have executable bit in git (RUN-07 / CI-04)
git ls-files -s run | grep -q '^100755' || {
  echo "FAIL: run file does not have executable bit in git (must be 100755)" >&2
  exit 1
}

echo "All 8 invariants pass."
```

### Color Output Pattern (POL-01)

```bash
# NO_COLOR: https://no-color.org/
# CI: GitLab sets CI=true automatically
if [[ -n "${NO_COLOR:-}" ]] || [[ "${CI:-}" == "true" ]]; then
  RED="" GREEN="" YELLOW="" BOLD="" RESET=""
else
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
fi

_info()  { echo "${GREEN}[INFO]${RESET} $*"; }
_warn()  { echo "${YELLOW}[WARN]${RESET} $*" >&2; }
_error() { echo "${RED}ERROR:${RESET} $*" >&2; }
```

### Doctor Command Pattern (POL-02)

```bash
# Check a required tool
_check_cmd() {
  local cmd="$1" install_hint="$2" min_major="${3:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "  ${RED}FAIL${RESET}  $cmd — not found (install: $install_hint)"
    (( fail++ ))
    return
  fi
  if [[ -n "$min_major" ]]; then
    local ver
    ver="$(_get_version "$cmd")"
    local major="${ver%%.*}"
    if [[ "$major" -lt "$min_major" ]]; then
      echo "  ${YELLOW}WARN${RESET}  $cmd — version $ver (need >= $min_major)"
      (( warn++ ))
      return
    fi
  fi
  echo "  ${GREEN}OK${RESET}    $cmd"
  (( pass++ ))
}
```

## CI Integration Analysis

### CI Bake Integration (CI-01)

**Current state:** The bake job runs `cd packer && packer init . && packer build -var "devbox_user=" -var "aws_region=${AWS_REGION}" .`

**Target state:** The bake job runs `./run build`.

**Gap analysis:**
1. `packer init .` — handled by `cmd_build` which calls `cmd_packer_init` first.
2. `-var "devbox_user="` — `devbox_user` defaults to `""` in `variables.pkr.hcl`; no override needed.
3. `-var "aws_region=${AWS_REGION}"` — CI must set `PKR_VAR_aws_region: ${AWS_REGION}` as a job variable so Packer picks it up from the environment.
4. `cd packer` — `./run` handles this internally via `(cd "$REPO_ROOT/packer" && ...)`.

**Resolution:** Set `PKR_VAR_aws_region: ${AWS_REGION}` in the bake job's `variables:` block. No changes to `./run build` needed.

### CI Deploy Integration (CI-02)

**Current state:** The deploy job runs:
```
tofu init -lockfile=readonly -backend-config=...
tofu plan -var "devbox_user=..." -var "key_name=..." -out=tfplan
tofu apply -auto-approve tfplan
```

**Target state:** The deploy job runs `./run tf-init && ./run tf-auto-apply`.

**Gap analysis:**
1. `-lockfile=readonly` — NOT in `./run tf-init`. Must add CI-aware flag.
2. `-backend-config=...` — `./run tf-init` derives these from env vars. CI must set `TF_STATE_BUCKET`, `DEVBOX_USER`, `TF_STATE_REGION`, `TF_STATE_LOCK_TABLE` (all already set as CI variables or in the pipeline `variables:` block).
3. Plan-file workflow (`-out=tfplan` + `apply tfplan`) — NOT in `./run tf-auto-apply`. The `./run tf-auto-apply` runs `tofu apply -auto-approve` with var args directly.
4. `-var` args — `./run` constructs these from `DEVBOX_USER` env var via `_tf_var_args`.

**Resolution options:**
- **Minimal:** Add `-lockfile=readonly` when `CI=true` to `cmd_tf_init`. Use `./run tf-auto-apply` (no plan-file). Remove tfplan artifact since it won't be produced.
- **Full:** Add a `cmd_tf_plan_apply` or modify `cmd_tf_auto_apply` to support plan-file mode when `CI=true`. Keeps the audit trail.

**Recommendation:** Minimal approach. The `when: manual` gate + protected branch + OIDC + DEVBOX_USER validation provide sufficient defense-in-depth. The plan-file was a nice-to-have for post-mortem, not a security control.

### Shellcheck Integration (CI-03)

**Current state:** `shellcheck scripts/*.sh`
**Target state:** `shellcheck scripts/*.sh run`

**Change:** Append `run` to the shellcheck command. The `run` file is already shellcheck-clean (verified by Phase 5).

**Pre-commit parity:** The pre-commit shellcheck hook uses `types: [shell]` which already detects the `run` file (verified: `pre-commit run shellcheck --files run` passes). No change needed to pre-commit.

### Grep-Gate Integration (CI-04)

**Current state:** 7 invariants in the grep-gate job.
**Target state:** 8 invariants (add executable bit check for `run`).

**New invariant:**
```bash
# 8. run file must have executable bit in git (RUN-07 / CI-04)
git ls-files -s run | grep -q '^100755' || {
  echo "FAIL: run file does not have executable bit in git" >&2; exit 1
}
```

**Pre-commit parity:** Must also add this check to the pre-commit grep-gates hook.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline shell in CI jobs | Delegate to `./run` script | Phase 6 (this phase) | Single source of truth for commands |
| No color output | NO_COLOR-aware color helpers | Phase 6 (this phase) | Better local UX, clean CI logs |
| Manual tool verification | `./run doctor` automated check | Phase 6 (this phase) | Faster onboarding, fewer "tool not found" surprises |

**Deprecated/outdated:**
- The Makefile's `make` targets are being replaced by `./run` commands across Phases 5-7. The Makefile itself is deleted in Phase 7, not this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Packer CI image (`hashicorp/packer:1.15.3`) ships bash 5.x | CI Bake Integration | If no bash, `./run build` fails; would need `apk add bash` in before_script |
| A2 | OpenTofu CI image (`ghcr.io/opentofu/opentofu:1.10.6`) ships bash 5.x | CI Deploy Integration | Same as A1; grep-gates job already uses this image with bash, so HIGH confidence |
| A3 | shellcheck-alpine image can run `shellcheck run` (file without .sh extension) | Shellcheck Integration | shellcheck detects shell scripts by shebang, not extension; HIGH confidence |
| A4 | Version output formats for tools in doctor command match expected patterns | Doctor Command | If format changed, version extraction may fail; fallback: report "version unknown" |
| A5 | GitLab CI sets `CI=true` automatically in all jobs | Color Output | Verified via official docs; HIGH confidence |
| A6 | `PKR_VAR_aws_region` env var is recognized by Packer for var injection | CI Bake Integration | Standard Packer behavior per Packer docs; HIGH confidence |

## Open Questions

1. **Plan-file workflow in CI deploy**
   - What we know: Current CI uses `tofu plan -out=tfplan && tofu apply tfplan` for auditability. `./run tf-auto-apply` does not use this pattern.
   - What's unclear: Is the plan-file artifact important enough to justify adding complexity to `./run`?
   - Recommendation: Use `./run tf-auto-apply` (no plan-file). Remove tfplan artifact config. If needed later, add a `./run tf-plan-apply` command.

2. **Doctor command and bash 3.2 on macOS**
   - What we know: The `run` script exits on bash < 4 (line 7). macOS default bash is 3.2. `./run doctor` should ideally work on bash 3.2 to diagnose the bash version itself.
   - What's unclear: Whether to restructure the guard or accept that macOS users must use `brew install bash` first.
   - Recommendation: Move the `doctor` dispatch before the bash 4+ guard. Write the doctor function in bash 3.2-compatible syntax. This lets `./run doctor` diagnose "bash too old" as a finding instead of dying silently.

3. **CI deploy `before_script` DEVBOX_USER validation redundancy**
   - What we know: The deploy job has its own DEVBOX_USER validation in `before_script`. `./run tf-init` also validates via `_require_devbox_user`.
   - What's unclear: Whether to keep the CI-side validation as defense-in-depth or remove it since `./run` handles it.
   - Recommendation: Keep both. The CI-side check runs before the STS AssumeRole (saving an API call on bad input). The `./run` check is the canonical validation.

## Environment Availability

> Step 2.6: SKIPPED (no external dependencies beyond what's already in the project toolchain)

All tools are the same as previous phases. No new external dependencies are introduced.

## Sources

### Primary (HIGH confidence)
- `.gitlab-ci.yml` in repository — current CI pipeline configuration, all job definitions, image digests, rules
- `run` file in repository — current `./run` script with all 20 commands
- `Makefile` in repository — current operator surface being replaced
- `packer/variables.pkr.hcl` — Packer variable defaults including `devbox_user` and `aws_region`
- `.pre-commit-config.yaml` — current pre-commit hooks including shellcheck and grep-gates
- `REQUIREMENTS.md` — requirement definitions CI-01 through CI-04, POL-01, POL-02

### Secondary (MEDIUM confidence)
- [no-color.org](https://no-color.org/) — NO_COLOR convention specification
- [GitLab predefined CI/CD variables](https://docs.gitlab.com/ee/ci/variables/predefined_variables.html) — CI=true, GITLAB_CI=true auto-set

### Tertiary (LOW confidence)
- Version output format for each tool in doctor command — based on training data, not verified in this session

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - no new packages, all changes to existing files
- Architecture: HIGH - CI pipeline structure well-understood from existing `.gitlab-ci.yml`
- Pitfalls: HIGH - identified from direct analysis of current `./run` vs CI job mismatches
- Color/doctor patterns: MEDIUM - based on established conventions (NO_COLOR) and common patterns

**Research date:** 2026-05-27
**Valid until:** 2026-06-27 (stable domain; no fast-moving library dependencies)
