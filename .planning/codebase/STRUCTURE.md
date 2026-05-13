# Codebase Structure

**Analysis Date:** 2026-05-13

## Directory Layout

```
devbox/
├── Makefile                       # Operator entry point (build / tg-* / start|stop|status / clean)
├── terragrunt.hcl                 # State backend + Terraform inputs (per-user S3 key)
├── CLAUDE.md                      # Empty placeholder for project-specific Claude notes
├── .gitignore                     # Excludes terraform/.terraform, *.tfstate, packer_cache, .terragrunt-cache, .claude
├── .planning/
│   └── codebase/                  # GSD codebase maps (this directory)
├── packer/
│   ├── devimage.pkr.hcl           # AL2023 source + Ansible provisioner + AMI build block
│   └── variables.pkr.hcl          # Packer input vars (region, instance_type, ami_name_prefix, …)
├── terraform/
│   ├── main.tf                    # aws_security_group.devbox + aws_instance.devbox
│   ├── outputs.tf                 # instance_id, public_ip, ssh_command, code_server_url, novnc_url, aws_region, devbox_user, …
│   └── variables.tf               # ami_id, key_name, vpc_id, subnet_id, devbox_user, …
├── ansible/
│   ├── playbook.yml               # Master playbook — 14 layered roles + post-import of firewalld fix
│   ├── firewalld-docker-fix.yml   # Post-playbook workaround setting firewalld default zone = docker
│   ├── layer_config.yml           # Toggle map: layers.<name> = true|false
│   ├── requirements.yml           # Galaxy collections (community.general, community.crypto, ansible.posix)
│   └── roles/
│       ├── base/                  # System packages, AWS CLI v2, Starship, sysctl tuning
│       ├── certs/                 # Custom CA cert install + SSL env vars (drop files into roles/certs/files/ca-certs/)
│       ├── git/                   # Git toolchain
│       ├── python/                # Python runtime layer
│       ├── golang/                # Go runtime layer
│       ├── rust/                  # Rust runtime layer
│       ├── java/                  # Java (Amazon Corretto) layer
│       ├── containers/            # Docker / container runtime
│       ├── terraform/             # Terraform CLI on the image
│       ├── devops/                # DevOps tooling layer
│       ├── devtools/              # General developer tools
│       ├── vscode/                # code-server install + config template + handlers
│       ├── desktop/               # XFCE + noVNC desktop stack with templates + handlers
│       ├── hardening/             # CIS hardening, SELinux enforcing, FIPS, mid-bake reboot
│       └── AMAZON2023-CIS/        # Vendored upstream CIS Galaxy role (full layout)
└── scripts/
    ├── _common.sh                 # Shared: parse_args, resolve_user, resolve_instance, init_devbox
    ├── devbox-start.sh            # aws ec2 start-instances + wait + connection info
    ├── devbox-stop.sh             # aws ec2 stop-instances + wait
    └── devbox-status.sh           # aws ec2 describe-instances → JSON → jq → printout
```

## Directory Purposes

**`packer/`:**
- Purpose: Image-bake configuration
- Contains: HCL2 Packer templates that filter the source AL2023 AMI, declare an Ansible provisioner, and tag the output
- Key files: `packer/devimage.pkr.hcl`, `packer/variables.pkr.hcl`

**`terraform/`:**
- Purpose: Per-user EC2 + security group provisioning module (called by Terragrunt)
- Contains: One small module — two resources, one provider block, one locals block, and the outputs that scripts consume
- Key files: `terraform/main.tf`, `terraform/outputs.tf`, `terraform/variables.tf`

**`ansible/`:**
- Purpose: Host configuration applied during the Packer bake
- Contains: A master playbook, the layer-toggle config, Galaxy collection requirements, a firewalld workaround playbook, and the roles tree
- Key files: `ansible/playbook.yml`, `ansible/layer_config.yml`, `ansible/firewalld-docker-fix.yml`, `ansible/requirements.yml`

**`ansible/roles/`:**
- Purpose: One directory per opt-in image layer (runtime, tool, hardening)
- Contains: 15 first-party roles + one vendored upstream role (`AMAZON2023-CIS`)
- Key files: each role has `tasks/main.yml` and (for first-party roles) `defaults/main.yml`; `vscode` and `desktop` add `templates/` + `handlers/`; `certs` adds `files/`

**`ansible/roles/AMAZON2023-CIS/`:**
- Purpose: Vendored upstream Galaxy role implementing Amazon Linux 2023 CIS benchmarks
- Contains: Full Galaxy layout — `tasks/section_1`–`section_6`, `vars/`, `defaults/`, `handlers/`, `templates/`, `collections/`, `meta/`, `site.yml`, `CONTRIBUTING.rst`, `Changelog.md`, `LICENSE`, `README.md`
- Key files: `ansible/roles/AMAZON2023-CIS/tasks/main.yml`, included via `ansible/roles/hardening/tasks/main.yml:31-34`

**`scripts/`:**
- Purpose: Day-2 lifecycle operations against an already-provisioned instance
- Contains: One sourced helper plus three end-user scripts that resolve user + instance via Terragrunt outputs, then drive `aws ec2`
- Key files: `scripts/_common.sh`, `scripts/devbox-start.sh`, `scripts/devbox-stop.sh`, `scripts/devbox-status.sh`

**`.planning/codebase/`:**
- Purpose: GSD-generated codebase maps (this document + `ARCHITECTURE.md`, and future focus-area documents)
- Contains: One Markdown file per generated map

**Project root:**
- Purpose: Operator surface (`Makefile`) and Terragrunt root (`terragrunt.hcl`)
- Contains: Top-level dotfiles, `CLAUDE.md` placeholder, and the four IaC subdirectories

## Key File Locations

**Entry Points:**
- `Makefile`: All operator commands; every target threads `DEVBOX_USER=$(DEVBOX_USER)` (`Makefile:4`, `Makefile:53-101`)
- `scripts/devbox-start.sh`, `scripts/devbox-stop.sh`, `scripts/devbox-status.sh`: Instance lifecycle entry points invoked from `Makefile:95-101`

**Configuration:**
- `terragrunt.hcl`: AMI ID, key pair, VPC/subnet, region, instance type, root volume size, state backend
- `ansible/layer_config.yml`: Layer toggles consumed via `--extra-vars @…` from `packer/devimage.pkr.hcl:63-64`
- `ansible/requirements.yml`: Galaxy collections installed by the Packer Ansible provisioner
- `packer/variables.pkr.hcl`: Build-time inputs (region, instance_type, ami_name_prefix, vpc_id, subnet_id, volume_size, extra_tags)
- `terraform/variables.tf`: Per-instance Terraform inputs (ami_id, key_name, vpc_id, subnet_id, devbox_user, …)

**Core Logic:**
- `terraform/main.tf`: SG + EC2 resource definitions, tag merging
- `packer/devimage.pkr.hcl`: Source AMI filter, Ansible provisioner block, AMI snapshot tags
- `ansible/playbook.yml`: Role sequence, cloud-init wait, post-build cleanup, manifest write
- `ansible/firewalld-docker-fix.yml`: Post-import workaround for code-server/noVNC reachability (flagged in-file as temporary)

**Testing:**
- Not applicable — no test harness committed. `make validate` (`Makefile:37-39`) runs `packer validate .` + `terragrunt validate` as static checks.

**State / generated (gitignored):**
- `terraform/backend.tf`: Generated by Terragrunt on each `init` (`terragrunt.hcl:14-17`)
- `terraform/.terraform/`, `terraform/.terraform.lock.hcl`, `terraform/terraform.tfstate*`: Terraform working files
- `.terragrunt-cache/`: Terragrunt scratch
- `packer/packer_cache/`: Packer plugin cache
- Remote state objects under `s3://devimage-tfstate-<account>/users/<user>/devbox.tfstate`

## Naming Conventions

**Files:**
- Shell scripts: `lowercase-with-hyphens.sh` (`devbox-start.sh`, `devbox-stop.sh`, `devbox-status.sh`); leading underscore for sourced-only files (`_common.sh`)
- YAML playbooks: `lowercase-with-hyphens.yml` (`firewalld-docker-fix.yml`); Ansible role internal files are conventionally `main.yml`
- Ansible config YAML: `lower_snake_case.yml` (`layer_config.yml`, `requirements.yml`)
- Packer: `lowercase.pkr.hcl` (`devimage.pkr.hcl`, `variables.pkr.hcl`)
- Terraform: `lowercase.tf` (`main.tf`, `variables.tf`, `outputs.tf`)
- Terragrunt root: `terragrunt.hcl`

**Directories:**
- Lowercase, single-word role names (`base`, `python`, `golang`, `hardening`)
- The vendored upstream role keeps its shipped name `AMAZON2023-CIS` (uppercase + digits + hyphen); do not rename it — `ansible/roles/hardening/tasks/main.yml:33` references it literally

**HCL (Terraform / Terragrunt / Packer):**
- Variables, locals, attributes: `snake_case` (`aws_region`, `name_prefix`, `common_tags`, `root_volume_size`)
- Resource labels: `snake_case` (`aws_instance.devbox`, `aws_security_group.devbox`)
- Locals named after their purpose, not their type (`name_prefix`, `ami_name`, `timestamp`)

**Shell:**
- Environment variables: `UPPER_SNAKE_CASE` (`DEVBOX_USER`, `INSTANCE_ID`, `REGION`, `PROJECT_DIR`, `TF_DIR`, `TG_DIR`)
- Functions: `lower_snake_case` (`parse_args`, `resolve_user`, `resolve_instance`, `init_devbox`, `usage`)
- Long-flag CLI: `--user`, `--instance-id`, `--region`, `--help` (mirrors `aws ec2` style)

**YAML / Ansible:**
- Role-scoped variables: `<role>_<thing>` (`base_packages`, `awscli_install`, `starship_install`, `dev_user`, `dev_home`)
- CIS overrides keep the upstream prefix `amzn2023cis_…` (`ansible/roles/hardening/defaults/main.yml`)
- Layer toggles: `layers.<rolename>` boolean map (`ansible/layer_config.yml`)
- Task `name:` fields use sentence case ("Update all packages", "Install AWS CLI v2")

**AWS resources:**
- Tags use `PascalCase` keys: `Project`, `ManagedBy`, `DevboxUser`, `Builder`, `BaseOS`, `BuildTime` (`terraform/main.tf:18-26`, `packer/devimage.pkr.hcl:46-54`)
- AMI Name: `devimage-al2023-<YYYYMMDDhhmmss>` (`packer/devimage.pkr.hcl:14-17`)
- EC2 Name tag: `${devbox_user}-${instance_name}` → e.g. `jsmith-devbox` (`terraform/main.tf:17, 97`)
- Security group name prefix: `${devbox_user}-${instance_name}-` plus a `-sg` Name tag (`terraform/main.tf:31, 71`)
- S3 state bucket: `devimage-tfstate-<aws_account_id>`; lock table: `devimage-tfstate-locks` (`terragrunt.hcl:19-23`)

## Where to Add New Code

**New runtime / tool layer (e.g. Node.js):**
1. Create `ansible/roles/nodejs/tasks/main.yml` and `ansible/roles/nodejs/defaults/main.yml`
2. Add a role block in `ansible/playbook.yml:14-55` with `when: layers.nodejs | default(false)`
3. Add `nodejs: true` (or `false`) to `ansible/layer_config.yml`
4. Rebuild the AMI: `make build`

**New Ansible collection:**
- Append it to `ansible/requirements.yml` — the Packer provisioner installs from this file at build time (`packer/devimage.pkr.hcl:62`)

**New AWS resource (e.g. Elastic IP):**
1. Add the `resource` block to `terraform/main.tf`
2. Expose any operator-relevant value in `terraform/outputs.tf` (lifecycle scripts can then read it via `terragrunt output -raw <name>`)
3. If it needs configuration, add a `variable` to `terraform/variables.tf` and a value to the `inputs` block in `terragrunt.hcl:27-37`

**New Terragrunt-level input:**
- Add the key to `terragrunt.hcl`'s `inputs` map (`terragrunt.hcl:27-37`) **and** declare a matching `variable` in `terraform/variables.tf`. Terraform fails fast if the variable is undeclared.

**New operator command:**
- Add a phony target near the existing groupings in `Makefile`, list it in `.PHONY:` (`Makefile:1`), and forward `DEVBOX_USER=$(DEVBOX_USER)` if the underlying script or tool reads it

**New lifecycle script:**
- Create `scripts/devbox-<verb>.sh`, mark executable, source `scripts/_common.sh`, define `usage()`, call `parse_args "$@"` then `init_devbox`, then implement the `aws ec2 …` logic. Mirror the structure of `scripts/devbox-start.sh:1-21` and `scripts/devbox-stop.sh:1-21`
- Wire it from `Makefile` as another phony target

**Custom CA certificates for the image:**
- Drop `*.crt` or `*.pem` files into `ansible/roles/certs/files/ca-certs/` before `make build`. The `certs` role copies them into `/etc/pki/ca-trust/source/anchors/` and runs `update-ca-trust extract` (`ansible/roles/certs/tasks/main.yml:1-19`)

**Tightening the firewall (long-term fix):**
- Modify `ansible/roles/hardening/defaults/main.yml` CIS toggles and remove the `import_playbook` line at `ansible/playbook.yml:82` — see the "Anti-Patterns" section in `ARCHITECTURE.md`

## Special Directories

**`ansible/roles/AMAZON2023-CIS/`:**
- Purpose: Vendored upstream Galaxy role; provides Amazon Linux 2023 CIS benchmark remediation
- Generated: No
- Committed: Yes
- Modification policy: Treat as third-party. Override via `ansible/roles/hardening/defaults/main.yml` rather than editing in place. Included by `ansible/roles/hardening/tasks/main.yml:31-34`

**`.planning/codebase/`:**
- Purpose: GSD codebase-map output (this file's home)
- Generated: Yes — produced by `/gsd-map-codebase`
- Committed: Yes

**`packer/packer_cache/`:**
- Purpose: Packer plugin downloads, populated by `packer init`
- Generated: Yes
- Committed: No (`.gitignore`)
- Reset via `make clean` (`Makefile:106`)

**`terraform/.terraform/`, `terraform/.terraform.lock.hcl`:**
- Purpose: Terraform provider plugins and lock metadata
- Generated: Yes (by `terraform init` / `terragrunt init`)
- Committed: No (`.gitignore`)
- Reset via `make clean` (`Makefile:107`)

**`terraform/backend.tf`:**
- Purpose: Backend configuration injected by Terragrunt
- Generated: Yes — written on every `terragrunt init` (`terragrunt.hcl:14-17`)
- Committed: No (`.gitignore`)
- Never hand-edit; changes belong in `terragrunt.hcl`

**`.terragrunt-cache/`:**
- Purpose: Terragrunt working tree for the Terraform module
- Generated: Yes
- Committed: No (`.gitignore`)

**`.claude/`:**
- Purpose: Per-user Claude Code settings
- Generated: Yes
- Committed: No (`.gitignore`)

---

*Structure analysis: 2026-05-13*
