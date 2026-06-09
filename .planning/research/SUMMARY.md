# Project Research Summary

**Project:** devbox — v3.1 noVNC HTTPS-Only
**Domain:** TLS-terminating reverse proxy for a WebSocket-based browser VNC client on AL2023
**Researched:** 2026-06-09
**Confidence:** HIGH

---

## Executive Summary

This milestone adds HTTPS-only enforcement to the noVNC service (:6080) on the devbox AMI. The current state is that websockify serves directly on :6080 with a self-signed cert but without `--ssl-only`, meaning it silently accepts plaintext connections and cannot produce an HTTP to HTTPS redirect or emit response headers. The fix is a standard reverse proxy pattern: nginx (available in the AL2023 base repo at ~1.26.3, no third-party repo needed) takes over port :6080, terminates TLS using the existing self-signed cert at `/etc/novnc/novnc-cert.pem`, and proxies WebSocket traffic to websockify on a loopback port (127.0.0.1:6081). Websockify loses its `--cert/--key` flags and becomes a plaintext loopback backend. No Terraform changes and no new firewalld ports are needed — nginx inherits the :6080 slot that websockify vacated. code-server (:8080) is unchanged; its `cert: true` already enforces HTTPS at the process level and does not have the same gap.

The architecture is well-documented and high-confidence across all four research areas. Three mandatory nginx directives (`proxy_http_version 1.1`, `Upgrade`, `Connection "upgrade"`) are required for WebSocket to work through the proxy; omitting any one of them silently breaks noVNC. A `proxy_read_timeout` above 60s (use 3600s) is equally critical — the default 60-second timeout kills idle VNC sessions. The new component belongs in a dedicated `novnc-proxy` Ansible role inserted immediately before `hardening`, consistent with project conventions. The `desktop` role gets one targeted modification: the `novnc.service.j2` template rebinds websockify to `127.0.0.1:6081` and drops the TLS flags.

The one unresolved decision is whether to include an HSTS header at all, and if so, with what `max-age`. The operator requested HSTS plus security headers, but HSTS with a self-signed cert creates a hard browser lockout with no bypass escape hatch once the cert changes after any rebake. This is a genuine tradeoff with two safe options: (a) omit HSTS entirely — TLS enforcement is fully satisfied by the nginx redirect alone, or (b) include HSTS with a short `max-age` (300-3600s), no `preload`, no `includeSubDomains` — limits the lockout window to minutes rather than months. This decision must be made at requirements time; see the Open Decision section below.

---

## OPEN DECISION: HSTS With a Self-Signed Certificate

**Status: UNRESOLVED — must be decided at requirements time before implementation begins.**

The operator requested HSTS plus security headers. Research in both FEATURES.md and PITFALLS.md confirms a hard conflict with the retained self-signed cert.

**The lockout mechanism (confirmed from MDN specification):**
Once a browser receives `Strict-Transport-Security` from a host, it will refuse to connect over plain HTTP and will not offer any "click through" or "Proceed anyway" bypass for subsequent TLS errors. If the self-signed cert changes after a rebake, the browser shows a hard error page with no escape. Recovery requires manually clearing the HSTS entry in `chrome://net-internals/#hsts` (Chrome) or `about:networking#dns` (Firefox).

**The two safe options:**

| Option | HSTS Header | Max-Age | Risk | TLS Enforcement Level |
|--------|-------------|---------|------|-----------------------|
| (a) Omit HSTS | None | n/a | No lockout risk | Full — nginx redirect + TLS-only listener |
| (b) Short max-age | Present | 300-3600s | 5min-1hr lockout window post-rebake | Full + MITM downgrade prevention on return visits |

**What is NOT safe:**
- HSTS with `max-age` in days, weeks, or years — hard lockout for the full duration after any rebake
- `preload` — requires a public domain; meaningless for an IP or private hostname; recovery takes weeks
- `includeSubDomains` — no subdomains exist; inert but misleading

**What the research recommends:**
PITFALLS.md recommends omitting HSTS entirely in v3.1 and adding it only after a trusted cert is provisioned. FEATURES.md classifies short-max-age HSTS as a differentiator (not table stakes) and explicitly flags long-max-age HSTS as an anti-feature for this case.

**Decision needed from operator:** Choose option (a) or option (b). If (b), confirm acceptable max-age value (300s recommended as a safe starting point).

---

## Key Findings

### Recommended Stack

nginx from the AL2023 base repo is the unambiguous choice. It is available via `dnf install nginx` (no third-party repo), has proven WebSocket proxy support, native `add_header` for security headers, and is the stack explicitly recommended by the noVNC project wiki. The only serious alternative evaluated was Caddy v2.11.4, which is not available in AL2023 base repos and loses its primary advantage (auto-HTTPS) when a manually-loaded self-signed cert is used — more Ansible boilerplate for no functional gain.

**Core technologies:**
- **nginx ~1.26.3 (AL2023 base repo):** TLS-terminating reverse proxy on :6080 — in-repo, proven noVNC WebSocket support, native header injection
- **websockify (existing, pip):** Retains its role as WebSocket-to-TCP bridge for TigerVNC on :5901 — moves to loopback plaintext on :6081, loses `--cert/--key`
- **OpenSSL 3.x / existing self-signed cert (existing):** `/etc/novnc/novnc-cert.pem` and `novnc-key.pem` reused as-is by nginx — no new cert infrastructure
- **ansible.posix.firewalld (pinned 2.1.0):** Adds `:6080/tcp` to the `public` zone — collection already present in `requirements.yml`

Version pinning: use `--releasever=<date-stamp>` on the dnf task plus the full NVR string (e.g., `nginx-1.26.3-1.amzn2023.0.X`) for reproducibility consistent with existing project policy. Confirm exact NVR with `dnf info nginx --releasever=<releasever>` on a live instance during implementation.

### Expected Features

**Must have (table stakes):**
- nginx TLS termination on :6080 with existing self-signed cert
- WebSocket proxy with `Upgrade`/`Connection` hop-by-hop headers forwarded — noVNC non-functional without these
- Remove `--cert/--key` from websockify `ExecStart` — mandatory once nginx owns TLS
- HTTP to HTTPS redirect via `error_page 497 =301 https://$host:$server_port$request_uri` — same-port redirect without a second listener
- `proxy_read_timeout 3600s` — prevents idle session disconnection at the 60-second default
- `proxy_buffering off` — prevents VNC stream corruption and latency
- `X-Content-Type-Options: nosniff` — zero-cost header, no false positives

**Should have (differentiators):**
- HSTS with short max-age (300-3600s) — conditional on OPEN DECISION above
- `X-Frame-Options: DENY` — clickjacking prevention
- `Referrer-Policy: no-referrer` — session URL leak prevention
- code-server TLS audit (read-only verification, no change expected)

**Defer or avoid entirely:**
- HSTS `preload` and `includeSubDomains` — anti-features for this case
- Full Content-Security-Policy — too tight for noVNC multi-path resources, overkill for internal tool
- Separate :80 listener for redirect — unnecessary ingress surface; `error_page 497` handles it on the same port
- OCSP stapling — incompatible with self-signed certs, will log errors
- code-server behind nginx — `cert: true` already enforces HTTPS; moving it behind proxy requires double TLS or a security regression

### Architecture Approach

nginx takes over the existing public-facing port (:6080) and websockify moves to loopback plaintext (:6081). No Terraform SG changes are needed — the existing `:6080` ingress rule is already in place. One firewalld rule is added by the new role (`:6080/tcp` in the `public` zone). The loopback port binding (`127.0.0.1`, not `0.0.0.0`) is a hard requirement — binding all interfaces would bypass the proxy on a non-SG-listed port.

**Major components:**

1. **`ansible/roles/novnc-proxy/` (NEW)** — nginx package install, config template rendering, `nginx.service` systemd management, firewalld `:6080/tcp` rule; layer-gated via `layers.novnc_proxy`
2. **`ansible/roles/desktop/` (MODIFIED)** — `novnc.service.j2` template updated: rebind websockify to `127.0.0.1:{{ desktop_novnc_loopback_port }}`, drop `--cert/--key` flags; add `desktop_novnc_loopback_port: 6081` to `defaults/main.yml`
3. **`ansible/playbook.yml` (MODIFIED)** — insert `novnc-proxy` after `desktop`, before `hardening` (invariant preserved)
4. **nginx config template `novnc.nginx.conf.j2`** — two server blocks on :6080: HTTP block issues `error_page 497` redirect; HTTPS block terminates TLS, proxies WebSocket with required headers, serves static assets, emits security headers
5. **`terraform/main.tf` (UNCHANGED)** — existing `:6080` SG ingress rule is already correct

Role dependency: `novnc-proxy` must run after `desktop` (depends on cert/key files and noVNC asset directory created by `desktop`) and before `hardening` (enforced invariant).

### Critical Pitfalls

1. **Missing WebSocket Upgrade/Connection headers** — nginx strips hop-by-hop headers by default; without `proxy_http_version 1.1` plus `proxy_set_header Upgrade $http_upgrade` plus `proxy_set_header Connection "upgrade"`, the WebSocket handshake silently fails. noVNC shows immediate disconnect. Verify with a `curl --http1.1 -H "Upgrade: websocket" ...` test returning HTTP 101.

2. **HSTS + self-signed cert = browser lockout** — MDN-confirmed: once HSTS is cached, no click-through bypass is offered for subsequent TLS errors. After any rebake that regenerates the cert, the operator's browser is locked out until manually cleared via `chrome://net-internals/#hsts`. Resolved by the OPEN DECISION before writing the nginx template.

3. **`proxy_read_timeout` default (60s) kills idle sessions** — VNC desktops with no screen activity disconnect exactly 60 seconds after the last update; misdiagnosed as VNC instability. Prevention: explicit `proxy_read_timeout 3600s` in the nginx template.

4. **Double TLS (nginx + websockify both with certs)** — if `--cert/--key` is left on websockify after nginx takes over TLS, nginx connects to a TLS-speaking websockify, fails self-signed cert verification, returns 502. Must remove cert flags from `novnc.service.j2` in the same PR.

5. **Redirect port drop in 301** — `return 301 https://$host$request_uri` silently drops the port (redirects to `:443`). Use `error_page 497 =301 https://$host:$server_port$request_uri` to preserve `:6080`. Verify: `curl -k http://host:6080/` must return `Location: https://host:6080/`.

---

## Implications for Roadmap

This is a single-phase milestone with a clear internal sequencing. All components are tightly coupled — the websockify service change and the nginx role must ship in the same AMI bake or noVNC will be broken during transition.

### Phase 1: nginx Reverse Proxy + websockify Rebinding

**Rationale:** The websockify service change and nginx role are inseparable. Shipping the websockify loopback rebinding without nginx would break noVNC entirely. Shipping nginx without the websockify change would leave double TLS. They are a single atomic bake.

**Delivers:** HTTPS-only enforcement on :6080 with HTTP to HTTPS redirect, WebSocket proxy, security headers, no Terraform changes.

**Addresses (from FEATURES.md):**
- All P1 table stakes: TLS termination, WebSocket headers, websockify cert removal, `error_page 497` redirect, `proxy_read_timeout 3600s`, `proxy_buffering off`, `X-Content-Type-Options`
- P2 differentiators: `X-Frame-Options`, `Referrer-Policy`; HSTS conditional on Open Decision

**Avoids (from PITFALLS.md):**
- WebSocket header omission (mandatory directives in template)
- `proxy_read_timeout` default (explicit 3600s)
- Double TLS (websockify cert flags removed in same PR)
- Redirect port drop (use `error_page 497` with `$server_port`)
- HSTS lockout (resolved by Open Decision before template is written)

**Implementation sequence within the phase:**
1. Add `desktop_novnc_loopback_port: 6081` to `desktop/defaults/main.yml`
2. Update `novnc.service.j2`: drop `--cert/--key`, rebind to `127.0.0.1:{{ desktop_novnc_loopback_port }}`
3. Create `ansible/roles/novnc-proxy/` skeleton (defaults, tasks, templates, handlers)
4. Write `novnc.nginx.conf.j2` (two server blocks; HSTS presence or absence per Open Decision)
5. Write `tasks/main.yml`: dnf install nginx (pinned NVR), deploy config, enable service, firewalld rule
6. Update `ansible/playbook.yml`: insert `novnc-proxy` before `hardening`
7. Update `ansible/layer_config.yml`: add `novnc_proxy: true`
8. Bake and smoke-test

**Smoke test checklist:**
- `curl -k http://host:6080/` returns `301` with `Location: https://host:6080/` (port preserved)
- `curl -kI https://host:6080/` returns 200 with expected security headers
- WebSocket upgrade test returns HTTP 101
- `curl http://host:6081/` from outside the instance is unreachable (loopback binding)
- `ss -tlnp` on the AMI shows no `:80` listener
- `proxy_read_timeout` present and above 60s in deployed config
- If HSTS omitted: `curl -kI https://host:6080/ | grep -i strict` returns nothing

### Phase 2: code-server TLS Audit (Read-Only)

**Rationale:** Research confirms code-server's `cert: true` already enforces HTTPS at the process level and does not have the same plaintext-acceptance gap as websockify. The audit is a verification step, not a code change. It can follow Phase 1 independently.

**Delivers:** Written confirmation that :8080 is already HTTPS-only.

**Expected outcome:** Zero Ansible changes. Document parity in the phase verification report.

### Phase Ordering Rationale

- Phase 1 before Phase 2: noVNC enforcement is the stated milestone goal; code-server audit is a supporting verification with no dependency on Phase 1's outcome.
- Websockify service change ships in the same PR as the nginx role — do not split across two bakes.
- Open Decision must be resolved before Phase 1 planning begins; it directly controls one line of the nginx template.

### Research Flags

**Phase 1 — does NOT need additional research-phase:**
The nginx WebSocket proxy pattern for noVNC is well-documented in the official noVNC wiki, official nginx docs, and verified against AL2023 package availability. All directives are confirmed. The only unresolved item is the HSTS Open Decision, which is a policy choice, not a technical unknown.

**Phase 1 — implementation-time validation needed (not a research phase):**
- Confirm exact nginx NVR string with `dnf info nginx --releasever=<releasever>` on a live instance
- Verify the noVNC websocket URL path (`/websockify` vs `/`) against the baked AMI HTML

**Phase 2 — does NOT need additional research-phase:**
Audit is a read of an existing config file and a behavior test. No new patterns required.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | nginx in AL2023 base repo confirmed from release notes; Caddy exclusion confirmed from two separate GitHub issues; websockify behavior confirmed from man page |
| Features | HIGH | Behaviors verified against MDN, OWASP, nginx docs, websockify source docs; HSTS tradeoff confirmed from MDN specification text |
| Architecture | HIGH | Grounded in direct codebase inspection of existing role files plus verified official sources; port topology and component boundaries unambiguous |
| Pitfalls | HIGH | All pitfalls verified against nginx official docs, noVNC wiki, MDN HSTS spec, AL2023 SELinux docs, and project playbook code |

**Overall confidence:** HIGH

### Gaps to Address

- **Exact nginx NVR string:** STACK.md gives `nginx-1.26.3-1.amzn2023.0.X` as a template; the precise release component must be confirmed with `dnf info nginx --releasever=<releasever>` during Phase 1 implementation. Fill-in-the-blank, not a blocker.

- **noVNC websocket URL path:** Architecture research uses a dedicated `/websockify` location block. FEATURES.md notes the path is `/websockify` or `/`. Verify against the baked AMI's noVNC HTML before finalizing the nginx template. If noVNC uses `/` exclusively, a single `location /` block replaces the split-location pattern.

- **HSTS decision (OPEN DECISION):** The HSTS header presence/absence and max-age value must be confirmed by the operator at requirements time. This is the only unresolved decision blocking the nginx template. All other template directives are confirmed.

- **firewalld workaround retirement interaction:** The `firewalld-docker-fix.yml` workaround sets the default zone to `docker` (ACCEPT), making the explicit `:6080/tcp public-zone` rule currently redundant but harmless. Add the rule anyway so the config is correct when the workaround is eventually retired. Confirm the `ansible.posix.firewalld` task targets `zone: public` explicitly.

---

## Sources

### Primary (HIGH confidence)
- [nginx WebSocket proxying](https://nginx.org/en/docs/http/websocket.html) — `proxy_http_version 1.1`, `Upgrade/Connection` directives
- [noVNC Proxying with nginx (project wiki)](https://github.com/novnc/noVNC/wiki/Proxying-with-nginx) — `proxy_buffering off`, `proxy_read_timeout > 60s`, nginx as recommended proxy
- [MDN Strict-Transport-Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security) — HSTS un-bypassable warning behavior with self-signed cert
- [AL2023 release notes 2023.7.20250331](https://docs.aws.amazon.com/linux/al2023/release-notes/relnotes-2023.7.20250331.html) — nginx 1.26.3 in base repo confirmed
- [AL2023 deterministic upgrades](https://docs.aws.amazon.com/linux/al2023/ug/deterministic-upgrades-usage.html) — `--releasever` pinning mechanism
- [websockify man page](https://github.com/novnc/websockify/blob/master/docs/websockify.1) — `--ssl-only`: "disallow non-encrypted connections" (no redirect, no headers)
- Direct codebase inspection: `ansible/roles/desktop/tasks/main.yml`, `templates/novnc.service.j2`, `ansible/roles/vscode/`, `ansible/playbook.yml`, `terraform/main.tf`, `ansible/firewalld-docker-fix.yml`

### Secondary (MEDIUM confidence)
- [Caddy AL2023 package request (amazonlinux/amazon-linux-2023#95)](https://github.com/amazonlinux/amazon-linux-2023/issues/95) — Caddy not in AL2023 base repos, open since 2023
- [caddyserver/dist#119](https://github.com/caddyserver/dist/issues/119) — COPR repo does not support AL2023
- [Caddy automatic HTTPS docs](https://caddyserver.com/docs/automatic-https) — manually-loaded cert disables auto-HTTPS and redirect
- [nginx error_page 497 same-port redirect](https://chrisguitarguy.com/2019/08/20/redirecting-http-requests-on-an-https-listener-in-nginx-status-code-497/) — same-port HTTP to HTTPS without second listener
- [OWASP HTTP Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html) — security header recommendations
- [AL2023 SELinux modes](https://docs.aws.amazon.com/linux/al2023/ug/selinux-modes.html) — permissive by default; no `httpd_can_network_connect` boolean needed currently
- [nginx SELinux httpd_can_network_connect](https://www.f5.com/company/blog/nginx/using-nginx-plus-with-selinux) — future enforcing-mode mitigation

---
*Research completed: 2026-06-09*
*Ready for roadmap: yes — pending resolution of HSTS Open Decision*
