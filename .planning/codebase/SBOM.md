<!-- generated: 2026-05-14 -->
# devbox AMI — Software Bill of Materials (planned)

This is the **planned / static** SBOM. It is derived from `ansible/roles/*/defaults/main.yml` and `ansible/requirements.yml` — i.e. what the bake **intends** to install. The actual runtime SBOM (post-bake) is produced by `make sbom` and written to `/etc/devbox/sbom.json` on the running EC2 (see §SBOM Generation below).

**SBOM format:** human-readable layered manifest here; CycloneDX JSON v1.5 at runtime via `syft`.

**AMI base:** Amazon Linux 2023 minimal x86_64 — pinned via AWS SSM Parameter Store path `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64` (Phase 3 REP-04; `:NN` version suffix follow-up deferred).

**Layer model:** Roles run in the order in `ansible/playbook.yml` and are gated by `ansible/layer_config.yml`. Every layer below is conditional; an operator can opt out (e.g. skip `java` if they don't write JVM code). The `hardening` layer always runs last and applies the vendored Amazon Linux 2023 CIS role with overrides documented in `ansible/roles/hardening/defaults/main.yml`.

---

## 1. Base image (`base` role)

| Component | Version | Provenance | Notes |
|-----------|---------|------------|-------|
| Amazon Linux 2023 minimal | per SSM `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64` | AWS public | x86_64; pin `:NN` suffix is Phase 3 deferred follow-up |
| Linux kernel | per AL2023 release | dnf | typically `6.1.x` LTS |
| systemd | per AL2023 | dnf | manages all baked services |
| cloud-init | per AL2023 | dnf | first-boot orchestration |
| amazon-ssm-agent | per AL2023 (preinstalled) | dnf | enables `make devbox-ssm` (Phase 2 NET-04) |
| aws CLI v2 | latest at bake time | upstream installer | `awscli_install: true` |
| starship prompt | latest | upstream installer | `starship_install: true` |

**dnf packages (base):**
`wget`, `unzip`, `tar`, `gzip`, `bzip2`, `xz`, `jq`, `htop`, `tmux`, `tree`, `make`, `cmake`, `gcc`, `gcc-c++`, `openssl-devel`, `zlib-devel`, `bzip2-devel`, `readline-devel`, `sqlite-devel`, `libffi-devel`, `xz-devel`, `ncurses-devel`, `patch`, `diffutils`, `which`, `man-db`, `bash-completion`, `procps-ng`, `net-tools`, `bind-utils`, `iputils`, `strace`, `lsof`, `socat`

Source: `ansible/roles/base/defaults/main.yml`

---

## 2. Certs (`certs` role)

System CA bundle plus `/etc/profile.d/ca-trust.sh` exporting `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS` to point at the merged store. No new packages.

---

## 3. Git tooling (`git` role)

| Component | Version | Source |
|-----------|---------|--------|
| `git` | per AL2023 | dnf |
| `git-lfs` | per AL2023 | dnf |
| `gh` (GitHub CLI) | latest | upstream installer (`gh_cli_install: true`) |
| `lazygit` | `0.44.1` | upstream release tarball |
| `delta` (git pager) | `0.18.2` | upstream release tarball |

---

## 4. Python (`python` role)

| Component | Version | Source |
|-----------|---------|--------|
| `python3` + `python3-pip` + `python3-devel` + `python3-setuptools` | per AL2023 | dnf |
| `uv` | `0.5.11` | upstream installer |
| `pipx` | latest | pip → user-local |
| `poetry`, `ruff`, `black`, `mypy` | latest at bake | `pipx install` (per-tool isolated venvs) |
| `virtualenvwrapper` | latest | user-local pip (Phase 0 WIP fix: per-user install under `dev_user`; system-wide install was unreadable under CIS umask 027) |

---

## 5. Go (`golang` role)

| Component | Version | Source |
|-----------|---------|--------|
| Go toolchain | `1.22.5` | upstream tarball → `/usr/local/go` |

---

## 6. Rust (`rust` role)

| Component | Version | Source |
|-----------|---------|--------|
| `rustc` + `cargo` (stable channel) | latest stable at bake | `rustup` per-user |
| Components: `clippy`, `rustfmt`, `rust-src`, `rust-analyzer` | matching toolchain | rustup |

---

## 7. JVM (`java` role)

| Component | Version | Source |
|-----------|---------|--------|
| Amazon Corretto 21 (`java-21-amazon-corretto-devel`, `java-21-amazon-corretto`) | per AL2023 | dnf |
| Apache Maven | `3.9.12` | upstream tarball |
| Gradle | `8.10.2` | upstream tarball |
| IntelliJ IDEA Community | `2024.3.1.1` | upstream tarball |
| Eclipse | `2024-12` build `R` | upstream tarball |

---

## 8. Containers (`containers` role)

| Component | Version | Source |
|-----------|---------|--------|
| Docker Engine + CLI | per AL2023 | dnf |
| `fixuid` | `0.6.0` | upstream release |

Networking: see `ansible/firewalld-docker-fix.yml` (Phase 0 WIP, documented retirement criteria in Phase 4 DOC-02 — `firewall-cmd --get-default-zone` to verify).

---

## 9. IaC tooling (`terraform` role)

| Component | Version | Source |
|-----------|---------|--------|
| HashiCorp Terraform | `1.9.3` | upstream zip |
| OpenTofu | `1.9.0` | upstream tarball |
| Terragrunt | `0.67.4` | upstream binary |
| `tflint` | `0.53.0` | upstream zip |
| `terraform-docs` | `0.18.0` | upstream tarball |

**Note:** operator workstation tofu version must satisfy the committed `terraform/.terraform.lock.hcl` (Phase 3 REP-01). The lockfile records `hashicorp/aws ~> 6.0` resolved to `v6.45.0` with 4 platform hashes.

---

## 10. DevOps / Kubernetes (`devops` role)

| Component | Version | Source |
|-----------|---------|--------|
| `kubectl` | `1.31.3` | upstream binary |
| `helm` | `3.16.3` | upstream binary |
| `k9s` | `0.32.7` | upstream tarball |
| `eksctl` | `0.194.0` | upstream tarball |
| `istioctl` | `1.24.2` | upstream tarball |

---

## 11. Dev tools (`devtools` role)

| Component | Version | Source |
|-----------|---------|--------|
| Node.js 20 + npm | dnf module `nodejs20`, `nodejs20-npm` | dnf |
| `nvm` | `0.40.1` | upstream installer (per-user) |
| `protobuf-compiler` | per AL2023 | dnf |
| `shellcheck` | `0.10.0` | upstream tarball |
| `thrift` | `0.21.0` | upstream tarball |
| `bazelisk` | `1.25.0` | upstream binary |
| `direnv` | latest | upstream installer |
| `fzf` | `0.55.0` | upstream tarball |
| `bat` | `0.24.0` | upstream tarball |
| `fd` | `10.2.0` | upstream tarball |
| `ripgrep` | `14.1.1` | upstream tarball |
| `yq` | `4.44.3` | upstream binary |

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

| Component | Version | Source |
|-----------|---------|--------|
| `code-server` | `4.93.1` | upstream RPM (Coder Inc.) |
| VS Code extensions (pre-installed) | latest at bake | code-server `--install-extension` |

**Extensions baked:**
- `ms-python.python`
- `golang.go`
- `hashicorp.terraform`
- `redhat.vscode-yaml`
- `esbenp.prettier-vscode`

**Service:** `code-server.service` (systemd) bound to `0.0.0.0:8080`; password sourced from SSM at boot.

---

## 14. Desktop / VNC (`desktop` role)

| Component | Version | Source |
|-----------|---------|--------|
| `@Desktop` (dnf group) | per AL2023 | dnf |
| `gnome-shell` | per AL2023 | dnf |
| `tigervnc-server` | per AL2023 | dnf |
| `dejavu-sans-fonts` + `dejavu-sans-mono-fonts` | per AL2023 | dnf |
| `mesa-dri-drivers` | per AL2023 | dnf |
| noVNC | `1.5.0` | upstream tarball |

**Services:** `vncserver@:1.service`, `novnc.service`.
**Known gap:** `gnome-session` not explicitly listed; relies on `@Desktop` group resolution. If the dnf group doesn't pull it, GNOME sessions fail to start. See §Known Concerns.

---

## 15. Hardening (`hardening` role — runs LAST)

| Component | Version | Source | Purpose |
|-----------|---------|--------|---------|
| `authselect` | per AL2023 | dnf | PAM profile selector |
| `crypto-policies-scripts` | per AL2023 | dnf | system crypto policy |
| `aide` | per AL2023 | dnf | (config disabled via `amzn2023cis_config_aide: false`; package still installed) |
| SELinux | `enforcing` | configured | not installed (baked in) |
| FIPS mode | enabled | `fips-mode-setup --enable` | requires reboot (role triggers) |
| Vendored AMAZON2023-CIS role | tagged release matching the Galaxy collections | git-source | Level 1 + selected Level 2 controls |

**Overrides** (`ansible/roles/hardening/defaults/main.yml`):
- Firewall (3.4.x): all rules disabled — EC2 security groups provide perimeter security
- Journal remote (5.1.2.1.x): disabled — single-node devbox doesn't ship logs offsite
- Logrotate (5.3): disabled — journald not rsyslog
- AIDE config (`amzn2023cis_config_aide`): disabled
- **CIS 2.2.1**: still ON by default (`amzn2023cis_rule_2_2_1: true`) — removes `xorg-x11-server-common`. This conflicts with the desktop layer. See §Known Concerns.

---

## 16. Galaxy collections (Ansible runtime only — not in AMI)

| Collection | Version | Source |
|------------|---------|--------|
| `community.general` | `==12.6.0` | Galaxy |
| `community.crypto` | `==3.2.0` | Galaxy |
| `ansible.posix` | `==2.1.0` | Galaxy |
| `community.aws` | `==9.0.0` | Galaxy (held; bump deferred — raises ansible-core floor) |

Vendored CIS role collections (git-sourced, tagged refs in `ansible/roles/AMAZON2023-CIS/collections/requirements.yml`) pin to identical versions.

---

## 17. Packer plugins (build host only — not in AMI)

| Plugin | Version | Source |
|--------|---------|--------|
| `github.com/hashicorp/amazon` | `>= 1.3.0` | Packer registry |
| `github.com/hashicorp/ansible` | `>= 1.1.0` | Packer registry |

---

## 18. Runtime configuration files

| Path | Purpose | Owner |
|------|---------|-------|
| `/etc/devimage-manifest.yml` | bake-time layer manifest (which roles ran) | root |
| `/etc/devbox/sbom.json` | runtime SBOM (CycloneDX, written by `make sbom` post-bake) | root |
| `/etc/profile.d/ca-trust.sh` | TLS trust env exports | root |
| `/etc/profile.d/go.sh` | `GOPATH`/`GOROOT` exports | root |
| `~/.cargo`, `~/.rustup` | Rust toolchain | `${dev_user}` |
| `~/.nvm` | Node version manager | `${dev_user}` |
| `~/.vnc/xstartup` | VNC session entry point | `${dev_user}` |
| `~/.config/code-server/config.yaml` | code-server bind + password | `${dev_user}` |

---

## 19. SBOM generation (proposed `make sbom` flow)

**Build-time** (in Packer, after Ansible provisioner):

1. Install [`syft`](https://github.com/anchore/syft) on the bake host (or in the Packer build EC2).
2. Run `syft / -o cyclonedx-json=/etc/devbox/sbom.json --scope all-layers`.
3. Append a hand-built header that captures the upstream-installer items syft can't see (Go, code-server, kubectl, etc. installed from tarball/binary rather than rpm).
4. Bake the file into the AMI snapshot.

**Operator-side:**

```bash
make sbom-show        # cat /etc/devbox/sbom.json on the running box via SSM
make sbom-diff        # diff this box's SBOM against .planning/codebase/SBOM.md (drift report)
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

- Static SBOM source: this file (`.planning/codebase/SBOM.md`)
- Runtime SBOM tool: [Anchore syft](https://github.com/anchore/syft) v1.x (CycloneDX JSON v1.5 output)
- Bake provenance: `/etc/devimage-manifest.yml` carries the active layer set + Packer manifest `custom_data.devbox_user` carries the operator-of-record (Phase 3 REP-05)
- Update policy: bump this file when a role default version changes, or whenever a new role lands. Phase 4 CI grep gate could be extended to assert "any change to `ansible/roles/*/defaults/main.yml` touches `SBOM.md` in the same PR" — deferred.
