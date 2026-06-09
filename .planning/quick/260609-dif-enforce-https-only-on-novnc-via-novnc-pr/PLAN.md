---
type: quick
slug: enforce-https-only-on-novnc-via-novnc-pr
created: 2026-06-09
status: complete
---

# Quick Task: Enforce HTTPS-only on noVNC (`--ssl-only`)

Force the noVNC web listener (`:6080`) to reject plaintext connections, by adding the
`--ssl-only` flag to the `novnc_proxy` invocation in the `desktop` role's systemd unit.

## Background

This started as a full milestone (v3.1 noVNC HTTPS-Only) scoped around a TLS-terminating
nginx reverse proxy in a new `novnc-proxy` role. The operator chose to **drop nginx** and
solve the core requirement — reject plaintext — with the one flag `novnc_proxy` already
supports. That collapses the milestone to a single-line change, so it ships as a quick task
and the v3.1 phased scaffold is abandoned.

## Approach

`novnc_proxy` (the noVNC launch wrapper) already serves TLS via `--cert/--key`. Adding
`--ssl-only` makes websockify refuse non-encrypted connections. Confirmed flag support via
Context7 (noVNC docs) — `novnc_proxy` forwards `--ssl-only` to websockify.

## Accepted tradeoff (no proxy)

- Plaintext hit on `:6080` → TLS handshake failure / connection reset. **No** HTTP→HTTPS
  redirect, **no** security headers (HSTS etc.) — websockify cannot emit them. The earlier
  HSTS/headers ask is dropped; TLS-only enforcement is fully satisfied by `--ssl-only`.
- Self-signed cert retained (CIDR-allowlisted, private VPC).
- code-server (`:8080`) unchanged — already HTTPS-only via `cert: true`.

## Files

- `ansible/roles/desktop/templates/novnc.service.j2` — append `--ssl-only` to `ExecStart`.

## Verification (bake-time, deferred — needs `./run build`)

- `novnc.service` starts cleanly (flag accepted by `novnc_proxy`).
- Browser connects over `wss://<host>:6080`.
- Plain `http://<host>:6080` is refused.
