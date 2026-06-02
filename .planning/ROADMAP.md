# Roadmap: devbox

## Milestones

- ✅ **v1.0 — Security hardening + CI baseline** — Phases 1-4 (shipped 2026-05-14)
- ✅ **v2.0 — Run Script + GitLab CI Integration** — Phases 5-7 (shipped 2026-06-02)
- 📋 **v3.0 — Jupyter + mise** — Phases 8-9 (active)

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

### 📋 v3.0 — Jupyter + mise (Phases 8-9)

- [x] **Phase 8: Jupyter + mise AMI Layer** — Ship JupyterLab in a loopback `/opt/jupyter` venv launchable on demand via `./run jupyter` (no systemd/TLS/password), and install the mise binary with ec2-user shell activation (completed 2026-06-02)
- [ ] **Phase 9: Jupyter Operator Surface + Docs** — Surface the on-demand Jupyter flow in `./run status` and document the `./run jupyter` + manual `:8888` SSM port-forward access path

## Phase Details

### Phase 8: Jupyter + mise AMI Layer
**Goal**: The baked AMI ships JupyterLab in an isolated `/opt/jupyter` venv, launchable on demand bound to loopback (`127.0.0.1:8888`) via `./run jupyter` over SSM — no systemd service, no password, no TLS (SSM/IAM is the auth boundary) — and ships the mise binary ready for ec2-user
**Depends on**: Phase 7 (v2.0 complete; `./run` is the operator surface; `secrets` role and `hardening` role patterns established)
**Requirements**: JUP-01, JUP-02, JUP-08, MISE-01, MISE-02, MISE-03  (JUP-03/JUP-04 superseded — see note below)
**Success Criteria** (what must be TRUE):
  1. A freshly baked AMI has an isolated `/opt/jupyter` venv with pinned JupyterLab + a registered `python3` kernel; `/opt/jupyter/bin/jupyter --version` succeeds
  2. JupyterLab is launched on demand via `./run jupyter` and binds `127.0.0.1` only — it is NOT a systemd service and is NOT reachable on any non-loopback interface
  3. No Jupyter password is generated or published, and no TLS cert is baked: there is no `/devbox/${devbox_user}/jupyter-password` SSM param and no jupyter listener on `0.0.0.0` (loopback + SSM/IAM gates access)
  4. Running `mise --version` as ec2-user in a new login shell succeeds; no `.mise.toml` is committed; Python/Go/Rust/Java/Node Ansible layers are unmodified
  5. `hardening` remains the last role in `ansible/playbook.yml` (grep-gate passes; CI green)
**Plans**: 4 plans
- [x] 08-01-PLAN.md — mise role: checksum-pinned binary + /etc/profile.d activation (Wave 1)
- [x] 08-02-PLAN.md — jupyter role: /opt/jupyter venv + kernel (loopback on-demand; systemd/TLS/password removed by amendment) (Wave 1)
- [x] 08-03-PLAN.md — secrets role: jupyter-password gen/publish reverted by amendment (code-server/VNC unchanged) (Wave 2)
- [x] 08-04-PLAN.md — playbook/layer_config wiring + hardening-last & no-.mise.toml grep gates (Wave 3)

> **Design amendment (2026-06-02):** Jupyter pivoted from a password-protected `0.0.0.0`
> HTTPS systemd service to loopback-only on-demand (`./run jupyter`). This **supersedes
> JUP-03** (Jupyter password in SSM) and **JUP-04** (boot-time password injection) — both
> intentionally dropped because a loopback listener reached only via SSM/IAM needs no
> app-layer password. **Knock-on to Phase 9:** JUP-05 (SG `:8888` ingress) is now
> unnecessary (nothing is network-exposed), and the JUP-06/07 `secrets-show`/`status`
> Jupyter wiring no longer applies as written. Phase 9 should be re-scoped or dropped.

---

### Phase 9: Jupyter Operator Surface + Docs
**Goal**: Operators can discover and use the loopback Jupyter flow through `./run` and the docs — no security-group changes, no password (the Phase 8 loopback pivot removed those needs)
**Depends on**: Phase 8
**Requirements**: JUP-07 (amended). JUP-05 and JUP-06 are superseded — see REQUIREMENTS.md.
**Success Criteria** (what must be TRUE):
  1. `./run status` output indicates JupyterLab is available on demand via `./run jupyter` (loopback, 127.0.0.1:8888)
  2. `docs/DEVELOPER-LIFECYCLE.md` (and/or README) documents the `./run jupyter` + manual `:8888` SSM port-forward access flow
  3. No security-group rule is added for `:8888` and no Jupyter password is introduced — the loopback + SSM/IAM model from Phase 8 is preserved
**Plans**: 1 plan
- [ ] 09-01-PLAN.md — surface JupyterLab (on-demand/loopback) in `./run status`; document the `./run jupyter` + manual `:8888` SSM port-forward flow in DEVELOPER-LIFECYCLE.md (Wave 1)

> **Re-scope note (2026-06-02):** The original Phase 9 (add `:8888` ingress to
> `aws_security_group.devbox`, surface the Jupyter password via `./run secrets-show`)
> was made obsolete by Phase 8's loopback pivot. Trimmed to operator-surface polish +
> documentation only — a single code-light plan (status line + docs).

---

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-4 | v1.0 | 10/10 | Complete | 2026-05-14 |
| 5. Run Script Core | v2.0 | 1/1 | Complete | 2026-05-27 |
| 6. GitLab CI + Polish | v2.0 | 2/2 | Complete | 2026-05-27 |
| 7. Docs + Cleanup | v2.0 | 1/1 | Complete | 2026-06-02 |
| 8. Jupyter + mise AMI Layer | v3.0 | 4/4 | Complete | 2026-06-02 |
| 9. Jupyter Operator Surface + Docs | v3.0 | 0/1 | Planned | - |

## Shipped Milestones

| Version | Shipped | Phases | Plans | Requirements | Archive |
|---------|---------|-------:|------:|-------------:|---------|
| v1.0 — Security hardening + CI baseline | 2026-05-14 | 4 | 10 | 23/23 | [v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md) |
| v2.0 — Run Script + GitLab CI Integration | 2026-06-02 | 3 | 4 | DOC/RUN/CI/POL | [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) |

## Pending (Deferred)

Carried from prior milestones; pick up in a future cycle:

- **Observability** (v3): CloudWatch metrics + login event shipping
- **Lifecycle** (v3): Idle auto-stop + scheduled nightly stop
- **Image lifecycle** (v3): Old AMI deregistration + inventory
- **Reproducibility follow-up** (v3): Pin Packer SSM parameter `:NN` version suffix (requires AWS creds)
