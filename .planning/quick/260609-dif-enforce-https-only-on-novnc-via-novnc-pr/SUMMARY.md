---
type: quick
slug: enforce-https-only-on-novnc-via-novnc-pr
created: 2026-06-09
completed: 2026-06-09
status: complete
commit: PENDING
---

# Summary: Enforce HTTPS-only on noVNC (`--ssl-only`)

Added `--ssl-only` to the `novnc_proxy` ExecStart in the `desktop` role's systemd unit so
the noVNC listener (`:6080`) rejects plaintext connections.

## What was done

- `ansible/roles/desktop/templates/novnc.service.j2` — appended `--ssl-only` after the
  existing `--cert/--key` flags. websockify now refuses non-encrypted connections.

## Decision: dropped the nginx milestone

The v3.1 noVNC HTTPS-Only milestone was scoped around a TLS-terminating nginx reverse proxy
(redirect + HSTS + security headers). The operator chose the minimal path: `novnc_proxy`
already supports `--ssl-only`, which satisfies the core "reject plaintext" requirement with
one line and no new component.

Consequences accepted:
- No HTTP→HTTPS redirect and no security headers (HSTS) — websockify cannot emit them
  without a proxy. The HSTS open-decision is moot (auto-resolved to "none").
- v3.1 phased scaffold abandoned; the nginx-based research (5 docs) archived to
  `.planning/milestones/v3.1-abandoned-research/`.

## Verification (deferred — needs live AMI bake)

Bake-time checks, cannot run in-session:
- `novnc.service` starts (flag accepted by `novnc_proxy`).
- Browser connects over `wss://<host>:6080`; plain `http://<host>:6080` refused.
