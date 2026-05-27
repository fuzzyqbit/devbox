# Domain Pitfalls: Make → Shell Script Migration

**Domain:** IaC operator tooling — replacing a Makefile with a `./run` shell script dispatcher, with GitLab CI calling `./run` instead of inline commands.
**Researched:** 2026-05-27
**Confidence:** HIGH — pitfalls verified against official docs, real GitHub issues, and this project's existing code.

---

## Critical Pitfalls

Mistakes that cause silent breakage, data loss, or security regression.

---

### Pitfall C-1: `TF_STATE_BUCKET` Derivation Silently Produces an Empty or Wrong Value

**What goes wrong:** In the Makefile, `TF_STATE_BUCKET` is computed via `$(shell aws sts get-caller-identity ...)` at parse time. In a shell script, the equivalent is a command substitution at assignment time. If credentials are absent, expired, or the command returns an error, the substitution silently produces an empty string (or `"devimage-tfstate-"`) and every subsequent `tofu init -backend-config="bucket=..."` points at a non-existent bucket. The Makefile has an explicit guard (`[ "$(TF_STATE_BUCKET)" != "devimage-tfstate-" ] || { … exit 1 }`) — the guard must be reproduced in `./run` or the failure mode degrades from "loud error" to "silently wrong state key".

**Why it happens:** Shell command substitutions swallow stderr when assigned: `bucket=$(aws sts get-caller-identity … 2>/dev/null)`. The trailing `2>/dev/null` hides the credential error; the variable is empty; `tofu init` then initialises against a bucket name of `""` or a string with a trailing `-`, and may succeed if the bucket happens to exist or fail with a confusing S3 error rather than a credentials error.

**Consequences:** `tofu apply` targets the wrong (possibly another operator's) state key. In the worst case it reads state from a shared bucket with a degenerate key path, destroying someone else's instance.

**Prevention:**
```bash
# In ./run, replicate the guard from the Makefile:
TF_STATE_BUCKET="${TF_STATE_BUCKET:-devimage-tfstate-$(aws sts get-caller-identity --query Account --output text 2>&1)}"
if [[ -z "$TF_STATE_BUCKET" || "$TF_STATE_BUCKET" == "devimage-tfstate-" || "$TF_STATE_BUCKET" == *"error"* ]]; then
  echo "ERROR: could not resolve AWS account ID. Check credentials or set TF_STATE_BUCKET explicitly." >&2
  exit 1
fi
```
Never suppress stderr from the STS call without also checking the exit code and content.

**Detection:** `./run tf-init` prints the resolved bucket name before running `tofu init`. CI logs show `bucket=devimage-tfstate-` in the `-backend-config` flags.

**Phase:** Must be addressed in the initial `./run` implementation phase, before any other command works.

---

### Pitfall C-2: `DEVBOX_USER` Guard Omitted from Some Commands

**What goes wrong:** The Makefile uses a `_require-devbox-user` prerequisite that every state-sensitive target lists. In a shell `case` dispatcher, it is easy to add the guard to the first few commands written and forget it on later-added ones. A single missing guard means `users//devbox.tfstate` becomes the state key — a shared, degenerate path that two operators can collide on.

**Why it happens:** Make's prerequisite graph enforces the guard mechanically. In a shell case statement, every branch is independent; there is no inheritance mechanism.

**Consequences:** Two operators running `./run tf-apply` without `DEVBOX_USER` both target `users//devbox.tfstate`. Last writer wins. One operator's EC2 instance gets destroyed.

**Prevention:** Extract the guard into a function called at the top of every branch that touches Terraform state, lifecycle scripts, or SSM parameters:
```bash
require_devbox_user() {
  if [[ -z "${DEVBOX_USER:-}" ]]; then
    echo "ERROR: DEVBOX_USER is not set. Pass it: DEVBOX_USER=jsmith ./run <cmd>" >&2
    exit 1
  fi
}
```
Call `require_devbox_user` before the first use of `$DEVBOX_USER` in every relevant `case` branch. Apply the same pattern in the GitLab CI `deploy:tofu-apply` job (already present — do not remove it).

**Detection:** `./run tf-plan` without `DEVBOX_USER` set produces an S3 error about a key path containing `//` instead of a clear "DEVBOX_USER is not set" message.

**Phase:** Must be addressed in the initial `./run` implementation phase.

---

### Pitfall C-3: `after_script` in GitLab CI Cannot See Exports from `before_script` / `script`

**What goes wrong:** GitLab CI runs `after_script` in a completely separate shell process from `before_script` and `script`. Variables exported with `export AWS_ACCESS_KEY_ID=...` in `.aws-auth`'s `before_script` are not visible in `after_script`. If cleanup logic (e.g. revoking a session, writing a status file) is added to `after_script` and it needs the AWS credentials, it will run unauthenticated.

**Why it happens:** This is a documented GitLab Runner architectural limitation. The runner concatenates `before_script` + `script` into one shell process; `after_script` is a separate invocation. See: https://gitlab.com/gitlab-org/gitlab-runner/-/issues/4146.

**Consequences:** Any `after_script` cleanup that depends on AWS credentials silently fails with `AuthFailure` or similar. If cleanup is critical (e.g. releasing a DynamoDB lock on failure), the lock is not released and the next `tofu apply` hangs.

**Prevention:** Keep all AWS-credential-dependent logic inside `script:`. If `after_script` needs credentials, write them to a dotfile in `before_script` (encrypted or ephemeral) and read them back — but this is a code smell. Prefer design where `after_script` does only credential-free cleanup (log parsing, artifact tagging).

**Detection:** Add a smoke test: `after_script: [ "aws sts get-caller-identity || true" ]`. If it prints `Unable to locate credentials`, the isolation is confirmed.

**Phase:** CI integration phase (when `./run` is wired into `.gitlab-ci.yml`).

---

### Pitfall C-4: Executable Bit Not Set on `./run` in Git

**What goes wrong:** The `./run` file is committed without `chmod +x` or `git update-index --chmod=+x`. Locally the developer `chmod +x`s it and forgets to commit the permission. CI runners clone the repo and get a file with mode `644` — `./run bake` returns `Permission denied`. The pipeline fails on the first run with a confusing error.

**Why it happens:** Git tracks the executable bit, but it is invisible in `git diff` output by default. It is trivially forgotten.

**Consequences:** Every CI job that calls `./run` fails immediately. The developer who wrote `./run` is surprised because it works on their machine.

**Prevention:**
```bash
git update-index --chmod=+x run
git show HEAD:run | head -1  # verify #!/usr/bin/env bash is line 1
```
Add a `shellcheck` check on `run` in the `validate:shellcheck` CI job alongside `scripts/*.sh` (the current job only lints `scripts/*.sh`).

**Detection:** `git ls-files -s run` shows `100644` (not executable) vs `100755` (executable). Check before merging.

**Phase:** Must be done at file creation — it cannot be retrofitted without a commit.

---

## Moderate Pitfalls

Mistakes that cause incorrect behaviour or operator confusion but do not destroy state.

---

### Pitfall M-1: macOS Ships bash 3.2 — Bash 4+ Features Break Locally

**What goes wrong:** `/usr/bin/bash` on macOS is 3.2 (GPLv2 — Apple has not shipped a newer version since Bash 4 adopted GPLv3). CI Alpine runners ship bash 5.x via `apk`. Features introduced in bash 4.0 that `./run` might use include: associative arrays (`declare -A`), `mapfile`/`readarray`, `&>>` append-redirect, `${var,,}` / `${var^^}` case modifiers, `**` globbing. Using any of these means `./run` silently fails or errors on the developer's Mac while passing CI.

**Why it happens:** Developers write bash scripts on Linux or in Homebrew bash (5.x) without testing against the system bash. The shebang `#!/usr/bin/env bash` picks up whichever `bash` is first in `PATH` — on macOS with Homebrew this is 5.x; in CI it is 5.x; on a stock macOS it is 3.2.

**Consequences:** `./run help` may work (simple case statements), but `./run validate` silently skips branches or exits with `declare: -A: invalid option` on a developer's machine. Discoverability of bugs is delayed.

**Prevention:** Keep `./run` to bash 3.2-compatible syntax. The existing `scripts/*.sh` already use `[[ ]]`, `set -euo pipefail`, and `BASH_SOURCE` which are 3.2-compatible. Avoid: `declare -A`, `mapfile`, `${var,,}`, `**`, `local -n`. Add `shellcheck --shell=bash` to CI (already present for `scripts/*.sh` — extend it to cover `run`). Optionally guard at the top of `./run`:
```bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]] && [[ "$(uname)" == "Darwin" ]]; then
  echo "WARNING: macOS system bash 3.2 detected. Some features may not work." >&2
  echo "         Run: brew install bash && hash -r" >&2
fi
```
Since the project already requires Homebrew for other tools (`packer`, `opentofu`), it is reasonable to document Homebrew bash as a soft prerequisite.

**Detection:** Run `bash --version` locally. `GNU bash, version 3.2.*` means stock macOS bash.

**Phase:** Initial `./run` implementation phase.

---

### Pitfall M-2: Missing `help` Command — No `.DEFAULT_GOAL` Equivalent

**What goes wrong:** The Makefile's `.DEFAULT_GOAL := help` means bare `make` prints usage. There is no shell equivalent — `./run` with no arguments does nothing (or errors with "no command specified"). Operators who relied on `make` (or `make help`) for discoverability lose that affordance.

**Why it happens:** Shell dispatchers default to running `"$@"` with no arguments, which either errors on the `case` statement's `*` branch or does nothing.

**Consequences:** Operators run `./run` and see `usage: ./run <command>` or a cryptic error rather than the formatted target list. `CLAUDE.md` becomes the only discovery surface — it diverges from actual commands over time.

**Prevention:** Make `./run` with no arguments (or with `help` as the first argument) print the full command reference, matching the current `make help` output exactly. The `help` branch should be the first case and should be the default when `$1` is unset:
```bash
cmd="${1:-help}"
case "$cmd" in
  help) print_help; exit 0 ;;
  …
  *) echo "ERROR: Unknown command: $cmd" >&2; print_help >&2; exit 1 ;;
esac
```
The `*` catch-all must exit non-zero so CI catches typos in job scripts.

**Detection:** `./run` with no arguments silently exits 0 instead of printing help.

**Phase:** Initial `./run` implementation phase.

---

### Pitfall M-3: Working Directory Assumed, Not Anchored — `cd terraform` Leaves the Script in `terraform/`

**What goes wrong:** The Makefile uses `cd packer && packer build .` and `cd terraform && tofu init ...` in each recipe. Each recipe runs in a fresh subshell, so the `cd` does not persist. In a shell script, a `cd terraform` inside a function or case branch changes the working directory for the entire remaining session unless the script explicitly returns with `cd -` or uses a subshell `(cd terraform && …)`. If two commands run sequentially — one `cd`s into `terraform/`, the next assumes the project root — the second command fails with "file not found" or silently operates on the wrong directory.

**Why it happens:** Developers port Makefile recipes line-by-line without accounting for the subshell-per-recipe property of Make.

**Consequences:** `./run validate` runs `packer validate .` from inside `terraform/` (the wrong directory) after `cd terraform`. Packer cannot find `packer/devimage.pkr.hcl`. Or, `tofu fmt` is run from the project root instead of `terraform/` and formats the wrong tree.

**Prevention:** One of two patterns — pick one and apply it consistently:

Option A — subshell: `(cd terraform && tofu init …)` — the subshell exits and the parent script remains at the project root.

Option B — `tofu -chdir=terraform init …` — OpenTofu / Terraform's `-chdir` global flag (must precede the subcommand). Note: `-chdir` affects `path.root` but leaves `path.cwd` at the caller's directory, which is different from `cd`. For this project's usage (no `path.cwd` references in HCL), either option is safe; subshell is less surprising.

Anchor the project root at script startup:
```bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
Then every `cd` uses `cd "$REPO_ROOT/terraform"` inside a subshell, not a relative `cd terraform`.

**Detection:** `./run validate` after `./run tf-plan` produces `packer: no such file or directory` or similar working-directory errors.

**Phase:** Initial `./run` implementation phase.

---

### Pitfall M-4: `set -euo pipefail` Not Propagated Into Sourced Files or Command Substitutions

**What goes wrong:** The top of `./run` sets `set -euo pipefail`. This does NOT automatically apply inside:
- Command substitutions: `result=$(false; echo "still runs")` — the `false` does not abort the outer script.
- Sourced scripts that override shell options: `source _common.sh` — if `_common.sh` does `set +e` for its own reasons, it disables error-exit for the caller too.
- The `.aws-auth` `before_script` in GitLab CI, which is `!reference`-included and runs in a concatenated shell context — if one step silently fails the next step may run with partial state.

**Why it happens:** `set -e` is scoped to the current shell, not subshells created by `$()`. Sourced scripts share the current shell, so they can mutate options.

**Consequences:** AWS credential export steps can fail silently (e.g. `assume-role-with-web-identity` returns non-zero because the OIDC token is wrong); the next step runs with empty `AWS_ACCESS_KEY_ID` and produces `AuthFailure` on the first real AWS call, which is harder to diagnose.

**Prevention:**
- For command substitutions that must fail-fast: `result=$(set -e; false)` or capture exit code explicitly.
- For sourced scripts: audit `_common.sh` and any future helpers to ensure they do not call `set +e`.
- In CI YAML, the `.aws-auth` `before_script` already has `set -euo pipefail` as the first line — verify this is preserved when `./run` replaces inline commands. Do not rely on the calling job's shell options propagating into `./run` as a subprocess (they don't — `./run` is a new process and reads its own shebang).

**Detection:** Insert `echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-UNSET}"` immediately after the `assume-role` step in CI to confirm the export succeeded before the first AWS call.

**Phase:** CI integration phase.

---

### Pitfall M-5: `tf-ensure-init` Auto-Init Guard Depends on `jq` Parsing `.terraform/terraform.tfstate`

**What goes wrong:** The Makefile's `tf-ensure-init` target reads `terraform/.terraform/terraform.tfstate` with `jq` to detect backend key mismatches and triggers `tf-reinit` if needed. This logic must be faithfully ported to `./run`. If it is dropped ("too complex for a shell script"), operators who switch `DEVBOX_USER` without re-running `tf-init` silently apply changes to the wrong operator's state.

**Why it happens:** The auto-init guard is non-obvious — it looks like boilerplate. Developers porting the Makefile may skip it because it uses `$(MAKE) --no-print-directory` recursion, which has no direct shell equivalent.

**Consequences:** Operator A switches to `DEVBOX_USER=bob` and runs `./run tf-apply` without re-initialising. The cached backend still points to `users/alice/devbox.tfstate`. The apply targets Alice's instance. If Alice's instance is running, Terraform may modify or destroy it.

**Prevention:** Port the guard faithfully:
```bash
ensure_tf_init() {
  require_devbox_user
  local cached_key
  cached_key="$(jq -r '.backend.config.key // empty' terraform/.terraform/terraform.tfstate 2>/dev/null || true)"
  local want_key="users/${DEVBOX_USER}/devbox.tfstate"
  if [[ "$cached_key" != "$want_key" ]]; then
    echo "[ensure-tf-init] backend cache mismatch (cached='$cached_key', want='$want_key'); reinitialising..."
    run_tf_reinit
  fi
}
```
Call `ensure_tf_init` at the top of every command that runs `tofu plan`, `tofu apply`, `tofu destroy`, or reads `tofu output`.

**Detection:** Run `./run tf-plan DEVBOX_USER=alice`, then `./run tf-plan DEVBOX_USER=bob` without an intervening `tf-init`. If the second plan targets Alice's state, the guard is missing.

**Phase:** Initial `./run` implementation phase — must match Makefile behaviour before shipping.

---

### Pitfall M-6: `./run` Called From CI Without Matching the Local Argument Interface

**What goes wrong:** GitLab CI currently passes variables as environment variables (`DEVBOX_USER`, `TF_STATE_BUCKET`) from CI/CD variable injection. If `./run` is designed to accept these as positional arguments (e.g. `./run tf-apply jsmith`) rather than environment variables, the CI job must be updated. If `./run` accepts them only as environment variables but the operator's local shell requires them as flags, neither surface works cleanly.

**Why it happens:** The Makefile uses Make variables (`DEVBOX_USER=...` on the command line), which are distinct from shell environment variables. Ports to shell scripts often oscillate between `--flag` CLI design and pure environment variable design, landing on an inconsistent hybrid.

**Consequences:** `./run tf-apply` works locally because `DEVBOX_USER` is exported in the shell, but fails in CI because the CI job sets `DEVBOX_USER` as a GitLab variable and calls `./run tf-apply` without exporting it first. Or vice versa.

**Prevention:** Pick one canonical interface and document it:
- **Recommended (matches current Makefile convention):** `DEVBOX_USER=jsmith ./run tf-apply` — pure environment variable, works in both local shells and CI with `export DEVBOX_USER=jsmith` or GitLab variable injection.
- If flags are desired: `./run tf-apply --user jsmith` — then `_common.sh`'s `parse_args` pattern can be reused, but CI YAML must pass `--user ${DEVBOX_USER}`.

Whichever is chosen, `./run` must check the env var first, then fall back to a flag, then exit with a clear error — never silently default to `whoami`.

**Detection:** Run `env -i DEVBOX_USER=jsmith ./run tf-plan` (clean environment) and `./run tf-plan --user jsmith` — both should work or both should fail with the same clear error.

**Phase:** Design decision in the initial `./run` implementation phase; document in `CLAUDE.md` section 5 ("Daily flow").

---

## Minor Pitfalls

Mistakes that cause inconvenience or CI noise, not data loss.

---

### Pitfall m-1: `shellcheck` Coverage Gap — `run` Excluded from Existing Gate

**What goes wrong:** The `validate:shellcheck` CI job currently lints only `scripts/*.sh`. A new top-level `run` file (without a `.sh` extension) is silently excluded. ShellCheck bugs in `./run` are never caught automatically.

**Prevention:** Update the CI shellcheck job to include `run`:
```yaml
- shellcheck scripts/*.sh run
```
Or use `find . -name 'run' -o -name '*.sh'` with the appropriate depth limit. Also update `.pre-commit-config.yaml`'s `shellcheck` hook `files` pattern to match `run`.

**Phase:** CI integration phase (when CI jobs are updated to call `./run`).

---

### Pitfall m-2: `clean` Command Leaks `users/*.auto.tfvars` If Ported Incorrectly

**What goes wrong:** The Makefile's `clean` target removes `packer/packer_cache`, `terraform/.terraform`, and `users/*.auto.tfvars`. The `users/` directory contains per-operator AMI ID handoff files written by `make build`. If `./run clean` only replicates the first two and skips `users/`, stale `ami_id` overrides persist and the next `./run tf-apply` deploys from an old AMI.

**Prevention:** Port the full `clean` body verbatim. Test with `ls users/*.auto.tfvars` before and after.

**Phase:** Initial `./run` implementation phase.

---

### Pitfall m-3: `devbox-port-forward` Uses `exec` — Must Remain in the Foreground Process

**What goes wrong:** The Makefile's `devbox-port-forward` target ends with `exec aws ssm start-session ...`, which replaces the Make process with the SSM session. If `./run devbox-port-forward` wraps this in a subshell or pipes to another command, `exec` replaces the subshell and the parent `./run` process hangs waiting for the subshell to exit — which it never does because the SSM session is interactive.

**Prevention:** The `exec` must remain the final statement in the `devbox-port-forward` branch of `./run`, with no subsequent code. Do not wrap this branch in a function that does anything after the `exec` returns.

**Phase:** Initial `./run` implementation phase.

---

### Pitfall m-4: Grep-Gate Invariant #7 Needs Updating for `run` File

**What goes wrong:** Invariant #7 in `validate:grep-gates` checks that every `image:` line in `.gitlab-ci.yml` is digest-pinned. When CI jobs are updated to call `./run` instead of inline shell, the job scripts become shorter but the `image:` lines remain. This invariant is unaffected. However, if the migration introduces a new CI job (e.g. a lint job specifically for `run`), it must also use a digest-pinned image or the invariant fires.

**Prevention:** Any new CI job added during the migration must follow the existing image-digest-pin convention. Run `make grep-gates` (or `./run grep-gates` after migration) locally before pushing.

**Phase:** CI integration phase.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| Initial `./run` dispatcher | C-1 (TF_STATE_BUCKET empty), C-2 (DEVBOX_USER guard missing) | Port guards from Makefile verbatim before adding new logic |
| Working directory handling | M-3 (cd persists in script scope) | Use subshell pattern `(cd dir && cmd)` or anchor `REPO_ROOT` at startup |
| `tf-ensure-init` port | M-5 (auto-init guard dropped) | Port the jq-based mismatch check into `ensure_tf_init()` function |
| bash compatibility | M-1 (bash 3.2 on macOS) | Audit for `declare -A`, `mapfile`, `${var,,}` — replace with 3.2-compatible alternatives |
| Help/discoverability | M-2 (no default goal) | Default to `help` when `$1` is unset; `*` catch-all exits non-zero |
| CI integration | C-3 (`after_script` isolation), C-4 (executable bit), M-4 (`set -e` propagation), m-1 (shellcheck gap) | Extend shellcheck to cover `run`; verify exec bit; add credential smoke test |
| Argument interface | M-6 (env var vs flag inconsistency) | Decide env-var-first interface before writing any CI YAML |

---

## Sources

- Makefile at `/Users/me/Documents/code/devbox/Makefile` — guards, auto-init logic, bucket derivation (HIGH confidence — primary source)
- `.gitlab-ci.yml` at `/Users/me/Documents/code/devbox/.gitlab-ci.yml` — CI structure, `before_script` concatenation, `after_script` isolation note (HIGH confidence — primary source)
- `scripts/_common.sh` — `parse_args`, `resolve_instance`, `BASH_SOURCE` usage (HIGH confidence — primary source)
- GitLab Runner issue [#4146](https://gitlab.com/gitlab-org/gitlab-runner/-/issues/4146): `after_script` does not inherit `before_script` exports (HIGH confidence — official issue tracker)
- [Nick Janetakis — Replacing make with a Shell Script](https://nickjanetakis.com/blog/replacing-make-with-a-shell-script-for-running-your-projects-tasks) — argument passing and environment compatibility (MEDIUM confidence)
- [Three Dots Labs — Keeping common scripts in GitLab CI](https://threedots.tech/post/keeping-common-scripts-in-gitlab-ci/) — synchronisation overhead, testing challenges (MEDIUM confidence)
- [GitHub — Rancher bash 3.2 incompatibility issue #51183](https://github.com/rancher/rancher/issues/51183) — real-world `declare -A` failure on macOS (HIGH confidence — verified issue)
- [GitHub Actions Permission Denied — DEV Community](https://dev.to/aileenr/github-actions-fixing-the-permission-denied-error-for-shell-scripts-4gbl) — executable bit git tracking (HIGH confidence, GitHub Actions context; same git mechanism applies to GitLab)
- [How to Use terraform -chdir](https://scalr.com/learning-center/how-to-use-terraform-chdir) — `-chdir` vs `cd` working directory difference (MEDIUM confidence — vendor learning center)
- [GitLab Forum — Can't run script file Permission Denied](https://forum.gitlab.com/t/cant-run-script-file-permission-denied/7074) — executable bit on runner (HIGH confidence — official forum)
