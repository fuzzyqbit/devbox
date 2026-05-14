# Roadmap: devbox

## Active Milestone

(none — Milestone 2 not yet defined; run `/gsd-new-milestone` to start)

## Shipped Milestones

| Version | Shipped | Phases | Plans | Requirements | Archive |
|---------|---------|-------:|------:|-------------:|---------|
| v1.0 — Security hardening + CI baseline | 2026-05-14 | 4 | 10 | 23/23 | [v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md) |

## Pending (Deferred)

Carried from prior milestones; pick up in a future cycle:

- **Observability** (v2): CloudWatch metrics + login event shipping
- **Lifecycle** (v2): Idle auto-stop + scheduled nightly stop
- **Image lifecycle** (v2): Old AMI deregistration + inventory
- **Reproducibility follow-up** (v2): Pin Packer SSM parameter `:NN` version suffix (requires AWS creds)
