#!/usr/bin/env bash
# Mount the persistent /home/ec2-user EBS volume at boot (devbox persistent-home role).
#
# WHY: the devbox is rebuilt by swapping AMIs (`tofu apply` replaces the instance), which
# destroys the root volume. /home lives on a SEPARATE EBS volume (Terraform
# aws_ebs_volume.home, attached at /dev/sdf) so user data survives the swap. This boot
# oneshot mounts that volume at /home/ec2-user BEFORE the secrets bootstrap, code-server,
# dcvserver, and the DCV session touch /home.
#
# FAIL-CLOSED: if the volume never attaches this FAILS (exit 1) instead of falling back to the
# ephemeral baked /home. code-server / dcvserver / dcv-virtual-session Requires= this unit, so
# they refuse to serve on disposable storage — a loud, recoverable failure beats silent data
# loss. RECOVERY if it ever wedges (volume genuinely absent / very slow attach): SSM in and
#   sudo systemctl restart devbox-home-mount && sudo systemctl restart code-server dcvserver
#
# Bake-safe by construction: on the Packer builder there is no /dev/sdf (no data volume) and
# no other device is ever touched, so at the bake reboot this simply polls then exits 1 — a
# harmless cosmetic failure (nothing is formatted/mounted) that is reset on the real boot.
set -euo pipefail

LABEL="DEVHOME"
ATTACH_DEV="/dev/sdf"   # contract: Terraform aws_volume_attachment.device_name
HOME_DIR="/home/ec2-user"
WAIT_SECS=300           # attach is a separate post-launch API call — give it a wide margin

log()  { echo "devbox-home-mount: $*"; }
fail() { echo "devbox-home-mount: ERROR: $*" >&2; exit 1; }

# Idempotent: a manual `systemctl restart` once /home is mounted is a no-op.
if mountpoint -q "$HOME_DIR"; then
  log "$HOME_DIR already mounted"
  exit 0
fi

# Resolve the data volume STRICTLY via the /dev/sdf udev symlink (amazon-ec2-utils on AL2023).
# NEVER guess a bare NVMe disk — that risks mkfs'ing the wrong device (instance store, a second
# volume, the root disk). Attach happens post-launch, so poll for the symlink to resolve.
dev=""
for _ in $(seq 1 $((WAIT_SECS / 2))); do
  if cand=$(readlink -f "$ATTACH_DEV" 2>/dev/null) && [ -b "$cand" ]; then
    dev="$cand"
    break
  fi
  sleep 2
done
[ -n "$dev" ] || fail "persistent /home volume ($ATTACH_DEV) never attached after ${WAIT_SECS}s — refusing to start on ephemeral /home"

# Format ONLY a genuinely blank device. Inspect the label ON THIS DEVICE (device-local, not the
# system-wide `blkid -L` which could resolve a different disk):
#   - label already DEVHOME      -> existing volume, just mount it
#   - device has NO filesystem    -> fresh -> mkfs + seed the baked /home onto it
#   - device has a DIFFERENT fs   -> anomaly (wrong device / foreign snapshot) -> abort, never reformat
existing_label=$(blkid -o value -s LABEL "$dev" 2>/dev/null || true)
if [ "$existing_label" != "$LABEL" ]; then
  if blkid "$dev" >/dev/null 2>&1; then
    fail "$dev has a foreign filesystem (label='${existing_label}') — refusing to reformat (manual intervention required)"
  fi
  log "fresh volume $dev — creating xfs (LABEL=$LABEL) and seeding $HOME_DIR"
  mkfs.xfs -L "$LABEL" "$dev"
  seed=$(mktemp -d)
  mount "$dev" "$seed"
  cp -a "$HOME_DIR"/. "$seed"/    # baked home incl. dotfiles -> new volume
  umount "$seed"
  rmdir "$seed"
fi

log "mounting $dev at $HOME_DIR"
mount "$dev" "$HOME_DIR"

# SELinux: relabel the mounted home so user_home_dir_t/user_home_t are correct under enforcing
# (cp -a preserved source contexts that may not match policy for the new fs). Do NOT swallow
# errors — a mislabel causes hard-to-diagnose login denials.
if command -v restorecon >/dev/null 2>&1; then
  restorecon -RF "$HOME_DIR" || log "WARNING: restorecon on $HOME_DIR returned non-zero"
fi

log "persistent /home mounted from $dev"
