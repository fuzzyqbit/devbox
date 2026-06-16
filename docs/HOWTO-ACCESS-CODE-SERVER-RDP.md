# How To: Access code-server and the RDP desktop

This guide covers connecting to the two operator-facing services on your devbox:

- **code-server** — VS Code in the browser, on port `:8080` (HTTPS)
- **RDP desktop** — the GNOME graphical desktop over RDP, on port `:3389`,
  reached with a native RDP client (Microsoft Remote Desktop / mstsc, FreeRDP,
  Remmina)

Both ports are restricted to the CIDR ranges in `var.allowed_web_cidrs`
(Terraform default `["10.0.0.0/8"]`). They are **never** exposed to the public
internet. There are two ways to reach them:

- **On the VPC** (VPN / peering / Direct Connect, source IP inside the
  allowlist): connect directly to the instance.
- **Off the VPC**: tunnel the port to your workstation over AWS SSM Session
  Manager. No public `:22`, `:8080`, or `:3389` ingress is opened.

> Every command below is `./run <command>`. Set `DEVBOX_USER` once per shell
> (defaults to your local username); it keys your instance, state, and secrets.
>
> ```bash
> export DEVBOX_USER=$(whoami)
> export AWS_REGION=us-east-1   # your region
> ```

---

## Prerequisites

1. The instance is built and provisioned (`./run build`, `./run tf-init`,
   `./run tf-apply` — see [DEVELOPER-LIFECYCLE.md](DEVELOPER-LIFECYCLE.md)).
2. The instance is **running**:

   ```bash
   ./run start
   ./run status      # confirm state + connection info
   ```

3. For off-VPC access (SSM tunneling), `session-manager-plugin` is installed:

   ```bash
   # macOS
   brew install --cask session-manager-plugin
   # Linux: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
   ```

4. For the RDP desktop, a native RDP client:

   - **macOS** — Microsoft Remote Desktop (App Store)
   - **Windows** — Remote Desktop Connection (`mstsc`, built in)
   - **Linux** — Remmina or FreeRDP (`xfreerdp`)

---

## Step 1 — Get your passwords

code-server and the RDP desktop each have a per-operator password, stored as an
SSM Parameter Store SecureString and rotated on every `./run build`:

```bash
./run secrets-show
```

This prints the code-server password and the RDP/desktop password. The RDP
desktop logs you in as the OS user **`ec2-user`** with the desktop password
shown here (it is the PAM password for the GNOME session).

> If it reports **"parameter not found"**, the AMI hasn't been baked yet for
> this `DEVBOX_USER`. Run `./run build`, then retry.

Keep these handy — you'll enter the code-server password on its login page, and
the desktop password in your RDP client.

---

## Step 2 — Connect

Pick the path that matches your network position.

### Option A — On the VPC (direct)

Your source IP is inside `var.allowed_web_cidrs`. Use the instance's private IP
(from `./run status`):

```
https://<private-ip>:8080      # code-server (browser)
<private-ip>:3389              # RDP desktop (native RDP client)
```

For code-server the TLS cert is self-signed — accept the browser warning, then
log in with the code-server password from Step 1. For the desktop, point your
RDP client at `<private-ip>:3389` and log in as `ec2-user` with the desktop
password from Step 1.

### Option B — Off the VPC (SSM port-forward)

Tunnel each port to `localhost` over SSM. **One port per session** — open a
separate terminal for each service you want.

**code-server (`:8080`)**:

```bash
./run devbox-port-forward          # forwards :8080 → localhost:8080
# then browse to https://localhost:8080
```

**RDP desktop (`:3389`)**:

```bash
./run devbox-port-forward 3389     # forwards :3389 → localhost:3389
# then point your RDP client at localhost:3389
```

Leave the session running while you work; press `Ctrl-C` to stop forwarding.

> Want both at once? Run `./run devbox-port-forward` in one terminal and
> `./run devbox-port-forward 3389` in a second terminal.

---

## Step 3 — Log in

- **code-server** → its browser login page → **code-server password** (accept
  the self-signed-cert warning first).
- **RDP desktop** → your RDP client → username **`ec2-user`**, password = the
  desktop password from `./run secrets-show`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `secrets-show` → "parameter not found" | AMI not baked for this `DEVBOX_USER`. Run `./run build`. |
| `session-manager-plugin: command not found` | Install it (see Prerequisites). Required for off-VPC tunneling. |
| Browser can't reach `https://<private-ip>:8080`, or RDP can't reach `<private-ip>:3389` | You're off the allowlisted CIDR. Use Option B (SSM port-forward), or add your IP to `var.allowed_web_cidrs` and `./run tf-apply`. |
| `localhost:8080` / `localhost:3389` refused after port-forward | The SSM session isn't up, or the instance is stopped. Check `./run status`; re-run `./run start`. |
| Connection hangs / instance not found | Instance is stopped or doesn't exist. `./run status`, then `./run start` (or `./run tf-apply`). |
| Login rejects the password | You may be on a stale password after a rebake — re-run `./run secrets-show` (passwords rotate on every `./run build`). |

---

## Quick reference

| Want to…                       | Command                                          |
|--------------------------------|--------------------------------------------------|
| Show passwords                 | `./run secrets-show`                             |
| Power on / check state         | `./run start` · `./run status`                   |
| Forward code-server `:8080`    | `./run devbox-port-forward`                      |
| Forward RDP `:3389`            | `./run devbox-port-forward 3389`                 |
| code-server (on VPC)           | `https://<private-ip>:8080`                      |
| RDP desktop (on VPC)           | `<private-ip>:3389` (RDP client, user `ec2-user`)|

For the full VM lifecycle (build, provision, on/off, destroy) see
[DEVELOPER-LIFECYCLE.md](DEVELOPER-LIFECYCLE.md). Architecture and rationale live
in `CLAUDE.md` and `.planning/`.
