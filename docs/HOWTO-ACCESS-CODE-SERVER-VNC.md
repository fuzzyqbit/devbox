# How To: Access code-server and VNC

This guide covers connecting to the two browser-facing services on your devbox:

- **code-server** — VS Code in the browser, on port `:8080`
- **noVNC** — the graphical desktop in the browser, on port `:6080`

Both ports are HTTPS and are restricted to the CIDR ranges in
`var.allowed_web_cidrs` (Terraform default `["10.0.0.0/8"]`). They are **never**
exposed to the public internet. There are two ways to reach them:

- **On the VPC** (VPN / peering / Direct Connect, source IP inside the
  allowlist): browse directly to the instance.
- **Off the VPC**: tunnel the port to your workstation over AWS SSM Session
  Manager. No public `:22` or `:8080`/`:6080` ingress is opened.

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

---

## Step 1 — Get your passwords

code-server and noVNC each have a per-operator password, stored as an SSM
Parameter Store SecureString and rotated on every `./run build`:

```bash
./run secrets-show
```

Output:

```
code-server (https://<host>:8080) password:  <code-server-password>
VNC / noVNC  (https://<host>:6080) password:  <vnc-password>
```

> If it reports **"parameter not found"**, the AMI hasn't been baked yet for
> this `DEVBOX_USER`. Run `./run build`, then retry.

Keep these handy — you'll enter them on the login page after connecting.

---

## Step 2 — Connect

Pick the path that matches your network position.

### Option A — On the VPC (direct browse)

Your source IP is inside `var.allowed_web_cidrs`. Point your browser straight at
the instance's private IP (from `./run status`):

```
https://<private-ip>:8080     # code-server
https://<private-ip>:6080     # noVNC desktop
```

The TLS cert is self-signed — accept the browser warning. Log in with the
matching password from Step 1.

### Option B — Off the VPC (SSM port-forward)

Tunnel each port to `localhost` over SSM. **One port per session** — open a
separate terminal for each service you want.

**code-server (`:8080`)** — there's a built-in helper:

```bash
./run devbox-port-forward          # forwards :8080 → localhost:8080
# then browse to https://localhost:8080
```

**noVNC (`:6080`)** — not auto-forwarded; open it manually. Get the instance ID
and region from `./run status` (or `tofu output -raw instance_id` /
`-raw aws_region` in `terraform/`):

```bash
aws ssm start-session \
  --target <instance-id> \
  --region <region> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'
# then browse to https://localhost:6080
```

Leave the session running while you work; press `Ctrl-C` to stop forwarding.

> Want both at once? Run `./run devbox-port-forward` in one terminal and the
> `:6080` command above in a second terminal.

---

## Step 3 — Log in

In the browser, accept the self-signed-cert warning, then enter the password
from Step 1:

- code-server → its login page → **code-server password**
- noVNC → its connect/login prompt → **VNC password**

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `secrets-show` → "parameter not found" | AMI not baked for this `DEVBOX_USER`. Run `./run build`. |
| `session-manager-plugin: command not found` | Install it (see Prerequisites). Required for off-VPC tunneling. |
| Browser can't reach `https://<private-ip>:8080` | You're off the allowlisted CIDR. Use Option B (SSM port-forward), or add your IP to `var.allowed_web_cidrs` and `./run tf-apply`. |
| `localhost:8080` refused after port-forward | The SSM session isn't up, or the instance is stopped. Check `./run status`; re-run `./run start`. |
| Connection hangs / instance not found | Instance is stopped or doesn't exist. `./run status`, then `./run start` (or `./run tf-apply`). |
| Login page rejects the password | You may be on a stale password after a rebake — re-run `./run secrets-show` (passwords rotate on every `./run build`). |

---

## Quick reference

| Want to…                       | Command                                          |
|--------------------------------|--------------------------------------------------|
| Show passwords                 | `./run secrets-show`                             |
| Power on / check state         | `./run start` · `./run status`                   |
| Forward code-server `:8080`    | `./run devbox-port-forward`                      |
| Forward noVNC `:6080`          | `aws ssm start-session … portNumber 6080` (above)|
| code-server (on VPC)           | `https://<private-ip>:8080`                      |
| noVNC desktop (on VPC)         | `https://<private-ip>:6080`                      |

For the full VM lifecycle (build, provision, on/off, destroy) see
[DEVELOPER-LIFECYCLE.md](DEVELOPER-LIFECYCLE.md). Architecture and rationale live
in `CLAUDE.md` and `.planning/`.
