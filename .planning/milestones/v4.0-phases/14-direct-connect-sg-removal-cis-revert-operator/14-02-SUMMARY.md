---
phase: 14-direct-connect-sg-removal-cis-revert-operator
plan: 02
subsystem: operator-surface
tags: [run, scripts, ansible-secrets, dcv, operator-surface]
requires: []
provides: ["DCV :8443 direct-connect operator surface", "desktop-password credential path retained"]
affects: [run, scripts/devbox-start.sh, scripts/devbox-status.sh, ansible/firewalld-docker-fix.yml, ansible/roles/secrets/tasks/publish.yml, CLAUDE.md]
tech-stack:
  added: []
  patterns: ["relabel-only RDP→DCV; keep desktop-password SSM path"]
key-files:
  created: []
  modified: [run, scripts/devbox-start.sh, scripts/devbox-status.sh, ansible/firewalld-docker-fix.yml, ansible/roles/secrets/tasks/publish.yml]
decisions:
  - "secrets-bootstrap templates + secrets/defaults comment were already swapped to dcvserver.service / DCV in commit caacb14 (14-03) — verified clean, no edit needed this session"
  - "CLAUDE.md edited on-disk only (git-ignored), NOT staged/committed"
metrics:
  duration: ~25m (combined wave)
  completed: 2026-06-19
---

# Phase 14 Plan 02: Operator Surface DCV Cutover Summary

Relabeled the operator-facing surface (run, status/start scripts, firewalld comment, secrets-publish, CLAUDE.md) from RDP/:3389→DCV with direct `:8443` connect. The `desktop-password` SSM credential path is kept everywhere.

## What changed

- **run**: `secrets-show` label `RDP login (ec2-user @ <host>:3389)`→`DCV login (ec2-user @ <host>:8443)` and the not-found error `RDP`→`DCV` (desktop-password fetch unchanged); `cmd_devbox_port_forward` dropped the `:3389`/RDP examples and added a note that DCV is direct connect (kept the function + the :8080/8888 examples); invalid-port `_error` example token `3389`→`8080`; help `devbox-port-forward` example dropped `3389`; help `secrets-show` desc `RDP`→`DCV`.
- **scripts/devbox-start.sh + devbox-status.sh**: RDP `:3389` banners → DCV `https://<ip>:8443` direct (browser web client or native DCV client); dropped the `devbox-port-forward 3389` hints, kept the `:8080` code-server hint.
- **ansible/firewalld-docker-fix.yml**: comment `(code-server :8080, RDP :3389)`→`(code-server :8080, DCV :8443)`; play body unchanged (stays its own named workaround playbook).
- **ansible/roles/secrets/tasks/publish.yml**: SSM task name + description `RDP/desktop`→`DCV/desktop login password`; param name/value unchanged.
- **CLAUDE.md** (on-disk only, NOT committed): §1 line 9, §4 Step 2, §5 daily-flow (dropped the `devbox-port-forward 3389` block, relabeled the DCV browser/native-client line, fixed the secrets-show comment to `desktop-password`), §7 troubleshooting (RDP→DCV :8443 direct), §8 invariant note (rewrote the stale CIS-2.2.1/xrdp-exception note → CIS 2.2.1 RE-ENABLED, DCV uses /usr/bin/Xdcv, post-hardening Xdcv assert).

## Verification

- `bash -n run` / `scripts/*.sh` parse; `shellcheck -S error` clean on all three.
- No `RDP`/`3389`/`xrdp` in run, scripts, firewalld comment, publish.yml, or CLAUDE.md.
- `desktop-password` SSM fetch path intact in run; secrets-bootstrap orders `Before=code-server.service dcvserver.service` (verified pre-existing from 14-03).
- CLAUDE.md NOT tracked (`git ls-files CLAUDE.md` empty).

## Deviations from Plan

**1. [Rule 1 - Already-done] secrets-bootstrap templates + secrets/defaults already DCV**
- **Found during:** Task 1
- **Issue:** The plan's Task 1 (swap xrdp→dcvserver in the bootstrap unit + defaults comment) was already completed in commit caacb14 (14-03). The credential is `desktop-password`, not `vnc-password`.
- **Fix:** Verified those files are RDP/xrdp-clean and order `dcvserver.service`; no edit needed. Only `publish.yml` (uncovered by the original plan, still had "RDP/desktop") required a relabel.
- **Files modified:** ansible/roles/secrets/tasks/publish.yml (the residual)
- **Commit:** 2dcbe60

## Self-Check: PASSED
- All listed files modified or verified-clean — confirmed in commit 2dcbe60.
- Commit 2dcbe60 verified via `git rev-parse`.
