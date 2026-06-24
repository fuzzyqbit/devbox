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
everything not baked into the image (home dir, projects, dotfiles, code-server state).
This is a latent data-loss bug for a workstation the operator actually works on.

## Locked design decisions (from the 2026-06-24 design pass)
- **Persist scope:** the whole **`/home/ec2-user`** moves onto a separate persistent EBS volume.
- **Backup tool:** **DLM** (`aws_dlm_lifecycle_policy`) — tag-targeted scheduled EBS snapshots + retention. (Not AWS Backup.)
- **Destroy policy:** `lifecycle { prevent_destroy = true }` on the data volume — it (and its snapshots) **survives `tofu destroy`**; removal is deliberate/manual.

## Design sketch (two layers)
**Layer 1 — PREVENT (primary): separate persistent data volume.**
- `aws_ebs_volume` (gp3, encrypted) + `aws_volume_attachment` at `/dev/sdf` (Nitro device → `/dev/nvme1n1`), `prevent_destroy`.
- Separate resource from the instance → AMI swap detaches it from the old instance and re-attaches to the new one; `/home` data survives.
- Idempotent first-boot mount: `mkfs` **only** if the volume has no filesystem (never reformat an existing one); relocate/seed `/home/ec2-user` onto it on first init; mount via systemd mount unit or fstab (`nofail`).
- Replacement ordering: instance has no `create_before_destroy` → destroy-then-create, so the attachment cleanly detaches with the old instance and recreates on the new (brief downtime). The volume itself persists.

**Layer 2 — BACKUP/RESTORE: DLM snapshots of the data volume.**
- `aws_dlm_lifecycle_policy` targeting the data volume by tag; daily snapshots, retain N; needs a DLM service role.
- **Restore:** create a volume from a snapshot → attach → mount. DR (volume lost) = recreate from latest snapshot.

## Open items to resolve at planning time
- Snapshot cadence + retention (e.g. daily / keep 7 or 30).
- KMS key for EBS encryption (default aws/ebs vs a customer-managed key) + DLM/role perms to use it.
- First-boot mechanics of relocating an existing `/home/ec2-user` onto a fresh volume vs an already-populated one (idempotency, ownership, SELinux relabel of the new mount).
- `./run` surface: a restore command? snapshot-list/restore helper? (or leave to console/CLI).
- Interaction with the `secrets` boot bootstrap and the DCV/code-server services that read from `/home`.

Related: [[project_unmerged_milestone_backlog]] — close v4.0 (merge + complete-milestone) before this milestone starts.
