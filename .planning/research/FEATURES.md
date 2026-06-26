# Feature Research

**Domain:** Amazon DCV remote desktop — single-operator, SSM-tunneled, GNOME-on-AL2023
**Researched:** 2026-06-18
**Confidence:** HIGH (all session/auth/connectivity/TLS claims from official AWS DCV admin guide; the SSM-over-TCP implication is a MEDIUM inference grounded in DCV's documented UDP-only QUIC transport + the existing `AWS-StartPortForwardingSession` TCP-only operator surface)

> **Scope note.** This file answers "how does DCV *work* for our use case" and splits behavior into
> table-stakes / differentiator / anti-feature. It deliberately does **not** cover the airgap install or
> the S3-license path (`dcv-license.<region>` VPC endpoint + IAM `s3:GetObject`) — that is the
> make-or-break dependency tracked separately in PROJECT.md and STACK/ARCHITECTURE research. Here the
> assumption is "dcvserver is installed and licensed; what must we configure for it to render GNOME for
> one operator over SSM."

---

## The Five Load-Bearing Facts (read these first)

These are the mechanics the milestone scope hinges on. Each is sourced from the AWS DCV Administrator Guide.

### 1. DCV does NOT auto-create a session on Linux — this is the #1 footgun

> "Linux and macOS Amazon DCV servers don't get a default console session after installation."
> — [Starting Amazon DCV sessions](https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-start.html)

Installing `dcvserver` and starting the systemd service gives you a **listening server with zero sessions**.
A browser pointed at `:8443` will authenticate but have nothing to attach to. You MUST do one of:

- **(a) Auto-console-session via `dcv.conf`** (recommended for our single-operator, baked-AMI model):
  ```ini
  [session-management]
  create-session = true

  [session-management/automatic-console-session]
  owner = "ec2-user"
  ```
  Then restart `dcvserver`. This creates a console session with the fixed ID `console`, owned by `ec2-user`,
  re-created automatically on every server start. No per-boot scripting needed — ideal for an immutable AMI.
  Other tunables in this section: `max-concurrent-clients`, `permissions-file`, `storage-root`.

- **(b) Manual / scripted `dcv create-session`** (a systemd oneshot or `./run` command):
  - Console: `sudo dcv create-session --type console --owner ec2-user my-session`
  - Virtual: `dcv create-session my-session` (owned by the invoking user) or
    `sudo dcv create-session --owner ec2-user --user ec2-user my-session` (root impersonates the user).
  - **`--type` and `--user` are Linux-only.** `--user` (impersonation) requires root and is **virtual-only**.

> **Note:** "Amazon DCV doesn't support automatic virtual sessions." Auto-create via `dcv.conf` is
> **console-only**. A virtual session that survives reboots needs a oneshot/`create-session` script.

### 2. Auth is OS-user via PAM by default — already aligned with our secrets model

> "`system` — This is the default authentication method… For Linux… authentication is delegated to PAM.
> Clients provide their system credentials when connecting to a Amazon DCV session."
> — [Configuring Amazon DCV authentication](https://docs.aws.amazon.com/dcv/latest/adminguide/security-authentication.html)

- `[security] authentication = system` (the default) runs the PAM service `/etc/pam.d/dcv`.
- The DCV login prompt takes an **OS username + OS password**. For us that is `ec2-user` + the password the
  existing `secrets` role already sets and publishes to SSM SecureString.
- **This is the existing flow, unchanged.** `./run secrets-show` already prints the `ec2-user` password
  (currently labelled "RDP login" in `run` lines 458-470 — that label needs to change to "DCV login", but
  the underlying SSM parameter and PAM-validated-OS-password mechanic are identical to the xrdp design).
- PAM steps are customizable via `[authentication] pam-service = dcv-custom`; default `/etc/pam.d/dcv` is
  fine — no custom PAM stack required for table-stakes.

### 3. Session owner gets full access by default — no perms file authoring needed

> "The default permissions file grants only the session owner full access to all features… located in…
> `/etc/dcv/default.perm` on Linux."
> — [Configuring Amazon DCV authorization](https://docs.aws.amazon.com/dcv/latest/adminguide/security-authorization.html)

For a single operator whose OS user (`ec2-user`) is also the session `owner`, the stock `/etc/dcv/default.perm`
already grants that user everything. **No `--permissions-file` and no custom `default.perm` authoring is needed
for the baseline.** The owner is authorized to their own session out of the box. (Custom perms files only
matter for multi-user / collaboration, which is an anti-feature for us — see below.)

### 4. Connectivity: one port (8443), two transports — and only one survives SSM

| Transport | Protocol | Port | Used by | Traverses `AWS-StartPortForwardingSession`? |
|-----------|----------|------|---------|---------------------------------------------|
| WebSocket | **TCP** | 8443 | **Web browser client** (always) + native client fallback | **YES** — SSM port-forward is TCP |
| QUIC | **UDP** | 8443 | Native client only, opportunistically | **NO** — SSM forwarding is TCP-only |

> "since version 2024.0, Amazon DCV supports both the WebSocket protocol, which is based on TCP, and the QUIC
> protocol, which is based on UDP… With QUIC, the server continues to use WebSocket for authentication traffic."
> — [Disabling the QUIC UDP transport protocol](https://docs.aws.amazon.com/dcv/latest/adminguide/disable-quic.html)

**The SSM implication (the core connectivity decision for this milestone):**
- The operator surface we mirror — `cmd_devbox_port_forward` (`run` lines 379-435) — wraps
  `aws ssm start-session --document-name AWS-StartPortForwardingSession`, which forwards **TCP only**.
- The **web browser client** uses TCP/WebSocket, so it works perfectly through an SSM TCP tunnel:
  `./run devbox-port-forward 8443` → open `https://localhost:8443` in a browser. No client install.
- **QUIC (UDP 8443) cannot traverse the SSM tunnel.** A native viewer attempting QUIC over the forward will
  silently fall back to WebSocket (fine) — but QUIC buys nothing over SSM and the UDP listener is dead weight
  and extra attack surface. **Decision: disable QUIC** (`[connectivity] enable-quic-frontend = false`) for the
  SSM access path, and **do not** open UDP 8443 in the security group.
- If an operator ever wants QUIC's low-latency benefit, the only path is the **SG-open** route (direct
  `https://<host>:8443` from an allowlisted CIDR with both TCP+UDP 8443 open) — explicitly out of the
  table-stakes SSM-first posture.

### 5. TLS: self-signed cert auto-generated, lives in `/etc/dcv/`, owned by `dcv`

> "Amazon DCV automatically generates a self-signed certificate… `dcv.pem`… and a key (`dcv.key`)… Place the
> certificate and its key in… `/etc/dcv/`… Grant ownership of both files to the `dcv` user… chmod 600."
> — [Managing the TLS certificate](https://docs.aws.amazon.com/dcv/latest/adminguide/manage-cert.html)

- Self-signed `dcv.pem` + `dcv.key` are generated on install — **no cert work is table-stakes**.
- Browser will warn on the self-signed cert; over an SSM tunnel the operator is hitting `localhost:8443` and
  clicks through (the same posture noVNC/code-server self-signed certs already use in this repo).
- A real CA cert is a differentiator, not a requirement; if added, files must keep the exact names
  `dcv.pem` / `dcv.key`, live in `/etc/dcv/`, be `dcv`-owned and `600`. DCV ≥ 2022.0 hot-reloads cert changes.

---

## Feature Landscape

### Table Stakes (Required for a working single-operator DCV-over-SSM box)

Missing any of these and "open browser → see GNOME" does not work.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| A session that renders GNOME exists after boot | DCV creates **no** session by default on Linux; a listening server with no session is useless | MEDIUM | Prefer `[session-management] create-session=true` + `[automatic-console-session] owner=ec2-user` in `dcv.conf` (console, fixed ID `console`, survives restarts, no per-boot script). Console session = direct desktop capture, simplest for one operator. |
| GNOME desktop reachable by the session | A blank X session is not a workstation | MEDIUM | AL2023 needs the GNOME/Workstation group + DCV's GL/desktop deps. Console session captures the running desktop; a virtual session starts its own `Xdcv`. Either renders GNOME — console is the lower-config default. |
| PAM (`system`) auth via `ec2-user` + SSM password | Operator must log in; reuse the existing secrets flow | LOW | Default `authentication=system` → `/etc/pam.d/dcv`. `ec2-user` OS password (already SSM-published by `secrets` role) is the DCV login. No new auth component. |
| Session owner = `ec2-user` with default perms | Owner must be authorized to their own session | LOW | Stock `/etc/dcv/default.perm` grants owner full access. Set `owner=ec2-user` and nothing else needed. |
| `:8443/tcp` reachable | The single web/native port | LOW | DCV listens 8443 by default. Reach via SSM TCP forward (table-stakes) **and/or** SG TCP 8443 from `var.allowed_web_cidrs`. Drop xrdp `:3389`. |
| Web browser client (no install) over SSM TCP tunnel | Zero-install operator UX, matches code-server/noVNC pattern | LOW | Browser client = TCP/WebSocket, traverses `AWS-StartPortForwardingSession`. `./run devbox-port-forward 8443` → `https://localhost:8443`. Served by DCV's built-in web server; nothing extra to install or host. |
| Self-signed TLS on 8443 | Encrypted transport; auto-provided | LOW | `dcv.pem`/`dcv.key` auto-generated in `/etc/dcv/`. Click-through warning on `localhost` is acceptable (same as existing self-signed posture). |
| `./run` port-forward + secrets + docs wired for DCV | Operator surface parity with current box | LOW | Reuse `cmd_devbox_port_forward` (already generic, supports `8443`); relabel `secrets-show` "RDP login" → "DCV login (ec2-user @ :8443)"; update help text. |

### Differentiators (Valuable but NOT required; defer)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| QUIC (UDP 8443) transport | Lower latency / better on lossy links for the **native** client | MEDIUM | **Useless over SSM** (UDP can't traverse the TCP forward). Only meaningful on the SG-open direct path. Adds a UDP listener + SG UDP rule = attack surface. Default OFF for our posture. |
| GPU-accelerated OpenGL (`dcv-gl`) | Hardware GL for 3D/CAD/graphics workloads | HIGH | Needs a GPU instance + the licensed `dcv-gl` package + `dcv-gl.conf` wiring. Our box is a code/dev workstation, not a graphics box. Defer. |
| File upload/download via the session | Move files through the desktop channel | LOW–MEDIUM | A `dcv.perms` feature; the owner already has it by default. We already have SSM/`scp`-over-SSM/code-server for file movement — not a driver. Leave at default, don't build tooling around it. |
| Multi-monitor / 4K | Native client supports up to 4 monitors / 4096×2160 | LOW | Web client caps at 2 screens @ 1920×1080. Single operator over a browser is fine at table-stakes resolution; multi-monitor needs the native client (and ideally non-SSM path). Defer. |
| Custom CA TLS cert | Removes the browser trust warning | MEDIUM | Over `localhost`-tunneled SSM the warning is low-friction. Drop-in: name files `dcv.pem`/`dcv.key`, `/etc/dcv/`, `dcv`-owned, `600`; hot-reloads ≥2022.0. Nice-to-have only. |
| Native DCV viewer (Win/Linux/mac) | USB redirect, smart cards, multi-channel audio, stylus/touch | MEDIUM | Requires a per-OS client install (breaks the zero-install promise) and most premium features assume the non-SSM/QUIC path. Web client covers the operator need. Defer. |
| Virtual session instead of console | Multiple concurrent sessions; per-user `Xdcv` | MEDIUM | We are single-operator/single-session — console is simpler and auto-creatable. Virtual only earns its keep with concurrency or GPU-sharing, neither in scope. |

### Anti-Features (Do NOT enable)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| `authentication = none` | "Skip the login, it's just me behind SSM" | Removes the OS-credential gate; anyone who reaches 8443 (e.g. an over-wide SG, or a future second user) is in with no auth. Violates secure-by-default. | Keep `authentication = system` (PAM/`ec2-user`). SSM + PAM are layered, not either/or. |
| QUIC enabled + UDP 8443 in the SG | "Better performance" | No benefit over the SSM TCP path (UDP can't tunnel); opening UDP 8443 widens attack surface for zero operator gain; QUIC auth still rides WebSocket anyway. | `enable-quic-frontend = false`; SG opens **TCP 8443 only**, gated on `var.allowed_web_cidrs`. |
| Multi-user collaboration / session sharing | "Pair programming, share my screen" | Pulls in custom `dcv.perms`, multiple owners, shared-resource caveats (D-Bus/home dir warnings for same-user virtual sessions); contradicts the one-operator-one-box design in PROJECT.md ("Out of Scope: Multi-tenant"). | Single owner = `ec2-user`, default perms. If sharing is ever needed, that's a separate milestone. |
| Public `:8443` ingress (`0.0.0.0/0`) | "Just reach it from anywhere" | Exposes a self-signed-TLS desktop login to the internet; breaks the no-public-ingress / SSM-first posture the project is built on. | SSM TCP forward (primary) or CIDR-allowlisted SG via `var.allowed_web_cidrs` (existing pattern). |
| DCV Session Manager / Connection Gateway / Access Console | "Proper enterprise session brokering" | Heavyweight broker/gateway services for fleets; massive over-build for one box and one session; more components to harden and license. | A single auto-created console session + `./run devbox-port-forward 8443`. |
| Custom PAM stack (`pam-service = dcv-custom`) | "Tighten the login" | Extra config + a CIS-hardening interaction surface for no benefit; default `/etc/pam.d/dcv` already validates the OS user. | Leave default `/etc/pam.d/dcv`. Revisit only if a concrete PAM requirement appears. |
| Leftover xrdp/VNC/noVNC alongside DCV | "Keep them as fallback" | Dead remote-desktop config = extra open services + the `:3389`/`:6080` attack surface PROJECT.md v4.0 explicitly says to remove ("no dead remote-desktop config in the image"). | Full removal of xrdp/xorgxrdp + VNC/noVNC remnants; DCV is the sole remote desktop. |

---

## Feature Dependencies

```
GNOME desktop group installed (AL2023)
        └──required by──> A renderable DCV session
                              └──auto-created by──> dcv.conf [session-management] create-session=true
                                                        + [automatic-console-session] owner=ec2-user
                                                    (console session; virtual cannot auto-create)

PAM auth (authentication=system, /etc/pam.d/dcv)
        └──validates──> ec2-user OS password  ──set & published by──> existing `secrets` role → SSM SecureString
                                                                          └──surfaced by──> `./run secrets-show`

Session owner = ec2-user
        └──authorized by──> /etc/dcv/default.perm (owner gets full access by default)

8443/tcp listener (DCV web server, WebSocket)
        └──reached by──> `./run devbox-port-forward 8443` (AWS-StartPortForwardingSession, TCP)
                             └──then──> browser https://localhost:8443  (zero-install web client)
        └──also reachable by──> SG TCP 8443 gated on var.allowed_web_cidrs (direct, optional)

self-signed dcv.pem/dcv.key in /etc/dcv/ (auto-generated, dcv-owned 600)
        └──secures──> 8443 (TLS)

QUIC (UDP 8443) ──conflicts──> SSM TCP port-forward (UDP cannot tunnel)  → disable QUIC
dcv-gl (GPU OpenGL) ──requires──> GPU instance + licensed dcv-gl pkg     → out of scope
```

### Dependency Notes

- **Renderable session requires the GNOME group AND explicit session creation:** install order is desktop
  group → DCV → `dcv.conf` session config. A server with no session is the default failure mode on Linux.
- **PAM auth reuses the existing secrets pipeline verbatim:** the only code change is the `secrets-show`
  label and docs; the SSM parameter and the OS-password mechanic are unchanged from the xrdp design.
- **Console auto-create vs virtual:** auto-creation via `dcv.conf` is **console-only**. Choosing console for
  the single operator removes the need for any per-boot session script.
- **QUIC conflicts with the SSM path:** UDP cannot traverse `AWS-StartPortForwardingSession`; disabling QUIC
  also keeps UDP 8443 out of the SG. The two are mutually exclusive for our access model.
- **dcv-gl conflicts with our instance shape:** requires a GPU instance and licensed package — out of scope.

---

## MVP Definition

### Launch With (v4.0 table-stakes)

The minimal "open a browser, log in as ec2-user, see GNOME" path.

- [ ] **GNOME desktop installed on AL2023** — nothing to render without it.
- [ ] **`dcvserver` installed + service enabled** — the listener (install/license path tracked separately).
- [ ] **Auto-console-session configured** (`dcv.conf` `create-session=true` + `automatic-console-session owner=ec2-user`) — DCV creates no session by default; this is the #1 gap.
- [ ] **`authentication=system` (default) + ec2-user PAM password from SSM** — reuse existing `secrets` flow.
- [ ] **Owner=ec2-user with stock `/etc/dcv/default.perm`** — owner authorized to own session, no perms authoring.
- [ ] **QUIC disabled** (`enable-quic-frontend=false`) — UDP can't tunnel over SSM; keep UDP 8443 off.
- [ ] **SG TCP 8443 gated on `var.allowed_web_cidrs`; drop `:3389`** — TCP-only; SSM-first preserved.
- [ ] **`./run devbox-port-forward 8443` documented + `secrets-show` relabeled "DCV login"** — operator surface.
- [ ] **Self-signed TLS left as-is** — auto-generated `dcv.pem`/`dcv.key`, click-through on localhost.
- [ ] **xrdp/xorgxrdp + VNC/noVNC fully removed** — no dead remote-desktop config (PROJECT.md v4.0).

### Add After Validation (v4.x)

- [ ] **Custom CA TLS cert** — trigger: operator tired of the browser trust warning (drop-in `dcv.pem`/`dcv.key`).
- [ ] **SG-open direct `:8443` access for an allowlisted CIDR** — trigger: SSM port-forward latency becomes painful.

### Future Consideration (v5+ / probably never for this box)

- [ ] **QUIC + UDP 8443** — only if the SG-open direct path is adopted and latency matters; never for SSM.
- [ ] **Native viewer + premium features** (USB, multi-monitor 4K, smart cards) — trigger: a concrete need the browser client can't meet; breaks zero-install.
- [ ] **`dcv-gl` GPU OpenGL** — only if the box becomes a graphics/CAD workstation on a GPU instance.
- [ ] **Session Manager / Connection Gateway / collaboration** — only if this stops being one-operator-one-box (explicitly Out of Scope in PROJECT.md).

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Auto-created console session rendering GNOME | HIGH | MEDIUM | P1 |
| PAM (`system`) auth via ec2-user + SSM password | HIGH | LOW | P1 |
| Owner=ec2-user + default perms | HIGH | LOW | P1 |
| 8443/tcp over SSM + web browser client | HIGH | LOW | P1 |
| SG TCP 8443 gated on allowed_web_cidrs; drop :3389 | HIGH | LOW | P1 |
| QUIC disabled / no UDP 8443 | HIGH (security) | LOW | P1 |
| `./run` port-forward + secrets-show relabel + docs | HIGH | LOW | P1 |
| Self-signed TLS (default) | MEDIUM | LOW (free) | P1 |
| Full xrdp/VNC removal | HIGH | MEDIUM | P1 |
| Custom CA TLS cert | LOW | MEDIUM | P3 |
| SG-open direct :8443 path | LOW | LOW | P3 |
| QUIC + UDP 8443 | LOW | MEDIUM | P3 |
| dcv-gl GPU OpenGL | LOW | HIGH | P3 |
| Native viewer / multi-monitor / file-transfer tooling | LOW | MEDIUM | P3 |
| Collaboration / Session Manager / Gateway | LOW | HIGH | P3 |

## Competitor Feature Analysis (the remote-desktop options this project has tried)

| Feature | xrdp/xorgxrdp (v3.2, superseded) | noVNC/VNC (v1–v3) | Amazon DCV (v4.0, our approach) |
|---------|----------------------------------|-------------------|---------------------------------|
| Zero-install client | RDP client per-OS (mstsc etc.) | Browser (noVNC web) | **Browser web client, no install** |
| Auth | PAM via ec2-user (xrdp PAM) | VNC password (cleartext, loopback-only) | **PAM via ec2-user (system) — reuses SSM secret** |
| Port over SSM | 3389/tcp forwarded | 6080/tcp forwarded | **8443/tcp forwarded (web client)** |
| TLS | xrdp TLS (X509) hand-configured | noVNC `--ssl-only` self-signed | **Self-signed auto-generated; CA cert drop-in** |
| Session model | X11/Xorg backend session per login | single VNC display | **Auto-console-session (must be configured — not default)** |
| Build complexity | from-source xrdp+xorgxrdp (heavy) | moderate | install + license (S3 path) + small `dcv.conf` |
| Our verdict | retired | retired | **adopted** — re-validated working live |

## Sources

All HIGH-confidence, from the official Amazon DCV Administrator Guide (docs.aws.amazon.com):

- [Starting Amazon DCV sessions](https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-start.html) — no default session on Linux; `dcv create-session` syntax; `[session-management] create-session` + `[session-management/automatic-console-session] owner` auto-console config; no automatic virtual sessions
- [Understanding Amazon DCV sessions](https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-intro.html) — console vs virtual table (one console per server, admin/root-created, direct capture; virtual Linux-only, per-session `Xdcv`, user-created, dcv-gl for GL)
- [Configuring Amazon DCV authentication](https://docs.aws.amazon.com/dcv/latest/adminguide/security-authentication.html) — `[security] authentication` = `system` (default) / `none`; PAM `/etc/pam.d/dcv`; `pam-service`
- [Configuring Amazon DCV authorization](https://docs.aws.amazon.com/dcv/latest/adminguide/security-authorization.html) — default `/etc/dcv/default.perm` grants the owner full access
- [Disabling the QUIC UDP transport protocol](https://docs.aws.amazon.com/dcv/latest/adminguide/disable-quic.html) — WebSocket=TCP, QUIC=UDP, both on 8443; `[connectivity] enable-quic-frontend=false`; QUIC auth still over WebSocket
- [Managing the TLS certificate](https://docs.aws.amazon.com/dcv/latest/adminguide/manage-cert.html) — auto-generated self-signed `dcv.pem`/`dcv.key` in `/etc/dcv/`, `dcv`-owned, `600`; CA-cert drop-in keeps same names; hot-reload ≥2022.0
- [Web browser client](https://docs.aws.amazon.com/dcv/latest/userguide/client-web.html) / [Amazon DCV (HPC)](https://aws.amazon.com/hpc/dcv/) — HTML5 web client, no install, `https://<host>:8443`; web client capped 2 screens @1920×1080, native up to 4 @4096×2160
- [Changing the Amazon DCV Server TCP/UDP ports and listen address](https://docs.aws.amazon.com/dcv/latest/adminguide/manage-port-addr.html) — 8443 default for both TCP and UDP

Repo cross-references (read directly):
- `.planning/PROJECT.md` — v4.0 milestone goal, SSM-first / no-public-:22 posture, "remove xrdp/VNC entirely", Out of Scope: multi-tenant
- `run` lines 379-435 (`cmd_devbox_port_forward`, `AWS-StartPortForwardingSession` = TCP-only) and 441-473 (`cmd_secrets_show`, the ec2-user password label to update)

---
*Feature research for: Amazon DCV remote desktop (single-operator, SSM-tunneled, GNOME-on-AL2023)*
*Researched: 2026-06-18*
