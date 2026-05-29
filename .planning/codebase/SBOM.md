<!-- generated: 2026-05-14; versions stripped 2026-05-29 -->
# devbox AMI — Software Bill of Materials (planned)

This is the **planned / static** SBOM. It is derived from `ansible/roles/*/defaults/main.yml` and `ansible/requirements.yml` — i.e. what the bake **intends** to install. The actual runtime SBOM (post-bake) is produced by `./run sbom` and written to `/etc/devbox/sbom.json` on the running EC2 (see §SBOM Generation below).

**Note on versions:** this file lists **components only**, not pinned versions. Versions drift faster than this doc — single sources of truth for pins live in `ansible/roles/*/defaults/main.yml`, `ansible/requirements.yml`, and `terraform/.terraform.lock.hcl`. The runtime `/etc/devbox/sbom.json` (CycloneDX) carries actual installed versions per-bake.

**SBOM format:** human-readable layered manifest here; CycloneDX JSON v1.5 at runtime via `syft`.

**AMI base:** Amazon Linux 2023 minimal x86_64 — pinned via AWS SSM Parameter Store path `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64` (Phase 3 REP-04; `:NN` version suffix follow-up deferred).

**Layer model:** Roles run in the order in `ansible/playbook.yml` and are gated by `ansible/layer_config.yml`. Every layer below is conditional; an operator can opt out (e.g. skip `java` if they don't write JVM code). The `hardening` layer always runs last and applies the vendored Amazon Linux 2023 CIS role with overrides documented in `ansible/roles/hardening/defaults/main.yml`.

---

## 1. Base image (`base` role)

| Component | Provenance | Notes |
|-----------|------------|-------|
| Amazon Linux 2023 minimal | AWS public AMI via SSM `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64` | x86_64; pin `:NN` suffix is Phase 3 deferred follow-up |
| Linux kernel | `dnf` (AL2023 repo) | LTS kernel from AL2023 |
| systemd | `dnf` (AL2023 repo) | manages all baked services |
| cloud-init | `dnf` (AL2023 repo) | first-boot orchestration |
| amazon-ssm-agent | `dnf` (preinstalled in AL2023 AMI) | enables `./run devbox-ssm` (Phase 2 NET-04) |
| aws CLI v2 | upstream installer (`https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip`) | `awscli_install: true` |
| starship prompt | upstream installer (`https://starship.rs/install.sh`) | `starship_install: true` |

**dnf packages (base):**
`wget`, `unzip`, `tar`, `gzip`, `bzip2`, `xz`, `jq`, `htop`, `tmux`, `tree`, `make`, `cmake`, `gcc`, `gcc-c++`, `openssl-devel`, `zlib-devel`, `bzip2-devel`, `readline-devel`, `sqlite-devel`, `libffi-devel`, `xz-devel`, `ncurses-devel`, `patch`, `diffutils`, `which`, `man-db`, `bash-completion`, `procps-ng`, `net-tools`, `bind-utils`, `iputils`, `strace`, `lsof`, `socat`

Source: `ansible/roles/base/defaults/main.yml`

---

## 2. Certs (`certs` role)

System CA bundle plus `/etc/profile.d/ca-trust.sh` exporting `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS` to point at the merged store. No new packages.

---

## 3. Git tooling (`git` role)

| Component | Source |
|-----------|--------|
| `git` | `dnf` (AL2023 repo) |
| `git-lfs` | `dnf` (AL2023 repo) |
| `gh` (GitHub CLI) | upstream rpm (`https://cli.github.com/packages/rpm/gh-cli.repo`); `gh_cli_install: true` |
| `lazygit` | upstream release tarball (`https://github.com/jesseduffield/lazygit/releases`) |
| `delta` (git pager) | upstream release tarball (`https://github.com/dandavison/delta/releases`) |

---

## 4. Python (`python` role)

| Component | Source |
|-----------|--------|
| `python3` + `python3-pip` + `python3-devel` + `python3-setuptools` | `dnf` (AL2023 repo) |
| `uv` | upstream installer (`https://astral.sh/uv/install.sh`) |
| `pipx` | `pip` → user-local (PyPI) |
| `poetry`, `ruff`, `black`, `mypy` | `pipx install` from PyPI (per-tool isolated venvs) |
| `virtualenvwrapper` | user-local `pip` (PyPI) — Phase 0 WIP fix: per-user install under `dev_user`; system-wide install was unreadable under CIS umask 027 |

---

## 5. Go (`golang` role)

| Component | Source |
|-----------|--------|
| Go toolchain | upstream tarball (`https://go.dev/dl/`) → `/usr/local/go` |

---

## 6. Rust (`rust` role)

| Component | Source |
|-----------|--------|
| `rustc` + `cargo` (stable channel) | `rustup` per-user (`https://sh.rustup.rs`) |
| `clippy`, `rustfmt`, `rust-src`, `rust-analyzer` | `rustup component add` (matching toolchain) |

---

## 7. JVM (`java` role)

| Component | Source |
|-----------|--------|
| Amazon Corretto 21 (`java-21-amazon-corretto-devel`, `java-21-amazon-corretto`) | `dnf` (AL2023 repo) |
| Apache Maven | upstream tarball (`https://dlcdn.apache.org/maven/maven-3/`) |
| Gradle | upstream tarball (`https://services.gradle.org/distributions/`) |
| IntelliJ IDEA Community | upstream tarball (`https://download.jetbrains.com/idea/`) |
| Eclipse | upstream tarball (`https://www.eclipse.org/downloads/packages/`) |

---

## 8. Containers (`containers` role)

| Component | Source |
|-----------|--------|
| Docker Engine + CLI | `dnf` (AL2023 repo — `docker` package) |
| `fixuid` | upstream release tarball (`https://github.com/boxboat/fixuid/releases`) |

Networking: see `ansible/firewalld-docker-fix.yml` (Phase 0 WIP, documented retirement criteria in Phase 4 DOC-02 — `firewall-cmd --get-default-zone` to verify).

---

## 9. IaC tooling (`terraform` role)

| Component | Source |
|-----------|--------|
| HashiCorp Terraform | upstream zip (`https://releases.hashicorp.com/terraform/`) |
| OpenTofu | upstream tarball (`https://github.com/opentofu/opentofu/releases`) |
| `tflint` | upstream zip (`https://github.com/terraform-linters/tflint/releases`) |
| `terraform-docs` | upstream tarball (`https://github.com/terraform-docs/terraform-docs/releases`) |

**Note:** operator workstation tofu version must satisfy the committed `terraform/.terraform.lock.hcl` (Phase 3 REP-01). The lockfile records `hashicorp/aws ~> 6.0` with 4 platform hashes; resolved patch version lives in the lockfile, not here.

**Phase 5 (May 2026):** Terragrunt removed. Makefile drives `tofu` directly; backend wired via partial `terraform/backend.tf` + `-backend-config` flags at init time.

---

## 10. DevOps / Kubernetes (`devops` role)

| Component | Source |
|-----------|--------|
| `kubectl` | upstream binary (`https://dl.k8s.io/release/`) |
| `helm` | upstream binary (`https://get.helm.sh/`) |
| `k9s` | upstream tarball (`https://github.com/derailed/k9s/releases`) |
| `eksctl` | upstream tarball (`https://github.com/eksctl-io/eksctl/releases`) |
| `istioctl` | upstream tarball (`https://github.com/istio/istio/releases`) |

---

## 11. Dev tools (`devtools` role)

| Component | Source |
|-----------|--------|
| Node.js 20 + npm | `dnf` module `nodejs20`, `nodejs20-npm` (AL2023 repo) |
| `nvm` | upstream installer per-user (`https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh`) |
| `protobuf-compiler` | `dnf` (AL2023 repo) |
| `shellcheck` | upstream tarball (`https://github.com/koalaman/shellcheck/releases`) |
| `thrift` | upstream tarball (`https://dlcdn.apache.org/thrift/`) |
| `bazelisk` | upstream binary (`https://github.com/bazelbuild/bazelisk/releases`) |
| `direnv` | upstream installer (`https://direnv.net/install.sh`) |
| `fzf` | upstream tarball (`https://github.com/junegunn/fzf/releases`) |
| `bat` | upstream tarball (`https://github.com/sharkdp/bat/releases`) |
| `fd` | upstream tarball (`https://github.com/sharkdp/fd/releases`) |
| `ripgrep` | upstream tarball (`https://github.com/BurntSushi/ripgrep/releases`) |
| `yq` | upstream binary (`https://github.com/mikefarah/yq/releases`) |

---

## 12. Secrets (`secrets` role)

No packages installed. Generates per-build random secrets:

| Secret | Length | Charset | Destination |
|--------|--------|---------|-------------|
| `code_server_password` | 32 | ASCII letters + digits | SSM Parameter Store `/devbox/${devbox_user}/code-server-password` (SecureString) |
| `desktop_vnc_password` | 8 | ASCII letters + digits | SSM Parameter Store `/devbox/${devbox_user}/vnc-password` (SecureString); VNC wire protocol truncates to 8 chars regardless |

Per-build randomization happens at AMI bake; no rotation Lambda. Fetched at boot by systemd oneshot (Phase 1 SEC-03).

---

## 13. code-server (`vscode` role)

| Component | Source |
|-----------|--------|
| `code-server` | upstream RPM from Coder Inc. (`https://github.com/coder/code-server/releases`) |
| VS Code extensions (pre-installed) | `code-server --install-extension` (Open VSX / VS Code Marketplace) |

**Extensions baked:**
- `ms-python.python`
- `golang.go`
- `hashicorp.terraform`
- `redhat.vscode-yaml`
- `esbenp.prettier-vscode`

**Service:** `code-server.service` (systemd) bound to `0.0.0.0:8080`; password sourced from SSM at boot.

---

## 14. Desktop / VNC (`desktop` role)

| Component | Source |
|-----------|--------|
| `@Desktop` (dnf group) | `dnf` (AL2023 repo) |
| `gnome-shell` | `dnf` (AL2023 repo) |
| `tigervnc-server` | `dnf` (AL2023 repo) |
| `dejavu-sans-fonts` + `dejavu-sans-mono-fonts` | `dnf` (AL2023 repo) |
| `mesa-dri-drivers` | `dnf` (AL2023 repo) |
| noVNC | upstream tarball (`https://github.com/novnc/noVNC/releases`) |

**Services:** `vncserver@:1.service`, `novnc.service`.
**Known gap:** `gnome-session` not explicitly listed; relies on `@Desktop` group resolution. If the dnf group doesn't pull it, GNOME sessions fail to start. See §Known Concerns.

---

## 15. Hardening (`hardening` role — runs LAST)

| Component | Source | Purpose |
|-----------|--------|---------|
| `authselect` | `dnf` (AL2023 repo) | PAM profile selector |
| `crypto-policies-scripts` | `dnf` (AL2023 repo) | system crypto policy |
| `aide` | `dnf` (AL2023 repo) | (config disabled via `amzn2023cis_config_aide: false`; package still installed) |
| SELinux | baked into AL2023 kernel/userspace (not installed separately) | enforcing mode (set in `/etc/selinux/config`) |
| FIPS mode | `fips-mode-setup --enable` (shipped with AL2023 `crypto-policies-scripts`) | requires reboot (role triggers) |
| Vendored AMAZON2023-CIS role | git clone (`https://github.com/ansible-lockdown/AMAZON2023-CIS`) at tagged ref | Level 1 + selected Level 2 controls; tagged release matches Galaxy collections |

**Overrides** (`ansible/roles/hardening/defaults/main.yml`):
- Firewall (3.4.x): all rules disabled — EC2 security groups provide perimeter security
- Journal remote (5.1.2.1.x): disabled — single-node devbox doesn't ship logs offsite
- Logrotate (5.3): disabled — journald not rsyslog
- AIDE config (`amzn2023cis_config_aide`): disabled
- **CIS 2.2.1**: still ON by default (`amzn2023cis_rule_2_2_1: true`) — removes `xorg-x11-server-common`. This conflicts with the desktop layer. See §Known Concerns.

---

## 16. Galaxy collections (Ansible runtime only — not in AMI)

| Collection | Source |
|------------|--------|
| `community.general` | Ansible Galaxy (`https://galaxy.ansible.com/community/general`) via `ansible-galaxy collection install` |
| `community.crypto` | Ansible Galaxy (`https://galaxy.ansible.com/community/crypto`) via `ansible-galaxy collection install` |
| `ansible.posix` | Ansible Galaxy (`https://galaxy.ansible.com/ansible/posix`) via `ansible-galaxy collection install` |
| `community.aws` | Ansible Galaxy (`https://galaxy.ansible.com/community/aws`) — held; bump deferred (raises ansible-core floor) |

Pinned versions live in `ansible/requirements.yml` (with `==X.Y.Z` enforced by the REP-02 grep-gate). Vendored CIS role collections (git-sourced, tagged refs in `ansible/roles/AMAZON2023-CIS/collections/requirements.yml`) pin to identical versions.

---

## 17. Packer plugins (build host only — not in AMI)

| Plugin | Source |
|--------|--------|
| `github.com/hashicorp/amazon` | Packer registry (`https://github.com/hashicorp/packer-plugin-amazon`) via `packer init` |
| `github.com/hashicorp/ansible` | Packer registry (`https://github.com/hashicorp/packer-plugin-ansible`) via `packer init` |

Pinned constraints live in `packer/devimage.pkr.hcl`.

---

## 18. Runtime configuration files

| Path | Purpose | Owner |
|------|---------|-------|
| `/etc/devimage-manifest.yml` | bake-time layer manifest (which roles ran) | root |
| `/etc/devbox/sbom.json` | runtime SBOM (CycloneDX, written by `./run sbom` post-bake) | root |
| `/etc/profile.d/ca-trust.sh` | TLS trust env exports | root |
| `/etc/profile.d/go.sh` | `GOPATH`/`GOROOT` exports | root |
| `~/.cargo`, `~/.rustup` | Rust toolchain | `${dev_user}` |
| `~/.nvm` | Node version manager | `${dev_user}` |
| `~/.vnc/xstartup` | VNC session entry point | `${dev_user}` |
| `~/.config/code-server/config.yaml` | code-server bind + password | `${dev_user}` |

---

## 19. SBOM generation (proposed `./run sbom` flow)

**Build-time** (in Packer, after Ansible provisioner):

1. Install [`syft`](https://github.com/anchore/syft) on the bake host (or in the Packer build EC2).
2. Run `syft / -o cyclonedx-json=/etc/devbox/sbom.json --scope all-layers`.
3. Append a hand-built header that captures the upstream-installer items syft can't see (Go, code-server, kubectl, etc. installed from tarball/binary rather than rpm).
4. Bake the file into the AMI snapshot.

**Operator-side:**

```bash
./run sbom-show        # cat /etc/devbox/sbom.json on the running box via SSM
./run sbom-diff        # diff this box's SBOM against .planning/codebase/SBOM.md (drift report)
```

**Why both layers:** this static doc is the **intent**; `/etc/devbox/sbom.json` is the **actuality**. Drift between them is signal — typically a salt-minion or org-policy remediation is rewriting the box (see §Known Concerns).

---

## 20. Known concerns (drift sources)

These reduce the trustworthiness of the planned SBOM vs the actual installed set on a running devbox. Listed here so consumers know what to verify:

1. **CIS rule 2.2.1 cascade**: `hardening` role removes `xorg-x11-server-common`, which dnf dependency-resolves through `tigervnc-server`, `gnome-shell`, `gnome-session`. The desktop layer is effectively uninstalled on a hardened box unless rule 2.2.1 is overridden. Fix path documented (override in playbook `vars:`).
2. **Packer source AMI**: SSM parameter path is unpinned (no `:NN` suffix). Two operators bake the same SHA on different days and could get different base AMIs. Phase 3 REP-04 deferred follow-up.
3. **Upstream-installer floats**: `aws` CLI, `starship`, `rustup`-driven toolchain, `pipx`-installed tools — all install "latest" at bake. Pin these in role defaults if reproducibility matters more than freshness.
4. **dnf-resolved versions**: anything not explicitly versioned in this file inherits whatever AL2023's repo is shipping on bake day. The committed lockfiles cover Terraform providers and Galaxy collections but not dnf packages.

---

## 21. Provenance

- Static SBOM source: this file (`.planning/codebase/SBOM.md`) — **components only, no pinned versions**
- Pinned versions: `ansible/roles/*/defaults/main.yml`, `ansible/requirements.yml`, `terraform/.terraform.lock.hcl`, `packer/devimage.pkr.hcl`
- Runtime SBOM tool: [Anchore syft](https://github.com/anchore/syft) (CycloneDX JSON output)
- Bake provenance: `/etc/devimage-manifest.yml` carries the active layer set + Packer manifest `custom_data.devbox_user` carries the operator-of-record (Phase 3 REP-05)
- Update policy: bump this file when a component is added, removed, or its source/provenance changes. Version drift is **not** a trigger for updates — version pins live in their respective lockfiles/defaults.
