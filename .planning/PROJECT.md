# devbox

## What This Is

Personal infrastructure-as-code project that builds a hardened Amazon Linux 2023 AMI (Packer + Ansible) and provisions per-user EC2 dev environments from it (Terragrunt + Terraform/OpenTofu). The resulting EC2 instance runs code-server (browser VS Code) on :8080, noVNC on :6080, and SSH on :22, with a Make-based operator surface and lifecycle scripts for start/stop/status. No application source code lives here — purely declarative IaC + bash glue.

## Core Value

A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one `make` target — without leaking credentials or exposing a vulnerable host to the public internet.

## Requirements

### Validated

<!-- Inferred from existing code via .planning/codebase/ map. Locked. -->

- ✓ Packer builds an Amazon Linux 2023 AMI via the `amazon-ebs` builder — `packer/devimage.pkr.hcl`
- ✓ 14-layer Ansible playbook installs Python/Go/Rust/Java/Node toolchains, code-server, VNC + noVNC desktop, Docker, terraform/terragrunt — `ansible/playbook.yml`, `ansible/layer_config.yml`
- ✓ Terragrunt provisions per-user state (`users/${DEVBOX_USER}/devbox.tfstate`) in an encrypted S3 backend with DynamoDB locks — `terragrunt.hcl:12-25`
- ✓ Terraform module creates `aws_security_group.devbox` + `aws_instance.devbox` from the baked AMI — `terraform/main.tf`
- ✓ Lifecycle scripts drive `aws ec2 start/stop/wait` and surface connection info — `scripts/devbox-{start,stop,status}.sh`
- ✓ Makefile is the single operator entry surface and threads `DEVBOX_USER` through every stage — `Makefile`
- ✓ CIS-style hardening baseline applied during AMI bake (real root password dropped, sshd config tightened) — `ansible/roles/amazon2023-cis/`
- ✓ Per-build randomized code-server and VNC passwords via Ansible `secrets` role; cleartext never lands in git — Phase 1 (SEC-01, SEC-02) — `ansible/roles/secrets/`
- ✓ Secrets published to AWS SSM Parameter Store SecureString and fetched at boot by a systemd oneshot via IAM instance profile (scoped to `/devbox/${devbox_user}/*`); IMDSv2 enforced on the EC2 — Phase 1 (SEC-03) — `terraform/main.tf`, `ansible/roles/secrets/`
- ✓ Per-operator SSH keypair `${devbox_user}-devbox`; hardcoded `key_name = "me"` removed — Phase 1 (SEC-04) — `terragrunt.hcl`
- ✓ `gitleaks` v8.30.1 + `no-changeme` guard in `.pre-commit-config.yaml` and `.github/workflows/security.yml` — Phase 1 (SEC-05) — `.pre-commit-config.yaml`, `.github/workflows/security.yml`, `.gitleaks.toml`
- ✓ Security group `:22` ingress dropped entirely; operator connects via AWS SSM Session Manager (`AmazonSSMManagedInstanceCore` attached to `aws_iam_role.devbox`); `:8080` and `:6080` gated on `var.allowed_web_cidrs` with default `[]` + plan-time validation refusing apply when empty unless `var.allow_open_ingress=true` — Phase 2 (NET-01, NET-02, NET-03, NET-04) — `terraform/main.tf`, `terraform/variables.tf`, `terragrunt.hcl`
- ✓ Operator UX wired for SSM-first posture: `make devbox-ssm`, `make devbox-port-forward`, `make devbox-allowlist-me`; status/start scripts surface SSM commands; `scripts/devbox-ssm.sh` and `scripts/devbox-allowlist-me.sh` pre-flight `session-manager-plugin` — Phase 2 — `Makefile`, `scripts/`
- ✓ Terraform provider lockfile committed for 4 platforms (`darwin_{arm64,amd64}`, `linux_{amd64,arm64}`); `hashicorp/aws ~> 6.0` — Phase 3 (REP-01) — `terraform/.terraform.lock.hcl`, `terraform/main.tf`
- ✓ All Ansible Galaxy collections pinned with `==X.Y.Z` (community.general==12.6.0, community.crypto==3.2.0, ansible.posix==2.1.0, community.aws==9.0.0) — Phase 3 (REP-02) — `ansible/requirements.yml`, `ansible/roles/AMAZON2023-CIS/collections/requirements.yml`
- ✓ Galaxy roles: satisfied by absence (no roles in either requirements.yml) — Phase 3 (REP-03)
- ✓ Packer source AMI pinned via `amazon-parameterstore` data source on `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64` (no `most_recent = true`; `:NN` version-suffix bump procedure documented inline; Phase 4 CI gate will catch unpinned regressions) — Phase 3 (REP-04) — `packer/devimage.pkr.hcl`
- ✓ AMI handoff automated: Packer manifest post-processor → `make packer-bake` parses with `jq` → writes `users/${DEVBOX_USER}.auto.tfvars`; hand-copied `ami_id` removed from `terragrunt.hcl` — Phase 3 (REP-05) — `packer/devimage.pkr.hcl`, `Makefile`, `terragrunt.hcl`

### Active

<!-- Milestone 1: Security hardening + CI baseline. All hypotheses until shipped. -->

- [ ] Add full CI pipeline (`terraform fmt -check`, `tofu validate`, `packer validate`, `ansible-lint`, `shellcheck`, `tfsec`/`checkov`) — Phase 4 (gitleaks gate already in via Phase 1)
- [ ] Extend pre-commit to mirror full CI checks — Phase 4 (gitleaks + no-changeme already in)
- [ ] Document the firewalld-docker workaround and audit whether it can be replaced with a CIS-compliant equivalent — Phase 4 — `ansible/firewalld-docker-fix.yml`
- [ ] Resolve Packer SSM parameter `:NN` version pin — Phase 4 deferred follow-up (requires AWS creds to query `aws ssm get-parameter-history`)

### Out of Scope

- Multi-region / multi-cloud — single AWS region per operator, dev workstation use case only
- Multi-tenant / shared infrastructure — every operator gets their own state file and EC2 instance by design
- GUI/web UI for managing the devbox — Makefile + AWS CLI is the deliberate UX
- Auto-scaling / fleet management — one box per user, stopped when idle
- Application code or product features — this repo only ships the workstation environment

## Context

**Origin:** Personal cloud workstation that an operator can start in the morning, work on, and stop overnight to save costs. Built incrementally on top of Amazon Linux 2023 with a CIS hardening layer.

**Current state:** Functional end-to-end (bake → provision → start/stop) but has known security holes documented in `.planning/codebase/CONCERNS.md` (3 CRITICAL, 12 HIGH, 6 MEDIUM, 13 LOW). The CRITICAL items make the host trivially exploitable if exposed to the public internet — fixing those is the explicit goal of Milestone 1.

**Codebase map:** Full reference material in `.planning/codebase/` (STACK, INTEGRATIONS, ARCHITECTURE, STRUCTURE, CONVENTIONS, TESTING, CONCERNS).

## Constraints

- **Tech stack**: Packer + Ansible + Terragrunt/Terraform-or-OpenTofu + AWS — established and not up for replacement in this milestone
- **Cloud**: AWS only (EC2, S3, DynamoDB, IAM)
- **Base image**: Amazon Linux 2023 minimal x86_64 (CIS hardening role is AL2023-specific)
- **Operator surface**: Must remain `make <target>` — no GUI, no extra CLI tools beyond what's already required (aws, jq, packer, tofu/terraform, terragrunt, ansible)
- **State**: Remote tfstate in S3 with DynamoDB lock is mandatory; never commit tfstate
- **Reproducibility**: After Milestone 1, builds must be byte-deterministic given a pinned base AMI + locked dependency versions
- **Secrets**: Must never appear in HCL, YAML, bash, or git history — use AWS Secrets Manager / SSM Parameter Store or per-build generation with operator delivery via AWS CLI

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| OpenTofu (`tofu`) over Terraform binary | License clarity, free, drop-in compatible | ✓ Good |
| Terragrunt for backend generation + per-user state | Avoids hand-maintained backend.tf per user; single source of `DEVBOX_USER` threading | ✓ Good |
| 14-layer toggleable Ansible role structure with `layer_config.yml` | Operators can opt out of layers (e.g., skip Java) without forking; manifest written to `/etc/devimage-manifest.yml` | ✓ Good |
| Per-build randomized secrets for code-server / VNC, delivered via AWS SSM Parameter Store SecureString | Eliminates `changeme` default; SSM SecureString chosen over Secrets Manager — $0/month at this scale vs $0.40/secret/month, identical KMS encryption, sufficient IAM granularity via path-prefix scoping. Per-build rotation happens at AMI bake; no rotation Lambda needed. | ✓ Phase 1 |
| Per-operator SSH key name `${devbox_user}-devbox` (replaces hardcoded `key_name = "me"`) | Per-operator isolation: no shared keypair authorized across all devboxes. Keys live outside the repo (`aws ec2 import-key-pair`), keeping public-key material out of tfstate. Rotation = `delete-key-pair` + `import-key-pair` + `terraform destroy/apply` to push the new public key. | ✓ Phase 1 |
| AWS SSM Session Manager vs SSH ingress CIDR list (NET-04) | **Hybrid posture chosen:** SSM Session Manager for shell access (eliminates :22 ingress entirely) + operator-supplied CIDR allowlist for code-server (:8080) and noVNC (:6080). Rationale: Phase 1 already laid the IAM groundwork (`aws_iam_role.devbox` + IMDSv2-enforced instance), so attaching `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` is a 3-line Terraform change; web ports cannot run "through SSM" the same way as SSH without imposing a daily port-forwarding tax, so CIDR-restricted public ingress is retained for them. NET-01 satisfied by **deletion** of the :22 ingress rule (strictly more restrictive than narrowing to a CIDR). Rollback: revert the Phase 2 commits — operator surface reverts to `ssh -i ~/.ssh/${USER}-devbox.pem ec2-user@<ip>` with the old SG (would need a one-shot manual CIDR add). | ✓ Phase 2 |
| CI on GitHub Actions vs alternative | Default to GH Actions (free for personal use, matches repo host) | — Pending (Milestone 1) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-14 after Phase 3 (Reproducibility & version pinning) complete*
