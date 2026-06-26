---
trigger_when: "starting the next milestone after v4.0; or any time data-loss-on-AMI-swap / backup / durability is raised"
planted_during: "v4.0 (Amazon DCV) — 2026-06-24"
---

# SEED-001: Persistent /home data volume + DLM snapshot backup/restore

## When to Surface
- Starting the milestone after v4.0 (Amazon DCV) closes.
- Any discussion of data loss, backup, restore, snapshots, or durability for the devbox.
- Before changing the AMI-swap / instance-replacement flow.

## Why This Matters
Today `aws_instance.devbox.ami = var.ami_id` (terraform/main.tf:155) and the AMI is a
ForceNew attribute, so a new bake + `tofu apply` **replaces** the instance. The only
volume is `root_block_device` with `delete_on_termination = true` (terraform/main.tf:170-174)
— there is no separate data volume and no snapshots. Result: every AMI swap **wipes**
everything not baked into the image (home, projects, dotfiles, code-server/VS Code state).

## Chosen architecture (design pass 2026-06-24)
**Separate persistent EBS volume holding `/home/ec2-user` + DLM snapshots. Snapshots are the
DR/rollback layer, NOT the everyday mechanism.** Decisions locked:
- **Persist scope:** the whole **`/home/ec2-user`** lives on the volume.
- **Backup tool:** **DLM** (`aws_dlm_lifecycle_policy`), tag-targeted daily snapshots + retention.
- **Destroy policy:** `lifecycle { prevent_destroy = true }` — volume + snapshots survive `tofu destroy`; removal is deliberate.
- **Why this over the alternatives** (see below): zero-touch on every update, no data-loss window, keeps the immutable-AMI model.

### Layer 1 — persistent volume (the transparent everyday path)
Data lives off the AMI; an update swaps only the OS disk; the same volume re-attaches.
`./run build && ./run tf-apply` stops being destructive with **no new steps**.

Terraform (terraform/main.tf):
```hcl
data "aws_subnet" "this" { id = var.subnet_id }            # pin the volume's AZ

resource "aws_ebs_volume" "home" {
  availability_zone = data.aws_subnet.this.availability_zone # MUST match instance AZ
  size              = var.home_volume_size                   # e.g. 50
  type              = "gp3"
  encrypted         = true
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-home", Backup = "devbox-home" })
  lifecycle { prevent_destroy = true }
}

resource "aws_volume_attachment" "home" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.home.id
  instance_id                    = aws_instance.devbox.id
  stop_instance_before_detaching = true                      # clean detach on replace
}
```
On AMI swap: instance replaced → attachment detaches/recreates → volume untouched (`prevent_destroy`). Brief downtime, data persists.

AMI side — a small `persistent-home` role (installs unit + script, runs before `hardening`; mount happens at runtime):
```bash
# /usr/local/sbin/devbox-home-mount.sh
set -euo pipefail
for i in $(seq 1 30); do dev=$(readlink -f /dev/sdf 2>/dev/null) && [ -b "$dev" ] && break; sleep 2; done  # attach is post-launch → poll (dcvserver-gate pattern)
if ! blkid -L DEVHOME >/dev/null 2>&1; then        # fresh volume, first ever
  mkfs.xfs -L DEVHOME "$dev"
  mount LABEL=DEVHOME /mnt/seed
  rsync -aAX /home/ec2-user/ /mnt/seed/            # seed baked home ONCE
  umount /mnt/seed
fi
mount LABEL=DEVHOME /home/ec2-user                  # mount by LABEL, never device path
restorecon -RvF /home/ec2-user                      # SELinux relabel (enforcing)
```
oneshot `devbox-home-mount.service`: `After=cloud-init.service`,
`Before=code-server.service dcvserver.service dcv-virtual-session.service devbox-secrets-bootstrap.service`,
`Type=oneshot RemainAfterExit=true`, `WantedBy=multi-user.target`. Everything reading `/home` gets `After=` it.

### Layer 2 — DLM snapshots (DR / rollback only)
```hcl
resource "aws_dlm_lifecycle_policy" "home" {
  description        = "devbox /home daily snapshots"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"
  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = { Backup = "devbox-home" }
    schedule {
      name        = "daily"
      create_rule { interval = 24, interval_unit = "HOURS", times = ["03:00"] }
      retain_rule { count = 7 }
    }
  }
}
```
\+ IAM role for `dlm.amazonaws.com` (managed `AWSDataLifecycleManagerServiceRole`).
**Restore (DR only):** `aws_ebs_volume.home { snapshot_id = <latest> }` (or CLI create-volume → attach). Optional `./run restore` helper later.

## Make-or-break details (the actual work)
1. **AZ match** — volume AZ = instance subnet AZ (`data.aws_subnet`).
2. **Mount by LABEL** — Nitro renames `/dev/sdf`→`/dev/nvme1n1`; only the first `mkfs` touches the raw device.
3. **Poll for the device at first boot** — Terraform attaches AFTER launch (same gate pattern as the dcvserver readiness fix).
4. **Service ordering** — mount `Before` code-server/dcv/secrets, else they start against the empty baked `/home`.
5. **Seed-once vs mount** — `mkfs`+rsync only when no `DEVHOME` label; never reformat real data.
6. **SELinux relabel** of the mounted home under enforcing.

## Alternatives considered (rejected as primary)
- **In-place ansible re-run** (update the live box over SSM, `hardening:false`/`secrets:false`): viable and transparent, but trades away reproducibility (config drift), risks re-running the terminal hardening role + the non-idempotent `secrets` regen on a live box, and has no clean rollback. Could be a *future* fast-iteration path on top of the volume — not the primary fix.
- **Snapshot + restore as the primary path** (data on root, snap-before/restore-after each apply): weakest — whole-root snapshots, file-level restore, a data-loss window since last snapshot, and boot-ordering races. Relegated to the DR/rollback layer (DLM above), which is where snapshots belong.

## Open decision (drives first-boot logic)
Once the volume holds `/home`, it **shadows** the AMI's baked `/home`, so future baked home-defaults
(new editor extensions, dotfiles) stop reaching the operator. Pick one at planning time:
- **Accept stale** — home is the operator's; re-add manually. Simplest.
- **System-path config** — bake tool defaults to system paths (`/etc/skel`-style) so updates apply regardless of the persisted home.
- **Versioned re-seed** — a `.devbox-home-vN` marker; on boot, if the AMI version is newer, re-apply just the managed dotfiles (not user files). More logic.

## Other open items at planning time
- Snapshot cadence + retention (daily / keep 7 vs 30).
- KMS key for EBS encryption (default aws/ebs vs CMK) + DLM/role perms.
- `./run` surface: snapshot-list / restore helper, or leave to CLI.
- `home_volume_size` default.

Related: [[project_unmerged_milestone_backlog]] — close v4.0 (merge + complete-milestone) before this milestone starts.
