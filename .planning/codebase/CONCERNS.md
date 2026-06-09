# Codebase Concerns

**Analysis Date:** 2026-05-13

This audit covers the devbox infrastructure project: Terraform/Terragrunt + Packer
+ Ansible + bash. Findings are grouped by category and ordered by severity.
File paths are repo-relative.

---

## Hardcoded Credentials & Secrets

### code-server password hardcoded in template (CRITICAL)

- **Files:**
  - `ansible/roles/vscode/templates/config.yaml.j2:3` — `password: changeme`
  - `ansible/roles/vscode/defaults/main.yml` (no override variable defined)
- **Risk:** The code-server IDE listens on `0.0.0.0:8080` (see
  `ansible/roles/vscode/defaults/main.yml:4`) and is exposed publicly by the
  security group (`terraform/main.tf:46-51`, `cidr_blocks = ["0.0.0.0/0"]`).
  Any AMI built from this code ships with a literal password of `changeme`,
  giving anyone on the internet remote code execution on the EC2 instance.
- **Why CRITICAL:** Internet-exposed IDE + universally-known password +
  process running as `ec2-user` who is in the `docker` group
  (`ansible/roles/containers/tasks/main.yml:7-11`) = trivial root escalation.
- **Fix:**
  1. Replace the literal in `config.yaml.j2` with `{{ code_server_password }}`.
  2. Generate a per-build password (e.g.
     `lookup('password', '/dev/null length=32')`) and surface it via the
     build manifest at `/etc/devimage-manifest.yml` (or, better, via SSM
     Parameter Store / Secrets Manager).
  3. Lock the SG ingress for 8080 to a known CIDR
     (`var.allowed_admin_cidr` defaulting to the operator's IP, not
     `0.0.0.0/0`).

### VNC password defaults to "changeme" (CRITICAL)

- **Files:**
  - `ansible/roles/desktop/defaults/main.yml:7` — `desktop_vnc_password: "changeme"`
  - `ansible/roles/desktop/tasks/main.yml:29-33` — used to seed
    `~/.vnc/passwd`
- **Risk:** Same shape as the code-server issue. VNC is reverse-proxied by
  noVNC on `:6080`, which is internet-exposed
  (`terraform/main.tf:54-60`). Anyone reaching the noVNC page can log in
  with `changeme` and get an interactive GNOME desktop running as
  `ec2-user`.
- **Why CRITICAL:** Same blast radius as code-server (RCE → docker group →
  root). The VNC server itself binds `-localhost yes`
  (`ansible/roles/desktop/templates/vncserver.service.j2:16`), so only
  noVNC is the entry point — but noVNC is published.
- **Fix:** Require `desktop_vnc_password` to be set per build (no default),
  fail the play if absent, and document how to provide it via `--extra-vars`
  or Packer var-files (which should be `.gitignore`d).

### `creates:` guard on VNC password is order-dependent (HIGH)

- **File:** `ansible/roles/desktop/tasks/main.yml:29-33`
- **Risk:** The `Set VNC password` shell task is guarded by
  `creates: {{ dev_home }}/.vnc/passwd`. Once the file exists from the
  first build, re-running the playbook with a *different*
  `desktop_vnc_password` is a silent no-op — operators may think they
  rotated the password when they did not.
- **Fix:** Either (a) drop the `creates:` guard and rely on
  `changed_when: false` plus an idempotent `vncpasswd` invocation, or
  (b) compare a hash and notify a handler.

---

## State File Handling

### Remote state correctly configured (LOW — informational)

- **File:** `terragrunt.hcl:11-21`
- **State:** S3-backed (`bucket = "devimage-tfstate-${account_id}"`,
  `encrypt = true`, DynamoDB lock table `devimage-tfstate-locks`).
  Per-user key path `users/${local.user}/devbox.tfstate` provides workspace
  isolation.
- **`.gitignore` correctly excludes** `terraform/terraform.tfstate*`,
  `terraform/backend.tf`, `terraform/terraform.tfvars`, and
  `.terragrunt-cache/` (`.gitignore:5-13`). No state files found in tree.
- **Residual concern (LOW):** The Terragrunt config does *not* assert that
  the bucket has versioning, MFA-delete, server-side encryption at rest
  with a CMK, public-access-block, or a bucket policy denying
  `s3:DeleteObject` from non-admin principals. The bucket is implicitly
  created on first `terragrunt init` but its security posture is invisible
  to this repo.
- **Fix:** Either (a) manage the backend bucket explicitly in a bootstrap
  Terraform module (`terraform/bootstrap/`) so its policy is reviewable, or
  (b) add a Terragrunt `remote_state.config.s3_bucket_tags` /
  `accesslogging_*` block and rely on the Terragrunt auto-create features
  to set versioning/encryption explicitly.

---

## SSH Key Handling

### SSH key name hardcoded to a person's username (HIGH)

- **File:** `terragrunt.hcl:26` — `key_name = "me"`
- **Risk:** Every devbox provisioned from this repo authorizes the same
  named SSH key pair in AWS. Anyone with the matching private key can SSH
  into *any* user's devbox. The Terraform `key_name` variable
  (`terraform/variables.tf:12-15`) is intentionally generic, but the
  Terragrunt input bypasses that.
- **Fix:** Make `key_name` resolve per-user (e.g.
  `key_name = "${local.user}-devbox"`), and require each operator to
  upload their own key pair before `tg-apply`. Document in `Makefile`/README.

### Packer disables host key checking globally (MEDIUM)

- **File:** `packer/devimage.pkr.hcl:67` —
  `ANSIBLE_HOST_KEY_CHECKING=False`
- **Risk:** Standard for ephemeral Packer builders but worth flagging:
  combined with `-o ForwardAgent=yes` (line 69), a compromised AMI build
  runner could harvest the operator's forwarded agent. Low likelihood
  given the builder is short-lived, but the agent forwarding is not
  needed for the AMI build itself.
- **Fix:** Drop `ForwardAgent=yes` from
  `packer/devimage.pkr.hcl:69` unless a specific role requires it; rely
  on Packer's ephemeral SSH keypair (the default).

### SSH command in `outputs.tf` references unsynchronized key path (LOW)

- **File:** `terraform/outputs.tf:18` —
  `ssh -i ~/.ssh/${var.key_name}.pem ec2-user@...`
- **Risk:** Assumes the private key is at `~/.ssh/<key_name>.pem`. Since
  `key_name` is hardcoded to `"me"` in Terragrunt
  (see HIGH above), this output advertises a path that exists only on
  one workstation. Misleading for the rest of the team.
- **Fix:** Tied to the per-user `key_name` fix.

---

## Privileged Tasks (become / sudo / root scope)

### Play-level `become: true` is broad but justified (LOW)

- **File:** `ansible/playbook.yml:4` — `become: true` at play scope.
- **Justification:** Almost every role installs system packages
  (`dnf`), writes to `/etc/`, or enables systemd units; per-task `become`
  on each would be churn. Three roles correctly drop privilege via
  `become_user: "{{ dev_user }}"`:
  - `ansible/roles/vscode/tasks/main.yml:48-54` (install extensions)
  - `ansible/roles/python/tasks/main.yml:13-17`, `19-25`, `77-84`
    (pipx + virtualenvwrapper per-user)
  - `ansible/roles/rust/tasks/main.yml:8-13`, `15-22` (rustup per-user)
  - `ansible/roles/git/tasks/main.yml:77-87` (git config per-user)
  - `ansible/roles/devtools/tasks/main.yml:286-291` (nvm per-user)
- **Fix:** No change required. The pattern is correct.

### Hardening role reboots the host mid-play (MEDIUM)

- **File:** `ansible/roles/hardening/tasks/main.yml:40-43`
- **Risk:** A reboot in the middle of a Packer build is fine, but the
  comment "Reboot to apply hardening" plus `reboot_timeout: 300` means
  any post-hardening role would re-run after reboot. Today, `hardening`
  is the last role in the playbook (`ansible/playbook.yml:54-55`), so
  the order is safe — but it is enforced only by convention. Anyone who
  adds a role after `hardening` in the future will hit "post-reboot
  state is unknown" surprises (FIPS-only crypto, locked-down PAM).
- **Fix:** Add a comment in `ansible/playbook.yml` near the role list
  stating "`hardening` MUST be last", or split hardening into a separate
  Packer provisioner block with `pause_before` semantics.

### Random root password generated on every play (LOW — informational)

- **File:** `ansible/roles/hardening/tasks/main.yml:19-23`
- **Note:** Uses `lookup('password', '/dev/null length=32')` so the
  password is generated, hashed, and discarded — it is never
  persisted. This satisfies CIS rule 4.6.6 but means the root account is
  effectively unusable via password. Since SSH is key-based for
  `ec2-user` only and `sudo` is via `authselect sssd with-sudo`, this is
  the intended posture. Documenting only.

---

## Idempotency Risks (Ansible shell/command)

Inventoried every `command:`/`shell:` task outside the vendored
`AMAZON2023-CIS` role. All of them either have `creates:`, `removes:`,
`changed_when:`, or are intentionally one-shot installers; one is
under-guarded.

### `desktop` role: `Apply dconf system defaults` has no `changed_when` (MEDIUM)

- **File:** `ansible/roles/desktop/tasks/main.yml:90-91`
- **Risk:** `dconf update` always reports `changed`, so every re-run
  flags this task as changed and any handler watching it (none today)
  would needlessly re-fire. Idempotency cosmetic, not correctness.
- **Fix:** Add `changed_when: false` (the preceding `copy` tasks already
  notify properly), or compare dconf db mtimes.

### `desktop` role: `Set VNC password` re-run does not rotate (HIGH)

See "Hardcoded Credentials & Secrets" above (`main.yml:29-33`).

### Idempotent shell tasks verified (LOW — informational)

The following are correctly guarded and listed for reference:

| File | Line(s) | Guard |
|------|---------|-------|
| `ansible/roles/base/tasks/main.yml` | 9-14 | `removes:` + `changed_when` + `failed_when` |
| `ansible/roles/base/tasks/main.yml` | 36-39 | `creates: /usr/local/bin/aws` |
| `ansible/roles/base/tasks/main.yml` | 58-61 | `creates: /usr/local/bin/starship` |
| `ansible/roles/certs/tasks/main.yml` | 16-18 | `when: ca_certs_copied.changed` |
| `ansible/roles/git/tasks/main.yml` | 77-87 | `changed_when: false` |
| `ansible/roles/python/tasks/main.yml` | 13-17 | `changed_when: false` |
| `ansible/roles/python/tasks/main.yml` | 19-25 | `creates:` per-tool |
| `ansible/roles/rust/tasks/main.yml` | 8-13 | `creates: ~/.cargo/bin/rustc` |
| `ansible/roles/rust/tasks/main.yml` | 15-22 | `changed_when: false` |
| `ansible/roles/devtools/tasks/main.yml` | 181-184 | `creates: /usr/local/bin/direnv` |
| `ansible/roles/devtools/tasks/main.yml` | 215-241 | `creates: Makefile` |
| `ansible/roles/devtools/tasks/main.yml` | 243-247 | `creates: thrift` binary |
| `ansible/roles/devtools/tasks/main.yml` | 286-291 | `creates: ~/.nvm/nvm.sh` |
| `ansible/roles/vscode/tasks/main.yml` | 48-54 | `changed_when: false` + `ignore_errors: true` |
| `ansible/roles/desktop/tasks/main.yml` | 142-150 | `creates: /etc/novnc/novnc-cert.pem` |
| `ansible/roles/desktop/tasks/main.yml` | 238-240 | `changed_when: false` |
| `ansible/roles/desktop/tasks/main.yml` | 242-245 | `creates: /var/lib/flatpak/...` |
| `ansible/roles/hardening/tasks/main.yml` | 11-12 | safe to re-run (authselect select is idempotent) |
| `ansible/roles/hardening/tasks/main.yml` | 36-37 | `fips-mode-setup --enable` is idempotent |

---

## firewalld-docker-fix.yml — Documented Workaround

### Status: HIGH (tracked tech debt; already self-documented)

- **File:** `ansible/firewalld-docker-fix.yml:1-26`
- **What it does:** Installs firewalld, restarts docker so it
  auto-registers the `docker` firewalld zone (target=ACCEPT), then sets
  that zone as the default. Net effect: firewalld is installed (so CIS
  scans pass) but **effectively permissive on the host**, deferring all
  perimeter security to the EC2 security group.
- **Why it's a workaround:** With `default zone = public`, host services
  bound to 0.0.0.0 (code-server :8080, noVNC :6080) are dropped at the
  firewalld INPUT chain even though the AWS SG allows them.
- **Inconsistency with `hardening` defaults:**
  - `ansible/roles/hardening/defaults/main.yml:4-13` disables
    *all* the firewalld/nftables CIS rules with the comment "EC2 security
    groups provide perimeter security." That is option (b) from the
    workaround's own header (`firewalld-docker-fix.yml:14-16`).
  - But the workaround takes option neither (a) nor (b): it installs
    firewalld anyway and makes it pass-through. So the role disables
    *configuring* firewalld but the post-task *installs and starts* it.
- **`playbook.yml:79-82` already FIXMEs this:** "remove once firewalld
  policy is managed properly (or once firewalld is removed entirely)."
- **Fix:** Decide. Option (b) (don't install firewalld) is simpler and
  aligns with the hardening defaults. If a CIS scan demands firewalld be
  present, choose option (a): pin docker0 to the `docker` zone
  explicitly and add per-port `--add-port` rules in `public` for
  `:8080,:6080,:22`.

---

## Network Exposure

### All three ingress ports open to `0.0.0.0/0` (CRITICAL)

- **File:** `terraform/main.tf:36-60`
- **Open to internet:**
  - `22/tcp` (SSH) — somewhat mitigated by key-based auth, but no fail2ban
    or SSM-session-manager fallback.
  - `8080/tcp` (code-server) — see code-server password CRITICAL above;
    auth is `password` with literal `changeme`.
  - `6080/tcp` (noVNC) — TLS termination uses a self-signed cert
    (`ansible/roles/desktop/tasks/main.yml:142-150`,
    `-subj '/CN=devbox'`, 10-year validity). VNC auth is PAM-backed
    (TigerVNC `SecurityTypes=Plain`) against a per-build SSM credential.
- **Why CRITICAL:** Each user's devbox is a publicly addressable RCE
  target until passwords are rotated. The `iam_instance_profile`
  variable is `null` by default (`terraform/variables.tf:51-55`), but
  any role attached at runtime is exfiltratable.
- **Fix:**
  1. Introduce `var.allowed_admin_cidr` (list) defaulting to operator's
     /32 or company VPN range, never `0.0.0.0/0`.
  2. Prefer SSM Session Manager + EC2 Instance Connect for shell access
     (`vpc_endpoint`-only), drop the `:22` SG rule entirely.
  3. Put code-server/noVNC behind an authenticated reverse proxy
     (cloudfront + signed URLs, or oauth2-proxy + Cognito) instead of
     direct ingress.

### Self-signed noVNC cert with 10-year lifetime (LOW)

- **File:** `ansible/roles/desktop/tasks/main.yml:143-150`
- **Risk:** Browsers will throw cert warnings forever. Users get
  trained to click through TLS warnings, undermining the value of TLS.
  Cert key is owned `root:ec2-user` mode 0640 (`main.yml:152-160`),
  which is fine.
- **Fix:** Use Let's Encrypt via DNS-01 (no port 80 needed) or
  cert-manager if the host has a stable DNS name.

---

## Image Provenance / AMI Pinning

### Packer base AMI filter is unpinned (HIGH)

- **File:** `packer/devimage.pkr.hcl:27-35`
- **Filter:** `name = "al2023-ami-minimal-*-x86_64"`,
  `most_recent = true`, `owners = ["amazon"]`.
- **Risk:** Every Packer build pulls whatever Amazon publishes as
  "most recent" matching the glob. Builds are not reproducible: a build
  today and a build tomorrow can start from different base images,
  making it impossible to bisect "did the AMI break because of our
  code, or because of the base?". No SHA pinning, no SSM parameter
  lookup with a frozen version.
- **Fix:** Use `aws_ssm_parameter` data source via Packer's `amazon` plugin
  to read the AL2023 release-version pointer
  (`/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-...`) and
  pin to a release tag in the var-file. Record the resolved AMI ID in
  the manifest.

### Built AMI ID is manually copied into Terragrunt inputs (HIGH)

- **File:** `terragrunt.hcl:25` — `ami_id = "ami-0b7cfe2135f319a55"`
- **Risk:** The link between "AMI Packer just built" and "AMI Terraform
  will launch" is a human edit. Easy to forget, easy to roll back to a
  stale image, easy to launch the wrong image silently.
- **Fix:** Have Packer's post-processor write
  `/.planning/last-ami.json` (or push to SSM Parameter Store) and have
  Terragrunt read it via `get_env` or `data.aws_ssm_parameter`. Tag
  every AMI with `Project=devimage` + git SHA so Terraform can use a
  `data "aws_ami"` filter against tags.

---

## Bash Safety

### Scripts use `set -euo pipefail` via sourced helper — verified OK (LOW)

- **File:** `scripts/_common.sh:5` — `set -euo pipefail`
- **Callers:** `devbox-start.sh:3`, `devbox-stop.sh:3`,
  `devbox-status.sh:3` all `source "$SCRIPT_DIR/_common.sh"` *before*
  any other shell logic, so the strict-mode settings apply to the
  caller's shell.
- **Concern:** This relies on shell semantics that `set` in a sourced
  file carries through. True for bash, but no `#!/usr/bin/env bash`
  guard exists *inside* `_common.sh` (only the shebang in callers).
  Anyone sourcing it from `sh` would silently lose `pipefail`.
- **Fix:** Add `[[ -n "${BASH_VERSION:-}" ]] || { echo "bash required"
  >&2; exit 1; }` near the top of `_common.sh`.

### All variable expansions in scripts are quoted — verified OK (LOW)

Walked `devbox-start.sh`, `devbox-stop.sh`, `devbox-status.sh`,
`_common.sh`. Every `$VAR` expansion in command position or path
context is double-quoted. No `eval`, no `cmd | sh`, no unquoted
command substitution. The only unquoted constructs are inside `[[ ]]`
which is bash-safe.

### Makefile shells out to user input via `whoami` (LOW)

- **File:** `Makefile:4` — `DEVBOX_USER ?= $(shell whoami)`
- **Risk:** `whoami` output is trusted as-is and embedded in:
  - S3 key path (`terragrunt.hcl:14`)
  - Terraform workspace name (`Makefile:67`)
  - Resource name_prefix (`terraform/main.tf:17`)
  - SSH `-i` path (`terraform/outputs.tf:18`)
  No quoting, no validation against `[a-z][a-z0-9-]*`. A username
  containing a space, `/`, or shell metachars would corrupt the state
  key or fail mid-apply.
- **Fix:** In `Makefile`, validate: `DEVBOX_USER := $(shell whoami |
  grep -E '^[a-z_][a-z0-9_-]*$$' || (echo "invalid user" >&2; exit 1))`.

---

## Terraform/Ansible Drift Risk

### No detection of drift between Terraform infra and Ansible config (HIGH)

- **Files:**
  - `terraform/main.tf:30-77` defines the SG ingress ports (22, 8080,
    6080).
  - `ansible/roles/vscode/defaults/main.yml:3-4` and
    `ansible/roles/desktop/defaults/main.yml:3-4` independently define
    those same ports.
- **Risk:** Changing `code_server_port` in Ansible to 8443 does not
  update the SG. Terraform plan stays clean; the service silently
  becomes unreachable from outside. There is no shared source of
  truth (e.g. a `ports.auto.tfvars` file or a `layer_config.yml`-style
  cross-import).
- **Fix:** Make ports a single Terraform variable
  (`var.service_ports`) and template them into the Ansible role via
  Packer `extra-vars`, or commit a `shared/ports.yaml` consumed by
  both layers.

### Hardening reboot is invisible to Terraform (MEDIUM)

- **File:** `ansible/roles/hardening/tasks/main.yml:40-43`
- **Risk:** Packer-baked hardening (FIPS, SELinux enforcing) is
  permanent in the AMI, but Terraform has no `user_data` step to
  re-apply or verify it on launch. If someone bakes a non-hardened AMI
  and updates `terragrunt.hcl:25` accidentally, the running instance
  is silently unhardened — there's no asg/launch-template check.
- **Fix:** Tag the AMI with `Hardened=true` in
  `packer/devimage.pkr.hcl:46-54` and add a Terraform
  `data "aws_ami"` filter requiring that tag, or assert it in a
  `precondition` block.

---

## Missing CI / Tests / Pre-commit

### No project-level CI pipeline (HIGH)

- **Searched:** `/Users/me/Documents/code/devbox/.github`,
  `Jenkinsfile`, `.gitlab-ci.yml`, `.circleci/`. None exist.
- **Risk:** No automated `packer validate`, `terraform validate`,
  `terragrunt hclfmt --check`, `ansible-lint`, `tflint`, `tfsec`/
  `checkov`/`kics`, `shellcheck`. The `Makefile:23-26` exposes
  `validate` and `fmt` targets but no enforcement.
- **Fix:** Add `.github/workflows/ci.yml` running on PR:
  - `terraform fmt -check -recursive`
  - `terragrunt hclfmt --check`
  - `packer validate ./packer`
  - `ansible-lint ansible/`
  - `tflint --recursive`
  - `tfsec` / `checkov -d terraform/`
  - `shellcheck scripts/*.sh`
  - `gitleaks detect`

### No project-level pre-commit hook (HIGH)

- **Searched:** Repo root, no `.pre-commit-config.yaml`. (The vendored
  `ansible/roles/AMAZON2023-CIS/.pre-commit-config.yaml` is for that
  role's upstream, not this project.)
- **Risk:** Same as CI gap, but at developer-machine scope. Easy to
  commit unformatted HCL, a TODO with a secret, a broken playbook.
- **Fix:** Add a root `.pre-commit-config.yaml` with hooks for
  `terraform_fmt`, `terraform_validate`, `terragrunt_hclfmt`,
  `ansible-lint`, `detect-secrets`, `shellcheck`, `end-of-file-fixer`,
  `trailing-whitespace`.

### No tests (HIGH)

- **Searched:** No `*_test.tf` files, no Terratest, no `molecule/`
  directory under any Ansible role, no Goss/InSpec suites at the repo
  root. The vendored CIS role *does* embed Goss templates
  (`ansible/roles/AMAZON2023-CIS/templates/ansible_vars_goss.yml.j2`)
  but they are scoped to that role's audit and not wired into the
  project.
- **Risk:** Every change is validated only by the operator running
  `make build` against AWS, which costs real money and 20-40 minutes.
- **Fix:**
  - Add `molecule/` scenarios for each role using the `docker` driver
    (AL2023 base image), running `ansible-playbook` + `verify.yml`.
  - Run the existing CIS Goss audit after `hardening` and publish the
    report as a build artifact.
  - Add Terratest in `terraform/test/` to spin up + destroy the SG
    against a sandbox account.

---

## Outdated / Unpinned Versions

### Galaxy collections not pinned to versions (HIGH)

- **File:** `ansible/requirements.yml:1-5`
  ```yaml
  collections:
    - name: community.general
    - name: community.crypto
    - name: ansible.posix
  ```
- **Risk:** No `version:` constraint, no `source:` URL hash. Every
  Packer build runs `ansible-galaxy collection install` resolving to
  whatever is latest on Ansible Galaxy. A compromised or breaking
  release lands in the next AMI silently.
- **Fix:** Pin: `version: "9.5.0"` etc. Even better, use
  `signatures:` with detached GPG signatures, or vendor the
  collections into `ansible/collections/`.

### Vendored CIS role's `collections/requirements.yml` also unpinned (MEDIUM)

- **File:** `ansible/roles/AMAZON2023-CIS/collections/requirements.yml`
  uses `type: git` against `main` of each upstream repo with no
  `version:` ref. Upstream history can rewrite under us.
- **Fix:** Pin to commit SHAs or tags
  (`version: 9.5.0` / `version: <sha>`).

### Tool versions in role defaults are pinned but not centrally tracked (LOW)

- **Files:** Every role's `defaults/main.yml` (e.g.
  `ansible/roles/devtools/defaults/main.yml:5-15`,
  `ansible/roles/terraform/defaults/main.yml:1-5`,
  `ansible/roles/golang/defaults/main.yml:1-2`,
  `ansible/roles/java/defaults/main.yml:5-9`).
- **State:** Pinned versions exist (`go_version: "1.22.5"`,
  `kubectl_version: "1.31.3"`, etc.) — good. But:
  - As of 2026-05-13, many of these (Go 1.22.5, kubectl 1.31.3, helm
    3.16.3, Terraform 1.9.3, OpenTofu 1.9.0, code-server 4.93.1) are
    multiple minor releases behind. The most concerning are
    `code_server_version: "4.93.1"` (older releases have known CVEs)
    and `terraform_version: "1.9.3"`.
- **Fix:** Create a single `ansible/versions.yml` (loaded by
  `playbook.yml` vars) or use Renovate/Dependabot rules pointed at the
  defaults files.

### `most_recent = true` on Packer source AMI (HIGH)

See "Image Provenance" → "Packer base AMI filter is unpinned" above.

### No `.terraform.lock.hcl` committed (HIGH)

- **Files:** `.gitignore:7,17` explicitly excludes
  `terraform/.terraform.lock.hcl` and root-level `.terraform.lock.hcl`.
- **Risk:** Provider versions are constrained only by
  `terraform/main.tf:7` (`version = ">= 5.0"`). Each operator's
  `terragrunt init` resolves to whichever AWS provider is latest at
  their workstation. Breaking changes in the AWS provider 6.x or 7.x
  would land silently and inconsistently across team members.
- **Fix:** Stop gitignoring the lockfile; commit it.

---

## Miscellaneous

### `disable_gpg_check: true` for code-server RPM (MEDIUM)

- **File:** `ansible/roles/vscode/tasks/main.yml:8-12`
- **Risk:** The RPM is downloaded over HTTPS from `github.com/coder/...`
  (line 4) which provides TLS integrity, but `disable_gpg_check: true`
  removes signature verification. A repo hijack or compromised
  release-asset on GitHub would land arbitrary code in the AMI.
- **Fix:** Verify the SHA256 of the downloaded RPM against a
  Renovate-managed pin (`get_url` supports `checksum:`), then install
  with GPG check enabled if Coder ships a key.

### `ignore_errors: true` on VS Code extension install (LOW)

- **File:** `ansible/roles/vscode/tasks/main.yml:54`
- **Risk:** Build "succeeds" even if every extension install fails.
  Users get a code-server with no extensions and no signal that
  anything went wrong.
- **Fix:** Replace with `failed_when:
  "'is already installed' not in (item_result.stdout | default(''))"`
  and let real failures stop the build, or at minimum capture and
  print the failed list at end-of-play.

### Build manifest leaks layer config but no version info (LOW)

- **File:** `ansible/playbook.yml:71-77` writes
  `/etc/devimage-manifest.yml` with `build_date` and `layers`.
- **Improvement opportunity:** Include the git SHA of the
  devbox repo, the Packer source AMI ID, the resolved Galaxy collection
  versions, and a SHA256 of `layer_config.yml`. This converts the
  manifest from "informational" to "forensically useful."

### CLAUDE.md is empty (LOW)

- **File:** `CLAUDE.md` is 0 bytes.
- **Risk:** If this is the project's instructions file for AI
  collaborators, it provides no guidance — operators (human or AI)
  cannot infer the constraints documented in this audit.
- **Fix:** Populate with a brief: "ports must stay in sync between TF
  and Ansible", "hardening must remain last", "AMI ID is hand-copied",
  "secrets must never default to `changeme`", etc.

---

## Severity Roll-Up

| Severity | Count |
|----------|-------|
| CRITICAL | 3 |
| HIGH | 12 |
| MEDIUM | 6 |
| LOW | 13 |

Top three to fix first:

1. **code-server `password: changeme`** + internet-exposed SG → RCE
   (`ansible/roles/vscode/templates/config.yaml.j2:3`,
   `terraform/main.tf:46-51`).
2. **VNC `desktop_vnc_password: "changeme"`** + noVNC exposure → RCE
   (`ansible/roles/desktop/defaults/main.yml:7`,
   `terraform/main.tf:54-60`).
3. **All three SG rules open to `0.0.0.0/0`**
   (`terraform/main.tf:36-60`) — even without the password issues, this
   is the wrong default for a per-user dev sandbox.

---

*Concerns audit: 2026-05-13*
