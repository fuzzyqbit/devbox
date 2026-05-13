# External Integrations

**Analysis Date:** 2026-05-13

This repository has exactly one cloud provider (AWS) and no application-level APIs. Every other "integration" is an upstream content source that the AMI build pulls binaries, archives, or RPMs from. They are enumerated below with exact `file:line` citations so the operator can build an allow-list and review provenance.

## APIs & External Services

**Primary cloud — AWS:**
- AWS provider declared as `hashicorp/aws >= 5.0` at `terraform/main.tf:4-9`; configured at `terraform/main.tf:12-14`.
- **EC2** — security group `terraform/main.tf:30-77`, instance `terraform/main.tf:81-99`.
- **EC2 (control plane via AWS CLI)** — start/stop/describe calls in:
  - `scripts/devbox-start.sh:24-69` (`describe-instances`, `start-instances`, `wait instance-running`, `wait instance-status-ok`)
  - `scripts/devbox-stop.sh:24-44` (`describe-instances`, `stop-instances`, `wait instance-stopped`)
  - `scripts/devbox-status.sh:24-28` (`describe-instances` with a JMESPath query)
- **S3** — Terraform state bucket `devimage-tfstate-${local.account_id}` at `terragrunt.hcl:19`.
- **DynamoDB** — Terraform state lock table `devimage-tfstate-locks` at `terragrunt.hcl:23`.
- **STS** — implicitly used by `get_aws_account_id()` at `terragrunt.hcl:3`.
- **AMI marketplace** — Packer source AMI filter pinned to `owners = ["amazon"]`, name `al2023-ami-minimal-*-x86_64` (`packer/devimage.pkr.hcl:27-35`).
- **AWS CLI v2 distribution** — downloaded onto the AMI from `https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip` (`ansible/roles/base/tasks/main.yml:24-28`).

**HashiCorp:**
- Packer plugin registry:
  - `github.com/hashicorp/amazon >= 1.3.0` (`packer/devimage.pkr.hcl:4-7`)
  - `github.com/hashicorp/ansible >= 1.1.0` (`packer/devimage.pkr.hcl:8-10`)
- HashiCorp yum repo for Terraform: `https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo` (`ansible/roles/terraform/tasks/main.yml:3-6`).

**GitHub release downloads (HTTPS, no auth required):**
- `gruntwork-io/terragrunt` v{terragrunt_version} (`ansible/roles/terraform/tasks/main.yml:14-16`)
- `terraform-linters/tflint` v{tflint_version} (`ansible/roles/terraform/tasks/main.yml:20-22`)
- `terraform-docs/terraform-docs` v{terraform_docs_version} (`ansible/roles/terraform/tasks/main.yml:38-40`)
- `opentofu/opentofu` v{tofu_version} (`ansible/roles/terraform/tasks/main.yml:58-60`)
- `derailed/k9s` v{k9s_version} (`ansible/roles/devops/tasks/main.yml:49-51`)
- `eksctl-io/eksctl` v{eksctl_version} (`ansible/roles/devops/tasks/main.yml:70-72`)
- `istio/istio` {istioctl_version} (`ansible/roles/devops/tasks/main.yml:99-101`)
- `astral-sh/uv` {uv_version} (`ansible/roles/python/tasks/main.yml:29-31`)
- `boxboat/fixuid` v{fixuid_version} (`ansible/roles/containers/tasks/main.yml:21-24`)
- `koalaman/shellcheck` v{shellcheck_version} (`ansible/roles/devtools/tasks/main.yml:9-11`)
- `BurntSushi/ripgrep` {ripgrep_version} (`ansible/roles/devtools/tasks/main.yml:37-39`)
- `sharkdp/fd` v{fd_version} (`ansible/roles/devtools/tasks/main.yml:71-73`)
- `sharkdp/bat` v{bat_version} (`ansible/roles/devtools/tasks/main.yml:105-107`)
- `junegunn/fzf` v{fzf_version} (`ansible/roles/devtools/tasks/main.yml:139-141`)
- `mikefarah/yq` v{yq_version} (`ansible/roles/devtools/tasks/main.yml:166-168`)
- `bazelbuild/bazelisk` v{bazelisk_version} (`ansible/roles/devtools/tasks/main.yml:273-277`)
- `nvm-sh/nvm` install script via `raw.githubusercontent.com` (`ansible/roles/devtools/tasks/main.yml:280-284`)
- `novnc/noVNC` archive (`ansible/roles/desktop/tasks/main.yml:107-108`)
- `jesseduffield/lazygit` v{lazygit_version} (`ansible/roles/git/tasks/main.yml:23-25`)
- `dandavison/delta` {delta_version} (`ansible/roles/git/tasks/main.yml:42-44`)
- `coder/code-server` v{code_server_version} RPM (`ansible/roles/vscode/tasks/main.yml:2-4`)

**Language toolchain origins:**
- Go binary tarball — `https://go.dev/dl/go{go_version}.linux-amd64.tar.gz` (`ansible/roles/golang/tasks/main.yml:3-5`).
- Rust installer — `https://sh.rustup.rs` piped to bash (`ansible/roles/rust/tasks/main.yml:3-5`).
- Python — dnf packages `python3*` + PyPI via `pipx` (`ansible/roles/python/tasks/main.yml:3-20`). `uv` comes from GitHub (above).
- Java — JDK from AL2023 dnf (`java-21-amazon-corretto*` `ansible/roles/java/tasks/main.yml:3-6`).
  - Maven from `https://archive.apache.org/dist/maven/maven-3/{maven_version}/...` (`ansible/roles/java/tasks/main.yml:16-18`).
  - Gradle from `https://services.gradle.org/distributions/gradle-{gradle_version}-bin.zip` (`ansible/roles/java/tasks/main.yml:42-44`).
  - IntelliJ IDEA CE from `https://download.jetbrains.com/idea/ideaIC-{intellij_version}.tar.gz` (`ansible/roles/java/tasks/main.yml:68-70`).
  - Eclipse from `https://download.eclipse.org/technology/epp/downloads/release/{eclipse_version}/{eclipse_build}/...` (`ansible/roles/java/tasks/main.yml:115-117`).
- Node.js — dnf packages `nodejs20`, `nodejs20-npm` (`ansible/roles/devtools/defaults/main.yml:3-4`); nvm install script from `https://raw.githubusercontent.com/nvm-sh/nvm/v{nvm_version}/install.sh` (`ansible/roles/devtools/tasks/main.yml:280-284`).

**Kubernetes / cloud-native:**
- kubectl — `https://dl.k8s.io/release/v{kubectl_version}/bin/linux/amd64/kubectl` (`ansible/roles/devops/tasks/main.yml:4-6`).
- Helm — `https://get.helm.sh/helm-v{helm_version}-linux-amd64.tar.gz` (`ansible/roles/devops/tasks/main.yml:19-21`).
- k9s, eksctl, istioctl — see GitHub list above.

**VS Code / code-server:**
- Server binary as RPM from GitHub (above).
- Extensions installed via `code-server --install-extension` (`ansible/roles/vscode/tasks/main.yml:39-44`) — five extensions listed in `ansible/roles/vscode/defaults/main.yml:6-11`. These resolve against the Open VSX or VS Code Marketplace endpoint that code-server is configured to use (default Open VSX; not overridden in this repo).

**Desktop / multimedia:**
- ffmpeg static build — `https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz` (`ansible/roles/desktop/tasks/main.yml:177-180`).
- Flathub remote — `https://dl.flathub.org/repo/flathub.flatpakrepo` (`ansible/roles/desktop/tasks/main.yml:239`).
- VLC — installed via Flatpak app id `org.videolan.VLC` (`ansible/roles/desktop/tasks/main.yml:243`).
- noVNC web client — GitHub archive (above).
- websockify — installed via pip (`ansible/roles/desktop/tasks/main.yml:103-104` area, pip module call).

**Git tooling:**
- GitHub CLI — RPM repo `https://cli.github.com/packages/rpm`; GPG key `https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x23F3D4EA75716059` (`ansible/roles/git/tasks/main.yml:9-19`).
- lazygit, delta — GitHub release downloads (above).

**Misc developer tools:**
- Starship — `https://starship.rs/install.sh` (`ansible/roles/base/tasks/main.yml:55-60`).
- direnv — `https://direnv.net/install.sh` (`ansible/roles/devtools/tasks/main.yml:175-184`).
- Apache Thrift source tarball — `https://archive.apache.org/dist/thrift/{thrift_version}/thrift-{thrift_version}.tar.gz`, built from source (`ansible/roles/devtools/tasks/main.yml:203-262`).
- Sublime Text — GPG key `https://download.sublimetext.com/sublimehq-rpm-pub.gpg`, RPM repo `https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo`, then dnf `sublime-text` (`ansible/roles/devtools/tasks/main.yml:298-313`).

**Operating system base:**
- Amazon Linux 2023 minimal x86_64 source AMI, filter at `packer/devimage.pkr.hcl:28-34` (owner `amazon`).
- All other packages installed via `dnf` from the default AL2023 repos.

## Data Storage

**Databases:**
- None for application data. **DynamoDB** is used solely as a Terraform state lock table (`devimage-tfstate-locks` at `terragrunt.hcl:23`).

**File storage:**
- **S3** — Terraform remote state only.
  - Bucket: `devimage-tfstate-${local.account_id}` (`terragrunt.hcl:19`)
  - Key: `users/${local.user}/devbox.tfstate` (`terragrunt.hcl:20`)
  - Region: `us-east-1` (`terragrunt.hcl:21`)
  - Encrypt: `true` (`terragrunt.hcl:22`)
- **EBS** — root volume snapshots / AMI backing storage (managed by EC2 / Packer; no explicit S3 artifact path).

**Caching:**
- None.

## Authentication & Identity

**Auth providers:**
- **AWS IAM** — standard SDK credential chain (env vars, shared credentials, instance profile). Packer + Terragrunt + AWS CLI all rely on whatever the operator has configured.
- **EC2 instance profile** — optional, supplied via `var.iam_instance_profile` (`terraform/main.tf:87`, `terraform/variables.tf:51-55`).
- **SSH key pair** — `var.key_name` (`terraform/variables.tf:12-15`); operator must hold matching private key at `~/.ssh/${var.key_name}.pem` (`terraform/outputs.tf:16-19`).

**Service auth on the deployed box:**
- **code-server** — password auth via `auth: password` with placeholder password `changeme` (`ansible/roles/vscode/templates/config.yaml.j2`). TLS terminated by `cert: true`, self-signed at first start.
- **VNC** — password `desktop_vnc_password: "changeme"` (`ansible/roles/desktop/defaults/main.yml:7`), stored hashed in `${dev_home}/.vnc/passwd`.
- **noVNC** — self-signed TLS cert generated at provision time via `openssl req -x509 -nodes -newkey rsa:2048 ... -out /etc/novnc/novnc-cert.pem` (`ansible/roles/desktop/tasks/main.yml:143-150`).

**System-level identity hardening (when `hardening` layer is enabled):**
- `authselect select sssd with-sudo` (`ansible/roles/hardening/tasks/main.yml:11-12`).
- Random 32-char root password generated at build time (`ansible/roles/hardening/tasks/main.yml:20-23`).
- SELinux enforcing + FIPS mode (`ansible/roles/hardening/tasks/main.yml:25-37`).

## Monitoring & Observability

**Error tracking:**
- None.

**Logs:**
- `journald` only. `rsyslog-logrotate` is explicitly disabled in the hardening overrides (`ansible/roles/hardening/defaults/main.yml:24` — `amzn2023cis_rule_5_3: false`).
- Journal-remote shipping rules are disabled (`ansible/roles/hardening/defaults/main.yml:19-22`).

**Build provenance:**
- A manifest is written to `/etc/devimage-manifest.yml` at the end of every Packer build (`ansible/playbook.yml:71-77`), capturing `build_date` and the enabled `layers` map.

## CI/CD & Deployment

**Hosting:**
- AWS EC2 in `us-east-1` by default.

**CI pipeline:**
- None in this repo. No `.github/workflows/`, no `.gitlab-ci.yml`, no equivalent.
- The vendored CIS role has its own upstream pre-commit pipeline at `ansible/roles/AMAZON2023-CIS/.pre-commit-config.yaml` (hooks for `pre-commit-hooks`, `detect-secrets`, `gitleaks`, `ansible-lint`, `yamllint`). It is **not** wired into this repo's workflow.

**Deployment entry points:**
- `make build` — builds the AMI (`Makefile:41-42`).
- `make tg-apply` / `make tg-auto-apply` — deploys an EC2 from the AMI (`Makefile:61-65`).
- `make start` / `make stop` / `make status` — lifecycle of the deployed instance (`Makefile:94-101`, scripts under `scripts/`).

## Environment Configuration

**Required env vars:**
- `DEVBOX_USER` — operator's identity used for all per-user scoping. Resolution chain: `--user` flag → env var → `whoami`. Files: `terragrunt.hcl:2`, `Makefile:4`, `scripts/_common.sh:30-34`.
- AWS SDK credentials — provided via env, shared file, or instance profile (no explicit references; standard provider chain).

**Optional env vars:**
- `AWS_REGION` / `AWS_DEFAULT_REGION` — fallback region in `scripts/_common.sh:46-49` (defaults to `us-east-1`).
- `USER` — fallback for `DEVBOX_USER` (`terragrunt.hcl:2`).

**Secrets location:**
- AWS credentials live in the operator's standard AWS SDK locations (env / `~/.aws/credentials` / instance profile). No secrets are stored in this repo.
- `.env*` files are not present at the repo root and are not used.
- Placeholder credentials `changeme` for `code-server` and VNC are committed in plaintext — these are not real secrets but **must** be rotated on first use; see CONCERNS.md (concerns focus, separate document).

## Webhooks & Callbacks

**Incoming:**
- None.

**Outgoing:**
- None initiated by the deployed box. (Outbound HTTPS during *build* fetches the dependencies listed above; outbound on the deployed box is permitted by the SG `egress` rule at `terraform/main.tf:62-68` but no application calls anything.)

## Third-Party Ansible Content

**Galaxy collections** (`ansible/requirements.yml:2-5`):
- `community.general`
- `community.crypto`
- `ansible.posix`

**Vendored role:**
- `ansible/roles/AMAZON2023-CIS/` — third-party role committed in-tree, upstream `ansible-lockdown/AMAZON2023-CIS`, MIT licensed per `ansible/roles/AMAZON2023-CIS/meta/main.yml:7`.
  - Author: Mark Bolwell, MindPoint Group (`ansible/roles/AMAZON2023-CIS/meta/main.yml:4-6`).
  - Min Ansible: `2.10.1` (`ansible/roles/AMAZON2023-CIS/meta/main.yml:10`).
  - Its own collection requirements at `ansible/roles/AMAZON2023-CIS/collections/requirements.yml:1-13` reuse the three above with explicit `source:` git URLs:
    - `https://github.com/ansible-collections/community.general`
    - `https://github.com/ansible-collections/community.crypto`
    - `https://github.com/ansible-collections/ansible.posix`
  - Optional audit binary `goss` referenced at `ansible/roles/AMAZON2023-CIS/vars/audit.yml:9-14` (`https://github.com/goss-org/goss/releases/...`) — not invoked by this repo's playbook, but available if the audit flow is enabled.

**Included playbooks:**
- `ansible/firewalld-docker-fix.yml` — imported by `ansible/playbook.yml:82`. Documented in-file as a temporary workaround (`ansible/firewalld-docker-fix.yml:2-25`).

## Network Egress Allow-List (operator workstation)

The following hosts must be reachable during `make build` so that the Ansible roles can fetch their respective payloads:

- `github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com` (release asset CDN)
- `awscli.amazonaws.com`, `*.amazonaws.com` (AWS APIs + AWS CLI installer)
- `rpm.releases.hashicorp.com`
- `go.dev` (Go tarballs)
- `sh.rustup.rs`, `static.rust-lang.org` (rustup default mirror)
- `dl.k8s.io`, `get.helm.sh`
- `archive.apache.org` (Maven + Thrift), `services.gradle.org` (Gradle)
- `download.jetbrains.com`, `download.eclipse.org`
- `cli.github.com`, `keyserver.ubuntu.com`
- `download.sublimetext.com`
- `dl.flathub.org`
- `johnvansickle.com`
- `direnv.net`, `starship.rs`
- `pypi.org`, `files.pythonhosted.org` (for pipx + pip installs)

The deployed devbox only needs whatever the operator's workloads call out to; no integration in this repo dictates production-side outbound traffic.

---

*Integration audit: 2026-05-13*
