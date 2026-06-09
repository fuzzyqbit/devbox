# Stack Research: noVNC HTTPS-Only + Reverse Proxy

**Domain:** TLS-terminating reverse proxy for a WebSocket-based browser VNC client on AL2023
**Researched:** 2026-06-09
**Milestone:** v3.1 noVNC HTTPS-Only
**Confidence:** HIGH (nginx core facts); MEDIUM (exact pinned version string; requires live `dnf info` to confirm)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| nginx | 1.26.3-*.amzn2023 (base repo) | TLS-terminating reverse proxy in front of websockify on :6080 | In AL2023 base repos (`dnf install nginx`), no third-party repo needed, full WebSocket proxy support, native `add_header` for HSTS and security headers, 301 redirect block for HTTP→HTTPS, established noVNC/Proxmox reference configurations. Stable branch (even minor = LTS maintenance). |
| websockify (existing) | pip-installed, already present | WebSocket-to-TCP bridge to TigerVNC :5901 | Already baked. In this design websockify is moved to loopback-only (`--listen 127.0.0.1:{{ desktop_novnc_port }}`); nginx owns the public-facing port and all TLS. No `--ssl-only` flag needed on websockify once it is loopback-only. |
| openssl (existing) | system package, AL2023 ships OpenSSL 3.x | Self-signed cert generation | Already baked as part of the desktop role. Cert/key at `/etc/novnc/novnc-cert.pem` / `/etc/novnc/novnc-key.pem` are reused by nginx as-is; no new cert infrastructure. |

### Supporting Ansible Tooling

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `community.general.dnf_versionlock` | community.general==12.6.0 (already pinned in requirements.yml) | Lock nginx at the installed version after the first bake | Use after `dnf install nginx` to prevent drift on future AMI rebuilds that reuse the same releasever. Alternative: pin via `name: nginx-<full-NVR>` in the dnf task. |
| `ansible.builtin.template` | built-in | Render nginx.conf from a Jinja2 template | Needed for the nginx vhost config and the redirect server block |
| `ansible.builtin.systemd` | built-in | Enable and start `nginx.service` | Same pattern as the existing `novnc.service` handling |

---

## Approach Analysis: Three Options

### Option 1: websockify `--ssl-only` alone

**What it does:** `--ssl-only` makes websockify reject plaintext connections. Per the official man page: "disallow non-encrypted connections." The implementation drops or closes the connection on SSL handshake failure — it does not send an HTTP 301, HTTP 302, or any redirect response. The `--ssl-only` flag has no mechanism to emit HTTP response headers at all, since websockify is a raw TCP/WebSocket proxy, not an HTTP server.

**Confirmed limitations:**
- No HTTP→HTTPS redirect: websockify cannot write a `Location:` header to an unencrypted HTTP request. The connection is simply closed (LOW confidence on exact error code — connection reset vs. 400 — but HIGH confidence that no redirect is produced: the source option string is "disallow non-encrypted connections", not "redirect").
- No HSTS header: websockify has no `add_header` or HTTP response header injection capability.
- No security headers (X-Frame-Options, X-Content-Type-Options, etc.).

**Verdict: Insufficient.** Covers only "reject plaintext." Does not satisfy "redirect HTTP→HTTPS" or "add HSTS/security headers," which are stated requirements for this milestone. `--ssl-only` is still useful as a defense-in-depth flag if websockify ever escapes loopback, but it cannot be the sole TLS enforcement mechanism.

### Option 2: nginx as TLS-terminating reverse proxy (RECOMMENDED)

**What it does:** nginx listens on :6080 (public), terminates TLS with the existing self-signed cert, proxies WebSocket traffic to websockify on `127.0.0.1:<internal_port>`, serves a 301 redirect from the plain-HTTP server block, and injects HSTS + security headers.

**AL2023 availability:** nginx is in the AL2023 base repo. `dnf install nginx` works with no extra repo configuration. The package as of AL2023 2023.7.20250331 is `nginx 1.26.3`. The package name is simply `nginx`; the Ansible `dnf` task installs the core server.

**WebSocket proxy support:** Confirmed. nginx WebSocket proxying requires `proxy_http_version 1.1` plus `Upgrade` and `Connection` header pass-through — standard nginx configuration, well-documented in the official nginx WebSocket guide and the noVNC project's own nginx wiki page. The noVNC wiki explicitly recommends nginx for this use case, including setting `proxy_read_timeout` above 60s and disabling `proxy_buffering`.

**HSTS and security headers:** Confirmed. Standard nginx `add_header Strict-Transport-Security "max-age=63072000" always` in the HTTPS server block. The `always` parameter ensures headers appear on all responses including error pages.

**HTTP→HTTPS redirect:** Standard nginx `server { listen 6080; return 301 https://$host$request_uri; }` block. This is a well-understood configuration.

**Reproducible pinning method:** Two complementary approaches that match the project's existing reproducibility policy:

1. **`--releasever` on dnf:** AL2023's deterministic upgrade system means every AMI bake should use `dnf install --releasever=<date-stamp> nginx`. The releasever pins the exact set of packages from that AL2023 quarterly release. The bake's Packer source AMI is already pinned via SSM Parameter Store; the matching releasever for that base AMI should be set as a variable in `ansible/roles/desktop/defaults/main.yml` (e.g., `desktop_al2023_releasever: "2023.7.20250331"`). This is the project's idiomatic approach — the same mechanism used for other AL2023 packages.

2. **Full NVR pinning in dnf task:** As a belt-and-suspenders measure, specify the full package NVR (Name-Version-Release) string in the Ansible `dnf` task: `name: nginx-1.26.3-1.amzn2023.0.3` (or whatever the exact string is for the chosen releasever — confirm with `dnf info nginx --releasever=<date-stamp>` on a live instance). This makes the exact version explicit in code and prevents silent drift if the releasever ever gets re-pointed.

**Interaction with existing systemd unit:** The `novnc.service` ExecStart must change so websockify binds to loopback only: `--listen 127.0.0.1:{{ desktop_novnc_port }}` instead of `--listen {{ desktop_novnc_port }}`. nginx gets a new `nginx.service` that depends on nothing (it starts before noVNC is reachable anyway — that is fine, nginx will 502 until websockify is up, which is the same behavior as the current direct TLS endpoint). The noVNC service should stay on port 6081 (or any non-conflicting port) for the loopback listener; nginx takes over :6080 externally.

**Port renaming consideration:** Since nginx takes :6080 externally, the internal websockify port can be any unused loopback port. Convention: keep `desktop_novnc_port: 6081` as the internal port and introduce `desktop_novnc_public_port: 6080` for nginx. The AWS security group rule stays on :6080 unchanged — no Terraform changes.

**firewalld:** The existing `firewalld-docker-fix.yml` workaround already handles the firewalld+Docker interaction. nginx will need a `firewall-cmd --add-port=6080/tcp --permanent` or the equivalent Ansible `ansible.posix.firewalld` task — the same pattern used by existing services. Since nginx takes over the port that websockify previously used, no new firewall port is required if the SG already allows :6080.

### Option 3: Caddy as reverse proxy

**AL2023 availability:** Caddy is NOT in the AL2023 base repos. The COPR `@caddy/caddy` project does not have a repository for Amazon Linux 2023 (confirmed: GitHub issue `amazonlinux/amazon-linux-2023#95` open as of 2026 with no resolution; `caddyserver/dist#119` documents the same error — "Repository 'epel-2023-x86_64' does not exist").

**Installation method available:** Binary download from GitHub releases. Caddy v2.11.4 (2026-06-03) is the current stable release. Download URL: `https://github.com/caddyserver/caddy/releases/download/v2.11.4/caddy_2.11.4_linux_amd64.tar.gz` with SHA-512 checksum from `caddy_2.11.4_checksums.txt`. This is the same binary-download-plus-checksum pattern used for mise, bazelisk, lazygit, and others already in this project.

**Automatic HTTPS implications with a self-signed cert:** Caddy's automatic HTTPS feature (which provides automatic HTTP→HTTPS redirect and automatic cert provisioning) is **disabled** when you manually specify your own certificate via `tls /path/to/cert /path/to/key`. Per official Caddy docs: "Manually loading certificates (unless `ignore_loaded_certificates` is set)" prevents automatic HTTPS activation, which includes the automatic HTTP→HTTPS redirect. This means if you bring your own self-signed cert, you must manually configure the redirect in the Caddyfile. Caddy does **not** automatically add HSTS headers — those must be added explicitly with `header Strict-Transport-Security "max-age=63072000"`.

**Net result for self-signed cert use case:** Caddy loses its primary advantage (zero-config HTTPS) in this scenario. With a manually-loaded cert, Caddy and nginx require essentially the same amount of explicit configuration for redirect + HSTS + WebSocket proxy. Caddy's Caddyfile syntax is more concise, but nginx has a proven track record in this exact noVNC use case with multiple reference configs (noVNC wiki, Proxmox documentation).

**Additional drawback:** Caddy is not a dnf package for AL2023. Installing it requires a binary download task in Ansible (get_url + checksum), creating a systemd unit, and adding a user manually — more Ansible boilerplate than `dnf install nginx`. This is additional complexity for no functional gain in this specific scenario.

**Verdict:** Caddy is a viable option technically but is the inferior choice here. It is not in the base repos, loses its killer feature (auto-HTTPS) with a self-signed cert, and has no functional advantage over nginx for this use case.

---

## Recommended Stack: nginx

Use `nginx` from the AL2023 base repo as the TLS-terminating reverse proxy. Configure it with:
1. An HTTPS server block on :6080 with `ssl_certificate /etc/novnc/novnc-cert.pem` and `ssl_certificate_key /etc/novnc/novnc-key.pem` (reusing existing cert)
2. WebSocket proxy directives to `http://127.0.0.1:{{ desktop_novnc_internal_port }}`
3. HSTS and security headers via `add_header ... always`
4. A second plain-HTTP server block on :6080 that issues a 301 redirect to HTTPS

Change websockify's `--listen` to `127.0.0.1:{{ desktop_novnc_internal_port }}` (remove `--ssl-only` and `--cert`/`--key` from the websockify unit — TLS is now nginx's responsibility).

### Reference nginx Configuration (Jinja2 template outline)

```nginx
# /etc/nginx/conf.d/novnc.conf
# Rendered from ansible/roles/desktop/templates/nginx-novnc.conf.j2

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

# HTTP → HTTPS redirect
server {
    listen {{ desktop_novnc_port }};
    server_name _;
    return 301 https://$host$request_uri;
}

# HTTPS + WebSocket proxy
server {
    listen {{ desktop_novnc_port }} ssl;
    server_name _;

    ssl_certificate     /etc/novnc/novnc-cert.pem;
    ssl_certificate_key /etc/novnc/novnc-key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # HSTS (2 years; no preload — self-signed cert, internal use)
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Content-Type-Options    "nosniff"          always;
    add_header X-Frame-Options           "SAMEORIGIN"       always;

    location / {
        proxy_pass         http://127.0.0.1:{{ desktop_novnc_internal_port }};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection $connection_upgrade;
        proxy_set_header   Host       $host;
        proxy_buffering    off;
        proxy_read_timeout 3600s;
    }
}
```

> Note: The `listen` directive uses the same `desktop_novnc_port` (6080) variable for both blocks because nginx distinguishes them by the `ssl` parameter. This is the standard dual-block redirect pattern.

---

## Installation

```yaml
# In ansible/roles/desktop/tasks/main.yml (or a new proxy role)

- name: Install nginx
  ansible.builtin.dnf:
    name: nginx
    state: present
  # For full reproducibility, pin to NVR: name: "nginx-1.26.3-1.amzn2023.0.X"
  # Confirm exact NVR with: dnf info nginx --releasever={{ desktop_al2023_releasever }}

- name: Install nginx noVNC reverse proxy config
  ansible.builtin.template:
    src: nginx-novnc.conf.j2
    dest: /etc/nginx/conf.d/novnc.conf
    owner: root
    group: root
    mode: "0644"
  notify: reload nginx

- name: Enable and start nginx
  ansible.builtin.systemd:
    name: nginx
    enabled: true
    state: started
    daemon_reload: true
```

```yaml
# handlers:
- name: reload nginx
  ansible.builtin.systemd:
    name: nginx
    state: reloaded
```

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Caddy | Not in AL2023 base repos; loses auto-HTTPS with self-signed cert; more Ansible boilerplate for no functional gain | nginx (base repo, proven WebSocket+noVNC support) |
| Let's Encrypt / ACM cert provisioning | Out of scope for this milestone; instance is CIDR-allowlisted inside a private VPC; self-signed cert is sufficient | Retain `/etc/novnc/novnc-cert.pem` (already baked) |
| `websockify --ssl-only` as the sole TLS control | Cannot produce HTTP→HTTPS redirect or emit HSTS headers | nginx handles all of this; `--ssl-only` may be kept as defense-in-depth but is not load-bearing once websockify is loopback-only |
| nginx from the official nginx.org yum repo | Extra repo config with GPG key management; base AL2023 repo already has nginx 1.26.3 stable; no version advantage justifies the extra dependency | `dnf install nginx` from base repo |
| HAProxy | Overkill for a single-backend TLS terminator; WebSocket proxy requires additional ACL config; no benefit over nginx here | nginx |
| stunnel | Only handles TLS wrapping; cannot produce HTTP redirect or inject response headers; additional service to manage | nginx |
| Apache httpd | Heavier than nginx; mod_proxy_wstunnel works but requires more module management on AL2023; nginx is the documented choice for noVNC | nginx |
| HSTS `preload` and `includeSubDomains` | Self-signed cert with a generic `/CN=devbox` — preload is meaningless and includeSubDomains has no subdomains; keep HSTS max-age only | `max-age=63072000` without preload/includeSubDomains |

---

## Alternatives Considered

| Category | Recommended | Alternative | When to Use Alternative |
|----------|-------------|-------------|-------------------------|
| Reverse proxy | nginx (base repo) | Caddy v2.11.4 (binary download) | Only if trusted-cert ACME provisioning is added in a future milestone — Caddy's auto-HTTPS becomes its killer feature with a real domain |
| Reverse proxy | nginx | HAProxy | Multi-backend load balancing; not needed here |
| TLS termination | nginx (terminates for websockify) | websockify `--ssl-only` alone | Acceptable only if redirect + HSTS are not requirements |
| Version pinning | `--releasever` + full NVR string | `community.general.dnf_versionlock` | versionlock is a reasonable supplement but does not work with dnf5; the NVR + releasever approach is more portable |

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| nginx 1.26.3 | AL2023 2023.7.20250331+ | Stable branch; WebSocket proxy via `proxy_http_version 1.1` + `Upgrade`/`Connection` headers. nginx docs note that `proxy_http_version 1.1` may be required for WebSocket upgrade on versions prior to 1.29.7. |
| websockify (pip, existing) | nginx 1.26.3 | websockify binds loopback; nginx proxies to it. No version conflict — they do not share code. |
| AL2023 OpenSSL 3.x (existing) | nginx 1.26.3 | nginx on AL2023 links against system OpenSSL 3.x. TLSv1.2 + TLSv1.3 supported. |
| community.general 12.6.0 | ansible-core ≥ 2.16 | Already pinned in requirements.yml; provides `dnf_versionlock` if needed. |

---

## Sources

- [nginx WebSocket proxying (official docs)](https://nginx.org/en/docs/http/websocket.html) — HIGH confidence; verified: `proxy_http_version 1.1`, `Upgrade`/`Connection` headers required
- [noVNC Proxying with nginx (project wiki)](https://github.com/novnc/noVNC/wiki/Proxying-with-nginx) — HIGH confidence; official noVNC project recommendation; `proxy_buffering off`, `proxy_read_timeout > 60s`
- [nginx Linux packages — AL2023 repo](https://nginx.org/en/linux_packages.html) — HIGH confidence; official nginx repo setup confirmed for `amzn/2023`
- [AL2023 release notes 2023.7.20250331](https://docs.aws.amazon.com/linux/al2023/release-notes/relnotes-2023.7.20250331.html) — HIGH confidence; nginx 1.26.3 in base repo confirmed
- [AL2023 deterministic upgrades](https://docs.aws.amazon.com/linux/al2023/ug/deterministic-upgrades-usage.html) — HIGH confidence; `--releasever` pinning mechanism documented
- [websockify man page](https://github.com/novnc/websockify/blob/master/docs/websockify.1) — HIGH confidence; `--ssl-only` "disallow non-encrypted connections" — no redirect, no headers
- [Caddy automatic HTTPS docs](https://caddyserver.com/docs/automatic-https) — HIGH confidence; manually-loaded cert disables auto-HTTPS/redirect
- [Caddy AL2023 install issue (caddyserver/dist#119)](https://github.com/caddyserver/dist/issues/119) — HIGH confidence; COPR repo does not support AL2023, unresolved
- [Caddy AL2023 package request (amazonlinux/amazon-linux-2023#95)](https://github.com/amazonlinux/amazon-linux-2023/issues/95) — HIGH confidence; Caddy not in AL2023 base repos, open request
- [community.general.dnf_versionlock module](https://docs.ansible.com/projects/ansible/latest/collections/community/general/dnf_versionlock_module.html) — HIGH confidence; available in community.general 12.6.0 (already pinned)
- [Caddy v2.11.4 release](https://github.com/caddyserver/caddy/releases) — HIGH confidence; latest stable as of 2026-06-03

---

*Stack research for: noVNC HTTPS-only enforcement + reverse proxy on AL2023*
*Researched: 2026-06-09*
