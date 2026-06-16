# Devbox — Developer Lifecycle Guide

Short version for developers who just want a VM. Spin it up, turn it on/off,
connect, tear it down. You do **not** need to read `.planning/` or the rest of
`CLAUDE.md` for this.

Every command is `./run <command>`. Set `DEVBOX_USER` once per shell (defaults to
your local username) and the commands below pick it up:

```bash
export DEVBOX_USER=$(whoami)
export AWS_REGION=us-east-1   # your region
```

> One operator → one instance → one state file, keyed by `DEVBOX_USER`.
> `./run` needs bash 4+ (macOS: `brew install bash`).

---

## 0. Prerequisites (once per laptop)

```bash
# macOS
brew install bash awscli packer opentofu jq
brew install --cask session-manager-plugin
```

You also need working AWS credentials (`aws sts get-caller-identity` must
succeed). SSH keypair setup is only needed if you want key-based access — SSM
(below) does not require it.

Run `./run doctor` anytime to check your local toolchain in one pass.

---

## 1. Create the VM (first time)

Three steps the first time, or after switching `DEVBOX_USER`:

```bash
./run build       # bake the AMI with Packer (slow; needed once / when image changes)
./run tf-init     # point Terraform at your per-operator state key
./run tf-apply    # provision the EC2 instance (prompts for confirmation)
```

After this the instance exists. It may be running or stopped depending on the
module default — check with `./run status`.

`./run tf-apply` is idempotent: re-run it any time to pick up a new AMI or config
change. Skip `./run build`/`./run tf-init` on later runs unless the image changed
or you switched users.

---

## 2. Turn it on / off (daily)

```bash
./run start     # power on the instance
./run stop      # power off (stops compute billing; disk persists)
./run status    # state + connection info
```

Stop it when you're done for the day — a stopped instance costs only EBS
storage, not compute.

---

## 3. Connect

No public SSH port (`:22`) is open. Access is over **AWS SSM Session Manager**.

### Shell

```bash
./run devbox-ssm
# equivalently:
# aws ssm start-session --target <instance-id> --region <region>
```

### Browser IDE (code-server on :8080)

- **On the VPC** (VPN / peering / Direct Connect): browse straight to
  `https://<private-ip>:8080`. Your IP must be inside `var.allowed_web_cidrs`.
- **Off the VPC**: tunnel it over SSM:

  ```bash
  ./run devbox-port-forward      # forwards :8080 → localhost:8080
  # then open https://localhost:8080
  ```

### Graphical desktop (RDP on :3389)

The GNOME desktop is served over RDP on `:3389`. Connect with a native RDP
client (Microsoft Remote Desktop / `mstsc`, FreeRDP, Remmina) — log in as
`ec2-user` with the desktop password from `./run secrets-show`.

- **On the VPC**: point your RDP client at `<private-ip>:3389`. Your IP must be
  inside `var.allowed_web_cidrs`.
- **Off the VPC**: tunnel it over SSM, then connect the client to localhost:

  ```bash
  ./run devbox-port-forward 3389   # forwards :3389 → localhost:3389
  # then point your RDP client at localhost:3389
  ```

### JupyterLab (on demand, loopback-only)

JupyterLab is not a systemd service — it starts on demand and binds to
`127.0.0.1:8888` only, never to a public interface. There is **no Jupyter
password**; the loopback binding plus SSM/IAM is the auth boundary (the token
in the printed URL is sufficient).

Access flow:

1. **Start JupyterLab** — run this in a shell session on the devbox (via `./run
   devbox-ssm` or any SSM interactive session) and leave it running. Note the
   `http://127.0.0.1:8888/lab?token=...` URL it prints.

   ```bash
   ./run jupyter
   ```

2. **Forward `:8888` over SSM** — in a **second terminal** on your workstation,
   open an SSM port-forward session:

   ```bash
   aws ssm start-session --target <instance-id> --region <region> \
     --document-name AWS-StartPortForwardingSession \
     --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'
   ```

   (`./run devbox-port-forward` forwards only `:8080` for code-server; the
   `:8888` forward is run manually, the same SSM pattern as the RDP `:3389`
   forward above — or use `./run devbox-port-forward 8888`.)

3. **Open the token URL** in your browser:

   ```
   http://127.0.0.1:8888/lab?token=<token>
   ```

Press `Ctrl-C` in the first shell to stop JupyterLab when you are done.

### Passwords

code-server and the RDP desktop each have a per-operator password stored in SSM
Parameter Store (SecureString). The RDP desktop logs in as `ec2-user` with the
desktop password:

```bash
./run secrets-show
```

If it reports "parameter not found", you haven't run `./run build` yet for this
`DEVBOX_USER`.

---

## 4. Destroy the VM

```bash
./run tf-destroy        # tears down the instance (prompts for confirmation)
```

This removes the EC2 instance and its resources. The AMI and your S3 state
remain. To also wipe local Packer/Terraform caches:

```bash
./run clean
```

---

## Cheat sheet

| Want to…                  | Command                    |
|---------------------------|----------------------------|
| Check local toolchain     | `./run doctor`             |
| Bake the image            | `./run build`              |
| Provision / update VM     | `./run tf-apply`           |
| Power on                  | `./run start`              |
| Power off                 | `./run stop`               |
| See state + how to connect| `./run status`             |
| Shell in                  | `./run devbox-ssm`         |
| Browser IDE off-VPC       | `./run devbox-port-forward`|
| RDP desktop off-VPC       | `./run devbox-port-forward 3389` |
| Get passwords             | `./run secrets-show`       |
| JupyterLab (on demand)    | `./run jupyter`            |
| Tear down                 | `./run tf-destroy`         |

Override target instance without state lookup:
`INSTANCE_ID=i-0abc123 REGION=us-east-1 ./run status`.

Run `./run help` for the full command list. Deeper architecture and rationale
live in `CLAUDE.md` and `.planning/`.
