# How To: Access code-server and the Amazon DCV desktop

This guide covers connecting to the two operator-facing services on your devbox:

- **code-server** — VS Code in the browser, on port `:8080` (HTTPS)
- **Amazon DCV desktop** — the GNOME graphical desktop over Amazon DCV, on port
  `:8443` (TLS), reached with the DCV browser web client or a native DCV client

Both ports are restricted to the CIDR ranges in `var.allowed_web_cidrs`
(Terraform default `["10.0.0.0/8"]`). They are **never** exposed to the public
internet.

- **code-server** can be reached either directly on the VPC (source IP inside the
  allowlist) or, off the VPC, by tunneling `:8080` over AWS SSM Session Manager.
- **Amazon DCV** is **direct connect** (TCP + UDP/QUIC) within the allowed CIDR
  — there is **no SSM port-forward** for the desktop. Your source IP must be in
  `var.allowed_web_cidrs`.

No public `:22`, `:8080`, or `:8443` ingress is opened.

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

3. For off-VPC code-server access (SSM tunneling), `session-manager-plugin` is
   installed:

   ```bash
   # macOS
   brew install --cask session-manager-plugin
   # Linux: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
   ```

4. A DCV client (optional): the DCV browser web client needs only a browser; for
   the native client install the Amazon DCV Client (macOS / Windows / Linux from
   the AWS DCV downloads page).

---

## Step 1 — Get your passwords

code-server and the Amazon DCV desktop each have a per-operator password, stored
as an SSM Parameter Store SecureString and rotated on every `./run build`:

```bash
./run secrets-show
```

This prints the code-server password and the DCV/desktop password. The DCV
desktop logs you in as the OS user **`ec2-user`** with the desktop password
shown here (it is the PAM password DCV's `authentication=system` authenticates
against).

> If it reports **"parameter not found"**, the AMI hasn't been baked yet for
> this `DEVBOX_USER`. Run `./run build`, then retry.

Keep these handy — you'll enter the code-server password on its login page, and
the desktop password in your DCV client (or the browser login).

---

## Step 2 — Connect

### code-server (`:8080`)

Pick the path that matches your network position.

**On the VPC (direct)** — your source IP is inside `var.allowed_web_cidrs`. Use
the instance's private IP (from `./run status`):

```
https://<private-ip>:8080      # code-server (browser)
```

The TLS cert is self-signed — accept the browser warning, then log in with the
code-server password from Step 1.

**Off the VPC (SSM port-forward)** — tunnel `:8080` to `localhost` over SSM:

```bash
./run devbox-port-forward          # forwards :8080 → localhost:8080
# then browse to https://localhost:8080
```

Leave the session running while you work; press `Ctrl-C` to stop forwarding.

### Amazon DCV desktop (`:8443`) — direct connect

DCV is **direct connect in-CIDR** (TCP + UDP/QUIC); there is **no port-forward
step**. Your source IP must be inside `var.allowed_web_cidrs`. Use the
instance's private IP (from `./run status`):

```
https://<private-ip>:8443      # Amazon DCV desktop (browser or native DCV client)
```

Open `https://<private-ip>:8443` in a browser for the DCV web client, or point a
native DCV client at the same host. Accept the self-signed-cert warning, then log
in as **`ec2-user`** with the desktop password from Step 1.

---

## Step 3 — Log in

- **code-server** → its browser login page → **code-server password** (accept
  the self-signed-cert warning first).
- **Amazon DCV desktop** → DCV web client (browser) or native DCV client →
  username **`ec2-user`**, password = the desktop password from
  `./run secrets-show`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `secrets-show` → "parameter not found" | AMI not baked for this `DEVBOX_USER`. Run `./run build`. |
| `session-manager-plugin: command not found` | Install it (see Prerequisites). Required for off-VPC code-server tunneling. |
| Browser can't reach `https://<private-ip>:8080` | You're off the allowlisted CIDR. Use the SSM port-forward, or add your IP to `var.allowed_web_cidrs` and `./run tf-apply`. |
| DCV client can't reach `https://<private-ip>:8443` | Confirm your source IP is in `var.allowed_web_cidrs` and the `:8443` TCP **and** UDP ingress is applied (`./run tf-apply`). DCV is direct connect — there is no SSM tunnel for it; browse `https://<private-ip>:8443` or use a native DCV client from inside the CIDR. |
| `localhost:8080` refused after port-forward | The SSM session isn't up, or the instance is stopped. Check `./run status`; re-run `./run start`. |
| Connection hangs / instance not found | Instance is stopped or doesn't exist. `./run status`, then `./run start` (or `./run tf-apply`). |
| Login rejects the password | You may be on a stale password after a rebake — re-run `./run secrets-show` (passwords rotate on every `./run build`). |

---

## Quick reference

| Want to…                       | Command                                          |
|--------------------------------|--------------------------------------------------|
| Show passwords                 | `./run secrets-show`                             |
| Power on / check state         | `./run start` · `./run status`                   |
| Forward code-server `:8080`    | `./run devbox-port-forward`                      |
| code-server (on VPC)           | `https://<private-ip>:8080`                      |
| DCV desktop (in-CIDR)          | `https://<private-ip>:8443` (DCV client / browser, user `ec2-user`) |

For the full VM lifecycle (build, provision, on/off, destroy) see
[DEVELOPER-LIFECYCLE.md](DEVELOPER-LIFECYCLE.md). Architecture and rationale live
in `CLAUDE.md` and `.planning/`.
