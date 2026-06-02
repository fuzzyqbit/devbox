# Devbox — Developer Lifecycle Guide

Short version for developers who just want a VM. Spin it up, turn it on/off,
connect, tear it down. You do **not** need to read `.planning/` or the rest of
`CLAUDE.md` for this.

Every command is `make <target>`. Set `DEVBOX_USER` once per shell (defaults to
your local username):

```bash
export DEVBOX_USER=$(whoami)
export AWS_REGION=us-east-1   # your region
```

> One operator → one instance → one state file, keyed by `DEVBOX_USER`.

---

## 0. Prerequisites (once per laptop)

```bash
# macOS
brew install awscli packer opentofu jq
brew install --cask session-manager-plugin
```

You also need working AWS credentials (`aws sts get-caller-identity` must
succeed). SSH keypair setup is only needed if you want key-based access — SSM
(below) does not require it.

---

## 1. Create the VM (first time)

Three steps the first time, or after switching `DEVBOX_USER`:

```bash
make build       # bake the AMI with Packer (slow; needed once / when image changes)
make tf-init     # point Terraform at your per-operator state key
make tf-apply    # provision the EC2 instance (prompts for confirmation)
```

After this the instance exists. It may be running or stopped depending on the
module default — check with `make status`.

`make tf-apply` is idempotent: re-run it any time to pick up a new AMI or config
change. Skip `make build`/`make tf-init` on later runs unless the image changed
or you switched users.

---

## 2. Turn it on / off (daily)

```bash
make start     # power on the instance
make stop      # power off (stops compute billing; disk persists)
make status    # state + connection info
```

Stop it when you're done for the day — a stopped instance costs only EBS
storage, not compute.

---

## 3. Connect

No public SSH port (`:22`) is open. Access is over **AWS SSM Session Manager**.

### Shell

```bash
make devbox-ssm
# equivalently:
# aws ssm start-session --target <instance-id> --region <region>
```

### Browser IDE (code-server on :8080)

- **On the VPC** (VPN / peering / Direct Connect): browse straight to
  `https://<private-ip>:8080`. Your IP must be inside `var.allowed_web_cidrs`.
- **Off the VPC**: tunnel it over SSM:

  ```bash
  make devbox-port-forward      # forwards :8080 → localhost:8080
  # then open https://localhost:8080
  ```

  noVNC (`:6080`) is not auto-forwarded — open a second port-forward session
  manually with `portNumber=6080` if you need the desktop.

### Passwords

code-server and noVNC each have a per-operator password stored in SSM Parameter
Store (SecureString):

```bash
make secrets-show
```

If it reports "parameter not found", you haven't run `make build` yet for this
`DEVBOX_USER`.

---

## 4. Destroy the VM

```bash
make tf-destroy        # tears down the instance (prompts for confirmation)
```

This removes the EC2 instance and its resources. The AMI and your S3 state
remain. To also wipe local Packer/Terraform caches:

```bash
make clean
```

---

## Cheat sheet

| Want to…                  | Command                   |
|---------------------------|---------------------------|
| Bake the image            | `make build`              |
| Provision / update VM     | `make tf-apply`           |
| Power on                  | `make start`              |
| Power off                 | `make stop`               |
| See state + how to connect| `make status`             |
| Shell in                  | `make devbox-ssm`         |
| Browser IDE off-VPC       | `make devbox-port-forward`|
| Get passwords             | `make secrets-show`       |
| Tear down                 | `make tf-destroy`         |

Override target instance without state lookup:
`make status INSTANCE_ID=i-0abc123 REGION=us-east-1`.

Run `make help` for the full target list. Deeper architecture and rationale
live in `CLAUDE.md` and `.planning/`.
