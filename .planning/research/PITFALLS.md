# Pitfalls Research

**Domain:** noVNC HTTPS-Only — adding a TLS-terminating reverse proxy (nginx) in front of noVNC/websockify on AL2023; enforcing HTTPS + redirect + HSTS with a self-signed certificate.
**Researched:** 2026-06-09
**Confidence:** HIGH — pitfalls verified against nginx official docs, noVNC wiki, MDN HSTS spec, AL2023 SELinux docs, and this project's existing playbook code.

---

## Critical Pitfalls

### Pitfall 1: WebSocket Broken — Missing `Upgrade`/`Connection` Hop-by-Hop Headers

**What goes wrong:**
nginx strips `Upgrade` and `Connection` headers by default when proxying. Without them the WebSocket handshake at `/websockify` fails: the browser sends `HTTP 101 Switching Protocols` but websockify never sees the upgrade request. The client sees a blank noVNC canvas or an immediate disconnect. This is the single most common way noVNC breaks behind nginx.

**Why it happens:**
`Upgrade` and `Connection` are hop-by-hop headers per RFC 2616. nginx does not forward them to the upstream unless explicitly told to. The default nginx proxy config (only `proxy_pass`) is correct for plain HTTP but silently wrong for WebSocket.

**How to avoid:**
Three directives are required together in the WebSocket location block:

```nginx
location /websockify {
    proxy_pass          http://127.0.0.1:6080;
    proxy_http_version  1.1;
    proxy_set_header    Upgrade    $http_upgrade;
    proxy_set_header    Connection "upgrade";
    proxy_read_timeout  61s;
    proxy_buffering     off;
}
```

`proxy_http_version 1.1` matters because the WebSocket upgrade is a HTTP/1.1 mechanism — HTTP/1.0 (nginx's default upstream protocol) does not support persistent connections or protocol switching. Note: nginx ≥ 1.29.7 sets 1.1 implicitly for WebSocket paths, but specifying it explicitly is defensive and required on the AL2023 nginx package version.

Use the `map`-based `$connection_upgrade` variable only if the same `location` serves both HTTP and WebSocket requests. For a noVNC-dedicated location, the literal `"upgrade"` string is simpler and correct.

**Warning signs:**
- Browser console: `WebSocket connection to 'wss://...' failed`
- nginx error log: upstream sent invalid header
- noVNC shows "Disconnected" immediately after connecting
- `curl -i --http1.1 -H "Upgrade: websocket" -H "Connection: upgrade" https://host:6080/websockify` returns HTTP 400 or 200 instead of 101

**Phase to address:** Phase implementing the nginx reverse proxy role (before `hardening`). Verify with `curl --http1.1 -H "Upgrade: websocket" -H "Connection: upgrade" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: $(openssl rand -base64 16)"` in the role's Molecule smoke test.

---

### Pitfall 2: HSTS + Self-Signed Certificate = Permanent Operator Lockout

**What goes wrong:**
Once a browser receives `Strict-Transport-Security` from a host and caches it, the browser will not allow the user to click through any subsequent TLS error for that host — including the self-signed cert warning. The devbox noVNC page becomes completely inaccessible from that browser profile with no bypass route. The operator is locked out.

**Why it happens:**
HSTS is designed precisely to prevent click-through bypasses. MDN specification states: "If a TLS warning or error, such as an invalid certificate, occurs when connecting to an HSTS host, the browser does not offer the user a way to proceed or 'click through' the error message." This is not a bug — it is the intended behavior. The lockout occurs only after the first successful HTTPS connection delivers the `STS` header (TOFU — trust on first use). The first visit still gets the bypassable cert warning; all subsequent visits do not.

**The risk quantification:**
- Without HSTS: operator clicks "Advanced → Accept Risk" on every browser session (annoying but recoverable)
- With HSTS `max-age=31536000`: any browser that successfully connected once will be locked out for one year after the cert regenerates or the operator switches browsers/profiles. Recovering requires manually clearing HSTS state in `chrome://net-internals/#hsts` — which only works if the operator knows to do it and can reach the browser.
- With HSTS `preload`: lockout is permanent and browser-global across all profiles until the domain is removed from the preload list (takes weeks via hstspreload.org — and an IP address host can never be submitted to the preload list anyway).

**The safe choice for this project:**
Do not emit `Strict-Transport-Security` at all in v3.1. The security goal (force TLS) is fully achieved by:
1. websockify dropping plaintext via `--ssl-only`
2. nginx terminating TLS and issuing a redirect (via `error_page 497`) for any HTTP request arriving on port 6080

HSTS adds no meaningful additional protection on a private VPC + CIDR-allowlisted host with a self-signed cert. The only beneficiary of HSTS here is protection against protocol-downgrade attacks from a MITM already inside the allowlisted CIDR — a threat outside this project's scope.

If HSTS is added in a future milestone after a trusted cert is provisioned (e.g., Let's Encrypt via DNS-01), start with `max-age=300` for the first bake cycle, verify no lockout issues, then ramp to a production value. Never use `preload` or `includeSubDomains` on an IP-addressed or private internal host.

**Warning signs:**
- Browser shows: "You cannot visit this site because it uses HSTS. Network errors and attacks are usually temporary..." with no "Advanced" button
- Operator cannot access noVNC even after accepting the cert in a fresh browser session
- `chrome://net-internals/#hsts` shows the host in the static or dynamic HSTS list

**Phase to address:** Phase implementing HTTPS enforcement. HSTS header must be explicitly absent from the nginx config for v3.1. Add a CI grep-gate asserting `Strict-Transport-Security` does not appear in the nginx template file.

---

### Pitfall 3: `proxy_read_timeout` Default (60 s) Kills Idle VNC Sessions

**What goes wrong:**
A VNC session that has no screen updates and no user input for 60 seconds will be silently killed by nginx's default `proxy_read_timeout`. The operator's desktop session appears to freeze or disconnect without warning. This is mistaken for a VNC stability issue when the actual cause is the nginx timeout.

**Why it happens:**
`proxy_read_timeout` is the time nginx waits for data from the upstream before closing the connection. A VNC idle session sends nothing. The 60-second default is appropriate for HTTP API calls but catastrophically short for an interactive remote desktop.

**How to avoid:**
Set `proxy_read_timeout 61s;` in the noVNC WebSocket location (per the noVNC wiki recommendation — 61 seconds ensures nginx never hits the 60-second boundary race). For a devbox with no idle timeout requirement, `proxy_read_timeout 3600s;` (1 hour) or `proxy_read_timeout 86400s;` (1 day) is reasonable. The session can also be kept alive by websockify's built-in ping mechanism, but that requires the client browser to support the WebSocket ping/pong protocol. Setting a long timeout is the defensive approach.

Additionally, set `proxy_buffering off;` to prevent nginx from trying to buffer the VNC frame stream, which increases latency and memory use with no benefit.

**Warning signs:**
- VNC disconnects exactly 60 seconds after the last mouse movement or screen update
- noVNC overlay shows "Disconnected" or "Server has closed connection"
- nginx access log shows `499` (client closed) or `504` entries on the WebSocket connection at ~60 s intervals

**Phase to address:** Phase implementing the nginx proxy config. Include `proxy_read_timeout` in the nginx template with a comment explaining the VNC idle reason.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Emit HSTS with short `max-age=300` as a "test" | Feels like forward progress toward HSTS | Operators who hit the lockout once may still lose browser access for 5 minutes; entropy compounds as short max-age is later bumped without fixing the cert | Never in v3.1 with self-signed cert; only after trusted cert is in place |
| Put `--ssl-only` on websockify AND terminate TLS in nginx | Belt-and-suspenders TLS | Double TLS: nginx sends TLS to a websockify that also speaks TLS → cert verification errors, opaque failures; websockify on loopback must be plaintext | Never. Only one TLS layer. Nginx terminates TLS externally; websockify speaks plaintext on 127.0.0.1 |
| `Connection "upgrade"` literal instead of map variable | One less nginx config block | If the same location ever serves plain HTTP (health check, static file), `Connection: upgrade` on a non-upgrade request is technically incorrect. For a noVNC-dedicated location it is harmless. | Acceptable for a dedicated `/websockify` location |
| Use `$host:$server_port` in the 497 redirect | Preserves port | If nginx is behind another proxy that sets `X-Forwarded-Host`, `$host` will be the proxy's host, not the EC2 host. For single-hop deployments this is fine. | Acceptable for this project (no upstream proxy) |
| Omit `ssl_protocols` / `ssl_ciphers` in nginx config | Less config to write | nginx on AL2023 defaults to TLS 1.2+ on modern packages, but the default cipher list can include weak-CBC suites. The CIS hardening role locks down openssl/systemwide defaults, but nginx reads its own list. | Never — always specify `ssl_protocols TLSv1.2 TLSv1.3;` and a vetted cipher list |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| websockify + nginx | nginx proxies to websockify's TLS port (double TLS) | nginx terminates TLS on `6080 ssl`; `proxy_pass http://127.0.0.1:<internal_port>;` to websockify's plaintext loopback listener. Remove `--cert`/`--key` from websockify if nginx is the TLS layer. |
| websockify service | Keeping `--cert`/`--key` on websockify after adding nginx TLS termination | Drop TLS from websockify when nginx is the terminator. Two paths: (a) bind websockify on a new loopback port (e.g., 6081) without `--cert`/`--key`; nginx proxies to 6081. (b) Add `--ssl-only` to close the plaintext gap at websockify level independently of nginx. |
| firewalld + nginx loopback port | Adding a new loopback-only websockify port requires a firewalld allowance | The loopback interface (`lo`) on AL2023 with the docker-zone workaround in place (default zone = `docker`, target=ACCEPT) passes all traffic including loopback. No additional firewalld rule is needed for loopback-to-loopback nginx→websockify traffic. If the workaround is ever retired and the default zone reverts to `public`, add `--zone=trusted --add-interface=lo` (CIS XCCDF rule `firewalld_loopback_traffic_trusted`). |
| SELinux + nginx proxy | nginx returns 502 because SELinux denies the outbound proxy connection | AL2023 ships SELinux in **permissive mode** by default — denials are logged but not enforced. No `httpd_can_network_connect` boolean is needed under permissive mode. If SELinux is ever hardened to enforcing (not done in this project's `hardening` role currently), run `setsebool -P httpd_can_network_connect 1`. The AVC denial log entry to look for is: `avc: denied { name_connect } for comm="nginx"`. |
| nginx + code-server :8080 | Routing :8080 through the same nginx for HSTS parity | code-server already enforces HTTPS via `cert: true`. Adding nginx in front of :8080 purely to emit HSTS headers carries the same self-signed lockout risk described in Pitfall 2 — avoid in v3.1. Parity is confirmed at the TLS-only enforcement level, not HSTS level. |
| Ansible `hardening`-last invariant | New nginx role inserted after `hardening` in `playbook.yml` | Insert the nginx/reverse-proxy role immediately before `hardening` in `ansible/playbook.yml`. The grep-gate in `.pre-commit-config.yaml` and CI already enforces `hardening` as the last role. Any insert-after will fail CI. |
| Self-signed cert idempotency | `openssl req` task without a `creates:` guard re-generates the cert on every bake | Use `args: creates: /etc/novnc/nginx-cert.pem` (or the `community.crypto.x509_certificate` module). The existing `desktop` role already does this correctly for the noVNC websockify cert at `tasks/main.yml:165`. Mirror the same pattern. |
| `error_page 497` and `wss://` redirect | 497 redirect fires on WebSocket upgrade requests that nginx misinterprets as plain HTTP | WebSocket upgrades arrive as HTTP/1.1 GET with `Upgrade: websocket`. nginx on an `ssl` listener that receives a TLS WebSocket upgrade does NOT trigger 497 — 497 fires only for literal plaintext HTTP bytes on the SSL port. The redirect does not affect WebSocket connections at all. |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `proxy_buffering on` (default) | noVNC appears sluggish; mouse events have 100–500 ms latency; frame updates arrive in bursts | Add `proxy_buffering off;` in the WebSocket location | Immediate — any load level |
| `proxy_read_timeout 60s` (default) | VNC session drops every minute of inactivity | Set `proxy_read_timeout 3600s;` | Immediate on any idle session |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Emitting HSTS with any positive `max-age` while using self-signed cert | Operator permanently locked out of noVNC web UI from any browser that successfully connected once | Do not include `Strict-Transport-Security` header in v3.1 nginx config |
| nginx `listen 6080;` (no `ssl`) block left alongside `listen 6080 ssl;` | nginx accepts plaintext on 6080 — the security goal is defeated | Use a single `listen 6080 ssl;` directive; use `error_page 497` for the redirect. Never add a parallel plaintext listener on the same port. |
| Keeping websockify `--cert`/`--key` when nginx does TLS termination | Double TLS: nginx connects to websockify over TLS, fails cert verification (self-signed), returns 502 to client | When nginx is the TLS terminator, websockify must bind on a loopback port without `--cert`/`--key` |
| `ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;` or omitting `ssl_protocols` | TLS 1.0/1.1 negotiation allowed; POODLE/BEAST vulnerable | Always specify `ssl_protocols TLSv1.2 TLSv1.3;` explicitly in the nginx server block |
| Accidentally exposing nginx on `0.0.0.0:80` for the redirect | Opens a new unintended plaintext port that bypasses the AWS SG allowlist for :6080 | Do not add a separate `:80` listener; the error_page 497 approach handles the redirect on the same port without a second listener |
| Using `$host` without considering nginx's actual `server_name` | If no `server_name` matches, `$host` falls back to nginx's catch-all and may produce an incorrect redirect URL | Set `server_name _; ` (or the EC2 hostname) and verify the 497 redirect URL matches `https://<ec2-host>:6080/` in testing |

---

## "Looks Done But Isn't" Checklist

- [ ] **WebSocket headers present:** Verify with `curl --http1.1 -H "Upgrade: websocket" -H "Connection: upgrade" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" https://host:6080/websockify` returns HTTP 101, not 200 or 400
- [ ] **Redirect works, not loops:** `curl -k http://host:6080/` must return `301 → https://host:6080/` (not `301 → https://host:443/` which is a port-drop bug)
- [ ] **HSTS absent:** `curl -kI https://host:6080/ | grep -i strict` must return nothing
- [ ] **Plaintext rejected at websockify level too:** Add `--ssl-only` to the websockify `ExecStart` as defense-in-depth against direct-to-port-5901/6080 bypass. `curl http://host:6080/` (if internal port is exposed) must fail with TLS error
- [ ] **`proxy_buffering off` confirmed:** `curl -kI https://host:6080/ | grep -i "X-Accel-Buffering"` should be absent or `no`
- [ ] **`proxy_read_timeout` > 60 s:** grep the nginx template for `proxy_read_timeout` — must not be absent or ≤ 60
- [ ] **`ssl_protocols` restricted:** nginx config must contain `ssl_protocols TLSv1.2 TLSv1.3;`
- [ ] **No port :80 listener:** `ss -tlnp | grep ':80 '` on the AMI must return nothing
- [ ] **`hardening` still last in playbook.yml:** `tail -5 ansible/playbook.yml | grep hardening` must match
- [ ] **ansible-lint clean:** the new nginx role must pass `ansible-lint` with zero violations (shellcheck-lint the Jinja2 templates if they contain `|shell`)
- [ ] **Cert idempotency:** running the playbook twice produces zero changed tasks on the cert generation step
- [ ] **Double TLS absent:** `ExecStart` for novnc.service must NOT include both `--cert`/`--key` AND `proxy_pass https://`

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| HSTS lockout from browser | LOW (if caught early) | Clear in `chrome://net-internals/#hsts` (Chrome) or `about:networking#dns` (Firefox). If max-age was short (≤ 300 s), wait for TTL. If max-age was long, clear manually in every affected browser. |
| HSTS lockout — preload submitted | HIGH | Removal via hstspreload.org takes weeks. Cannot be self-served. Private IP hosts are not eligible for preload — this failure path is only possible if the host has a registered domain. |
| WebSocket broken (no Upgrade headers) | LOW | Add the three directives to the nginx template, rebake, `./run build && ./run tf-apply`. |
| Double TLS (nginx → websockify TLS) | LOW | Remove `--cert`/`--key` from the websockify `ExecStart` (or move websockify to a new loopback port without cert args), rebake. |
| Redirect loop (port drop in 301) | LOW | Replace `return 301 https://$host$request_uri;` with `error_page 497 =301 https://$host:$server_port$request_uri;` in the nginx ssl server block. |
| VNC session drops at 60 s | LOW | Add `proxy_read_timeout 3600s;` to the nginx WebSocket location, rebake. |
| SELinux 502 after enforcing mode enabled | MEDIUM | `setsebool -P httpd_can_network_connect 1` on the running instance; add a `community.general.seboolean` task to the nginx Ansible role so future bakes include it. |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Missing WebSocket Upgrade/Connection headers | Phase adding nginx proxy role | `curl` WebSocket upgrade test returning HTTP 101 |
| `proxy_read_timeout` 60 s VNC disconnect | Phase adding nginx proxy role | Template review + 65-second idle test in smoke test |
| `proxy_buffering` on | Phase adding nginx proxy role | `curl -I` check for buffering header; subjective latency test |
| HSTS + self-signed lockout | Phase adding HTTPS enforcement | CI grep-gate: `Strict-Transport-Security` absent from nginx template |
| Redirect loop / port drop in 301 | Phase adding HTTP→HTTPS redirect | `curl -k http://host:6080/` returns `Location: https://host:6080/` (port preserved) |
| Double TLS (proxy→websockify TLS) | Phase restructuring novnc.service | `novnc.service.j2` must not contain both `--cert` and `proxy_pass https://` |
| nginx plaintext port :80 accidentally opened | Phase adding nginx proxy role | `ss -tlnp` smoke test on baked AMI |
| Weak TLS protocols/ciphers | Phase adding nginx proxy role | `ssl_protocols` restricted in template; `nmap --script ssl-enum-ciphers` in verification |
| `hardening`-last invariant violated | Phase inserting nginx Ansible role | Pre-commit grep-gate + CI grep-gate (already enforced) |
| Cert idempotency broken | Phase adding nginx role with cert generation | Run playbook twice; second run must have 0 changed tasks on cert step |
| SELinux enforcing mode 502 | Future phase (if enforcing mode is enabled) | `setsebool` task present in nginx role; AVC audit log checked |
| firewalld blocking loopback (if docker-zone workaround retired) | Future phase (retirement of firewalld-docker-fix.yml) | `firewalld_loopback_traffic_trusted` rule present in public zone |
| HSTS on code-server :8080 | Phase auditing code-server TLS parity | Confirm `add_header Strict-Transport-Security` absent from any nginx config block proxying :8080 |

---

## Sources

- nginx WebSocket proxying official docs: https://nginx.org/en/docs/http/websocket.html
- noVNC nginx wiki: https://github.com/novnc/noVNC/wiki/Proxying-with-nginx
- nginx HSTS blog: https://blog.nginx.org/blog/http-strict-transport-security-hsts-and-nginx
- MDN HSTS spec: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security
- nginx error_page 497: https://chrisguitarguy.com/2019/08/20/redirecting-http-requests-on-an-https-listener-in-nginx-status-code-497/
- AL2023 SELinux modes: https://docs.aws.amazon.com/linux/al2023/ug/selinux-modes.html
- nginx SELinux httpd_can_network_connect: https://www.f5.com/company/blog/nginx/using-nginx-plus-with-selinux
- firewalld loopback trusted zone CIS rule: https://ato-pathways.com/catalogs/xccdf/benchmarks/ssg-al2023-ds.xml:latest/items/xccdf_org.ssgproject.content_rule_firewalld_loopback_traffic_trusted
- websockify `--ssl-only` flag: https://github.com/novnc/websockify/wiki/encrypted-connections
- Project firewalld workaround: ansible/firewalld-docker-fix.yml (inline documentation)
- Project playbook invariants: CLAUDE.md §8, .planning/PROJECT.md §Key Decisions

---
*Pitfalls research for: noVNC HTTPS-Only reverse proxy on AL2023 (v3.1 milestone)*
*Researched: 2026-06-09*
