# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-13 after Phase 2)

**Core value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one `make` target — without leaking credentials or exposing a vulnerable host to the public internet.
**Current focus:** Phase 3 — Reproducibility & version pinning

## Current Position

Phase: 3 of 4 (Reproducibility & version pinning)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-05-13 — Phase 2 complete; verifier verdict COMPLETE; 9 of 23 requirements done (SEC-01..05, NET-01..04). All 3 CRITICAL CONCERNS.md findings closed.

Progress: [████░░░░░░] 39% (9 of 23 v1 requirements complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 5 (Phase 1: 3 plans, Phase 2: 2 plans)
- Average duration: ~10 min wall time per plan
- Total phase-execution time: Phase 1 ~26 min, Phase 2 ~22 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 1 | 3 | ~26 min | ~9 min |
| Phase 2 | 2 | ~22 min | ~11 min |

**Recent Trend:**
- Last 5 plans: 01-01 (~7m), 01-03 (~7m parallel), 01-02 (~11m), 02-01 (~11m), 02-02 (~11m)
- Trend: Stable; sequential waves naturally slower than parallel

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Phase 2 added:

- Phase 2 (NET-04): Hybrid posture — SSM Session Manager for shell (eliminates :22 ingress), CIDR allowlist for code-server/noVNC
- Phase 2: `var.allowed_web_cidrs` default `[]` with plan-time validation refusing apply unless `var.allow_open_ingress=true` (escape hatch off by default)
- Phase 2: AL2023 SSM Agent preinstalled — no Ansible role added; `session-manager-plugin` declared as operator-side CLI prereq (surface to Phase 4 DOC-01)
- Phase 2: `devbox-port-forward` covers :8080 only (`AWS-StartPortForwardingSession` single-port); :6080 either gets CIDR allowlist or a second SSM session

### Pending Decisions

- Phase 3: How to source the AMI ID — `data "aws_ami"` filter vs Terragrunt input wired from Packer manifest output
- Phase 3: Specific pinned versions for ansible-galaxy collections (Phase 1 already pinned `community.aws=9.0.0`; others still float)

### Pending Todos

None.

### Blockers/Concerns

- Operator migration required before next `make tg-apply` (in addition to Phase 1 items):
  - Set `CODE_SERVER_ALLOWED_CIDRS` / `VNC_ALLOWED_CIDRS` env vars OR run `make devbox-allowlist-me` (auto-populates `users/${DEVBOX_USER}.auto.tfvars`); otherwise `tofu plan` refuses
  - Install `session-manager-plugin` locally (`brew install --cask session-manager-plugin` on Mac)
  - Existing in-flight devbox: SG tighten on next apply will not kick active sessions, but SSH reconnects fail; use `make devbox-ssm` instead
- Remaining CONCERNS.md HIGH items: ~8 (all 3 CRITICAL closed; HIGH spread across Phase 3 reproducibility and Phase 4 CI gaps)

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Observability | CloudWatch metrics + login event shipping | v2 | 2026-05-13 (init) |
| Lifecycle | Idle auto-stop + scheduled nightly stop | v2 | 2026-05-13 (init) |
| Image lifecycle | Old AMI deregistration + inventory | v2 | 2026-05-13 (init) |

## Session Continuity

Last session: 2026-05-13 (Phase 2 close)
Stopped at: Phase 2 verification COMPLETE; STATE/ROADMAP/PROJECT/REQUIREMENTS updated; ready for `/gsd-plan-phase 3`
Resume file: None
