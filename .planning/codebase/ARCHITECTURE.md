<!-- refreshed: 2026-05-13 -->
# Architecture

**Analysis Date:** 2026-05-13

## System Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                       Operator Surface                           │
│  `Makefile` targets  ─►  `scripts/devbox-*.sh`  ─►  AWS CLI      │
└───────┬───────────────────────┬──────────────────────────────────┘
        │                       │
        │ build / fmt           │ start / stop / status
        ▼                       │
┌──────────────────┐            │
│   Packer (bake)  │            │
│ `packer/         │            │
│  devimage.pkr    │            │
│  .hcl`           │            │
│                  │            │
│  pulls AL2023    │            │
│  base AMI ──►    │            │
│  spawns build    │            │
│  EC2, invokes    │            │
│  Ansible over    │            │
│  SSH             │            │
└────────┬─────────┘            │
         │ provisioner          │
         ▼                      │
┌──────────────────────────┐    │
│   Ansible (configure)    │    │
│ `ansible/playbook.yml`   │    │
│ + roles/*  (14 layers,   │    │
│   each gated by          │    │
│   layer_config.yml)      │    │
│                          │    │
│ Produces hardened AMI    │    │
│ with /etc/devimage-      │    │
│ manifest.yml             │    │
└────────┬─────────────────┘    │
         │ AMI ID (manual copy) │
         ▼                      │
┌──────────────────────────┐    │
│ Terragrunt → Terraform   │◄───┘
│ `terragrunt.hcl`         │
│ `terraform/main.tf`      │
│                          │
│ - Per-user state key:    │
│   users/$DEVBOX_USER/    │
│   devbox.tfstate         │
│ - S3 backend +           │
│   DynamoDB locks         │
│ - Creates SG + EC2       │
│   instance from AMI      │
└────────┬─────────────────┘
         │ outputs: instance_id,
         │          aws_region,
         │          public_ip, …
         ▼
┌──────────────────────────────────────────────────────────────┐
│ Running EC2 devbox (per user)                                │
│  - SSH :22, code-server :8080, noVNC :6080                   │
│  - Lifecycle managed by `scripts/devbox-{start,stop,status}` │
│    via `aws ec2 describe-instances / start / stop / wait`    │
└──────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Makefile | Single operator entry surface; dispatches to packer/terragrunt/scripts; threads `DEVBOX_USER` into every stage | `Makefile` |
| Terragrunt root | Generates `terraform/backend.tf`, injects `inputs` (ami_id, key_name, subnet_id, vpc_id, instance_type, region) into Terraform; pins state key to `users/${DEVBOX_USER}/devbox.tfstate`; uses OpenTofu (`terraform_binary = "tofu"`) | `terragrunt.hcl` |
| Terraform module | Provisions per-user `aws_security_group.devbox` + `aws_instance.devbox` from a pre-baked AMI; emits outputs consumed by the lifecycle scripts | `terraform/main.tf`, `terraform/outputs.tf`, `terraform/variables.tf` |
| Packer build | Boots a fresh AL2023 minimal AMI, hands it to Ansible, then snapshots the result as `devimage-al2023-<timestamp>` | `packer/devimage.pkr.hcl`, `packer/variables.pkr.hcl` |
| Ansible playbook | Sequences 14 conditional roles + a firewalld/Docker post-play; writes `/etc/devimage-manifest.yml` recording the active layer set | `ansible/playbook.yml`, `ansible/firewalld-docker-fix.yml` |
| Layer config | Single source of truth for which roles run during the bake | `ansible/layer_config.yml` |
| Galaxy requirements | Declares Ansible collections (`community.general`, `community.crypto`, `ansible.posix`) installed at provision time | `ansible/requirements.yml` |
| Lifecycle scripts | Read Terragrunt outputs and drive `aws ec2 …` for start/stop/status; surface SSH/code-server/noVNC connection info | `scripts/devbox-start.sh`, `scripts/devbox-stop.sh`, `scripts/devbox-status.sh` |
| Shared script helpers | Centralize `parse_args`, `resolve_user`, `resolve_instance`; sourced by every `devbox-*.sh` | `scripts/_common.sh` |

## Pattern Overview

**Overall:** Three-stage IaC pipeline — **Provision → Bake → Configure → Run** — with operator orchestration in shell + Make.

**Key Characteristics:**
- **Bake-then-launch (immutable image).** Heavy software install runs once inside Packer; per-user EC2 instances launch from a fixed `ami_id` (`terragrunt.hcl:29`) with no runtime provisioning.
- **Per-user isolation by state key, not by code.** Terraform code is shared; `DEVBOX_USER` selects an isolated S3 state key in `terragrunt.hcl:21` (`users/${local.user}/devbox.tfstate`) — and a Terraform workspace in the legacy direct-Terraform path (`Makefile:78-90`).
- **Composable image via opt-in layers.** `ansible/layer_config.yml` toggles 14 roles; each role in `ansible/playbook.yml:14-55` is gated by `when: layers.<name> | default(...)`.
- **Outputs are the integration contract.** Lifecycle scripts read `terragrunt output -raw instance_id` and `aws_region` (`scripts/_common.sh:39-49`) — no `.tfvars` files or ad-hoc state parsing.
- **No remote-exec, no userdata.** All host configuration lives in Ansible; Terraform only allocates AWS resources.

## Layers

**Operator (Make):**
- Purpose: Stable CLI surface (`make build`, `make tg-apply`, `make start`)
- Location: `Makefile`
- Contains: Phony targets that set `DEVBOX_USER` and shell out to packer/terragrunt/scripts
- Depends on: `packer`, `terragrunt`, `terraform`/`tofu`, `aws`, the lifecycle scripts
- Used by: Humans

**Image-bake (Packer + Ansible):**
- Purpose: Produce a versioned AMI containing the desired toolchain
- Location: `packer/`, `ansible/`
- Contains: One Packer source (`amazon-ebs.al2023`), one Ansible provisioner block, one master playbook, and per-tool roles under `ansible/roles/`
- Depends on: AWS API (EBS, EC2), Ansible Galaxy
- Used by: Operator (`make build`)

**Infra-provision (Terragrunt + Terraform):**
- Purpose: Allocate per-user EC2 + SG from the baked AMI
- Location: `terragrunt.hcl`, `terraform/`
- Contains: One module with two resources (`aws_security_group.devbox`, `aws_instance.devbox`) and the outputs that the lifecycle scripts consume
- Depends on: S3 (state), DynamoDB (locks), AWS EC2 + VPC
- Used by: Operator (`make tg-*`), Lifecycle scripts (read outputs only)

**Lifecycle (shell):**
- Purpose: Day-2 ops — start/stop/status of an already-provisioned instance
- Location: `scripts/`
- Contains: Three end-user scripts + one sourced helper
- Depends on: `aws` CLI, `jq` (status), `terragrunt output`
- Used by: Operator (`make start/stop/status`)

## Data Flow

### Build flow (provision → bake → configure)

1. Operator runs `make build` → `cd packer && packer build .` (`Makefile:42`).
2. Packer resolves a fresh `al2023-ami-minimal-*-x86_64` via `source_ami_filter` (`packer/devimage.pkr.hcl:27-35`) and launches a build instance with vars from `packer/variables.pkr.hcl`.
3. Packer's `ansible` provisioner runs `ansible/playbook.yml` against the build host with `--extra-vars @ansible/layer_config.yml` and galaxy collections from `ansible/requirements.yml` (`packer/devimage.pkr.hcl:60-72`).
4. The playbook waits for cloud-init, then runs each role gated by `layers.<name>` (`ansible/playbook.yml:9-56`), writes `/etc/devimage-manifest.yml` (`ansible/playbook.yml:71-77`), and imports `firewalld-docker-fix.yml` as a post-play (`ansible/playbook.yml:82`).
5. Packer snapshots the instance as `devimage-al2023-<YYYYMMDDhhmmss>` (`packer/devimage.pkr.hcl:14-17`). The resulting AMI ID is **not** automatically wired into Terraform — the operator pastes it into `terragrunt.hcl:29` (`ami_id`).

### Provision flow (Terragrunt → Terraform → EC2)

1. Operator runs `make tg-apply DEVBOX_USER=jsmith` (`Makefile:61`).
2. Terragrunt evaluates `terragrunt.hcl`:
   - Computes `local.user` from `DEVBOX_USER` env var (`terragrunt.hcl:2`).
   - Generates `terraform/backend.tf` pointing at `s3://devimage-tfstate-<account_id>/users/<user>/devbox.tfstate` with DynamoDB locks (`terragrunt.hcl:12-25`).
   - Injects `inputs` (ami_id, key_name, subnet_id, vpc_id, instance_type, root_volume_size, instance_name, aws_region, devbox_user) into Terraform (`terragrunt.hcl:27-37`).
3. Terraform (via OpenTofu, set on `terragrunt.hcl:6`) applies `terraform/main.tf` — `aws_security_group.devbox` (ports 22/8080/6080) and `aws_instance.devbox`, both tagged with `DevboxUser` and named `${devbox_user}-${instance_name}` (`terraform/main.tf:16-26, 30-99`).
4. Outputs from `terraform/outputs.tf` (`instance_id`, `aws_region`, `public_ip`, `ssh_command`, `code_server_url`, `novnc_url`, etc.) are persisted into the per-user state object.

### Lifecycle flow (status / start / stop)

1. Operator runs `make start` → `scripts/devbox-start.sh` (`Makefile:95`).
2. The script sources `scripts/_common.sh`, then calls `parse_args "$@"` and `init_devbox` (`scripts/devbox-start.sh:20-21`).
3. `resolve_user` falls back through `--user` flag → `DEVBOX_USER` env → `whoami` (`scripts/_common.sh:30-34`).
4. `resolve_instance` runs `terragrunt output -raw instance_id` (and `aws_region`) from the project root with the right `DEVBOX_USER` (`scripts/_common.sh:37-50`). If state is missing, it instructs the operator to run `make tg-apply` first.
5. The script then runs `aws ec2 describe-instances` → branches on state → `aws ec2 start-instances` (or `stop-instances`) → `aws ec2 wait instance-running` + `wait instance-status-ok` (`scripts/devbox-start.sh:24-53`).
6. On success it prints SSH, code-server, and noVNC URLs derived from the live `PublicIpAddress` and `KeyName` (`scripts/devbox-start.sh:58-74`).

**State Management:**
- All authoritative state lives in S3 (`devimage-tfstate-<account_id>`) keyed by user; DynamoDB table `devimage-tfstate-locks` provides mutual exclusion (`terragrunt.hcl:18-24`).
- No local `*.tfstate` is committed — `.gitignore` excludes `terraform/.terraform/`, `terraform/terraform.tfstate*`, `terraform/backend.tf` (generated by Terragrunt), and `.terragrunt-cache/`.
- `ansible/layer_config.yml` is the only build-time configuration committed in-repo (no per-user variants).

## Key Abstractions

**`DEVBOX_USER`:**
- Purpose: Cross-stage tenancy key — selects state, names resources, tags instances
- Examples: `terragrunt.hcl:2` (state key), `terraform/main.tf:17` (`name_prefix`), `scripts/_common.sh:30-34` (script default)
- Pattern: Environment-variable propagation; `Makefile` sets `DEVBOX_USER ?= $(shell whoami)` (`Makefile:4`) and forwards it on every shell-out

**Layer (Ansible role + flag):**
- Purpose: Single opt-in unit of image content (a runtime, a tool, a hardening profile)
- Examples: `ansible/roles/python/`, `ansible/roles/hardening/`, `ansible/layer_config.yml`
- Pattern: One directory per role under `ansible/roles/<name>/` with `tasks/main.yml` + `defaults/main.yml`; gated in `ansible/playbook.yml` via `when: layers.<name> | default(...)`

**Output contract:**
- Purpose: Decouple post-provision tooling from Terraform internals
- Examples: `terraform/outputs.tf:1-49`, `scripts/_common.sh:38-49`
- Pattern: Scripts only read `terragrunt output -raw <name>`; no other state coupling

## Entry Points

**`Makefile`:**
- Location: `Makefile`
- Triggers: Human invocation
- Responsibilities: Authoritative target list (image lifecycle, terragrunt lifecycle, instance lifecycle, cleanup); only place that injects `DEVBOX_USER`

**`packer build`:**
- Location: `packer/devimage.pkr.hcl`
- Triggers: `make build` (`Makefile:41-42`)
- Responsibilities: Source AMI selection, build-instance launch, Ansible provisioner, AMI snapshot + tagging

**`terragrunt apply` / `init`:**
- Location: `terragrunt.hcl`
- Triggers: `make tg-init`, `make tg-apply`, etc. (`Makefile:52-71`)
- Responsibilities: Backend bootstrap, input injection, Terraform invocation via OpenTofu

**`scripts/devbox-start.sh` (and `-stop.sh`, `-status.sh`):**
- Location: `scripts/devbox-start.sh`
- Triggers: `make start` / `make stop` / `make status`
- Responsibilities: User & instance resolution, AWS EC2 lifecycle commands, connection info output

## Architectural Constraints

- **AMI ID is hand-edited.** `terragrunt.hcl:29` hard-codes `ami_id = "ami-0b7cfe2135f319a55"`. There is no automated handoff from Packer's snapshot output to Terragrunt's `inputs`. Building a new image requires an operator to copy the new AMI ID into `terragrunt.hcl`.
- **Single AWS region / VPC / subnet / key pair.** `terragrunt.hcl:30-36` pins `key_name`, `subnet_id`, `vpc_id`, `aws_region` for the whole project. Multi-region or multi-VPC fan-out is not modeled.
- **One instance per user, period.** State key uniqueness in `terragrunt.hcl:21` means a given `DEVBOX_USER` owns at most one devbox at a time.
- **Terragrunt outputs must exist before scripts run.** `scripts/_common.sh:38-44` exits if `terragrunt output -raw instance_id` fails; there is no fallback discovery (e.g. tag-based lookup).
- **OpenTofu, not stock Terraform.** `terragrunt.hcl:6` sets `terraform_binary = "tofu"`. Operators without `tofu` on PATH will fail at `terragrunt init`. The legacy `make tf-*` path still calls plain `terraform` (`Makefile:75-90`).
- **Public SG, intentionally.** `terraform/main.tf:36-60` opens 22/8080/6080 to `0.0.0.0/0`. Hardening is expected to happen inside the image (`ansible/roles/hardening/`), not at the SG.
- **Root password is randomized but discarded.** `ansible/roles/hardening/tasks/main.yml:19-23` hashes a 32-char random string and never surfaces it — recovery is via SSH key only.
- **Reboot mid-bake.** `ansible/roles/hardening/tasks/main.yml:40-43` reboots the Packer build instance to apply SELinux/FIPS/GRUB. Any role placed *after* `hardening` in `ansible/playbook.yml:14-55` runs post-reboot.

## Anti-Patterns

### AMI promotion by manual edit

**What happens:** After `make build` succeeds, Packer prints a new AMI ID, but `terragrunt.hcl:29` still references the previous one until a human edits the file and commits it.
**Why it's wrong:** No audit trail tying a deployed instance to its build, easy to apply against a stale or destroyed AMI, no way to roll forward in CI.
**Do this instead:** Tag the AMI deterministically (already done: `Name=devimage-al2023-<timestamp>` in `packer/devimage.pkr.hcl:46-54`) and resolve it inside Terraform via an `aws_ami` data source filtered by `Builder=packer` + `most_recent=true`, falling back to a `var.ami_id` override for pinning.

### Runtime workaround embedded in image build

**What happens:** `ansible/playbook.yml:82` unconditionally imports `firewalld-docker-fix.yml`, which the file itself describes as a temporary workaround (`ansible/firewalld-docker-fix.yml:1-26`) that sets firewalld's default zone to `docker` to bypass INPUT drops for code-server/noVNC.
**Why it's wrong:** A workaround pinned into every image obscures the intended firewall design; the comment explicitly flags two correct alternatives (per-port allowances in `public`, or stop relying on host firewalld and trust the EC2 SG).
**Do this instead:** Either (a) drop firewalld via the `hardening` role's CIS overrides (already prepared — see `ansible/roles/hardening/defaults/main.yml:3-13`) and rely solely on the SG, or (b) move per-service allowances into the role that installs that service (e.g. `vscode`, `desktop`).

### Two configuration paths for the same outcome

**What happens:** `Makefile:75-90` keeps a legacy `tf-*` path that calls plain `terraform` with `-var="devbox_user=..."` and Terraform *workspaces* for per-user isolation, while the documented path (`tg-*`) uses Terragrunt + per-user S3 keys.
**Why it's wrong:** Two backends (local-vs-S3, workspaces-vs-key-prefix) can drift; running `make tf-apply` after `make tg-apply` will operate on different state and create a duplicate instance.
**Do this instead:** Remove the `tf-*` targets once Terragrunt adoption is complete, or label them clearly as a break-glass path and document the gotcha in `Makefile` help output.

## Error Handling

**Strategy:** Shell `set -euo pipefail` for scripts; Terraform/Packer/Ansible surface their own non-zero exits; no retry logic.

**Patterns:**
- `scripts/_common.sh:5` sets `set -euo pipefail` once for everything that sources it.
- `scripts/_common.sh:38-44` catches a failed `terragrunt output` and prints actionable guidance (`Run 'make tg-apply DEVBOX_USER=… ' first`) before exiting non-zero.
- Lifecycle scripts validate AWS state explicitly: `if [[ "$CURRENT_STATE" == "running" ]]` etc. (`scripts/devbox-start.sh:30-53`, `scripts/devbox-stop.sh:30-49`) — unknown states are refused, not retried.
- Packer fails fast if the `ansible` provisioner returns non-zero; there is no `on_error = "cleanup"` block, so failed builds leave a tagged-but-unsnapshotted instance unless Packer's default cleanup runs.

## Cross-Cutting Concerns

**Logging:** Standard stdout/stderr from each tool. No centralized log aggregation in repo. Build manifest written to `/etc/devimage-manifest.yml` on the baked AMI (`ansible/playbook.yml:71-77`) records `build_date` + active layers.

**Validation:** `make validate` runs `packer validate .` and `terragrunt validate` (`Makefile:37-39`). No schema validation on `ansible/layer_config.yml` — typos silently disable layers via the `| default(...)` filter in `ansible/playbook.yml`.

**Authentication:** AWS credentials resolved by the SDK chain (env vars, `~/.aws/credentials`, instance profile). SSH to the running devbox uses an EC2 key pair (`key_name = "me"` in `terragrunt.hcl:31`). The Terraform module accepts an optional `iam_instance_profile` (`terraform/variables.tf:51-55`) but `terragrunt.hcl` doesn't currently set one.

**Tagging:** Every AWS resource is tagged with `Project=devimage`, `ManagedBy=terraform`, `DevboxUser=<user>` (`terraform/main.tf:18-26`); AMIs add `Builder=packer`, `BaseOS=al2023`, `BuildTime=<ts>` (`packer/devimage.pkr.hcl:46-54`). Useful for cost allocation and lifecycle discovery.

---

*Architecture analysis: 2026-05-13*
