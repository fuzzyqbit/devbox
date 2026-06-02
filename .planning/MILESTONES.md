# Milestones

## v3.0 Jupyter + mise (Shipped: 2026-06-02)

**Phases completed:** 2 phases, 5 plans
**Git range:** `v2.0..HEAD` — 51 commits, 51 files (+4396 / −57 LOC), 2026-06-02
**Known deferred items at close:** 3 (see STATE.md Deferred Items — 2 Phase-8 bake-time UAT/verification checks requiring a live AMI bake, 1 completed-but-unarchived v2.0 quick-task)

**Key accomplishments:**

- JupyterLab baked into an isolated `/opt/jupyter` venv (pinned JupyterLab 4.5.7 + ipykernel 6.29.5, registered python3 kernel; installed via the `devtools` role), launched **on demand** via `./run jupyter` bound to `127.0.0.1:8888` and reached over an SSM port-forward — no systemd service, no TLS, no password
- Mid-milestone security pivot to the loopback model eliminated code-review Critical CR-01 (auth-floor bypass) by removing the network-exposed listener entirely; supply-chain checkpoints (mise SHA-256, PyPI packages) operator-verified against live sources
- `mise` version manager: checksum-pinned official jdx binary + system-wide `/etc/profile.d` bash activation, folded into the `devops` role alongside kubectl/helm/k9s/eksctl/istioctl
- New grep-gate invariants (hardening-stays-last, no committed `.mise.toml`) mirrored across pre-commit + CI; `./run status` surfacing + `docs/DEVELOPER-LIFECYCLE.md` access flow

---

## v2.0 Run Script + GitLab CI Integration (Shipped: 2026-06-02)

**Phases completed:** 3 phases, 4 plans, 6 tasks
**Git range:** `v1.0..649ce1b` — 58 commits, 82 files (+5964 / −13078 LOC), 2026-05-14 → 2026-06-02
**Known deferred items at close:** 5 (see STATE.md Deferred Items — 2 human-UAT, 2 verification gaps, 1 quick-task summary; all require live AWS to close)

**Key accomplishments:**

- Standalone ./run bash dispatcher with all 20 Makefile commands, DEVBOX_USER validation + regex guard, lazy TF_STATE_BUCKET derivation, and tf-ensure-init auto-reinit — shellcheck clean at 337 lines
- NO_COLOR/CI-aware color helpers and ./run doctor dependency checker with bash 3.2-compatible dispatch
- CI bake and deploy stages delegate to ./run, shellcheck and grep-gates extended to cover the run file
- Makefile retired; `./run` is the sole operator surface, enforced by a new grep-gate across all three CI surfaces

---
