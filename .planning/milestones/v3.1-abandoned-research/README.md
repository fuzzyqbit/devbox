# v3.1 noVNC HTTPS-Only — abandoned research

These 5 research docs were produced 2026-06-09 for a planned **v3.1 noVNC HTTPS-Only**
milestone scoped around a TLS-terminating **nginx reverse proxy** (redirect + HSTS +
security headers) in a new `novnc-proxy` Ansible role.

**The milestone was abandoned.** The operator chose the minimal path: `novnc_proxy` already
supports `--ssl-only`, which satisfies the core "reject plaintext" requirement with one line
and no new component. Shipped as quick task `260609-dif`
(`.planning/quick/260609-dif-enforce-https-only-on-novnc-via-novnc-pr/`).

The nginx architecture, WebSocket-proxy directives, and HSTS analysis here are sound but
**no longer reflect the implemented approach**. Retained for reference only — if a future
milestone needs HTTP→HTTPS redirect or security headers (which `--ssl-only` cannot provide),
this is the starting point.
