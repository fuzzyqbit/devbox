# Roadmap: devbox

## Milestones

- ✅ **v1.0 — Security hardening + CI baseline** — Phases 1-4 (shipped 2026-05-14)
- ✅ **v2.0 — Run Script + GitLab CI Integration** — Phases 5-7 (shipped 2026-06-02)
- ✅ **v3.0 — Jupyter + mise** — Phases 8-9 (shipped 2026-06-02)

## Phases

<details>
<summary>✅ v1.0 — Security hardening + CI baseline (Phases 1-4) — SHIPPED 2026-05-14</summary>

Full detail: [milestones/v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [milestones/v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md)

</details>

<details>
<summary>✅ v2.0 — Run Script + GitLab CI Integration (Phases 5-7) — SHIPPED 2026-06-02</summary>

Replaced the Makefile with a single `./run` shell dispatcher that works locally and in CI,
wired the GitLab CI pipeline to call `./run`, and retired the Makefile entirely.

- [x] Phase 5: Run Script Core (1/1 plan) — `./run` dispatcher with all 20 commands + safety guards. Requirements: RUN-01…RUN-08
- [x] Phase 6: GitLab CI + Polish (2/2 plans) — CI delegates to `./run`; colored output + `./run doctor`. Requirements: CI-01…CI-04, POL-01, POL-02
- [x] Phase 7: Docs + Cleanup (1/1 plan) — CLAUDE.md → `./run`; Makefile deleted; grep-gate invariant. Requirements: DOC-01, DOC-02

Full detail: [milestones/v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [milestones/v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md)

</details>

<details>
<summary>✅ v3.0 — Jupyter + mise (Phases 8-9) — SHIPPED 2026-06-02</summary>

Added JupyterLab + the `mise` version manager to the baked AMI. Shipped JupyterLab as
**loopback-only, on-demand** (`./run jupyter` → `127.0.0.1:8888` over SSM; no systemd
service, no password, no TLS) after a mid-milestone pivot, plus a checksum-pinned `mise`
binary with system-wide shell activation (folded into the `devops` role).

- [x] Phase 8: Jupyter + mise AMI Layer (4/4 plans) — loopback `/opt/jupyter` venv + checksum-pinned mise. Requirements: JUP-01/08, MISE-01…03 (JUP-02/03/04 superseded)
- [x] Phase 9: Jupyter Operator Surface + Docs (1/1 plan) — `./run status` surfacing + DEVELOPER-LIFECYCLE docs. Requirements: JUP-07 (JUP-05/06 superseded)

Full detail: [milestones/v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md)

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-4 | v1.0 | 10/10 | Complete | 2026-05-14 |
| 5. Run Script Core | v2.0 | 1/1 | Complete | 2026-05-27 |
| 6. GitLab CI + Polish | v2.0 | 2/2 | Complete | 2026-05-27 |
| 7. Docs + Cleanup | v2.0 | 1/1 | Complete | 2026-06-02 |
| 8. Jupyter + mise AMI Layer | v3.0 | 4/4 | Complete | 2026-06-02 |
| 9. Jupyter Operator Surface + Docs | v3.0 | 1/1 | Complete | 2026-06-02 |

## Shipped Milestones

| Version | Shipped | Phases | Plans | Requirements | Archive |
|---------|---------|-------:|------:|-------------:|---------|
| v1.0 — Security hardening + CI baseline | 2026-05-14 | 4 | 10 | 23/23 | [v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md) |
| v2.0 — Run Script + GitLab CI Integration | 2026-06-02 | 3 | 4 | DOC/RUN/CI/POL | [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) |
| v3.0 — Jupyter + mise | 2026-06-02 | 2 | 5 | 6 delivered / 5 superseded | [v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) |

## Pending (Deferred)

Carried from prior milestones; pick up in a future cycle:

- **Observability** (v3): CloudWatch metrics + login event shipping
- **Lifecycle** (v3): Idle auto-stop + scheduled nightly stop
- **Image lifecycle** (v3): Old AMI deregistration + inventory
- **Reproducibility follow-up** (v3): Pin Packer SSM parameter `:NN` version suffix (requires AWS creds)
