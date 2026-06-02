# Requirements: devbox v3.0 — Jupyter + mise

Scoped requirements for milestone v3.0. Adds a hardened JupyterLab service and the
`mise` version manager to the baked devbox AMI, reusing the established
secrets / systemd-service / security-group patterns from code-server and noVNC.

## v3.0 Requirements

### Jupyter (JUP)

- [ ] **JUP-01**: JupyterLab is installed in the baked AMI via the Ansible playbook
- [~] **JUP-02**: ~~JupyterLab runs as a systemd service that starts on boot~~ — **SUPERSEDED 2026-06-02**: launched on demand via `./run jupyter` (no systemd service); see ROADMAP Phase 8 amendment
- [~] **JUP-03**: ~~A per-build random Jupyter password is generated and published to SSM SecureString~~ — **SUPERSEDED 2026-06-02**: loopback-only Jupyter needs no password
- [~] **JUP-04**: ~~JupyterLab requires that password (no tokenless / open access)~~ — **SUPERSEDED 2026-06-02**: bound to `127.0.0.1`, reached only via SSM/IAM port-forward, which is the auth boundary
- [~] **JUP-05**: ~~Additional `:8888` ingress rule on `aws_security_group.devbox`~~ — **SUPERSEDED 2026-06-02**: nothing network-exposed; no SG rule needed (Phase 9 re-scope)
- [~] **JUP-06**: ~~`./run secrets-show` reveals the Jupyter password~~ — **SUPERSEDED 2026-06-02**: no Jupyter password exists (Phase 9 re-scope)
- [~] **JUP-07**: ~~`./run status` Jupyter URL + `devbox-port-forward` reaches Jupyter~~ — **AMENDED 2026-06-02**: access is `./run jupyter` + a manual `:8888` SSM port-forward (Phase 9 re-scope)
- [ ] **JUP-08**: The `hardening` role remains the last role in `ansible/playbook.yml` (invariant); the Jupyter role is inserted before it

### mise (MISE)

- [ ] **MISE-01**: The `mise` binary is installed in the baked AMI via the Ansible playbook
- [ ] **MISE-02**: `mise` shell activation is configured for `ec2-user` interactive shells (mise is on PATH / hooked in new shells)
- [ ] **MISE-03**: No committed `.mise.toml` is shipped, and the existing per-language Ansible layers (Python/Go/Rust/Java/Node) are left unchanged

## Future Requirements

Deferred to a later milestone:

- A committed `.mise.toml` pinning canonical tool versions baked into the image (reproducibility follow-up — explicitly out of scope for v3.0)
- Migrating the per-language Ansible layers to be mise-managed (larger refactor / breaking change)

## Out of Scope

- **New security group for Jupyter** — Jupyter reuses `aws_security_group.devbox` with an added rule (JUP-05); no second SG.
- **mise replacing the existing toolchain layers** — v3.0 installs the binary only (MISE-03); the baked Python/Go/Rust/Java/Node layers stay.
- **Publicly-exposed Jupyter** — Jupyter binds `127.0.0.1` only and is reached via SSM port-forward; it is never on a public/VPC interface. (Amended 2026-06-02: the original "password-mandatory, CIDR-gated :8888" model in JUP-04/JUP-05 was replaced by loopback + SSM/IAM gating, which needs no app-layer password.)
- **Observability / lifecycle automation** — still deferred (carried from prior milestones).

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| JUP-01 | Phase 8 | Pending |
| JUP-02 | Phase 8 | Superseded (loopback on-demand) |
| JUP-03 | Phase 8 | Superseded (no password) |
| JUP-04 | Phase 8 | Superseded (loopback + SSM/IAM) |
| JUP-05 | Phase 9 | Superseded (no SG exposure) |
| JUP-06 | Phase 9 | Superseded (no password) |
| JUP-07 | Phase 9 | Amended (./run jupyter + manual forward) |
| JUP-08 | Phase 8 | Pending |
| MISE-01 | Phase 8 | Pending |
| MISE-02 | Phase 8 | Pending |
| MISE-03 | Phase 8 | Pending |
