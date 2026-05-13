# Technology Stack

**Analysis Date:** 2026-05-13

This repository is an infrastructure-as-code "devbox" project that builds a custom Amazon Linux 2023 AMI (via Packer + Ansible) and deploys per-user EC2 instances from it (via Terraform/OpenTofu wrapped in Terragrunt). It contains no application source code; the artifacts are declarative configuration in HCL, YAML, and Bash.

## Languages

**Primary (declarative IaC):**
- HCL2 - Used by Terraform, Terragrunt, and Packer.
  - Terraform: `terraform/main.tf`, `terraform/variables.tf`, `terraform/outputs.tf`
  - Terragrunt: `terragrunt.hcl`
  - Packer: `packer/devimage.pkr.hcl`, `packer/variables.pkr.hcl`
- YAML (Ansible) - Used for all provisioning logic.
  - Top-level: `ansible/playbook.yml`, `ansible/requirements.yml`, `ansible/layer_config.yml`, `ansible/firewalld-docker-fix.yml`
  - Roles: `ansible/roles/<layer>/{tasks,defaults,handlers,templates}/*.yml`

**Secondary (orchestration / runtime helpers):**
- Bash (`#!/usr/bin/env bash`, `set -euo pipefail`) - Lifecycle scripts.
  - `scripts/_common.sh` (shared helpers, sourced by others)
  - `scripts/devbox-start.sh`, `scripts/devbox-stop.sh`, `scripts/devbox-status.sh`
- GNU Make - Top-level task runner: `Makefile`
- Jinja2 - Ansible template files: `ansible/roles/vscode/templates/*.j2`, `ansible/roles/desktop/templates/*.j2`

**Languages installed onto the built AMI (not used to author the repo):**
- Python 3 + pipx + uv (`ansible/roles/python/`)
- Go 1.22.5 (`ansible/roles/golang/defaults/main.yml:2`)
- Rust stable via rustup (`ansible/roles/rust/`)
- Java 21 (Amazon Corretto) + Maven 3.9.12 + Gradle 8.10.2 (`ansible/roles/java/defaults/main.yml`)
- Node.js 20 + nvm 0.40.1 (`ansible/roles/devtools/defaults/main.yml:3,9`)

## Runtime

**Local toolchain (operator workstation):**
- Packer with HashiCorp plugins (`packer/devimage.pkr.hcl:1-12`)
  - `github.com/hashicorp/amazon` plugin `>= 1.3.0`
  - `github.com/hashicorp/ansible` plugin `>= 1.1.0`
- Terraform `>= 1.5` (`terraform/main.tf:2`) - actual binary preferred is OpenTofu
- OpenTofu - selected via `terraform_binary = "tofu"` in `terragrunt.hcl:6`
- Terragrunt - wraps Terraform/OpenTofu (`terragrunt.hcl`, all `tg-*` make targets in `Makefile:52-71`)
- Ansible - invoked by Packer's `ansible` provisioner (`packer/devimage.pkr.hcl:60-72`)
- AWS CLI v2 - required by `scripts/devbox-*.sh` (uses `aws ec2 describe-instances`, `aws ec2 wait`, etc.)
- `jq` - required by `scripts/devbox-status.sh:30-35`
- GNU Make - `Makefile`
- Bash 4+ (`#!/usr/bin/env bash` with arrays + `[[ ]]`)

**Provisioning runtime (ephemeral build host EC2):**
- Amazon Linux 2023 minimal x86_64 (source AMI filter in `packer/devimage.pkr.hcl:28-34`)
- `dnf` package manager (used throughout `ansible/roles/*/tasks/main.yml`)
- SSH as `ec2-user` (`packer/devimage.pkr.hcl:37,71`)
- `cloud-init` (waited on in `ansible/playbook.yml:9-12`)

**Deployment runtime (resulting devbox EC2 instance):**
- Amazon Linux 2023 (the baked AMI)
- `systemd` - manages `code-server`, `vncserver`, `novnc`, `docker`, `firewalld` (templates: `ansible/roles/vscode/templates/code-server.service.j2`, `ansible/roles/desktop/templates/vncserver.service.j2`, `ansible/roles/desktop/templates/novnc.service.j2`)
- Default instance type `t3.medium` (`terraform/variables.tf:6-9`, `packer/variables.pkr.hcl:7-11`)
- Default root volume 50 GB gp3 (`terraform/main.tf:90-94`, `terraform/variables.tf:34-38`)

## Package Manager

**Tool plugin managers:**
- `packer init` - downloads required plugins per `packer/devimage.pkr.hcl:1-12`; invoked by `make init` (`Makefile:34-35`).
- `ansible-galaxy` - driven by Packer's `galaxy_file` referencing `ansible/requirements.yml` (`packer/devimage.pkr.hcl:62`).
- No application-level package manifest exists (no `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `requirements.txt`).

**Lockfiles (gitignored, generated locally):**
- `packer/*.pkr.hcl.lock` - `.gitignore:3`
- `terraform/.terraform.lock.hcl` and root `.terraform.lock.hcl` - `.gitignore:7,27`
- `.terragrunt-cache/` - `.gitignore:15`

## Frameworks

**Infrastructure orchestration:**
- Terragrunt - thin wrapper that:
  - Selects the OpenTofu binary (`terragrunt.hcl:6`)
  - Generates an S3+DynamoDB remote-state backend file (`terragrunt.hcl:12-25`)
  - Injects per-user inputs (`terragrunt.hcl:27-37`)
  - Operator-side version is whatever is on the workstation; the AMI bakes Terragrunt `0.67.4` (`ansible/roles/terraform/defaults/main.yml:4`).
- Terraform / OpenTofu - `terraform/` defines a single AWS EC2 + security-group module.

**Image build:**
- Packer with the `amazon-ebs` builder (`packer/devimage.pkr.hcl:19-55`) and the `ansible` provisioner (`packer/devimage.pkr.hcl:60-72`).

**Configuration management:**
- Ansible (community.* collections), driven via roles selected by booleans in `ansible/layer_config.yml`. Role list in `ansible/playbook.yml:14-55`:
  - `base`, `certs`, `git`, `python`, `golang`, `rust`, `java`, `containers`, `terraform`, `devops`, `devtools`, `vscode`, `desktop`, `hardening`
- A vendored security-hardening role: `ansible/roles/AMAZON2023-CIS/` (third-party, see INTEGRATIONS.md).

**Testing:**
- Not detected. No test framework, no `*_test.*` files, no CI workflow files under `.github/`.

**Build / lint helpers (operator-side, run via `make fmt` `Makefile:44-48`):**
- `packer fmt`
- `terraform fmt`
- `terragrunt hclfmt`

**Build / lint helpers (installed onto the AMI):**
- `tflint 0.53.0`, `terraform-docs 0.18.0` (`ansible/roles/terraform/defaults/main.yml:5-6`)
- `shellcheck 0.10.0` (`ansible/roles/devtools/defaults/main.yml:6`)
- `ansible-lint`, `yamllint`, `pre-commit`, `detect-secrets`, `gitleaks` - referenced only by the vendored CIS role's own dev pipeline at `ansible/roles/AMAZON2023-CIS/.pre-commit-config.yaml`; not wired into this repo's workflow.

## Key Dependencies

**Critical (operator must have installed locally):**
- HashiCorp Packer - builds the AMI (`Makefile:34,41`).
- Terragrunt - default IaC entry point for deploys (`Makefile:52-71`).
- OpenTofu (`tofu`) - selected by `terragrunt.hcl:6`.
- AWS CLI v2 - required by all lifecycle scripts.
- `jq` - required by `scripts/devbox-status.sh`.
- Ansible (>= 2.10.1 per CIS role meta `ansible/roles/AMAZON2023-CIS/meta/main.yml:10`) - invoked by Packer.

**Critical (installed onto the AMI by the `base` role):**
- AWS CLI v2 (`ansible/roles/base/tasks/main.yml:23-49`)
- Starship prompt (`ansible/roles/base/tasks/main.yml:51-73`)
- Core build packages: `gcc`, `gcc-c++`, `cmake`, `make`, `openssl-devel`, `zlib-devel`, etc. (`ansible/roles/base/defaults/main.yml:4-37`)
- jq, htop, tmux, tree, strace, lsof, net-tools, bind-utils, etc. (same file)

**Infrastructure (per-layer, installed onto the AMI):**
- Python: `pipx`; pipx tools `poetry`, `ruff`, `black`, `mypy`; `uv 0.5.11` (`ansible/roles/python/defaults/main.yml:4-15`).
- Go: `1.22.5` from go.dev (`ansible/roles/golang/defaults/main.yml:2`).
- Rust: `stable` toolchain via rustup, components `clippy`, `rustfmt`, `rust-src`, `rust-analyzer` (`ansible/roles/rust/defaults/main.yml`).
- Java: `java-21-amazon-corretto[-devel]`, Maven `3.9.12`, Gradle `8.10.2`, IntelliJ IDEA CE `2024.3.1.1`, Eclipse `2024-12-R` (`ansible/roles/java/defaults/main.yml`).
- Containers: `docker`, `fixuid 0.6.0` (`ansible/roles/containers/defaults/main.yml`).
- HashiCorp tools: Terraform (latest from HashiCorp yum repo), Terragrunt `0.67.4`, tflint `0.53.0`, terraform-docs `0.18.0`, OpenTofu `1.9.0` (`ansible/roles/terraform/defaults/main.yml`).
- Kubernetes / cloud-native: kubectl `1.31.3`, Helm `3.16.3`, k9s `0.32.7`, eksctl `0.194.0`, istioctl `1.24.2` (`ansible/roles/devops/defaults/main.yml`).
- Git tooling: `git`, `git-lfs`, GitHub CLI `gh`, lazygit `0.44.1`, git-delta `0.18.2` (`ansible/roles/git/defaults/main.yml`).
- Devtools: Node.js 20 + npm (dnf), protobuf-compiler, ShellCheck `0.10.0`, Thrift `0.21.0` (built from source), bazelisk `1.25.0`, nvm `0.40.1`, direnv (latest), fzf `0.55.0`, bat `0.24.0`, fd `10.2.0`, ripgrep `14.1.1`, yq `4.44.3`, Sublime Text (latest from official repo) (`ansible/roles/devtools/defaults/main.yml`, `ansible/roles/devtools/tasks/main.yml`).
- VS Code: `code-server 4.93.1`, extensions `ms-python.python`, `golang.go`, `hashicorp.terraform`, `redhat.vscode-yaml`, `esbenp.prettier-vscode` (`ansible/roles/vscode/defaults/main.yml:1-11`).
- Desktop: GNOME (`@Desktop` group), tigervnc-server, noVNC `1.5.0`, websockify (pip), ffmpeg static, VLC via Flatpak (`ansible/roles/desktop/defaults/main.yml:9`, `ansible/roles/desktop/tasks/main.yml`).
- Hardening: `ansible-lockdown/AMAZON2023-CIS` (vendored under `ansible/roles/AMAZON2023-CIS/`), plus `authselect`, `crypto-policies-scripts`, `aide`, SELinux enforcing, FIPS mode (`ansible/roles/hardening/tasks/main.yml`).

**Ansible Galaxy collections** (`ansible/requirements.yml:2-5`):
- `community.general`
- `community.crypto`
- `ansible.posix`

## Configuration

**Environment (operator-side):**
- `DEVBOX_USER` - per-user scoping for resources, Terragrunt state key, S3 bucket subpath, etc. Resolved by `terragrunt.hcl:2`, `scripts/_common.sh:30-34`, `Makefile:4`. Falls back to `$USER`, then `whoami`, then `default`.
- `AWS_REGION` / `AWS_DEFAULT_REGION` - fallback region in `scripts/_common.sh:46-49` (defaults to `us-east-1`).
- Standard AWS SDK env vars / profile / IAM role chain (for both Packer and Terraform/Terragrunt).
- `ANSIBLE_HOST_KEY_CHECKING`, `ANSIBLE_SSH_TRANSFER_METHOD`, `ANSIBLE_SSH_ARGS` - passed to Ansible by Packer (`packer/devimage.pkr.hcl:66-70`).

**Configuration files (this repo):**
- `terragrunt.hcl` - remote-state backend + Terraform inputs.
- `terraform/variables.tf` - Terraform input contract.
- `terraform/main.tf` - AWS provider, SG, EC2 instance.
- `terraform/outputs.tf` - emits `instance_id`, `public_ip`, `private_ip`, `ssh_command`, `code_server_url`, `novnc_url`, `aws_region`, `devbox_user`, etc.
- `packer/devimage.pkr.hcl` - Packer build + provisioner.
- `packer/variables.pkr.hcl` - Packer input contract.
- `ansible/layer_config.yml` - the on/off switches for each Ansible role.
- `ansible/playbook.yml` - role ordering.
- `ansible/firewalld-docker-fix.yml` - post-playbook workaround (imported at `ansible/playbook.yml:82`).
- `Makefile` - canonical task runner.
- `.gitignore` - lists local artifacts that must not be committed.

**Configuration files generated locally (gitignored, never read here):**
- `terraform/backend.tf` - generated by Terragrunt at runtime (`terragrunt.hcl:13-16`).
- `terraform/terraform.tfvars`, `terraform/terraform.tfstate*` - listed in `.gitignore:8-11`.
- `.terragrunt-cache/`, `packer/packer_cache/` - tool caches.

**Per-deployment configuration (hard-coded inputs in `terragrunt.hcl:27-37`):**
- `ami_id = "ami-0b7cfe2135f319a55"`
- `key_name = "me"`
- `subnet_id = "subnet-07513680b824b3dbe"`
- `vpc_id = "vpc-0dafcc61f21dac9cd"`
- `instance_type = "t3.medium"`
- `root_volume_size = 50`
- `aws_region = "us-east-1"`

## Platform Requirements

**Development (operator workstation):**
- macOS or Linux with Bash 4+, GNU Make.
- Packer, Terragrunt, OpenTofu (or Terraform), Ansible, AWS CLI v2, `jq` on `$PATH`.
- AWS credentials with permissions for EC2 (run/stop/start/describe), S3 (state bucket), DynamoDB (lock table), and IAM (optional, for `iam_instance_profile`).
- SSH key pair name configured in `terragrunt.hcl:30` (currently `key_name = "me"`); matching private key at `~/.ssh/<key_name>.pem` per the `ssh_command` output (`terraform/outputs.tf:18`).
- Network egress to a wide set of upstream hosts (GitHub, AWS, HashiCorp, Apache, JetBrains, Eclipse, Flathub, etc.). See INTEGRATIONS.md for the full enumerated list.

**Production (built AMI / EC2 deployment):**
- AWS account with an existing VPC, subnet, and EC2 key pair (referenced by ID/name in `terragrunt.hcl:30-32`).
- S3 bucket `devimage-tfstate-<account_id>` and DynamoDB table `devimage-tfstate-locks` (auto-managed by Terragrunt per `terragrunt.hcl:19-23`).
- Region `us-east-1` (default; `terraform/variables.tf:17-21`).
- Security group opens TCP `22` (SSH), `8080` (code-server), `6080` (noVNC) to `0.0.0.0/0` (`terraform/main.tf:36-60`). The operator's network must reach these from wherever they connect.

---

*Stack analysis: 2026-05-13*
