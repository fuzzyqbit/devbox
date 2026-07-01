#!/usr/bin/env bash
# Restore /data/home -> /home/ec2-user. Invoked on the instance via `./run restore-home`
# (operator runs it AFTER a refreshed instance is up). Manual by design.
# MERGE (no --delete): lays the saved home over the new AMI's /home, keeping the AMI's fresh
# defaults (e.g. new code-server config) and adding the operator's saved files on top.
set -euo pipefail

SRC="/data/home"
DST="/home/ec2-user"

data_dev="$(findmnt -no SOURCE /data 2>/dev/null)" || {
  echo "ERROR: /data is not mounted (persistent volume absent) — cannot restore" >&2
  exit 1
}
if [ "$(blkid -o value -s LABEL "$data_dev" 2>/dev/null)" != "DEVDATA" ]; then
  echo "ERROR: /data is not the DEVDATA persistent volume (device: $data_dev) — refusing to restore" >&2
  exit 1
fi
if [ ! -d "$SRC" ]; then
  echo "ERROR: no backup found at $SRC — run './run save-home' on the old instance first" >&2
  exit 1
fi

# Quiesce the home consumers so rsync doesn't overwrite open files; restart after. --chown
# sets ownership on transferred files (no blanket chown -R that could clobber unrelated paths).
services="code-server.service dcvserver.service dcv-virtual-session.service"
# shellcheck disable=SC2086
systemctl stop $services 2>/dev/null || true
rsync -aHAX --chown=ec2-user:ec2-user "$SRC"/ "$DST"/
# shellcheck disable=SC2086
systemctl start $services 2>/dev/null || true
echo "restored $SRC -> $DST"
