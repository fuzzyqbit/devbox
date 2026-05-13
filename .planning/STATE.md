# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-13 after Phase 1)

**Core value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one `make` target — without leaking credentials or exposing a vulnerable host to the public internet.
**Current focus:** Phase 2 — Network exposure remediation

## Current Position

Phase: 2 of 4 (Network exposure remediation)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-05-13 — Phase 1 complete; verifier verdict COMPLETE; 5 of 23 requirements done (SEC-01..SEC-05)

Progress: [██░░░░░░░░] 22% (5 of 23 v1 requirements complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: ~9 min (executor wall time)
- Total execution time: ~26 min (Wave 1 ~7 min parallel + Wave 2 ~11 min + Verifier ~4 min + plan + research + check)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 1 | 3 | ~26 min | ~9 min |

**Recent Trend:**
- Last 3 plans: 01-01 (~7 min), 01-03 (~7 min, parallel with 01-01), 01-02 (~11 min)
- Trend: Stable; Wave 2's larger scope (Terraform IAM + IMDSv2 + 4 new task files) drove the higher duration

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Phase 1 added:

- Phase 1: SSM Parameter Store SecureString over Secrets Manager ($0 vs $0.40/secret/mo at this scale; identical KMS encryption; path-prefix IAM scoping works)
- Phase 1: Per-build randomization happens at AMI bake; no rotation Lambda needed
- Phase 1: Per-operator SSH key `${devbox_user}-devbox`; public-key material lives outside the repo via `aws ec2 import-key-pair`
- Phase 1: IMDSv2 enforced (`http_tokens=required`, `hop_limit=1`); `DevboxUser` tag exposed via `instance_metadata_tags=enabled` to avoid `ec2:DescribeTags` IAM grant
- Phase 1: gitleaks v8.30.1 + local `no-changeme` guard; GitHub Actions SHA-pinned (real 40-char hex)

### Pending Decisions

- Phase 2: AWS SSM Session Manager (removes port 22 ingress entirely) vs CIDR allowlist (simpler, but still exposes 22 to operator IPs). Recorded in PROJECT.md as Pending.

### Pending Todos

None.

### Blockers/Concerns

- Operator migration required before next `make tg-apply`:
  1. `aws ec2 import-key-pair --key-name "${USER}-devbox" --public-key-material "fileb://$HOME/.ssh/${USER}-devbox.pub"` (Phase 1 renamed `key_name` from `"me"`)
  2. `var.iam_instance_profile` removed from `terraform/variables.tf` — any external consumers must drop the input
  3. Pre-Phase-1 baked AMIs still ship `changeme`; rebake before re-launch
- Remaining CONCERNS.md HIGH items: 12 (CRITICAL all closed by Phase 1; remaining HIGH spread across Phase 2-4)

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Observability | CloudWatch metrics + login event shipping | v2 | 2026-05-13 (init) |
| Lifecycle | Idle auto-stop + scheduled nightly stop | v2 | 2026-05-13 (init) |
| Image lifecycle | Old AMI deregistration + inventory | v2 | 2026-05-13 (init) |

## Session Continuity

Last session: 2026-05-13 18:50
Stopped at: Phase 1 verification COMPLETE; STATE/ROADMAP/PROJECT/REQUIREMENTS updated; ready for `/gsd-plan-phase 2`
Resume file: None
