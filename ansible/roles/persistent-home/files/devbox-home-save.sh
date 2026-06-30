#!/usr/bin/env bash
# Mirror /home/ec2-user -> /data/home on the persistent volume. Invoked on the instance via
# `./run save-home` (operator runs it BEFORE an AMI refresh / instance replace). Manual by design.
# --delete makes /data/home an exact mirror of /home at save time (no stale files accumulate).
set -euo pipefail

SRC="/home/ec2-user"
DST="/data/home"

if ! mountpoint -q /data; then
  echo "ERROR: /data is not mounted (persistent volume absent) — cannot save" >&2
  exit 1
fi

mkdir -p "$DST"
rsync -aHAX --delete "$SRC"/ "$DST"/
echo "saved $SRC -> $DST ($(du -sh "$DST" 2>/dev/null | cut -f1))"
