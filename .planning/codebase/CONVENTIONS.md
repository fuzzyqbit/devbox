# Coding Conventions

**Analysis Date:** 2026-05-13

This is an Infrastructure-as-Code repository: HCL (Terraform, Terragrunt, Packer), YAML (Ansible), bash (instance lifecycle scripts), and a GNU Make front door. No application code. Conventions below are extracted from the actual files — deviations are called out explicitly.

## Naming Patterns

### Files

- **Terraform**: split by canonical concern — `terraform/main.tf` (resources + provider), `terraform/variables.tf` (input variables), `terraform/outputs.tf` (outputs). No `versions.tf` — `required_version` / `required_providers` live inline at `terraform/main.tf:1-10`.
- **Packer**: split by concern — `packer/devimage.pkr.hcl` (build + source + provisioner), `packer/variables.pkr.hcl` (input variables). The `packer {}` block lives inline at `packer/devimage.pkr.hcl:1-12` (no separate `versions.pkr.hcl`).
- **Terragrunt**: single root `terragrunt.hcl` at repo root. No child `terragrunt.hcl` per environment — environments are virtualised via `DEVBOX_USER`.
- **Ansible roles**: one role per concern, snake_case directory names (`base`, `python`, `golang`, `containers`, `devtools`, `hardening`, `certs`, `desktop`, `vscode`, `git`, `java`, `rust`, `terraform`, `devops`). All non-vendor roles use the minimal `tasks/main.yml` + `defaults/main.yml` (+ `templates/` + `handlers/` where needed) layout — no `meta/`, `vars/`, or `tests/`. The vendored `AMAZON2023-CIS` role keeps its upstream layout.
- **Ansible playbooks**: kebab-case (`playbook.yml`, `firewalld-docker-fix.yml`, `layer_config.yml`, `requirements.yml`) directly under `ansible/`.
- **Bash scripts**: kebab-case, `devbox-<verb>.sh` (`devbox-start.sh`, `devbox-stop.sh`, `devbox-status.sh`). Shared library is `_common.sh` (leading underscore = "not directly executable, sourced only"). All `.sh` files live in `scripts/`.
- **CIS task files**: vendored — preserve upstream `cis_<section>.<rule>.yml` pattern, e.g. `ansible/roles/AMAZON2023-CIS/tasks/section_1/cis_1.1.1.x.yml`. Do not mirror this pattern in first-party roles.

### Variables (HCL)

- **Terraform inputs**: `snake_case`, every variable declared with `type` and `description`, defaults provided where sensible — see `terraform/variables.tf:1-67`. Examples: `ami_id`, `instance_type`, `root_volume_size`, `devbox_user`, `iam_instance_profile`, `associate_public_ip`, `extra_tags`.
- **Terraform locals**: `snake_case`, declared in a single `locals {}` block at the top of `main.tf`. Current locals: `name_prefix`, `common_tags` (`terraform/main.tf:16-26`). Locals are used to compose values consumed multiple times — never as a stash for one-off intermediates.
- **Terraform outputs**: `snake_case` with `description` on every output (`terraform/outputs.tf:1-49`). Outputs surface user-facing info (`ssh_command`, `code_server_url`, `novnc_url`) alongside infra IDs (`instance_id`, `security_group_id`). Outputs prefer composed strings (e.g. `terraform/outputs.tf:18` builds a usable `ssh` command).
- **Packer inputs**: same conventions as Terraform — `snake_case`, `type` + `description` always, defaults where sensible (`packer/variables.pkr.hcl:1-41`).
- **Packer locals**: `snake_case`, declared at top of build file (`packer/devimage.pkr.hcl:14-17`). `timestamp` and `ami_name` are computed once and reused.
- **Terragrunt locals**: `snake_case`, declared at the top of `terragrunt.hcl` (`terragrunt.hcl:1-4`). Two locals only: `user` (with double-fallback `DEVBOX_USER` → `USER` → `"default"`) and `account_id` (from `get_aws_account_id()`).

### Resources, providers, modules (Terraform)

- Resource block labels are `snake_case` and describe the role, not the type: `aws_security_group.devbox`, `aws_instance.devbox` (`terraform/main.tf:30, 81`). Both use the bare label `devbox` because there is one of each.
- Use `name_prefix` (not `name`) for resources that benefit from `create_before_destroy` — see `aws_security_group.devbox` (`terraform/main.tf:31, 74-76`).
- **Tagging convention** — every resource gets `merge(local.common_tags, { Name = "..." })`. `common_tags` always includes `Project`, `ManagedBy`, `DevboxUser`; `Name` is per-resource (`terraform/main.tf:18-25, 70-72, 96-98`).

### Ansible variables

- **Role defaults**: `snake_case` in `<role>/defaults/main.yml`. Each role defines `dev_user: ec2-user` and `dev_home: /home/ec2-user` even though the values are constant project-wide — this is deliberate, see "Var precedence" below.
- **Version pins**: every external binary version lives in defaults as `<tool>_version`: `go_version`, `kubectl_version`, `helm_version`, `terraform_version`, `tofu_version`, `code_server_version`, `nvm_version`, etc. Values are quoted strings (`"1.22.5"`, not `1.22.5`) — see `ansible/roles/golang/defaults/main.yml:2`, `ansible/roles/devops/defaults/main.yml:2-6`.
- **Booleans**: `<feature>_install` for optional installs (`awscli_install`, `starship_install`, `gh_cli_install`, `direnv_install`, `ca_cert_env_vars`). Used as the `when:` clause for an enclosing `block:` — see `ansible/roles/base/tasks/main.yml:21-23, 50-52`.
- **Layer toggles**: every role is gated in `playbook.yml` by `layers.<role> | default(<bool>)`. Master toggle file is `ansible/layer_config.yml` (`layers.python: true`, `layers.golang: true`, ...). Default for most layers is `false` in `playbook.yml` (opt-in); `base` and `certs` default to `true` (`ansible/playbook.yml:15-55`).
- **CIS overrides**: `amzn2023cis_*` — these are the vendored role's variable names; do not invent new prefixes. Override values live in `ansible/roles/hardening/defaults/main.yml` (`ansible/roles/hardening/defaults/main.yml:1-26`).

### Make targets

- **kebab-case**, grouped by tool: `tf-*` (raw Terraform via workspaces), `tg-*` (Terragrunt, the default path), `start`/`stop`/`status` (lifecycle), `init`/`validate`/`build`/`fmt`/`clean` (Packer + cross-tool). See `Makefile:1`.
- `auto-` prefix for non-interactive variants (`tg-auto-apply`, `tg-auto-destroy` — `Makefile:64-71`).
- Help target is `help`, not `default`. It is the first non-`.PHONY` target so `make` with no args prints help (`Makefile:6-31`).

## Code Style

### HCL (Terraform / Terragrunt / Packer)

- **Formatter is canonical** — `make fmt` runs `packer fmt`, `terraform fmt`, and `terragrunt hclfmt` against the three trees (`Makefile:44-48`). Treat the formatter output as the style guide; do not hand-format.
- **2-space indent**, attribute alignment within a block (visible in `terraform/main.tf:36-42` where `description`/`from_port`/`to_port`/`protocol`/`cidr_blocks` line up).
- **One blank line** between resource blocks; comment dividers `# --- Section ---` separate logical groups inside a file (`terraform/main.tf:28, 79`; `packer/devimage.pkr.hcl` has none — divider style only used where the file has multiple logical sections).
- **Conditional null** for optional fields rather than separate resources: `vpc_id != "" ? var.vpc_id : null` (`packer/devimage.pkr.hcl:24-25`).
- **`merge()` for tags**, never inline literal maps when there's a base set to extend (`terraform/main.tf:18-25, 70-72, 96-98`; `packer/devimage.pkr.hcl:46-54`).

### Ansible YAML

- **Document-start marker `---` required** on every file (every `*.yml` in roles begins with `---` — `ansible/roles/base/tasks/main.yml:1`, `ansible/playbook.yml:1`).
- **2-space indent** in first-party roles; the vendored `AMAZON2023-CIS` role uses 4-space indent and its own `.yamllint` config (`ansible/roles/AMAZON2023-CIS/.yamllint:23-26`). Do not mix styles within a role.
- **Module names are bare** in first-party roles (`dnf:`, `copy:`, `get_url:`, `file:`, `systemd:`, `lineinfile:`, `blockinfile:`, `template:`, `unarchive:`, `pip:`, `user:`, `sysctl:`, `command:`, `shell:`). The vendored CIS role uses fully-qualified collection names (`ansible.builtin.*`, `ansible.posix.*`). The only first-party FQCN currently is `ansible.builtin.reboot` at `ansible/roles/hardening/tasks/main.yml:41` — added because reboot lives in `ansible.builtin` and the bare name is unambiguous but the explicit form makes the side effect more visible.
- **Task names** are Title Case, descriptive sentence fragments — "Install AWS CLI v2", "Add Rust components", "Configure git to use delta". Avoid trailing periods. Version interpolation goes in the name where relevant: `name: Download Go {{ go_version }}` (`ansible/roles/golang/tasks/main.yml:2`).
- **File permissions are always quoted strings**: `mode: "0644"`, `mode: "0755"`, `mode: "0600"` — never bare octal (which Ansible would interpret as decimal). See `ansible/roles/base/tasks/main.yml:28, 85, 93`.
- **Loops** use `loop:` (not deprecated `with_items:`), except for the file-glob case which keeps `with_fileglob:` (`ansible/roles/certs/tasks/main.yml:11-13`).
- **Section dividers** inside long task files use `# --- Section name ---` comments (`ansible/roles/python/tasks/main.yml:27, 70`; `ansible/roles/devops/tasks/main.yml:2, 17, 47, 68, 97`; `ansible/roles/devtools/tasks/main.yml:7, 35, 69, 103, 137, 164, 171, 194, 272, 279, 298`).

### Bash

- **Strict mode is in `_common.sh` only** (`scripts/_common.sh:5`: `set -euo pipefail`). The three entry-point scripts (`devbox-start.sh`, `devbox-stop.sh`, `devbox-status.sh`) do NOT re-declare strict mode — they inherit it by sourcing `_common.sh` immediately after computing `SCRIPT_DIR`. This is fragile: if `_common.sh` is ever sourced after other code runs, that code runs without strict mode. Acceptable here because sourcing is the first non-trivial action in every script (`scripts/devbox-start.sh:2-3`, `scripts/devbox-stop.sh:2-3`, `scripts/devbox-status.sh:2-3`).
- **Shebang**: `#!/usr/bin/env bash` (not `/bin/bash`) — see `scripts/_common.sh:1`, `scripts/devbox-start.sh:1`.
- **Double-quote all variable expansions**: `"$INSTANCE_ID"`, `"$REGION"`, `"$DEVBOX_USER"`. Compliance is consistent across all four scripts.
- **`[[ ]]` for conditionals**, never `[ ]` (`scripts/_common.sh:18, 31`; `scripts/devbox-start.sh:30, 32`).
- **`$()` for command substitution**, never backticks (`scripts/_common.sh:7, 8`; `scripts/devbox-status.sh:24, 30`).
- **Errors to stderr, then `exit 1`**: `echo "Error: ..." >&2; exit 1` (`scripts/_common.sh:40-42`; `scripts/devbox-start.sh:51-52`; `scripts/devbox-stop.sh:47-48`).
- **`SCRIPT_DIR` idiom** — every script computes its own dir via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and sources siblings via `"$SCRIPT_DIR/_common.sh"` (`scripts/devbox-start.sh:2-3`). `_common.sh` uses `BASH_SOURCE[1]` instead of `[0]` because it is always sourced, never executed (`scripts/_common.sh:7`).
- **No `function` keyword** — POSIX-style function definitions: `parse_args() { ... }`, `resolve_user() { ... }` (`scripts/_common.sh:17, 30, 37, 53`).
- **Long AWS CLI invocations** use line-continuation `\` with one flag per line and 2-space continuation indent (`scripts/devbox-start.sh:24-28, 34-37, 40-42`). Avoid `--no-cli-pager` flags; rely on `--output text` / `--output json` + `jq`.
- **`jq` for JSON parsing** (`scripts/devbox-status.sh:30-35`), not `grep`/`sed`/`awk` on JSON.
- **ShellCheck**: scripts are written ShellCheck-clean by inspection (quoted expansions, `[[ ]]`, `$()`, `BASH_SOURCE` indirection) but there is **no `make shellcheck` target** and no pre-commit hook enforcing it. ShellCheck is installed by the `devtools` Ansible role onto the built image (`ansible/roles/devtools/tasks/main.yml:7-33`), but is not run against this repo's own scripts as part of any gate.

### Makefile

- **`.PHONY` declared once** at the top, listing every non-file target on a single line (`Makefile:1`). All targets in this Makefile are phony.
- **Tabs for recipe indentation** (Make requires this) — visible in `Makefile:7-30` (help) and all recipe bodies.
- **`?=` for user-overridable defaults**: `DEVBOX_USER ?= $(shell whoami)` (`Makefile:4`). User can override per-invocation: `make tg-plan DEVBOX_USER=jsmith`.
- **`$(VAR)` for Make variables**, `$$VAR` if you need a literal shell `$VAR` inside a recipe (no current uses).
- **`@echo` (silent)** for help and status output; bare commands for things the user should see executed (`Makefile:7-31, 39, 47-48`).
- **Recipe = one logical action per target**. Multi-command recipes use `&& \` continuation (`Makefile:78-81`) — but most targets shell out to a single tool invocation or a single script. Composition lives in the script or in Terragrunt, not in the Makefile.
- **Section dividers** as `# --- Section ---` comments (`Makefile:32, 50, 73, 92, 103`), matching the HCL/Ansible style.

## Import Organization

Not applicable in the traditional sense — IaC modules.

- **Terragrunt → Terraform**: `terragrunt.hcl:8-10` points `source = "./terraform"`. Inputs are passed via the `inputs = { ... }` block (`terragrunt.hcl:27-37`), which Terragrunt converts into `TF_VAR_*` env vars. Do NOT also use `terraform.tfvars` — that file is `.gitignore`d (`.gitignore:11`) and bypassing the Terragrunt inputs block would split the source of truth.
- **Packer → Ansible**: `packer/devimage.pkr.hcl:60-72` invokes the `ansible` provisioner with `playbook_file = "${path.root}/../ansible/playbook.yml"`. `path.root` is the Packer build directory; the `../` reaches up to repo root. Don't move files without updating both ends.
- **Ansible roles** are wired up in `ansible/playbook.yml:14-55`, each gated by a `layers.<name>` boolean. To add a role, create `ansible/roles/<name>/{tasks,defaults}/main.yml`, then add a `- role: <name>` block to `playbook.yml` AND a `<name>: true|false` entry to `ansible/layer_config.yml`. The `ansible/playbook.yml:79-82` final line `- import_playbook: firewalld-docker-fix.yml` is a one-off — do not chain additional playbooks there without rethinking the layer model.

## Error Handling

### HCL

- **No explicit error blocks** — rely on Terraform/Packer's native validation (type checks, required-field errors).
- **Defensive defaults** for optional integrations: `iam_instance_profile` defaults to `null` so AWS provider treats it as unset (`terraform/variables.tf:51-55`), and `vpc_id`/`subnet_id` in Packer use the `"" ? null` trick to fall back to AWS defaults (`packer/devimage.pkr.hcl:24-25`).
- **Lifecycle protection** where rebuilds are destructive: `aws_security_group.devbox` uses `create_before_destroy = true` (`terraform/main.tf:74-76`) so SG replacement doesn't transiently strip the EC2 instance's traffic rules.

### Ansible

- **Explicit `changed_when: false`** for read-only commands so they don't pollute the change set:
  - `cloud-init status --wait` (`ansible/playbook.yml:11-12`)
  - `dnf clean all` (`ansible/playbook.yml:58-60`)
  - `python3 -m pipx ensurepath` (`ansible/roles/python/tasks/main.yml:17`)
  - `rustup component add` (`ansible/roles/rust/tasks/main.yml:22`)
  - `git config --global` (`ansible/roles/git/tasks/main.yml:87`)
  - `flatpak remote-add --if-not-exists` (`ansible/roles/desktop/tasks/main.yml:240`)
  - `firewall-cmd --get-default-zone` (`ansible/firewalld-docker-fix.yml:56`)
- **`creates:` for idempotency on `command:`** — 11 task uses outside the vendored CIS role, e.g.:
  - AWS CLI installer (`ansible/roles/base/tasks/main.yml:39`)
  - Starship installer (`ansible/roles/base/tasks/main.yml:61`)
  - rustup-init (`ansible/roles/rust/tasks/main.yml:13`)
  - rustup install of toolchain (`ansible/roles/rust/tasks/main.yml:13`)
  - VNC password file (`ansible/roles/desktop/tasks/main.yml:33`)
  - openssl cert generation (`ansible/roles/desktop/tasks/main.yml:149-150`)
- **Custom `changed_when:` + `failed_when:`** for `dnf swap`, where the command's exit code and stdout don't map cleanly to Ansible's success model:
  ```yaml
  - name: Swap curl-minimal for full curl
    command: dnf swap -y curl-minimal curl
    args:
      removes: /usr/bin/curl
    register: curl_swap
    changed_when: "'Nothing to do' not in curl_swap.stdout"
    failed_when: curl_swap.rc != 0 and 'already installed' not in curl_swap.stderr
  ```
  (`ansible/roles/base/tasks/main.yml:8-14`). Use this pattern when a command's failure-vs-no-op distinction is encoded in output text, not exit codes.
- **`ignore_errors: true` is rare and deliberate** — single use case is VS Code extension installs (`ansible/roles/vscode/tasks/main.yml:54`), where individual extension failures shouldn't fail the entire image build. Treat this as an exceptional pattern, not a default; CIS handlers also use it for IPv6 sysctl flush on container builds (`ansible/roles/AMAZON2023-CIS/handlers/main.yml:13`).
- **`register:` + conditional handler trigger** instead of always firing handlers: see firewalld → docker restart chain (`ansible/firewalld-docker-fix.yml:40-51`), where docker is only restarted when firewalld state actually changed.

### Bash

- **Strict mode (`set -euo pipefail`)** sourced from `_common.sh:5` propagates to all entry-point scripts.
- **State validation before action** — `devbox-start.sh:24-28` reads the current EC2 state and explicitly handles `running`, `stopped`, and "anything else" before issuing commands. Same pattern in `devbox-stop.sh:24-28`. Don't issue mutating AWS calls without first confirming the resource is in a state that accepts the transition.
- **Graceful fallback for region**: `REGION` is resolved from Terragrunt output, but if that fails, falls back to `AWS_REGION` → `AWS_DEFAULT_REGION` → `us-east-1` literal (`scripts/_common.sh:46-49`). Failure to read region is non-fatal because the user can still recover; failure to read `INSTANCE_ID` IS fatal (`scripts/_common.sh:38-43`) because the script has nothing to act on without it.
- **`||` after `terragrunt output -raw ...`** is required because `set -e` would otherwise kill the script on a missing-state error. The pattern is `INSTANCE_ID="$(... 2>/dev/null)" || { ...; exit 1; }` (`scripts/_common.sh:39-43`).

## Logging

- **No framework** — scripts use bare `echo` to stdout, `echo "... " >&2` to stderr. Acceptable because these are short, interactive utilities, not long-running services.
- **Section headers** in script output use `=== Label ===` (`scripts/devbox-start.sh:70`, `scripts/devbox-status.sh:37, 49`). Consistent across all three lifecycle scripts.
- **Make targets** print `@echo "..."` for the help target only. Recipes do not pre-announce what they're about to run — the shell does that.
- **Ansible** uses task names for logging; no explicit `debug:` calls in first-party roles. The vendored CIS role uses `ansible.builtin.debug:` for the post-run audit summary (`ansible/roles/AMAZON2023-CIS/tasks/main.yml:172-179`).

## Comments

### When to comment

- **Comment WHY, not WHAT.** Examples of valuable comments in the repo:
  - `ansible/roles/python/tasks/main.yml:70-76` — explains why `virtualenvwrapper` is installed per-user instead of system-wide (CIS hardening sets umask 027 which makes a root `pip install` unreadable to `ec2-user`). This is the kind of comment that prevents future regressions.
  - `ansible/roles/certs/tasks/main.yml:1-3` — tells you the operational contract (drop files into `files/ca-certs/` before building).
  - `ansible/roles/certs/tasks/main.yml:20-22` — explains why `SSL_CERT_FILE` etc. need to be set despite `update-ca-trust` already running.
  - `ansible/roles/hardening/defaults/main.yml:3, 15, 22, 25` — every CIS override is annotated with the reason it's disabled (firewall handled by SG, journal-remote not needed, etc.).
  - `ansible/firewalld-docker-fix.yml:2-25` — a 24-line header comment documenting that the entire playbook is a workaround, why it works, what the correct fix would be, and the ordering constraints. **This is the project standard for "this is a hack" headers.**
  - `Makefile:3, 50` — `# User detection: override with make <target> DEVBOX_USER=jsmith` and `# --- Terragrunt (user-scoped via DEVBOX_USER, auto-creates S3 backend) ---` document non-obvious semantics.
- **Avoid noise comments** — there are no `# Install foo` comments above `- name: Install foo` tasks. The task name IS the comment.

### `FIXME` policy

- Use `FIXME:` for known workarounds with a clear "right answer" that is currently deferred. Both repo `FIXME`s point at the same issue (`ansible/playbook.yml:79-81`, `ansible/firewalld-docker-fix.yml:2`). Format: `# FIXME: <one-line summary>. <multi-line context with the proper fix>.`
- No `TODO:` markers anywhere in first-party code. Either implement it, or write a `FIXME` with the deferred decision documented.

## Function Design (bash)

- **Functions are small and single-purpose**: `parse_args`, `resolve_user`, `resolve_instance`, `init_devbox` — none exceed 15 lines (`scripts/_common.sh:17-61`).
- **`init_devbox` is the canonical orchestrator** — entry points call `parse_args "$@"` then `init_devbox` and never the underlying helpers individually (`scripts/devbox-start.sh:20-21`, `scripts/devbox-stop.sh:20-21`, `scripts/devbox-status.sh:20-21`).
- **`usage()` is defined in each entry-point script, not in `_common.sh`** — because the usage text varies per script. `_common.sh:23` calls `usage` (defined by the caller) when `-h|--help` is encountered. This is an implicit contract: every script sourcing `_common.sh` must define `usage`. Document this when adding new scripts.
- **Globals set by helpers, not return-by-print**: `parse_args` and `resolve_*` mutate `DEVBOX_USER`, `INSTANCE_ID`, `REGION` as global vars rather than printing values to capture (`scripts/_common.sh:12-14`). Acceptable in a small script; would be wrong in a library.

## Module Design (Terraform / Ansible / Packer)

- **Single Terraform module**, no nesting. Terraform code lives entirely in `terraform/*.tf`. A second module would be premature given the scope (one SG + one EC2 instance).
- **Single Packer build** (`source.amazon-ebs.al2023`), single provisioner (`ansible`). Don't split into multiple sources until there's a second OS or architecture.
- **Roles are the unit of reuse in Ansible**, one role per "layer". Layers are independent — `base` is the only soft prerequisite (it installs gcc, make, etc. that other roles assume). Don't introduce role-to-role dependencies via `meta/main.yml` — the layer-toggle model in `playbook.yml` is the dependency mechanism.

## Var Precedence (Ansible)

The build accepts vars from three sources, in increasing precedence:

1. **Role defaults** — `<role>/defaults/main.yml`. Repeating `dev_user`/`dev_home` here makes each role independently runnable (you can `ansible-playbook` against a single role) and surfaces "this is the user/home this role assumes" right next to the role's own vars. **Convention: every role redeclares `dev_user` and `dev_home` in its defaults.**
2. **Playbook vars** — `playbook.yml:6-7` (`vars:` block) sets the project-wide `dev_user: ec2-user`, `dev_home: /home/ec2-user`. These override role defaults.
3. **Extra-vars from Packer** — `packer/devimage.pkr.hcl:63-65` passes `--extra-vars @../ansible/layer_config.yml`, which currently carries only the `layers:` toggles. Use this for anything that should differ per AMI build.

`layer_config.yml` is the toggle layer; per-role version pins and tool lists live in role defaults. **Don't move version pins into `layer_config.yml`** — the file is meant for per-build composition, not per-tool config.

## Idempotency Patterns (Ansible)

In order of preference:

1. **Native module idempotency** — `dnf: state: present`, `file: state: directory`, `lineinfile: regexp: ...`, `blockinfile: marker: ...`. Default first choice. Used pervasively (`ansible/roles/base/tasks/main.yml:17-19, 88-93, 96-101`).
2. **`creates:` arg on `command:`/`shell:`** — when the action installs a binary or writes a file (`ansible/roles/base/tasks/main.yml:39, 61`; `ansible/roles/python/tasks/main.yml:24`; `ansible/roles/rust/tasks/main.yml:13`; `ansible/roles/desktop/tasks/main.yml:33, 150`; `ansible/roles/containers/tasks/main.yml`'s pattern carries through).
3. **`changed_when: false`** — read-only commands and idempotent shell helpers (`ansible/playbook.yml:11-12, 58-60`; `ansible/roles/python/tasks/main.yml:17`; `ansible/roles/rust/tasks/main.yml:22`).
4. **Custom `changed_when:` / `failed_when:`** — when the previous three don't fit. Reserve for cases like the `dnf swap` block (`ansible/roles/base/tasks/main.yml:8-14`).
5. **`lookup('password', '/dev/null length=32')`** — for "always change" semantics where intent is regeneration on every run; currently only used to set a random root password under CIS rule 4.6.6 (`ansible/roles/hardening/tasks/main.yml:22`).

`ignore_errors: true` is NOT an idempotency tool — it suppresses failures. Use it only when partial failure is acceptable (VS Code extension installs).

---

*Convention analysis: 2026-05-13*
