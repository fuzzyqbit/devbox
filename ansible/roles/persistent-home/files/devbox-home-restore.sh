#!/usr/bin/env bash
# Restore /data/home -> /home/ec2-user. Invoked on the instance via `./run restore-home`
# (operator runs it AFTER a refreshed instance is up). Manual by design.
# MERGE (no --delete): lays the saved home over the new AMI's /home, keeping the AMI's fresh
# defaults (e.g. new code-server config) and adding the operator's saved files on top.
set -euo pipefail

SRC="/data/home"
DST="/home/ec2-user"

if ! mountpoint -q /data; then
  echo "ERROR: /data is not mounted (persistent volume absent) — cannot restore" >&2
  exit 1
fi
if [ ! -d "$SRC" ]; then
  echo "ERROR: no backup found at $SRC — run './run save-home' on the old instance first" >&2
  exit 1
fi

rsync -aHAX "$SRC"/ "$DST"/
chown -R ec2-user:ec2-user "$DST"
echo "restored $SRC -> $DST"
