#!/usr/bin/env bash
# Mount the persistent /home/ec2-user EBS volume at boot (devbox persistent-home role).
#
# WHY: the devbox is rebuilt by swapping AMIs (`tofu apply` replaces the instance), which
# destroys the root volume. /home lives on a SEPARATE EBS volume (Terraform
# aws_ebs_volume.home, attached at /dev/sdf) so user data survives the swap. This boot
# oneshot mounts that volume at /home/ec2-user BEFORE the secrets bootstrap, code-server,
# and DCV touch /home.
#
# FAIL-CLOSED: on a provisioned devbox, if the volume never attaches this FAILS (exit 1)
# rather than silently falling back to the ephemeral baked /home — code-server / DCV
# Requires= this unit, so they refuse to serve on disposable storage. A loud boot failure
# the operator can see (and SSM in to fix) beats silent data loss.
set -euo pipefail

LABEL="DEVHOME"
ATTACH_DEV="/dev/sdf"   # contract: Terraform aws_volume_attachment.device_name
HOME_DIR="/home/ec2-user"
WAIT_SECS=300           # attach is post-launch (separate AttachVolume API call) — can lag

log()  { echo "devbox-home-mount: $*"; }
fail() { echo "devbox-home-mount: ERROR: $*" >&2; exit 1; }

# Idempotent: a manual `systemctl restart` after the home is already mounted is a no-op.
if mountpoint -q "$HOME_DIR"; then
  log "$HOME_DIR already mounted"
  exit 0
fi

# Bake/builder guard. The provisioned instance carries a DevboxUser IMDS tag (Terraform
# instance_metadata_tags=enabled); the Packer builder does not. During the bake the hardening
# role reboots the builder, which would otherwise start this enabled unit on a host with no
# data volume. Skip cleanly ONLY when IMDS is reachable AND the tag is absent (= builder /
# non-devbox). If IMDS is unreachable we do NOT skip — we proceed and fail-closed, so an IMDS
# glitch on a real instance can never silently drop us onto ephemeral /home.
imds_token=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [ -n "$imds_token" ]; then
  if ! curl -sf -H "X-aws-ec2-metadata-token: $imds_token" \
      "http://169.254.169.254/latest/meta-data/tags/instance/DevboxUser" >/dev/null 2>&1; then
    log "no DevboxUser IMDS tag — bake builder / non-devbox host; skipping"
    exit 0
  fi
fi

# Resolve the data volume STRICTLY via the /dev/sdf udev symlink (amazon-ec2-utils on AL2023).
# Never guess a bare NVMe disk — that risks mkfs'ing the wrong device (instance store, a second
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

# Format ONLY a genuinely blank device. Gate on BOTH: no DEVHOME label anywhere AND no existing
# filesystem signature on the resolved device. A device that has a filesystem but not the
# DEVHOME label is an anomaly (mislabeled, wrong device, foreign restored snapshot) — abort
# loudly, never auto-reformat real data.
if ! blkid -L "$LABEL" >/dev/null 2>&1; then
  if blkid "$dev" >/dev/null 2>&1; then
    fail "$dev has a filesystem but no LABEL=$LABEL — refusing to reformat (manual intervention required)"
  fi
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

# SELinux: relabel the mounted home so user_home_dir_t/user_home_t are correct under enforcing
# (cp -a preserved the source root-fs contexts, which may not match policy for the new fs). Do
# NOT swallow errors — a mislabel causes hard-to-diagnose login denials.
if command -v restorecon >/dev/null 2>&1; then
  restorecon -RF "$HOME_DIR" || log "WARNING: restorecon on $HOME_DIR returned non-zero"
fi

log "persistent /home mounted from $dev"
