# Requirements: devbox

**Defined:** 2026-05-13
**Core Value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one `make` target — without leaking credentials or exposing a vulnerable host to the public internet.

## v1 Requirements

Milestone 1 — Security hardening + CI baseline. Closes all CRITICAL / HIGH findings in `.planning/codebase/CONCERNS.md` and adds automated gates so they cannot regress.

### Secrets

- [ ] **SEC-01**: code-server (:8080) password is generated per-build, never `changeme`, never in HCL/YAML/git
- [ ] **SEC-02**: VNC (:6080) password is generated per-build, never `changeme`, never in HCL/YAML/git
- [ ] **SEC-03**: Generated secrets are stored in AWS Secrets Manager or SSM Parameter Store and fetched by the running EC2 via instance-profile IAM (no static keys on disk)
- [ ] **SEC-04**: SSH keypair is per-operator, not the hardcoded `me` key; documented procedure for rotation
- [ ] **SEC-05**: `gitleaks` (or equivalent) scan runs in CI and pre-commit; build fails on any detected secret

### Network exposure

- [ ] **NET-01**: Security group ingress for SSH (:22) is restricted to operator-supplied CIDR list (default: `[]`, refuses to apply if empty without explicit override) — replace `0.0.0.0/0` in `terraform/main.tf`
- [ ] **NET-02**: Security group ingress for code-server (:8080) is restricted to operator-supplied CIDR list
- [ ] **NET-03**: Security group ingress for noVNC (:6080) is restricted to operator-supplied CIDR list
- [ ] **NET-04**: Decision recorded in PROJECT.md key decisions: AWS SSM Session Manager for SSH vs CIDR allowlist (implement chosen option)

### Reproducibility / version pinning

- [ ] **REP-01**: `.terraform.lock.hcl` removed from `.gitignore` and committed
- [ ] **REP-02**: `ansible/requirements.yml` collections pinned to exact versions
- [ ] **REP-03**: Galaxy roles pinned to exact versions (no floating refs)
- [ ] **REP-04**: Packer source AMI replaced with pinned snapshot ID or pinned filter (no `most_recent = true` for unpinned filters)
- [ ] **REP-05**: AMI ID consumed by Terraform via `data "aws_ami"` lookup with deterministic filter, or Terragrunt input wired from Packer manifest output (no hand-copied IDs)

### CI / pre-commit gates

- [ ] **CI-01**: GitHub Actions workflow runs on every push and PR
- [ ] **CI-02**: CI runs `terraform fmt -check` and `tofu validate`
- [ ] **CI-03**: CI runs `packer validate` against `packer/devimage.pkr.hcl`
- [ ] **CI-04**: CI runs `ansible-lint` and `ansible-playbook --syntax-check`
- [ ] **CI-05**: CI runs `shellcheck` on every `scripts/*.sh`
- [ ] **CI-06**: CI runs `tfsec` or `checkov` against `terraform/`; build fails on HIGH/CRITICAL findings
- [ ] **CI-07**: Pre-commit hooks (`.pre-commit-config.yaml`) mirror the CI checks for local feedback

### Documentation

- [ ] **DOC-01**: Top-level `CLAUDE.md` (currently empty) documents operator quickstart, env vars (`DEVBOX_USER`, region), and the bake → provision → start flow
- [ ] **DOC-02**: `ansible/firewalld-docker-fix.yml` documents what the workaround does, why it's needed, and the conditions under which it can be retired

## v2 Requirements

Deferred to future milestone(s). Tracked but not in current roadmap.

### Observability

- **OBS-01**: CloudWatch agent installed and exporting host metrics (CPU, mem, disk, network)
- **OBS-02**: SSH and code-server login events shipped to CloudWatch Logs
- **OBS-03**: Cost guardrail: alarm when monthly EC2 cost crosses operator-defined threshold

### Lifecycle automation

- **LIFE-01**: Auto-stop EC2 after N hours of idleness (idle = no SSH/code-server activity)
- **LIFE-02**: Scheduled nightly stop with `make` opt-out for long-running work

### Image lifecycle

- **IMG-01**: Old AMIs older than N days are deregistered and their snapshots deleted
- **IMG-02**: AMI inventory accessible via `make ami-list`

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-region / multi-cloud | Personal dev workstation; one region is sufficient |
| Multi-tenant / shared instance | Each operator gets their own state file and EC2 by design |
| GUI / web operator console | Makefile + AWS CLI is the deliberate UX |
| Auto-scaling / fleet management | One box per user; stopped when idle |
| Application source code in this repo | This repo only ships the workstation environment |
| ARM64 / Graviton support in Milestone 1 | x86_64 only until base image and toolchain ports are reviewed |
| Windows / non-Linux base images | Linux only; AL2023 CIS role is Linux-specific |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SEC-01 | Phase 1 | Complete |
| SEC-02 | Phase 1 | Complete |
| SEC-03 | Phase 1 | Complete |
| SEC-04 | Phase 1 | Complete |
| SEC-05 | Phase 1 | Complete |
| NET-01 | Phase 2 | Complete |
| NET-02 | Phase 2 | Complete |
| NET-03 | Phase 2 | Complete |
| NET-04 | Phase 2 | Complete |
| REP-01 | Phase 3 | Pending |
| REP-02 | Phase 3 | Pending |
| REP-03 | Phase 3 | Pending |
| REP-04 | Phase 3 | Pending |
| REP-05 | Phase 3 | Pending |
| CI-01 | Phase 4 | Pending |
| CI-02 | Phase 4 | Pending |
| CI-03 | Phase 4 | Pending |
| CI-04 | Phase 4 | Pending |
| CI-05 | Phase 4 | Pending |
| CI-06 | Phase 4 | Pending |
| CI-07 | Phase 4 | Pending |
| DOC-01 | Phase 4 | Pending |
| DOC-02 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 23
- Complete: 9 (Phase 1 SEC-01..05 + Phase 2 NET-01..04)
- Pending: 14 (Phases 3-4)

---
*Requirements defined: 2026-05-13*
*Last updated: 2026-05-13 after Phase 2 complete*
