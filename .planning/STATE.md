---
gsd_state_version: 1.0
milestone: null
milestone_name: null
status: between-milestones
last_updated: "2026-06-09T13:43:42.048Z"
last_activity: 2026-06-09
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-02 after v3.0 milestone start)

**Core value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one command — without leaking credentials or exposing a vulnerable host to the public internet.
**Current focus:** No active milestone. noVNC HTTPS-only shipped as quick task `260609-dif` (`novnc_proxy --ssl-only`); the planned v3.1 nginx milestone was abandoned. Start the next with `/gsd:new-milestone`.

## Current Position

Phase: Not started (between milestones)
Plan: —
Status: Between milestones
Last activity: 2026-06-09 — Quick task 260609-dif (noVNC --ssl-only); v3.1 nginx milestone abandoned

## Performance Metrics (v1.0)

| Phase | Plans | Total wall | Avg/Plan |
|-------|------:|-----------:|---------:|
| Phase 1 | 3 | ~26 min | ~9 min |
| Phase 2 | 2 | ~22 min | ~11 min |
| Phase 3 | 2 | ~19 min (parallel) | ~9 min |
| Phase 4 | 3 | ~10 min (parallel) | ~7 min |
| **v1.0 total** | **10** | **~77 min execution** | **~8 min** |

Calendar window: 2026-05-13 17:04 → 2026-05-14 10:58 (~18 hours wall clock; ~77 min active executor time).
Commits: 66 in `b0bd004..7e63829`. Files changed: 75 (+14488 / −69 LOC).

**Trend:** Parallel-safe phases (3 + 4) demonstrably faster wall-clock than serial (1 + 2).

### v2.0 Performance Metrics

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 05 | 01 | 5min | 2 | 1 |
| 06 P01 | 5min | 1 tasks | 1 files |
| 06 P02 | 4min | 2 tasks | 3 files |

## Accumulated Context

See PROJECT.md Key Decisions table. Locked v1.0 decisions:

- SSM Parameter Store SecureString (vs Secrets Manager)
- Hybrid network posture (SSM SM + CIDR allowlist for web)
- Packer manifest → auto.tfvars AMI handoff
- Checkov (NOT tfsec / Trivy / KICS — supply-chain incidents March 2026)
- Parallel CI jobs; tiered pre-commit (fast at commit, slow at push)
- Terragrunt dropped post-v1.0; `./run` drives `tofu` directly with `-backend-config` flags

**v2.0 decisions:**

- Makefile is deleted as the final step (Phase 7) — not before CI and `./run` are verified working
- Research build order: dispatcher + guards → CI integration → docs/cleanup
- Existing `scripts/*.sh` stay as helpers called by `./run` (no consolidation into the script body)
- Standalone `./run` dispatcher: does not source `_common.sh`; lazy TF_STATE_BUCKET derivation; DEVBOX_USER regex validation added

**v3.0 decisions (at roadmap time):**

- Jupyter reuses the existing `secrets` role pattern (per-build random password → SSM SecureString `/devbox/${devbox_user}/jupyter-password`) — same as code-server / VNC
- Jupyter uses the existing `aws_security_group.devbox` with an added ingress rule for :8888 (no new SG) — governed by `var.allowed_web_cidrs`
- mise is binary-only: no committed `.mise.toml`, no migration of existing Ansible language layers
- Phase split: Phase 8 = Ansible/AMI work (Jupyter service + secrets + mise); Phase 9 = Terraform + `./run` operator surface
- `hardening` invariant enforced: Jupyter Ansible role inserted before `hardening` (JUP-08)

## Deferred / Carried Forward

| Category | Item | Status | Originated |
|----------|------|--------|-----------|
| Observability | CloudWatch metrics + login event shipping | v3 backlog | v1.0 init |
| Lifecycle | Idle auto-stop + scheduled nightly stop | v3 backlog | v1.0 init |
| Image lifecycle | Old AMI deregistration + inventory | v3 backlog | v1.0 init |
| Reproducibility | SSM `:NN` version suffix on Packer source | v3 follow-up | v1.0 Phase 3 |
| uat_gap | 05-HUMAN-UAT.md (3 scenarios) | partial — needs live AWS/devbox | v2.0 close |
| uat_gap | 06-HUMAN-UAT.md (3 scenarios) | partial — needs live AWS/devbox | v2.0 close |
| verification_gap | 05-VERIFICATION.md | human_needed | v2.0 close |
| verification_gap | 06-VERIFICATION.md | human_needed | v2.0 close |
| quick_task | 260520-be1-create-gitlab-ci-pipeline-packer-build-a | completed (has SUMMARY); unarchived orphan | v2.0 close (re-deferred v3.0) |
| uat_gap | 08-HUMAN-UAT.md (2 scenarios: Jupyter venv + mise --version) | partial — needs live AMI bake | v3.0 close |
| verification_gap | 08-VERIFICATION.md | human_needed — bake-time runtime checks | v3.0 close |
| tech_debt | WR-05: bootstrap .sh.j2 outside CI shellcheck glob | open follow-up | v3.0 close |

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260520-be1 | create gitlab CI pipeline: packer build AMI then tofu apply EC2 from that AMI | 2026-05-20 | 72f3157 | [260520-be1-create-gitlab-ci-pipeline-packer-build-a](./quick/260520-be1-create-gitlab-ci-pipeline-packer-build-a/) |
| 260602-add-golang-dev-tools | add 11 pinned Go developer tools (gopls, dlv, golangci-lint, govulncheck, …) to the golang role | 2026-06-02 | 88541f0 | [260602-add-golang-dev-tools](./quick/260602-add-golang-dev-tools/) |
| 260609-dif | enforce noVNC HTTPS-only via `novnc_proxy --ssl-only` (dropped the planned v3.1 nginx milestone) | 2026-06-09 | fb59449 | [260609-dif-enforce-https-only-on-novnc-via-novnc-pr](./quick/260609-dif-enforce-https-only-on-novnc-via-novnc-pr/) |

## Session Continuity

Last session: 2026-06-09 — quick task `260609-dif` (noVNC `--ssl-only`); started v3.1 noVNC HTTPS-Only as a full nginx milestone, then collapsed it to the one-line flag and abandoned the phased scaffold.
Stopped at: between milestones (no active milestone)
Next: `/gsd:new-milestone` — start the next milestone (Observability / Lifecycle / Image-lifecycle queued)

## Operator Next Steps

- (Optional) `DEVBOX_USER=$(whoami) ./run build` then confirm noVNC: `novnc.service` starts with `--ssl-only`, `wss://<host>:6080` connects, plain `http://<host>:6080` refused (quick task `260609-dif` bake-time UAT)
- (Optional) same bake clears the carried Phase-8 checks (Jupyter venv, `mise --version`, Go tools)
- `/gsd:new-milestone` — define the next milestone (Observability / Lifecycle / Image-lifecycle are queued in Pending)
