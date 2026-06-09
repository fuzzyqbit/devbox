# Feature Landscape: noVNC HTTPS-Only Enforcement

**Domain:** TLS-only enforcement for a browser-reached internal service (noVNC) behind a reverse proxy
**Researched:** 2026-06-09
**Confidence:** HIGH — behaviors verified against MDN, OWASP, nginx docs, websockify source docs, and noVNC wiki

---

## Context: What Already Exists

| Component | Current State | Gap |
|-----------|--------------|-----|
| `novnc_proxy` on :6080 | TLS via `--cert/--key` (self-signed `/CN=devbox`) | `--ssl-only` flag absent; websockify accepts plaintext connections on the same port |
| code-server on :8080 | HTTPS-only via `cert: true` in config.yaml | Already correct; audit needed to confirm no plaintext fallback |
| Reverse proxy | None — websockify serves directly | Required to produce HTTP→HTTPS redirect and add security headers |
| Firewalld | Running (CIS role enablement); :6080 open to CIDR allowlist | No change needed |

The milestone introduces nginx as a TLS-terminating reverse proxy in front of websockify, which then runs in plaintext-only mode on a loopback port.

---

## Table Stakes

Features users/browsers expect for a service advertised as HTTPS-only. Missing these = the enforcement is incomplete or broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **TLS-only listener — reject plaintext** | An HTTPS-only service that silently accepts plaintext is not HTTPS-only | Low | Two mechanisms: (a) websockify `--ssl-only` flag rejects at the websockify layer, OR (b) nginx terminates TLS and websockify runs in plaintext-only on loopback (no `--cert/--key` needed). Prefer (b) — nginx is the proxy anyway. |
| **HTTP→HTTPS redirect on the same port (:6080)** | Browsers and users will type the base URL without `https://`; a silent reject produces a confusing blank page | Medium | nginx `error_page 497` handles the case where HTTP plaintext is sent to an SSL-listening port: `error_page 497 =301 https://$host:$server_port$request_uri;`. This is nginx-specific and correct for the shared-port case. A separate :80 listener is NOT appropriate here — :6080 is the only open web port for noVNC. |
| **WebSocket-over-TLS (wss://) working through the proxy** | noVNC's core connection is a WebSocket; breaking it renders the tool non-functional | Medium | Three nginx directives are mandatory: `proxy_http_version 1.1`, `proxy_set_header Upgrade $http_upgrade`, `proxy_set_header Connection "upgrade"`. Without these, nginx strips the Upgrade header and the WebSocket handshake returns 400 or silently drops. Additionally: `proxy_read_timeout` must be extended well beyond 60s (use 3600s or 86400s) to prevent idle session disconnection. `proxy_buffering off` to avoid stream buffering. |
| **Self-signed cert served consistently** | The cert is already baked into the AMI; nginx must use the same cert/key pair that websockify was using | Low | Use existing `/etc/novnc/novnc-cert.pem` and `/etc/novnc/novnc-key.pem`. No new cert generation needed. |
| **X-Content-Type-Options: nosniff** | Prevents MIME-type sniffing attacks; lowest-cost header with no false positives | Low | `add_header X-Content-Type-Options "nosniff" always;` |

---

## Differentiators

Features that add meaningful security or quality beyond the bare minimum. Appropriate for an internal CIDR-allowlisted tool.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **HSTS with a short max-age (no preload, no includeSubDomains)** | Forces the browser to remember HTTPS for subsequent visits without HTTP round-trip exposure. Scoped correctly for an internal tool with a self-signed cert. **See HSTS tradeoff section below.** | Low | `Strict-Transport-Security: max-age=300` — 5 minutes is sufficient for a personal tool. Do NOT use `includeSubDomains` (no subdomains exist). Do NOT use `preload` (requires a public domain). Short max-age limits the "I've locked myself out" blast radius if the cert expires or changes. |
| **X-Frame-Options: DENY (or CSP frame-ancestors)** | Prevents the VNC session from being embedded in a hostile iframe (clickjacking vector even on internal tools) | Low | `add_header X-Frame-Options "DENY" always;` or the modern equivalent `Content-Security-Policy: frame-ancestors 'none';`. For an internal tool CSP is overkill — use X-Frame-Options. |
| **Referrer-Policy: no-referrer** | Prevents the URL of the noVNC session from leaking in referer headers to any embedded resources | Low | `add_header Referrer-Policy "no-referrer" always;` |
| **code-server TLS audit** | Confirms :8080 has no plaintext fallback and is already at parity with the noVNC enforcement | Low | Audit `cert: true` behavior in code-server: this flag uses a self-signed cert but code-server itself DOES refuse plaintext (unlike websockify). Document the confirmed parity; no change expected. |

---

## Anti-Features

Things that appear useful but are wrong or counterproductive for this specific use case.

| Anti-Feature | Why Problematic | What to Do Instead |
|--------------|-----------------|-------------------|
| **HSTS with `preload`** | `preload` submits the domain to a browser-embedded list. Requires a real public domain, min `max-age=31536000`, and `includeSubDomains`. For an EC2 IP address or private hostname with a self-signed cert this is impossible and meaningless — the domain is not publicly resolvable. | Use `max-age=<short>` only, no `preload`, no `includeSubDomains`. |
| **HSTS with a long max-age and a self-signed cert** | This combination makes the cert warning un-bypassable AND persists for months. If the self-signed cert changes (rebake, key rotation) or the operator reaches the host from a new browser, the browser shows a hard error with no "Proceed anyway" escape hatch for the max-age duration. The operator can clear it manually via `chrome://net-internals/#hsts` but this is a surprise footgun. | Use a short max-age (300–3600s). HSTS still prevents protocol downgrade attacks on repeat visits; short max-age limits lockout exposure. |
| **HSTS with `includeSubDomains`** | There are no subdomains. The directive would apply to any subdomain of the EC2 hostname, which does not exist and cannot serve HTTPS. It is inert but misleading. | Omit entirely. |
| **Full Content-Security-Policy for noVNC** | noVNC loads resources from multiple paths (JS, CSS, PNG icons, websocket connections). A CSP that is too tight will break the UI. Getting CSP right requires auditing every resource URL in the noVNC HTML output. For an internal CIDR-allowlisted tool the XSS attack surface is already minimal. | Skip CSP. Use X-Frame-Options to cover the meaningful clickjacking vector instead. |
| **Separate :80 listener for HTTP→HTTPS redirect** | Port :80 is not in the security group allowlist. Opening it for redirects adds an ingress rule to collect requests only to immediately redirect them — an unnecessary attack surface expansion. The nginx `error_page 497` mechanism handles the same-port redirect without needing a second listener. | Use `error_page 497` redirect only. |
| **Terminating TLS at both nginx and websockify** | Running websockify with `--cert/--key` while nginx also terminates TLS means double-TLS on loopback. It adds cert management complexity with zero security benefit — loopback traffic does not traverse a network. | Remove `--cert/--key` from the websockify `ExecStart` once nginx is the TLS terminator. Let websockify run as a plaintext-over-loopback backend. |
| **Permissions-Policy header** | Lists browser capabilities to deny (camera, microphone, geolocation). noVNC is a VNC client — it uses none of these. The header adds noise without meaning for this use case. | Omit. |
| **OCSP stapling** | Requires a CA that participates in OCSP (self-signed certs have no OCSP endpoint). Nginx will fail to fetch OCSP responses, log errors, and potentially delay handshakes. | Omit `ssl_stapling on` for self-signed certs. |

---

## HSTS With a Self-Signed Cert: Explicit Tradeoff Analysis

This is the most nuanced feature decision in this milestone.

**What HSTS does:** After the browser receives the `Strict-Transport-Security` header on a successful HTTPS response, it will refuse to connect over plain HTTP to the same host for the duration of `max-age`. It upgrades future requests to HTTPS internally before they leave the browser.

**Why it is normally useful:** Prevents SSL-stripping attacks where a MITM downgrades the first request from HTTPS to HTTP. Prevents accidental plain-HTTP bookmarks or links from working.

**The self-signed cert interaction (confirmed from MDN):**
> "If a TLS warning or error, such as an invalid certificate, occurs when connecting to an HSTS host, the browser does not offer the user a way to proceed or 'click through' the error message."

This means: once the browser has stored the HSTS entry for the EC2 hostname, and then the self-signed cert changes (rebake, new AMI, key rotation), the operator sees a hard error page with NO bypass option. The only escape is manually deleting the HSTS entry from `chrome://net-internals/#hsts` (Chrome) or `about:preferences#privacy` (Firefox). This is a support burden on a personal tool.

**The verdict: HSTS is differentiator-level (not table stakes) with a short max-age.**

- A `max-age` of 300–3600 seconds still prevents protocol downgrade on the current browser session and any repeat visits within the window.
- After the window expires (e.g., after a rebake), the browser will accept a new cert exception normally again.
- This gives meaningful MITM protection for the working session without creating a hard lockout footgun on every AMI rebuild.
- `preload` and `includeSubDomains` are explicitly anti-features for this case (see above).

**Contrast with code-server:** code-server's `cert: true` makes it HTTPS-only without HSTS — the browser still shows a cert warning but allows bypass. noVNC with nginx can match this posture. Adding HSTS then raises the bar by removing the bypass, which is the desired direction — but only if max-age is short enough to self-heal.

---

## WebSocket-over-TLS Through nginx: Required Behavior

When nginx terminates TLS in front of websockify, the client connects over `wss://` (TLS WebSocket) to nginx. nginx then speaks plain `ws://` to websockify on loopback. This is correct and standard — the loopback path does not need encryption.

**What must hold for the WebSocket connection to work:**

1. nginx forwards `Upgrade: websocket` and `Connection: upgrade` headers to websockify. These are hop-by-hop headers that nginx strips by default. Explicit `proxy_set_header` directives are required.
2. nginx uses `proxy_http_version 1.1` — the HTTP/1.0 default does not support the `Upgrade` mechanism; WebSocket upgrade will silently fail.
3. `proxy_read_timeout` must exceed the expected idle time. Default is 60 seconds; an idle VNC session will be disconnected. Use 3600s (1 hour) minimum.
4. `proxy_buffering off` — nginx must not buffer the binary VNC stream; buffering causes visible lag and can corrupt the protocol.
5. websockify must no longer run with `--cert/--key` (remove from `novnc.service.j2`) once nginx owns TLS termination. Leaving both causes double-TLS on loopback and confuses the handshake.

**The noVNC websocket path:** By default, noVNC connects its websocket to the same host+port that served the HTML, at path `/websockify` (or `/`). The nginx location block for websocket proxying must match this path. The static noVNC HTML/JS assets are also served by websockify (via `--web`); nginx proxies these over the same upstream, so a single `location /` block is sufficient rather than splitting `/websockify` and `/` across two blocks.

---

## Feature Dependencies

```
nginx TLS termination
    └──requires──> websockify runs without --cert/--key (loopback plaintext backend)
    └──requires──> proxy_set_header Upgrade + Connection (WebSocket headers)
    └──requires──> proxy_http_version 1.1 (HTTP/1.1 for upgrade)
    └──requires──> proxy_read_timeout > 60s (idle session survival)
    └──enables──>  error_page 497 redirect (HTTP→HTTPS same port)
    └──enables──>  add_header HSTS / security headers (response from nginx, not websockify)

HSTS header
    └──requires──> short max-age (self-signed cert rebake protection)
    └──conflicts──> preload (needs public domain + 1yr max-age)
    └──conflicts──> includeSubDomains (no subdomains exist)
    └──conflicts──> long max-age (hard lockout footgun post-rebake)
```

---

## Prioritization Summary

| Feature | Category | Priority | Implementation Note |
|---------|----------|----------|---------------------|
| nginx TLS termination on :6080 | Table Stakes | P1 | Core of the milestone |
| WebSocket proxy with Upgrade headers | Table Stakes | P1 | noVNC non-functional without it |
| Remove `--cert/--key` from websockify | Table Stakes | P1 | Follows from nginx TLS ownership |
| `error_page 497` HTTP→HTTPS redirect | Table Stakes | P1 | Single-port redirect mechanism |
| `proxy_read_timeout` extension | Table Stakes | P1 | Prevents idle disconnection |
| `proxy_buffering off` | Table Stakes | P1 | Prevents VNC stream corruption |
| `X-Content-Type-Options: nosniff` | Table Stakes | P1 | Zero-cost, no false positives |
| HSTS with short max-age | Differentiator | P2 | Useful with short max-age; footgun with long |
| `X-Frame-Options: DENY` | Differentiator | P2 | Clickjacking prevention |
| `Referrer-Policy: no-referrer` | Differentiator | P3 | Low risk for internal tool; low cost |
| code-server TLS audit | Differentiator | P2 | Confirms parity; expected no-change |
| HSTS preload / includeSubDomains | Anti-Feature | N/A | Do not implement |
| Full CSP | Anti-Feature | N/A | Skip for this use case |
| Separate :80 listener | Anti-Feature | N/A | Unnecessary ingress surface |
| Double TLS (nginx + websockify) | Anti-Feature | N/A | Remove cert flags from websockify |
| OCSP stapling | Anti-Feature | N/A | Incompatible with self-signed certs |

---

## Sources

- websockify `--ssl-only` flag: https://github.com/novnc/websockify/blob/master/docs/websockify.1
- nginx noVNC proxying: https://github.com/novnc/noVNC/wiki/Proxying-with-nginx
- nginx WebSocket proxy headers: https://nginx.org/en/docs/http/websocket.html
- nginx `error_page 497` for same-port HTTP→HTTPS redirect: https://davidwesterfield.net/2021/03/redirecting-http-requests-to-https-on-same-port-in-nginx/
- HSTS semantics and self-signed cert behavior (MDN): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security
- HSTS un-bypassable warning behavior: https://support.mozilla.org/en-US/questions/1175070
- OWASP security headers cheat sheet: https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html
- nginx WSS + proxy_pass configuration: https://websocket.org/guides/infrastructure/nginx/

---
*Feature research for: noVNC HTTPS-only enforcement (v3.1 milestone)*
*Researched: 2026-06-09*
