# Milestones

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
