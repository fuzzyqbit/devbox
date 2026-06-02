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

- [ ] **Phase 8: Jupyter + mise AMI Layer** — Bake JupyterLab as a hardened systemd service with per-build SSM password, and install the mise binary with ec2-user shell activation
- [ ] **Phase 9: Terraform SG Rule + Operator Surface** — Add :8888 ingress to the existing security group and wire ./run secrets-show, status, and port-forward for Jupyter

## Phase Details

### Phase 8: Jupyter + mise AMI Layer
**Goal**: The baked AMI runs JupyterLab as a password-protected systemd service at boot, publishes its password to SSM, and ships the mise binary ready for ec2-user
**Depends on**: Phase 7 (v2.0 complete; `./run` is the operator surface; `secrets` role and `hardening` role patterns established)
**Requirements**: JUP-01, JUP-02, JUP-03, JUP-04, JUP-08, MISE-01, MISE-02, MISE-03
**Success Criteria** (what must be TRUE):
  1. A freshly baked AMI boots and `systemctl status jupyter` reports active (running)
  2. An unauthenticated HTTP request to :8888 is rejected (no token or password = no notebook access)
  3. `/devbox/${devbox_user}/jupyter-password` exists in SSM Parameter Store as a SecureString after a bake; cleartext does not appear in the AMI filesystem or git history
  4. Running `mise --version` as ec2-user in a new login shell succeeds; no `.mise.toml` is committed; Python/Go/Rust/Java/Node Ansible layers are unmodified
  5. `hardening` remains the last role in `ansible/playbook.yml` (grep-gate passes; CI green)
**Plans**: TBD

---

### Phase 9: Terraform SG Rule + Operator Surface
**Goal**: Operators can reach Jupyter through the CIDR-gated security group and interact with it via the existing ./run commands (secrets-show, status, port-forward)
**Depends on**: Phase 8
**Requirements**: JUP-05, JUP-06, JUP-07
**Success Criteria** (what must be TRUE):
  1. `tofu plan` shows an ingress rule for port 8888 added to `aws_security_group.devbox` (no new SG created); the rule is governed by `var.allowed_web_cidrs` consistent with the :8080 and :6080 rules
  2. `./run secrets-show` prints the Jupyter password alongside the code-server and VNC passwords
  3. `./run status` output includes the Jupyter URL (e.g. `http://<host>:8888`)
  4. `./run devbox-port-forward` establishes a tunnel that reaches Jupyter at the forwarded local port
**Plans**: TBD

---

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-4 | v1.0 | 10/10 | Complete | 2026-05-14 |
| 5. Run Script Core | v2.0 | 1/1 | Complete | 2026-05-27 |
| 6. GitLab CI + Polish | v2.0 | 2/2 | Complete | 2026-05-27 |
| 7. Docs + Cleanup | v2.0 | 1/1 | Complete | 2026-06-02 |
| 8. Jupyter + mise AMI Layer | v3.0 | 0/? | Not started | - |
| 9. Terraform SG Rule + Operator Surface | v3.0 | 0/? | Not started | - |

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
