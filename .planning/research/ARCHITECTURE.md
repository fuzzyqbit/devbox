# Architecture Research: v3.1 noVNC HTTPS-Only — TLS Reverse Proxy Integration

**Domain:** Packer+Ansible-baked AL2023 AMI cloud workstation
**Researched:** 2026-06-09
**Confidence:** HIGH — grounded in direct codebase inspection + verified official sources

---

## Summary of Findings

The cleanest integration puts nginx on the existing public-facing port (:6080), moves
websockify to loopback plaintext (:6081), and does NOT move code-server behind the proxy.
The proxy lives in a new dedicated `novnc-proxy` Ansible role inserted immediately before
`hardening`. No Terraform SG changes are needed. One firewalld rule is needed for the
`public` zone. code-server stays as-is — its TLS posture already satisfies the parity
requirement.

---

## Existing Architecture (Baseline)

```
Browser
  |
  |  HTTPS :6080  (websockify --cert/--key, self-signed /CN=devbox)
  |  -- also accepts plaintext (no --ssl-only; cannot produce redirect or HSTS)
  v
EC2 :6080  novnc.service  (websockify on 0.0.0.0:6080 with TLS)
  |
  v
localhost:5901  vncserver.service (TigerVNC)


Browser
  |
  |  HTTPS :8080  (code-server cert: true; self-generated cert)
  |  -- refuses plaintext at the process level; already HTTPS-only
  v
EC2 :8080  code-server.service (0.0.0.0:8080)
```

Key gap for noVNC: websockify/novnc_proxy cannot produce an HTTP-to-HTTPS redirect or
emit HSTS response headers. `--ssl-only` only rejects plaintext connections; it does not
issue a 301 or set `Strict-Transport-Security`. A real HTTP server must sit in front.

---

## Recommended Architecture (v3.1 Target)

```
Browser
  |
  |-- HTTP  :6080 ----> nginx (return 301 https://$host:6080$request_uri)
  |
  +-- HTTPS :6080 ----> nginx (TLS termination: /etc/novnc/novnc-{cert,key}.pem)
                          |  Strict-Transport-Security header
                          |  X-Frame-Options, X-Content-Type-Options headers
                          |  proxy_pass http://127.0.0.1:6081 (WS upgrade)
                          v
                      localhost:6081  novnc.service (websockify, plaintext, no TLS)
                          |
                          v
                      localhost:5901  vncserver.service (TigerVNC, unchanged)


Browser
  |
  +-- HTTPS :8080 ----> code-server.service (unchanged, cert: true, HTTPS-only)
```

---

## Decision 1: Port Topology

**Recommendation: nginx takes over :6080 publicly; websockify moves to 127.0.0.1:6081
(loopback only, plaintext). This is option (a) from the research question.**

Rationale:

- The existing Terraform SG already exposes :6080 with `var.allowed_web_cidrs`. Changing
  to a new external port would require SG edits, a new firewalld rule, CLAUDE.md updates,
  and `./run devbox-port-forward` script changes. Option (a) avoids all of this — the
  public port is unchanged; only the internal socket moves.
- The operator's port-forward muscle memory (`./run devbox-port-forward`) stays intact.
- Option (b) (proxy on a new port) would leave the existing :6080 websockify listener
  alive unless novnc.service is also changed — creating a gap where both ports accept
  connections or requiring careful coordination.
- Loopback port :6081 is invisible to the SG and firewalld (loopback traffic bypasses
  the INPUT chain on AL2023/firewalld). No additional rule needed for :6081 itself.

**websockify listen address change:**
`--listen {{ desktop_novnc_port }}` (currently resolves to `6080`, all interfaces)
becomes `--listen 127.0.0.1:{{ desktop_novnc_loopback_port }}` (loopback only, :6081).

The `127.0.0.1` binding is essential. Binding `0.0.0.0:6081` would mean port :6081
bypasses the proxy; port :6081 is not in the SG today, but defense-in-depth requires
an explicit loopback binding rather than relying on the SG omission.

---

## Decision 2: websockify TLS

**Recommendation: websockify runs plaintext on loopback. Remove `--cert` and `--key`
from the novnc.service ExecStart line.**

Rationale:

- Double TLS (nginx terminates TLS externally, websockify re-encrypts on loopback) has
  zero security value. Loopback traffic never leaves the kernel; it is not subject to
  interception by any network-layer attacker. Re-encrypting loopback is pure CPU
  overhead.
- The industry-standard reverse proxy pattern: proxy terminates TLS at the edge,
  backends receive plaintext on loopback. This is the documented pattern in the official
  noVNC wiki ("Proxying with nginx") and in every nginx-fronted noVNC deployment in the
  community literature.
- The cert/key files at `/etc/novnc/novnc-cert.pem` and `/etc/novnc/novnc-key.pem` are
  reused by nginx. The OpenSSL generation task and permission tasks in the `desktop`
  role remain intact — they just serve nginx instead of websockify.

Updated `novnc.service.j2` ExecStart (no --cert, no --key, loopback binding):

```
ExecStart=/usr/local/share/noVNC/utils/novnc_proxy \
  --listen 127.0.0.1:{{ desktop_novnc_loopback_port }} \
  --vnc localhost:{{ desktop_vnc_port }}
```

---

## Decision 3: code-server

**Recommendation: code-server stays on :8080 at `0.0.0.0:8080` with `cert: true`.
Do NOT move it behind the proxy.**

Rationale:

- `cert: true` in `~/.config/code-server/config.yaml` makes code-server itself refuse
  plaintext — the binary generates a self-signed cert and enforces HTTPS at the process
  level. This already satisfies the parity requirement: no plaintext accepted.
- The noVNC gap was that websockify accepts plaintext AND cannot produce a redirect.
  code-server has neither problem: it rejects plaintext at the process level. The audit
  conclusion is: parity confirmed, no change required.
- Moving code-server behind the proxy would require either (a) nginx-to-code-server over
  TLS (double TLS overhead) or (b) rebinding code-server to loopback plaintext (disabling
  `cert: true` — a regression from current security posture). Neither option improves
  security; both add complexity.
- HSTS on :8080 is a future nice-to-have. If it becomes a requirement, a lightweight
  nginx block on :8080 can be added in a later phase without disrupting this milestone.

---

## Decision 4: Ansible Role Ownership

**Recommendation: New dedicated role `ansible/roles/novnc-proxy/`, inserted immediately
before `hardening` in `ansible/playbook.yml`.**

Rationale:

- Project convention (MEMORY.md, CLAUDE.md §8 precedent from firewalld-docker-fix.yml):
  new components get their own role; workarounds get their own named playbook. A reverse
  proxy is a new functional component, not a kludge.
- The `desktop` role is already substantive (GNOME, TigerVNC, noVNC, dconf, ffmpeg, VLC).
  Adding nginx configuration, service management, and firewalld rules would erode its
  cohesion and prevent independent layer-gating.
- A dedicated role can be disabled (`layers.novnc_proxy: false`) without disabling the
  desktop, which is useful for local builds or lightweight AMI variants.
- nginx is a separate package with its own systemd service and config tree. Separation is
  natural here.

The `desktop` role requires one targeted modification: update `novnc.service.j2` to move
websockify off port 6080 to loopback 6081. This is a modification to an existing role's
template, not a new responsibility being added to it.

**playbook.yml insertion (updated role sequence):**

```yaml
roles:
  - role: base
  - role: certs
  # ... language/toolchain roles ...
  - role: secrets
  - role: vscode
  - role: desktop        # MODIFIED: novnc.service moves to 127.0.0.1:6081
  - role: novnc-proxy    # NEW: nginx on :6080, TLS proxy, HSTS, redirect
  - role: hardening      # MUST remain last -- invariant unchanged
```

`novnc-proxy` must come after `desktop` because it depends on:
1. `/etc/novnc/novnc-cert.pem` and `/etc/novnc/novnc-key.pem` (created by `desktop`).
2. `/usr/local/share/noVNC/` as the nginx document root (installed by `desktop`).

`novnc-proxy` must come before `hardening` to satisfy the enforced invariant.

**Layer gating:** Add `novnc_proxy: true` to `ansible/layer_config.yml`. Gate in
`playbook.yml` as `when: layers.novnc_proxy | default(false)`. Because `novnc-proxy`
is meaningless without `desktop`, either document this dependency explicitly in the
role's README, or add a guard assertion in `novnc-proxy/tasks/main.yml` that checks for
the cert file presence before proceeding.

---

## Component Inventory: New vs Modified

| Component | Change Type | What Changes |
|-----------|-------------|--------------|
| `ansible/roles/novnc-proxy/` | NEW | Full new role: nginx package, config template, systemd service, firewalld rule |
| `ansible/roles/novnc-proxy/tasks/main.yml` | NEW | `dnf install nginx`; deploy config template; `systemd enable+start nginx`; `ansible.posix.firewalld` port :6080/tcp |
| `ansible/roles/novnc-proxy/templates/novnc.nginx.conf.j2` | NEW | Two server blocks on :6080 (HTTP redirect + HTTPS proxy with WS upgrade + security headers) |
| `ansible/roles/novnc-proxy/defaults/main.yml` | NEW | `novnc_proxy_novnc_loopback_port: 6081`; cert/key paths |
| `ansible/roles/novnc-proxy/handlers/main.yml` | NEW | `systemctl reload nginx` handler |
| `ansible/roles/desktop/templates/novnc.service.j2` | MODIFIED | Remove `--cert/--key`; rebind `--listen` to `127.0.0.1:{{ desktop_novnc_loopback_port }}` |
| `ansible/roles/desktop/defaults/main.yml` | MODIFIED | Add `desktop_novnc_loopback_port: 6081` |
| `ansible/playbook.yml` | MODIFIED | Insert `novnc-proxy` role before `hardening` |
| `ansible/layer_config.yml` | MODIFIED | Add `novnc_proxy: true` |
| `terraform/main.tf` | UNCHANGED | :6080 SG ingress rule already present and correct |

---

## Terraform / Security Group Impact

**No changes required to `terraform/main.tf`.**

The existing ingress rule:

```hcl
ingress {
  description = "noVNC (HTTPS) restricted to operator CIDR allowlist"
  from_port   = 6080
  to_port     = 6080
  protocol    = "tcp"
  cidr_blocks = var.allowed_web_cidrs
}
```

Already covers nginx binding to :6080. The only behavioral change is that the socket
owner is nginx instead of websockify — transparent to the SG.

The new websockify loopback port (:6081) requires no SG rule. It is bound to
`127.0.0.1` and unreachable from outside the instance by design.

---

## firewalld Impact

**One new rule required, added by the `novnc-proxy` role.**

Current state: `firewalld-docker-fix.yml` sets the default zone to `docker`
(target=ACCEPT — effectively permissive). Under this workaround, traffic to :6080 and
:8080 passes regardless of zone rules. However, the retirement criteria for that
workaround (documented in the play header) include adding per-port allowances in the
`public` zone as the proper fix. The `novnc-proxy` role should add its allowance
explicitly now, making the configuration correct under both the current workaround state
and the future clean state.

Using the `ansible.posix.firewalld` module (collection already pinned at
`ansible.posix==2.1.0` in `ansible/requirements.yml`):

```yaml
- name: Allow noVNC proxy port through firewalld (public zone)
  ansible.posix.firewalld:
    port: 6080/tcp
    zone: public
    permanent: true
    state: enabled
    immediate: true
```

This is idempotent whether the default zone is `docker` (current workaround state) or
`public` (future clean state). The rule targets the `public` zone explicitly and does
not depend on the default zone setting.

Note: nginx also needs to handle plain HTTP on :6080 to produce the redirect. This does
NOT require a separate :80 listener — both the HTTP and HTTPS server blocks listen on
port 6080. nginx distinguishes them via TLS detection (presence/absence of a TLS
ClientHello on the socket). No :80 firewalld rule and no :80 SG rule are needed.

---

## Data Flow (Complete Request Paths)

### WebSocket session (VNC frames)

```
Browser
  |
  | 1. HTTPS :6080 -- TLS ClientHello
  v
nginx :6080 -- TLS termination (/etc/novnc/novnc-{cert,key}.pem)
  |  Strict-Transport-Security: max-age=63072000; includeSubDomains
  |  proxy_pass http://127.0.0.1:6081
  |  proxy_set_header Upgrade $http_upgrade
  |  proxy_set_header Connection "upgrade"
  |  proxy_http_version 1.1
  |  proxy_read_timeout 61s    (> 60s default; prevents race-condition disconnect)
  |  proxy_buffering off
  v
websockify 127.0.0.1:6081 -- plaintext WebSocket, no TLS
  |
  | TCP
  v
TigerVNC localhost:5901
  |
  | VNC framebuffer frames (binary, over WebSocket back to browser)
  v
(browser renders desktop)
```

### HTTP-to-HTTPS redirect

```
Browser
  |
  | HTTP :6080 (plain HTTP request -- no TLS ClientHello)
  v
nginx :6080 HTTP server block
  |  return 301 https://$host:6080$request_uri
  v
Browser follows redirect --> HTTPS :6080 (flow above)
```

### noVNC static asset serving

```
Browser
  |
  | HTTPS GET /  (or /vnc.html)
  v
nginx :6080 HTTPS server block
  |  root /usr/local/share/noVNC/;
  |  index vnc.html;
  v
File served directly by nginx (no proxy; only /websockify path proxies to websockify)
  v
noVNC JS client loads in browser --> opens WSS connection --> VNC session flow above
```

---

## nginx Configuration Structure

Two server blocks, both on port 6080:

**Block 1 -- HTTP redirect (no ssl keyword, catches plaintext connections):**
```nginx
server {
    listen 6080;
    server_name _;
    return 301 https://$host:6080$request_uri;
}
```

**Block 2 -- HTTPS proxy (ssl keyword, catches TLS connections):**
```nginx
server {
    listen 6080 ssl;
    server_name _;

    ssl_certificate     /etc/novnc/novnc-cert.pem;
    ssl_certificate_key /etc/novnc/novnc-key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;

    # Static noVNC assets
    root  /usr/local/share/noVNC/;
    index vnc.html;

    # WebSocket proxy to websockify on loopback
    location /websockify {
        proxy_pass         http://127.0.0.1:{{ novnc_proxy_novnc_loopback_port }}/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_read_timeout 61s;
        proxy_buffering    off;
    }
}
```

Both blocks on port 6080 is valid nginx. The HTTP block catches connections that arrive
without a TLS ClientHello; the SSL block handles TLS connections. nginx determines which
to use via socket-level protocol detection, not port-level routing.

nginx is available in the AL2023 core dnf repository (`dnf install nginx`) at version
1.24.x. No third-party repo is required. Caddy is NOT available via COPR for AL2023
(the COPR project has no `epel-2023` build target -- confirmed via `caddyserver/dist`
GitHub issue #119) and would require a manual binary download or a custom repo, both of
which add bake-time complexity and break package-manager auditability. nginx is the
correct choice.

---

## Build Order for v3.1 Implementation

Role sequence respects the existing invariant (hardening last) and the new dependency
chain (novnc-proxy after desktop):

```
base
  -> certs
  -> [language/toolchain roles as before]
  -> secrets
  -> vscode
  -> desktop  (MODIFIED: novnc.service rebinds to loopback :6081, drops TLS flags)
  -> novnc-proxy  (NEW: nginx on :6080, TLS termination, redirect, HSTS, firewalld rule)
  -> hardening  (invariant: MUST remain last)
```

Implementation sequence within a single PR:

1. Add `desktop_novnc_loopback_port: 6081` to `ansible/roles/desktop/defaults/main.yml`.
2. Update `ansible/roles/desktop/templates/novnc.service.j2` -- remove `--cert/--key`,
   rebind `--listen` to `127.0.0.1:{{ desktop_novnc_loopback_port }}`.
3. Create `ansible/roles/novnc-proxy/` skeleton (defaults, tasks, templates, handlers).
4. Write `novnc.nginx.conf.j2` with the two server blocks above.
5. Write `tasks/main.yml`: install nginx, deploy config, enable service, firewalld rule.
6. Update `ansible/playbook.yml`: insert `novnc-proxy` before `hardening`.
7. Update `ansible/layer_config.yml`: add `novnc_proxy: true`.
8. Bake and smoke-test:
   - `curl -k http://<host>:6080/` must return 301.
   - `curl -kI https://<host>:6080/` must return 200 with `Strict-Transport-Security`.
   - noVNC browser session must function (WebSocket connect through proxy to VNC).
   - `curl http://<host>:6081/` from outside must be unreachable (loopback binding).

---

## Anti-Patterns to Avoid

### Double TLS on Loopback

**What:** Keeping `--cert/--key` in websockify's ExecStart after nginx takes over TLS.
**Why wrong:** Re-encrypting loopback traffic burns CPU with zero security benefit.
Loopback traffic never leaves the kernel.
**Instead:** Remove `--cert/--key`; reuse the cert files in nginx only.

### Extending `desktop` with Proxy Logic

**What:** Adding nginx install, config, and service management inside `desktop/tasks/`.
**Why wrong:** Violates single responsibility; prevents independent layer-gating of the
proxy; contradicts the project convention (new components get their own role).
**Instead:** New `novnc-proxy` role.

### Binding websockify to `0.0.0.0:6081`

**What:** Moving websockify from :6080 to :6081 but binding all interfaces.
**Why wrong:** Port :6081 is not in the SG today, but relying on SG omission for security
is not defense-in-depth. If the SG is widened or the host moved to a more permissive
network, plaintext websockify would be directly exposed.
**Instead:** Bind `127.0.0.1:6081` explicitly.

### Separate :80 Listener for the Redirect

**What:** Adding a second nginx listener on :80 for HTTP-to-HTTPS redirect.
**Why wrong:** Port :80 is not in the SG and not in firewalld. A redirect on :80 is
unreachable by external clients. The redirect must live on the same port as the service
(:6080), differentiated from HTTPS by TLS detection, not by port number.
**Instead:** Both server blocks on :6080; HTTP vs HTTPS distinguished by the `ssl`
keyword in the `listen` directive.

### Moving code-server Behind the Proxy

**What:** Putting code-server (:8080) behind the nginx proxy to get HSTS parity.
**Why wrong:** code-server's `cert: true` already enforces HTTPS at the process level.
Moving it behind a proxy requires either double TLS (nginx+code-server both with TLS)
or disabling `cert: true` (plaintext code-server on loopback -- a security regression).
The gap does not exist; no fix is needed.
**Instead:** Confirm parity via audit (code-server rejects plaintext); no Ansible change.

---

## Integration Points

### Internal Boundaries

| Boundary | Communication | Key Config |
|----------|---------------|------------|
| nginx <-> websockify | HTTP/1.1 WebSocket upgrade over loopback TCP | `proxy_http_version 1.1`; `Upgrade` + `Connection` headers forwarded; `proxy_read_timeout 61s`; `proxy_buffering off` |
| `novnc-proxy` role -> `desktop` role | File system (cert/key paths; noVNC static asset dir) | Role ordering dependency: novnc-proxy runs after desktop |
| `novnc-proxy` role -> `ansible.posix` | Ansible module for firewalld | Collection already pinned at `ansible.posix==2.1.0` in `requirements.yml` |
| nginx -> firewalld | Port :6080/tcp allowed in `public` zone | `ansible.posix.firewalld` module; `permanent: true; immediate: true` |
| novnc.service -> nginx | Dependency ordering: nginx should start before novnc (or independently; they don't share a socket) | Consider `After=nginx.service` in novnc.service if nginx fails to start first |

---

## Sources

- noVNC wiki -- [Proxying with nginx](https://github.com/novnc/noVNC/wiki/Proxying-with-nginx) -- HIGH confidence (official noVNC project)
- nginx docs -- [WebSocket proxying](https://nginx.org/en/docs/http/websocket.html) -- HIGH confidence (official nginx)
- nginx AL2023 availability -- confirmed in AL2023 core dnf repo at version 1.24.x -- MEDIUM confidence (multiple community guides; consistent with AWS package listing)
- Caddy on AL2023 -- NOT available via COPR (no `epel-2023` build target) -- MEDIUM confidence ([caddyserver/dist#119](https://github.com/caddyserver/dist/issues/119))
- [Websockify + noVNC behind nginx](https://datawookie.dev/blog/2021/08/websockify-novnc-behind-an-nginx-proxy/) -- MEDIUM confidence (pattern consistent with official noVNC wiki)
- Direct codebase inspection: `ansible/roles/desktop/tasks/main.yml`, `templates/novnc.service.j2`, `ansible/roles/vscode/defaults/main.yml`, `ansible/roles/vscode/templates/config.yaml.j2`, `ansible/roles/hardening/defaults/main.yml`, `ansible/playbook.yml`, `terraform/main.tf`, `ansible/firewalld-docker-fix.yml` -- HIGH confidence (primary sources)

---

*Architecture research for: v3.1 noVNC HTTPS-Only -- TLS reverse proxy integration*
*Researched: 2026-06-09*
