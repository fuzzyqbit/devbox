# devbox

## Current State

**Shipped:** v3.0 (2026-06-02) — Jupyter + mise · v2.0 (2026-06-02) — Run script + GitLab CI integration · v1.0 (2026-05-14) — Security hardening + CI baseline

Personal cloud workstation that bakes an AL2023 AMI and provisions per-user EC2 from it. End-to-end secure-by-default: per-build secrets via SSM Parameter Store + IAM instance profile + IMDSv2; SSM Session Manager for shell (no port 22); CIDR-allowlisted code-server (:8080) + noVNC (:6080); loopback-only on-demand JupyterLab (`./run jupyter`); reproducible builds via committed `.terraform.lock.hcl` + pinned Galaxy collections + Packer source via SSM Parameter Store + manifest-driven AMI handoff; CI + tiered pre-commit gates against every invariant. The operator surface is a single `./run` shell dispatcher (the Makefile was retired in v2.0); the GitLab CI pipeline calls `./run` for bake + deploy.

noVNC HTTPS-only enforcement shipped as quick task `260609-dif` (2026-06-09) — `novnc_proxy --ssl-only` rejects plaintext on `:6080`. The originally-planned v3.1 nginx-reverse-proxy milestone (redirect + HSTS + headers) was abandoned in favour of the one-line flag; nginx research archived to `milestones/v3.1-abandoned-research/`.

**Deferred to a later cycle:** observability (CloudWatch metrics + login events), lifecycle automation (idle auto-stop, scheduled stop), image lifecycle (old AMI deregistration + inventory), Packer SSM `:NN` version pin (requires AWS creds).

## Current Milestone: v4.1 Google Chrome in desktop role

**Goal:** Every desktop bake ships Google Chrome, installed from Google's signed dnf repo at bake time.

**Target features:**
- `google-chrome-stable` installed inside the existing `desktop` role — no new layer flag; applies whenever `layers.desktop` is on
- Google's official dnf repo config + GPG key baked; GPG verification stays ON (airgap-posture consistent)
- Latest-at-bake version policy (Google's repo serves only the current stable — historic RPMs are not hosted); exact baked version captured by the existing SBOM pass + build manifest
- Bake-assert: chrome binary present + executes headlessly (bake-green-but-dead guard); post-hardening survival check if hardening touches its deps

**Key decisions:** No sub-gate flag (unlike `vscode_desktop`) — Chrome is unconditional desktop content. Latest-at-bake accepted over a strict pin (pin would break every bake on Chrome's ~4-6-week release cadence); remediation for a bad version is rebake, matching the SPAL/xrdp precedent.

## Shipped since last archive (bookkeeping pending)

GSD archival (`complete-milestone`) has not run since v3.0; the following shipped to `main` outside or after v4.0's records — STATE.md/MILESTONES.md were stale until v4.1 started:

- **v4.0 Amazon DCV** — code-complete, merged 2026-06-26 (dcv role, `:8443`, airgap license path via S3 VPC endpoint). Live UAT still open.
- **xrdp re-added** (quick-task `260707-o7s`, merged 2026-07-13) — SPAL xrdp/xorgxrdp on `:3389` as a second, WebGL-free desktop path ADDITIVE to DCV. Deliberately reverses v4.0's "full removal" bullet; CIS 2.2.1 scoped off for xrdp builds. See CLAUDE.md §8.
- **persistent-home** (merged 2026-06-26) — separate `/home` EBS volume + DLM snapshots + `prevent_destroy` (obsoletes SEED-001's core idea).
- **ai_tools role** (merged 2026-07-14, PR #6) — pinned agentic AI CLIs (claude, codex, opencode).
- **kion-creds** (branch `feat/kion-creds`, pushed 2026-07-22, UNMERGED) — Kion STAK fetcher role (`layers.kion`), final review "Ready to merge", live token-endpoint verification in progress.

All live UAT items (DCV, xrdp, ai-tools first-bake, kion-creds endpoints) remain open; next `tf-apply` replaces the instance.

## Superseded: v3.2 XRDP Remote Desktop

Shipped code-complete (2026-06-16; phases 10–12, adversarially verified; RDP-14 live UAT was the only open gate). Superseded by v4.0 (Amazon DCV) before RDP-14 ran — DCV was re-validated as the preferred path. The xrdp/xorgxrdp role and its SG/operator-surface wiring are removed in v4.0. v3.2 planning records retained under `.planning/phases/10–12/` and the git history (`main` through `5ad3309`).

## Abandoned: v3.1 noVNC HTTPS-Only (nginx milestone)

Scoped 2026-06-09 around a TLS-terminating nginx reverse proxy in a new `novnc-proxy` role
(redirect + HSTS + security headers). Replaced by quick task `260609-dif`: `novnc_proxy`
already supports `--ssl-only`, which satisfies the core "reject plaintext" requirement with
one line and no new component. Tradeoff accepted: no HTTP→HTTPS redirect and no security
headers (HSTS) — websockify cannot emit them without a proxy. code-server (`:8080`) was
already HTTPS-only via `cert: true`. Research retained at
`milestones/v3.1-abandoned-research/` if redirect/headers are ever revisited.

## Shipped Milestone: v3.0 Jupyter + mise

**Delivered (2026-06-02):** JupyterLab + the `mise` version manager added to the baked AMI.
A mid-milestone security pivot replaced the originally-planned password-protected `0.0.0.0`
HTTPS systemd service with a **loopback-only, on-demand** model:
- JupyterLab installed in an isolated `/opt/jupyter` venv (pinned JupyterLab 4.5.7 + ipykernel 6.29.5, python3 kernel) via the `devtools` role; launched on demand with `./run jupyter` bound to `127.0.0.1:8888` and reached over an SSM port-forward. No systemd service, no TLS, no password — SSM/IAM is the auth boundary (eliminated code-review Critical CR-01).
- `mise` binary (checksum-pinned official jdx release) installed via the `devops` role with system-wide `/etc/profile.d` bash activation — binary only, no committed `.mise.toml`, existing per-language layers untouched.
- New grep-gate invariants (hardening-stays-last, no committed `.mise.toml`) mirrored across pre-commit + CI; `./run status` surfacing + `docs/DEVELOPER-LIFECYCLE.md` access flow.
- Superseded by the pivot: JUP-02 (systemd service), JUP-03/04 (password), JUP-05 (SG `:8888` ingress), JUP-06 (`secrets-show` password).

See `milestones/v3.0-ROADMAP.md` · `milestones/v3.0-REQUIREMENTS.md`.

## Shipped Milestone: v2.0 Run Script + GitLab CI Integration

**Delivered:** A single `./run` shell dispatcher replaces the Makefile entirely (locally + in CI); the GitLab CI pipeline calls `./run` for bake and deploy; all operator docs reference `./run`. 5 items deferred at close (human-UAT + verification needing live AWS — see STATE.md).

## What This Is

Personal infrastructure-as-code project that builds a hardened Amazon Linux 2023 AMI (Packer + Ansible) and provisions per-user EC2 dev environments from it (OpenTofu; Terragrunt was dropped post-v1.0). The resulting EC2 instance runs code-server (browser VS Code) on :8080 and noVNC on :6080, reached via AWS SSM Session Manager (no public :22). The operator surface is a single `./run` shell dispatcher (retired the Makefile in v2.0) wrapping lifecycle scripts for build/provision/start/stop/status/connect. No application source code lives here — purely declarative IaC + bash glue.

## Core Value

A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one `./run` command — without leaking credentials or exposing a vulnerable host to the public internet.

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
- ✓ Full CI pipeline: 8 parallel SHA-pinned jobs in `.github/workflows/ci.yml` covering `tofu fmt -check`, `tofu init -lockfile=readonly` + `tofu validate`, `packer validate`, `ansible-lint`, `ansible-playbook --syntax-check`, `shellcheck`, Checkov (`--hard-fail-on HIGH`), and 6 Phase-3 grep-gates — Phase 4 (CI-01..CI-06) — `.github/workflows/ci.yml`, `.checkov.yaml`, `.ansible-lint`
- ✓ Tiered pre-commit hooks: fast (gitleaks, no-changeme, tofu_fmt, terragrunt_fmt, shellcheck, packer fmt, grep-gates, hygiene) at `pre-commit`; slow (tofu_validate, ansible-lint, packer validate, Checkov) at `pre-push` — Phase 4 (CI-07) — `.pre-commit-config.yaml`
- ✓ Top-level `CLAUDE.md` operator quickstart (205 lines, 9 sections): prereqs, env vars, one-shot setup, daily flow, rotation procedures, troubleshooting — Phase 4 (DOC-01)
- ✓ `ansible/firewalld-docker-fix.yml` header expanded: what (firewalld + Docker bridge conflict), why (CIS role enables firewalld), 3 OR-joined retirement criteria + `firewall-cmd --get-default-zone` verification — Phase 4 (DOC-02)
- ✓ Standalone `./run` shell dispatcher (337 lines, shellcheck-clean) replaces all 20 Makefile targets; DEVBOX_USER regex validation, lazy `TF_STATE_BUCKET` derivation, `tf-ensure-init` auto-reinit — v2.0 Phase 5 (RUN-01…RUN-08) — `run`
- ✓ `NO_COLOR`/`CI`-aware colored output + `./run doctor` toolchain checker (bash 3.2-compatible dispatch) — v2.0 Phase 6 (POL-01, POL-02) — `run`
- ✓ GitLab CI bake + deploy stages delegate to `./run` (no inline shell); shellcheck + grep-gates extended to cover `run` — v2.0 Phase 6 (CI-01…CI-04) — `.gitlab-ci.yml`
- ✓ Makefile deleted; `./run` is the sole operator surface; all operator docs/scripts/TF strings reference `./run`; grep-gate invariant rejects retired `make <target>` invocations across pre-commit + GitLab + GitHub CI — v2.0 Phase 7 (DOC-01, DOC-02) — `.pre-commit-config.yaml`, `.gitlab-ci.yml`, `.github/workflows/ci.yml`

### Active

<!-- v1.0 complete 2026-05-14 (23 reqs). v2.0/v3.0 complete 2026-06-02. v3.2 requirements defined below. -->

(see Milestone v3.2 requirements in `.planning/REQUIREMENTS.md`)

### Out of Scope

- Multi-region / multi-cloud — single AWS region per operator, dev workstation use case only
- Multi-tenant / shared infrastructure — every operator gets their own state file and EC2 instance by design
- GUI/web UI for managing the devbox — `./run` + AWS CLI is the deliberate UX
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
- **Operator surface**: Single `./run <command>` dispatcher (Makefile retired in v2.0) — no GUI, no extra CLI tools beyond what's already required (aws, jq, packer, tofu/terraform, ansible; bash 4+ for `./run`)
- **State**: Remote tfstate in S3 with DynamoDB lock is mandatory; never commit tfstate
- **Reproducibility**: After Milestone 1, builds must be byte-deterministic given a pinned base AMI + locked dependency versions
- **Secrets**: Must never appear in HCL, YAML, bash, or git history — use AWS Secrets Manager / SSM Parameter Store or per-build generation with operator delivery via AWS CLI

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| OpenTofu (`tofu`) over Terraform binary | License clarity, free, drop-in compatible | ✓ Good |
| Terragrunt for backend generation + per-user state | Avoids hand-maintained backend.tf per user; single source of `DEVBOX_USER` threading | ⚠️ Removed post-v1.0 (May 2026) — Terragrunt's value didn't justify its weight at one-module / one-environment scale; replaced by partial `backend "s3" {}` in `terraform/backend.tf` + Makefile `-backend-config` derived from `aws sts get-caller-identity`. |
| 14-layer toggleable Ansible role structure with `layer_config.yml` | Operators can opt out of layers (e.g., skip Java) without forking; manifest written to `/etc/devimage-manifest.yml` | ✓ Good |
| Per-build randomized secrets for code-server / VNC, delivered via AWS SSM Parameter Store SecureString | Eliminates `changeme` default; SSM SecureString chosen over Secrets Manager — $0/month at this scale vs $0.40/secret/month, identical KMS encryption, sufficient IAM granularity via path-prefix scoping. Per-build rotation happens at AMI bake; no rotation Lambda needed. | ✓ Phase 1 |
| Per-operator SSH key name `${devbox_user}-devbox` (replaces hardcoded `key_name = "me"`) | Per-operator isolation: no shared keypair authorized across all devboxes. Keys live outside the repo (`aws ec2 import-key-pair`), keeping public-key material out of tfstate. Rotation = `delete-key-pair` + `import-key-pair` + `terraform destroy/apply` to push the new public key. | ✓ Phase 1 |
| AWS SSM Session Manager vs SSH ingress CIDR list (NET-04) | **Hybrid posture chosen:** SSM Session Manager for shell access (eliminates :22 ingress entirely) + operator-supplied CIDR allowlist for code-server (:8080) and noVNC (:6080). Rationale: Phase 1 already laid the IAM groundwork (`aws_iam_role.devbox` + IMDSv2-enforced instance), so attaching `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` is a 3-line Terraform change; web ports cannot run "through SSM" the same way as SSH without imposing a daily port-forwarding tax, so CIDR-restricted public ingress is retained for them. NET-01 satisfied by **deletion** of the :22 ingress rule (strictly more restrictive than narrowing to a CIDR). Rollback: revert the Phase 2 commits — operator surface reverts to `ssh -i ~/.ssh/${USER}-devbox.pem ec2-user@<ip>` with the old SG (would need a one-shot manual CIDR add). | ✓ Phase 2 |
| CI on GitHub Actions vs alternative | Default to GH Actions (free for personal use, matches repo host) | ✓ Good — GH Actions + GitLab CI both maintained |
| Single `./run` bash dispatcher replaces the Makefile (v2.0) | One source of truth for operator + CI commands; `make` semantics (var=val args) gave way to env-prefix form (`DEVBOX_USER=x ./run tf-apply`). Standalone script (does not source `_common.sh`); bash 4+ required (guarded). | ✓ v2.0 |
| grep-gate scoped to former Makefile target names, not blanket `make ` (v2.0 Phase 7) | A blanket match false-positives on the genuine `make -j` C++/thrift build in `ansible/roles/devtools` and English prose. Target-name scoping enforces "no retired operator invocation" without those false hits. | ✓ v2.0 |

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
*Last updated: 2026-07-24 — v4.1 Google Chrome in desktop role milestone started.*
