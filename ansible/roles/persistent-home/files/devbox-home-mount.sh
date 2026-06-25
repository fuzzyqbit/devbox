#!/usr/bin/env bash
# Mount the persistent /home/ec2-user EBS volume at boot (devbox persistent-home role).
#
# WHY: the devbox is rebuilt by swapping AMIs (`tofu apply` replaces the instance), which
# destroys the root volume. /home lives on a SEPARATE EBS volume (Terraform
# aws_ebs_volume.home, attached at /dev/sdf) so user data survives the swap. This boot
# oneshot mounts that volume at /home/ec2-user BEFORE code-server / DCV start.
#
# Idempotent: formats + seeds the baked /home only on a brand-new volume; otherwise just
# mounts by LABEL. Fail-open: if the volume never attaches it falls back to the baked
# (ephemeral) /home with a LOUD warning rather than bricking boot.
set -euo pipefail

LABEL="DEVHOME"
ATTACH_DEV="/dev/sdf"   # contract: Terraform aws_volume_attachment.device_name
HOME_DIR="/home/ec2-user"
WAIT_SECS=60

log() { echo "devbox-home-mount: $*"; }

# Already mounted (e.g. a manual `systemctl restart`)? Nothing to do.
if mountpoint -q "$HOME_DIR"; then
  log "$HOME_DIR already mounted"
  exit 0
fi

# Find the data volume's block device. Terraform attaches it AFTER instance launch, so
# poll (same pattern as the dcvserver readiness gate). On Nitro /dev/sdf is exposed as a
# udev symlink (amazon-ec2-utils) -> resolve it; fall back to the single non-root NVMe disk
# (the root disk's partitions carry a mountpoint; a fresh data disk has none).
find_dev() {
  local cand
  if cand=$(readlink -f "$ATTACH_DEV" 2>/dev/null) && [ -b "$cand" ]; then
    echo "$cand"; return 0
  fi
  for cand in /dev/nvme*n1; do
    [ -b "$cand" ] || continue
    if lsblk -nro MOUNTPOINT "$cand" | grep -q .; then continue; fi
    echo "$cand"; return 0
  done
  return 1
}

dev=""
for _ in $(seq 1 $((WAIT_SECS / 2))); do
  if dev=$(find_dev); then break; fi
  dev=""
  sleep 2
done

if [ -z "$dev" ]; then
  log "WARNING: persistent /home volume ($ATTACH_DEV) not found after ${WAIT_SECS}s."
  log "WARNING: using EPHEMERAL baked /home — data will NOT survive an instance replace."
  touch /run/devbox-home-ephemeral || true
  mkdir -p /etc/motd.d 2>/dev/null || true
  echo "WARNING: /home is EPHEMERAL — the persistent EBS volume did not attach; data is lost on instance replacement." \
    >/etc/motd.d/00-devbox-home-ephemeral 2>/dev/null || true
  exit 0
fi

# Brand-new volume (no DEVHOME filesystem) -> format once and seed the baked home onto it.
if ! blkid -L "$LABEL" >/dev/null 2>&1; then
  log "fresh volume $dev — creating xfs (LABEL=$LABEL) and seeding $HOME_DIR"
  mkfs.xfs -L "$LABEL" "$dev"
  seed=$(mktemp -d)
  mount "LABEL=$LABEL" "$seed"
  cp -a "$HOME_DIR"/. "$seed"/    # baked home incl. dotfiles -> new volume
  umount "$seed"
  rmdir "$seed"
fi

log "mounting LABEL=$LABEL at $HOME_DIR"
mount "LABEL=$LABEL" "$HOME_DIR"
restorecon -RF "$HOME_DIR" 2>/dev/null || true   # SELinux contexts on the mounted home
rm -f /run/devbox-home-ephemeral 2>/dev/null || true
log "persistent /home mounted from $dev"
