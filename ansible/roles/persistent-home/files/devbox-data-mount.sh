#!/usr/bin/env bash
# Mount the persistent /data EBS volume at boot (devbox persistent-home role).
#
# /data holds MANUAL backups of /home/ec2-user (devbox-home-save.sh / devbox-home-restore.sh,
# driven by `./run save-home` / `./run restore-home`). It is mounted at an EMPTY /data, so it
# never shadows /home — /home stays normal root storage. NON-CRITICAL to boot: if the volume is
# absent, /data is just not mounted (save/restore report it); nothing depends on it. This is the
# deliberate replacement for the old mount-over-/home + seed design (shadowing/seed/fail-closed).
set -euo pipefail

LABEL="DEVDATA"        # a pre-existing DEVHOME volume (old mount-over-/home layout) hits the
                       # foreign-fs guard below and fails LOUD rather than silently mounting a
                       # mismatched layout at /data — wipefs it to re-init (test volumes only).
ATTACH_DEV="/dev/sdf"  # contract: Terraform aws_volume_attachment.device_name
MOUNT_DIR="/data"
WAIT_SECS=120

log() { echo "devbox-data-mount: $*"; }

if mountpoint -q "$MOUNT_DIR"; then
  log "$MOUNT_DIR already mounted"
  exit 0
fi

# Resolve the volume strictly via the /dev/sdf udev symlink (attach is post-launch -> poll).
dev=""
for _ in $(seq 1 $((WAIT_SECS / 2))); do
  if cand=$(readlink -f "$ATTACH_DEV" 2>/dev/null) && [ -b "$cand" ]; then
    dev="$cand"
    break
  fi
  sleep 2
done
if [ -z "$dev" ]; then
  # Non-critical: do not block boot. /home is on the root and fully functional without /data;
  # `./run save-home`/`restore-home` will report /data missing if the operator tries to use it.
  log "WARNING: data volume ($ATTACH_DEV) not attached after ${WAIT_SECS}s — /data not mounted"
  exit 0
fi

# Format only a genuinely blank device (device-local label check; never reformat a foreign fs).
existing_label=$(blkid -o value -s LABEL "$dev" 2>/dev/null || true)
if [ "$existing_label" != "$LABEL" ]; then
  if blkid "$dev" >/dev/null 2>&1; then
    log "ERROR: $dev has a foreign filesystem (label='${existing_label}') — refusing to reformat"
    exit 1
  fi
  log "fresh volume $dev — creating xfs (LABEL=$LABEL)"
  mkfs.xfs -L "$LABEL" "$dev"
fi

mkdir -p "$MOUNT_DIR"
mount "$dev" "$MOUNT_DIR"
chown ec2-user:ec2-user "$MOUNT_DIR"
restorecon -RF "$MOUNT_DIR" 2>/dev/null || true
log "mounted $dev at $MOUNT_DIR"
