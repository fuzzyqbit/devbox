_Operator quickstart for the devbox IaC repo. Last updated: 2026-05-14 (Phase 4 DOC-01). For project history and architecture, see `.planning/PROJECT.md`._

# devbox

## 1. What this is

Personal cloud workstation as infrastructure-as-code. Packer + Ansible bake a hardened
Amazon Linux 2023 AMI; Terragrunt + OpenTofu provision a per-operator EC2 instance from
that AMI. The instance runs code-server (browser VS Code) on `:8080`, noVNC on `:6080`,
and is reached via AWS SSM Session Manager (no public `:22`). The operator surface is
`make <target>` — one operator, one instance, one state file. Full architecture and
decision log live in `.planning/PROJECT.md` and `.planning/codebase/`.

## 2. Prerequisites

Install the toolchain once per workstation. The full version floor for each tool is in
`.planning/phases/03-reproducibility-version-pinning/03-RESEARCH.md`; the snippets below
are sufficient for a fresh clone.

```bash
# macOS
brew install awscli packer opentofu ansible ansible-lint jq \
             gitleaks pre-commit shellcheck
brew install --cask session-manager-plugin
# Optional (CI is authoritative; install locally for `pre-commit run --hook-stage pre-push`):
brew install checkov
```

```bash
# Fedora / RHEL
dnf install -y awscli packer opentofu ansible-core jq \
               gitleaks ShellCheck
pip install ansible-lint==26.4.0 pre-commit==4.6.0 checkov==3.2.528
# session-manager-plugin: download the .rpm from
#   https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-rpm.html
```

Required floor versions: `aws` CLI v2.x, `packer` ≥ 1.12, `tofu` ≥ 1.10 (NOT `terraform`
— the lockfile is OpenTofu-flavoured), `ansible-core` ≥ 2.16 +
`ansible-lint` ≥ 26, `jq`, `gitleaks` ≥ 8.30, `pre-commit` ≥ 4.6, `shellcheck` ≥ 0.10,
`checkov` ≥ 3.2 (optional — CI is the source of truth).

> **Phase 5 note:** Terragrunt was dropped post-v1.0. The Makefile now drives `tofu`
> directly with `-backend-config` flags; `tf-init` derives the state bucket from
> `aws sts get-caller-identity`. If you still see `tg-*` targets referenced in old
> notes, use the `tf-*` equivalents (`tg-apply` → `tf-apply`, etc.).

### Pre-commit hooks — install all three stages

Pre-commit has three install points and they are not interchangeable. Install all three
after every clone, or local feedback will silently diverge from CI:

```bash
pre-commit install                       # commit-stage hooks (fast: format, lint, gitleaks)
pre-commit install --hook-type pre-push  # pre-push hooks (slower: checkov, ansible-lint)
pre-commit install --install-hooks       # pre-warm hook environments (avoids first-commit lag)
```

## 3. Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEVBOX_USER` | `$(whoami)` | Threads through every Makefile target. Controls the S3 tfstate key (`users/${DEVBOX_USER}/devbox.tfstate`), the SSH keypair name (`${DEVBOX_USER}-devbox`), the security-group name prefix, and the SSM parameter prefix (`/devbox/${DEVBOX_USER}/*`). Override per-invocation: `make tf-apply DEVBOX_USER=alice`. |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | inherited | Operator region. The Terraform `region` input defaults to the value baked into `terraform/terraform.tfvars`; export this for the `aws` CLI calls in scripts. |
| `TF_STATE_BUCKET` | derived | Backend bucket name. Defaults to `devimage-tfstate-$(aws sts get-caller-identity --query Account --output text)`. Override to point at a different state bucket. |
| `AWS_PROFILE` | unset | Optional; pass through to the `aws` CLI for multi-account operators. |
| `TF_BIN` | `tofu` | IaC binary. Default OpenTofu (canonical — the committed `terraform/.terraform.lock.hcl` is OpenTofu-flavoured). Override to `terraform` for compatibility testing: `make tf-apply TF_BIN=terraform`. Lockfile + provider checksums will diverge — expect drift. |

## 4. One-time per-operator setup

### Step 1 — SSH keypair (Phase 1 SEC-04)

Each operator owns their own keypair; the historical hardcoded `key_name = "me"` is gone.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/${USER}-devbox -C "${USER}-devbox"
aws ec2 import-key-pair \
  --key-name "${USER}-devbox" \
  --public-key-material "fileb://$HOME/.ssh/${USER}-devbox.pub" \
  --region "$AWS_REGION"
```

The public key lives in AWS only; the private key never leaves your workstation. Rotation
procedure: see section 6.

### Step 2 — CIDR allowlist for code-server / noVNC (Phase 2 NET-02/03)

`:8080` (code-server) and `:6080` (noVNC) are restricted to `var.allowed_web_cidrs`.
The Terraform default is `["10.0.0.0/8"]` — appropriate when the devbox lives
inside a private VPC reached over VPC peering / Direct Connect / VPN. `make
tf-apply` works out-of-the-box with that default; no operator action needed.

To narrow (or widen) externally, supply your own value via any standard Terraform
mechanism — for example a per-operator tfvars file you manage outside this repo,
a `-var` flag, or the `TF_VAR_allowed_web_cidrs` env. The project no longer
ships an in-repo allowlist helper.

## 5. Daily flow

Every operator-facing command is a Makefile target. Run `make help` for the inline
reference; targets used in the daily loop are listed below in execution order.

```bash
# 1. Bake the AMI. Terraform picks it up via a `data "aws_ami"` filter at apply time.
make build DEVBOX_USER=$(whoami)

# 2. First-time only (or after switching DEVBOX_USER): point Terraform at this
#    operator's S3 state key. Derives the bucket via `aws sts get-caller-identity`.
make tf-init DEVBOX_USER=$(whoami)

# 3. Provision (or update) the EC2 instance. Idempotent; replaces the AMI if it changed.
make tf-apply DEVBOX_USER=$(whoami)

# 3. Start the instance when you're ready to work.
make start

# 4. Connect via SSM (Phase 2 NET-04 hybrid posture — no public :22 ingress).
make devbox-ssm                 # interactive shell over SSM
make devbox-port-forward        # tunnel :8080 to localhost over SSM
# Or, with your allowlist active, point your browser at https://<host>:8080.

# 5. Reveal your per-operator passwords (decrypted from SSM Parameter Store SecureString).
make secrets-show               # reads /devbox/${DEVBOX_USER}/{code-server,vnc}-password

# 6. When done for the day.
make stop

# Anytime: see current state.
make status
```

Bake variants and additional Terraform targets (`tf-init`, `tf-reinit`, `tf-plan`,
`tf-auto-apply`, `tf-destroy`, `tf-auto-destroy`, plus `packer-init`, `validate`, `build`,
`fmt`, `clean`) are documented in `make help`; the daily loop above is sufficient for
typical use.

## 6. Rotations

- **SSH key** (Phase 1 SEC-04). Delete the AWS-side keypair, re-import a fresh one, and
  let Terraform push the new public key to the instance metadata:
  ```bash
  aws ec2 delete-key-pair --key-name ${USER}-devbox --region "$AWS_REGION"
  ssh-keygen -t ed25519 -f ~/.ssh/${USER}-devbox -C "${USER}-devbox"
  aws ec2 import-key-pair --key-name "${USER}-devbox" \
    --public-key-material "fileb://$HOME/.ssh/${USER}-devbox.pub" --region "$AWS_REGION"
  make tf-apply DEVBOX_USER=$(whoami)
  ```
- **Secrets** (Phase 1 SEC-01/02/03). Per-build secrets are regenerated by the `secrets`
  role on every `make build` and re-published to SSM Parameter Store as
  SecureStrings. To rotate: just rebake (`make build && make tf-apply`).
- **CIDR allowlist** (Phase 2 NET-02/03). `var.allowed_web_cidrs` is operator-managed
  externally (per-operator tfvars / `-var` / `TF_VAR_allowed_web_cidrs`). Update via
  whatever mechanism you use, then `make tf-apply`.

## 7. Troubleshooting

- **`session-manager-plugin: command not found`** — install it: `brew install --cask session-manager-plugin`
  (macOS) or download the platform package from
  [AWS docs](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).
  Required by `make devbox-ssm` and `make devbox-port-forward`.
- **`tofu: command not found`** — install OpenTofu (`brew install opentofu`). Do **not**
  substitute the upstream `terraform` binary; the committed lockfile
  (`terraform/.terraform.lock.hcl`) is OpenTofu-flavoured and the policy in section 8
  forbids reverting it (Phase 3 REP-01).
- **`AMI not found`** on `make tf-apply` — the `data "aws_ami"` filter in
  `terraform/` returned no matches. Either bake one (`make build
  DEVBOX_USER=$(whoami)`), check the filter `name`/`owners` against your account,
  or pin an explicit `ami_id` in a per-operator tfvars override.
- **Lockfile checksum mismatch** on `tofu init` — wipe the cache:
  `cd terraform/ && rm -rf .terraform/ && tofu init`. Operator-migration note in
  `.planning/phases/03-reproducibility-version-pinning/03-01-SUMMARY.md`.
- **firewalld blocking ports inside the AMI** — known workaround in
  [`ansible/firewalld-docker-fix.yml`](ansible/firewalld-docker-fix.yml); the header of
  that file is the canonical explanation and lists the conditions under which the play
  can be retired (DOC-02).
- **`pre-commit run --all-files` slow on first run** — you skipped step three in
  section 2. Run `pre-commit install --install-hooks` to pre-warm the hook venvs;
  subsequent runs reuse them.
- **`make secrets-show` reports "parameter not found"** — your AMI hasn't been baked
  yet for this `DEVBOX_USER` (the Packer `secrets` role is what publishes the SSM
  parameters). Run `make build DEVBOX_USER=$(whoami)`, then retry.

## 8. Invariants — do not violate

These are enforced mechanically by the pre-commit `grep-gates` hook and the CI
`grep-gates` job. The list lives here as the human-readable contract; the gates are
authoritative.

- **`hardening` MUST remain the last role in `ansible/playbook.yml`.** Inserting any role
  after `hardening` re-opens what the role just locked down. Convention is enforced by a
  comment + the grep gate; do not add roles below it.
- **`terraform/.terraform.lock.hcl` MUST stay committed and MUST NOT be re-added to
  `.gitignore`.** This is REP-01; the lockfile is the reproducibility anchor for the four
  pinned provider platforms.
- **Action SHA-pin policy:** every `uses: org/repo@<ref>` in `.github/workflows/*` MUST
  pin to a 40-character hex commit SHA, never a tag (mutable refs would let an upstream
  compromise reach our CI).
- **Packer source AMI MUST stay pinned via SSM parameterstore** (`amazon-parameterstore`
  data source on `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64`).
  CI greps `most_recent = true` as a regression marker; Phase 3 REP-04 set this up.
- **`changeme` literal MUST NOT appear in any tracked code file.** Phase 1 SEC-01/02 — the
  pre-commit `no-changeme` hook enforces.

## 9. Known follow-ups

- **Packer SSM parameter `:NN` version pin** (Phase 3 REP-04 deferred — needs AWS creds
  to resolve the current version; see `packer/devimage.pkr.hcl` lines 19-31 for the bump
  procedure; the Phase 4 grep gate `grep -E '/aws/service/ami-amazon-linux-latest/.*:[0-9]+'`
  will start failing once `:NN` is added — that is the intentional ratchet).

---

_See `.planning/PROJECT.md` for the project's "what / why / decisions" record,
`.planning/codebase/` for the codebase reference map (STACK, INTEGRATIONS, ARCHITECTURE,
STRUCTURE, CONVENTIONS, TESTING, CONCERNS), and `.planning/phases/*/` for per-phase
research, plans, and verification reports._
