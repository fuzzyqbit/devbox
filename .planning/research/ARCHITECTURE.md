# Architecture Patterns: ./run Script + GitLab CI Integration

**Domain:** IaC operator script replacing a Makefile
**Researched:** 2026-05-27
**Confidence:** HIGH — based on direct codebase analysis, not web search

---

## Recommended Architecture

### Script structure: single monolith with sourced helpers

Use a single `./run` entry-point script that dispatches via a `case` statement to
command functions defined inline. The existing `scripts/_common.sh` is promoted to
`scripts/lib.sh` (or kept as `_common.sh`) and sourced by `./run` at startup.

Do NOT split `./run` into multiple sourced modules (e.g., `run-tf.sh`, `run-packer.sh`).
The full command set (about 20 targets) fits comfortably in one file at roughly
300-400 lines with the current command volume. Splitting introduces sourcing order
complexity, makes `shellcheck` harder to enforce across the boundary, and creates
friction for CI job authors who now need to know which module owns which command.

**Structure layout:**

```
./run               # single dispatcher — 300-400 lines
scripts/
  _common.sh        # shared helpers (already exists); sourced by ./run
  devbox-start.sh   # keep as-is; called by ./run cmd_start
  devbox-stop.sh    # keep as-is; called by ./run cmd_stop
  devbox-status.sh  # keep as-is; called by ./run cmd_status
  devbox-ssm.sh     # keep as-is; called by ./run cmd_devbox_ssm
```

The `scripts/*.sh` files stay as they are — they are already written as small,
focused helpers. `./run` simply becomes the new Makefile-equivalent dispatcher that
sets up environment variables and delegates to them, the same way Makefile recipes
currently do.

### Internal layout of ./run

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. SCRIPT_DIR + PROJECT_DIR (same idiom as scripts/_common.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Defaults (mirrors Makefile variable block)
DEVBOX_USER="${DEVBOX_USER:-}"
TF_BIN="${TF_BIN:-tofu}"
TF_STATE_REGION="${TF_STATE_REGION:-us-east-1}"
TF_STATE_LOCK_TABLE="${TF_STATE_LOCK_TABLE:-devimage-tfstate-locks}"
INSTANCE_ID="${INSTANCE_ID:-}"
REGION="${REGION:-}"

# 3. Derived variables (computed lazily or at startup)
# TF_STATE_BUCKET and TF_STATE_KEY are computed at the point of use,
# not at startup — avoids an aws sts call on every ./run invocation
# (e.g., `./run help` should never hit AWS).

# 4. Command functions — one function per command
cmd_help()        { ... }
cmd_build()       { ... }
cmd_tf_init()     { ... }
cmd_tf_ensure_init() { ... }   # prerequisite helper
cmd_tf_plan()     { ... }
cmd_tf_apply()    { ... }
# ... etc.

# 5. Main dispatcher
COMMAND="${1:-help}"
shift || true   # consume the command name; remaining args are forwarded

case "$COMMAND" in
  help)              cmd_help ;;
  build)             cmd_build "$@" ;;
  tf-init)           cmd_tf_init "$@" ;;
  tf-plan)           cmd_tf_plan "$@" ;;
  tf-apply)          cmd_tf_apply "$@" ;;
  tf-auto-apply)     cmd_tf_auto_apply "$@" ;;
  tf-destroy)        cmd_tf_destroy "$@" ;;
  tf-auto-destroy)   cmd_tf_auto_destroy "$@" ;;
  start)             cmd_start "$@" ;;
  stop)              cmd_stop "$@" ;;
  status)            cmd_status "$@" ;;
  devbox-ssm)        cmd_devbox_ssm "$@" ;;
  devbox-port-forward) cmd_devbox_port_forward "$@" ;;
  secrets-show)      cmd_secrets_show "$@" ;;
  validate)          cmd_validate "$@" ;;
  fmt)               cmd_fmt "$@" ;;
  packer-init)       cmd_packer_init "$@" ;;
  clean)             cmd_clean "$@" ;;
  *)
    echo "ERROR: Unknown command '${COMMAND}'. Run './run help' for usage." >&2
    exit 1
    ;;
esac
```

---

## Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `./run` | Dispatcher; variable setup; guard assertions; calls scripts or tool binaries directly | `scripts/_common.sh`, `scripts/devbox-*.sh`, `packer`, `tofu`, `aws` |
| `scripts/_common.sh` | `parse_args`, `resolve_user`, `resolve_instance`, `init_devbox`; sourced by `./run` and `scripts/*.sh` | `tofu` (reads outputs) |
| `scripts/devbox-*.sh` | Single-purpose EC2 lifecycle actions; keep existing interface unchanged | `aws` CLI, `scripts/_common.sh` |
| `.gitlab-ci.yml` | CI pipeline; calls `./run <command>` in script blocks | `./run` only |

---

## How CI Jobs Call the Script

CI jobs call `./run` the same way an operator would:

```yaml
# validate stage — no DEVBOX_USER needed
validate:tofu-fmt:
  script:
    - ./run fmt --check   # or keep inline tofu/packer calls for validate; see below

# bake stage
bake:packer-build:
  script:
    - ./run build

# deploy stage
deploy:tofu-apply:
  script:
    - ./run tf-apply
```

**Key design constraint:** The validate jobs currently use specific tool images
(one for `tofu`, one for `packer`, one for `ansible-lint`) and invoke tools directly
because mixing binaries in one image is expensive. These jobs do NOT need to call
`./run` — they can continue calling `tofu fmt -check`, `packer fmt -check`, etc.
directly. The value of `./run` is for commands that share complex variable setup
(DEVBOX_USER, TF_STATE_BUCKET derivation, tf-ensure-init) — that is the bake and
deploy stages.

Validate jobs are better left as direct tool invocations rather than being forced
through `./run`, because:
1. The validate image has a single binary; `./run` would add a sourcing overhead
   with no benefit.
2. `./run` would need to handle "am I in a tofu image or a packer image?" — that
   is complexity that belongs in CI, not in the operator script.

**Recommendation for CI:**
- Validate jobs: keep direct tool invocations as today.
- Bake job: replace inline `packer init . && packer build ...` with `./run build`.
- Deploy job: replace inline `tofu init ... && tofu plan ... && tofu apply ...` with
  `./run tf-init && ./run tf-apply` (or a single `./run deploy` compound command).

---

## Prerequisite Chain Migration: tf-ensure-init

The `tf-ensure-init` Make prerequisite is the most complex piece to carry over. Its
logic is:

1. Read the cached backend key from `terraform/.terraform/terraform.tfstate`.
2. Compare it to the desired key (`users/$DEVBOX_USER/devbox.tfstate`).
3. If they differ (or the cache is absent), call `tf-reinit`.

In `./run`, this becomes a plain shell function called explicitly by commands that
need it, rather than via Make's prerequisite mechanism:

```bash
_tf_state_key() {
  echo "users/${DEVBOX_USER}/devbox.tfstate"
}

_tf_state_bucket() {
  # Lazy — only called when a tf command needs it.
  # Fail-fast if aws sts returns nothing (same guard as Makefile lines 121-124).
  local bucket
  bucket="devimage-tfstate-$(aws sts get-caller-identity \
    --query Account --output text 2>/dev/null)"
  if [[ -z "$bucket" || "$bucket" == "devimage-tfstate-" ]]; then
    echo "ERROR: could not resolve AWS account ID via 'aws sts get-caller-identity'." >&2
    echo "       Check your AWS credentials/profile, or set TF_STATE_BUCKET= explicitly." >&2
    exit 1
  fi
  echo "$bucket"
}

cmd_tf_ensure_init() {
  _require_devbox_user
  local desired_key
  desired_key="$(_tf_state_key)"
  local cached_key
  cached_key="$(jq -r '.backend.config.key // empty' \
    "${SCRIPT_DIR}/terraform/.terraform/terraform.tfstate" 2>/dev/null || true)"

  if [[ "$cached_key" != "$desired_key" ]]; then
    echo "[tf-ensure-init] backend cache mismatch (cached='$cached_key', want='$desired_key'); reinitializing..."
    cmd_tf_reinit
  fi
}

cmd_tf_apply() {
  cmd_tf_ensure_init   # explicit call, not Make prerequisite
  local bucket
  bucket="$(_tf_state_bucket)"
  cd "${SCRIPT_DIR}/terraform"
  "$TF_BIN" apply \
    -var "devbox_user=${DEVBOX_USER}" \
    -var "key_name=${DEVBOX_USER}-devbox"
}
```

The key insight: Make prerequisites are pulled automatically; in a shell script,
callers must call `cmd_tf_ensure_init` explicitly at the start of each command
that needs an initialized backend. This is more verbose but equally correct, and
it makes the dependency visible in the source rather than implicit in the target
graph.

**Commands that must call `cmd_tf_ensure_init` first:**
`tf-plan`, `tf-apply`, `tf-auto-apply`, `tf-destroy`, `tf-auto-destroy`,
`start`, `stop`, `status`, `devbox-ssm`

**Commands that must call `_require_devbox_user` but NOT `tf-ensure-init`:**
`tf-init`, `tf-reinit`, `secrets-show`, `devbox-port-forward`

**Commands that need neither guard:**
`help`, `build`, `validate`, `fmt`, `packer-init`, `clean`

---

## Guard Function Pattern

```bash
_require_devbox_user() {
  if [[ -z "${DEVBOX_USER:-}" ]]; then
    echo "ERROR: DEVBOX_USER is not set." >&2
    echo "       Set per-invocation: DEVBOX_USER=jsmith ./run <command>" >&2
    echo "       Or export it:       export DEVBOX_USER=jsmith" >&2
    exit 1
  fi
}
```

The DEVBOX_USER validation in the deploy CI job should remain in `.gitlab-ci.yml`'s
`before_script` (as it is today) and also be enforced inside `./run _require_devbox_user`.
Defence in depth: CI catches it before wasting an STS call; `./run` catches it for
local operators who forget.

---

## Variable Resolution Order

Mirrors Makefile lines 14-52. In `./run`:

| Variable | Source priority |
|----------|----------------|
| `DEVBOX_USER` | Env var (no default — explicit is required) |
| `TF_BIN` | Env var, default `tofu` |
| `TF_STATE_REGION` | Env var, default `us-east-1` |
| `TF_STATE_LOCK_TABLE` | Env var, default `devimage-tfstate-locks` |
| `TF_STATE_BUCKET` | Env var override OR derived from `aws sts get-caller-identity` |
| `TF_STATE_KEY` | Always derived: `users/${DEVBOX_USER}/devbox.tfstate` |
| `INSTANCE_ID` | Env var override OR read from `tofu output -raw instance_id` |
| `REGION` | Env var override OR read from `tofu output -raw aws_region` |

---

## Data Flow

```
Operator/CI invokes:
  ./run <command> [flags]
        │
        ├── sets DEVBOX_USER, TF_BIN, etc. from env
        ├── calls _require_devbox_user (if command needs it)
        ├── calls cmd_tf_ensure_init (if command needs initialized backend)
        │         └── reads terraform/.terraform/terraform.tfstate via jq
        │             if mismatch → calls cmd_tf_reinit
        │                 → cd terraform && tofu init -reconfigure <backend flags>
        │
        ├── [tf commands]
        │   cd terraform && tofu plan/apply/destroy <var flags>
        │
        ├── [lifecycle commands]
        │   export DEVBOX_USER INSTANCE_ID REGION
        │   exec scripts/devbox-{start,stop,status,ssm}.sh
        │
        └── [packer commands]
            cd packer && packer build/validate/fmt .
```

---

## Suggested Build Order for Implementation

1. **Write `./run` skeleton** — dispatcher, help text, variable block, guard functions.
   No command implementations yet; all commands `echo "TODO" && exit 1`.

2. **Implement packer commands** — `packer-init`, `validate`, `build`, `fmt`.
   These have no `DEVBOX_USER` or backend dependencies; safe to test without AWS creds.

3. **Implement tf-init and tf-reinit** — the backend derivation + `TF_STATE_BUCKET`
   lazy resolution. These are the foundation for everything else.

4. **Implement `cmd_tf_ensure_init`** — the prerequisite chain. Write a unit test
   by manually editing `terraform/.terraform/terraform.tfstate` to have a wrong key
   and confirming reinit fires.

5. **Implement tf-plan, tf-apply, tf-auto-apply, tf-destroy, tf-auto-destroy** —
   all share the same pattern: call `cmd_tf_ensure_init`, then delegate to `tofu`.

6. **Implement lifecycle commands** — `start`, `stop`, `status`, `devbox-ssm`,
   `devbox-port-forward`. These call `cmd_tf_ensure_init` and then exec/call the
   existing `scripts/*.sh`.

7. **Implement secrets-show** — standalone AWS SSM reads; no backend needed.

8. **Implement clean** — `rm -rf` of packer cache + terraform local state.

9. **Update `.gitlab-ci.yml`** — replace inline packer/tofu in bake and deploy jobs
   with `./run build` and `./run tf-init && ./run tf-apply`. Leave validate jobs
   as direct tool calls (see "How CI Jobs Call the Script" above).

10. **Update docs** — CLAUDE.md, error messages in `_common.sh` that reference
    `make <target>` → `./run <target>`.

11. **Delete Makefile** — only after all tests pass and CI is green.

---

## Anti-Patterns to Avoid

### Monkeying with PATH inside ./run

Do not `export PATH="$SCRIPT_DIR:$PATH"` or anything that causes `./run` to shadow
system binaries. The script operates on explicit paths or relies on the caller's PATH
for `tofu`, `packer`, `aws`, `jq`. Consistent with the existing Makefile.

### Eager TF_STATE_BUCKET resolution

Do not call `aws sts get-caller-identity` at the top of `./run` unconditionally.
Commands like `./run help`, `./run fmt`, `./run validate` must work with no AWS
credentials. Derive `TF_STATE_BUCKET` lazily inside `_tf_state_bucket()` and call
it only from commands that actually need the backend.

### Reimplementing Make's prerequisite graph

Do not build a dependency resolver in bash. Make's prerequisite graph maps directly
to explicit function calls in the script. `cmd_tf_apply` calls `cmd_tf_ensure_init`
which calls `cmd_tf_reinit` if needed. That is the full depth needed; do not generalize.

### Embedding CI-specific logic in ./run

`./run` is the operator script. CI uses it; CI does not own it. OIDC token exchange,
`--role-session-name` construction, DEVBOX_USER format validation — these belong in
`.gitlab-ci.yml`'s `before_script`, not in `./run`. The script should work identically
for a local operator and a CI runner.

### Making validate jobs call ./run

The nine validate CI jobs each run in a purpose-specific image with a single binary.
Adding `./run` as an indirection layer here would require either a multi-binary image
or complex detection logic. Leave validate as direct tool invocations; `./run` adds
value where variable setup is complex (bake, deploy, lifecycle).

---

## Scalability Considerations

| Concern | Current (1 operator) | If multi-operator |
|---------|---------------------|-------------------|
| State isolation | `DEVBOX_USER` threads through TF_STATE_KEY | No change — same mechanism |
| Concurrent CI runs | CI serializes deploy via `when: manual` | Add DynamoDB lock contention handling (already present in tofu) |
| New commands | Add a function + case branch to `./run` | Same pattern; file stays readable at 50+ commands |

---

## Sources

- Direct analysis of `Makefile`, `.gitlab-ci.yml`, `scripts/_common.sh`,
  `scripts/devbox-start.sh`, `scripts/devbox-stop.sh`, `scripts/devbox-status.sh`,
  `scripts/devbox-ssm.sh`, `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md`,
  `.planning/codebase/CONVENTIONS.md` — HIGH confidence (primary sources).
- No web search performed; domain is well-understood bash scripting patterns.
