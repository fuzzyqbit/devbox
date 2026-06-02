---
phase: 09-jupyter-operator-surface-docs
plan: "01"
subsystem: operator-surface-docs
tags: [jupyter, status, documentation, developer-lifecycle]
dependency_graph:
  requires: [08-02, 08-03]
  provides: [operator-discoverable-jupyter-flow]
  affects: [scripts/devbox-status.sh, docs/DEVELOPER-LIFECYCLE.md]
tech_stack:
  added: []
  patterns: [loopback-only-on-demand, ssm-port-forward, no-password-loopback]
key_files:
  created: []
  modified:
    - scripts/devbox-status.sh
    - docs/DEVELOPER-LIFECYCLE.md
decisions:
  - "JupyterLab surfaced as on-demand/loopback-only in status — no https://<ip>:8888 URL (preserves Phase 8 loopback model)"
  - "Cheat-sheet row added pointing to ./run jupyter alongside existing rows"
metrics:
  duration: "~10 min"
  completed: "2026-06-02T23:02:00Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 9 Plan 01: Jupyter Operator Surface + Docs Summary

JupyterLab on-demand loopback capability surfaced in `./run status` and documented in `DEVELOPER-LIFECYCLE.md` with the full `./run jupyter` + `:8888` SSM port-forward access flow and explicit no-password statement.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Surface JupyterLab in ./run status Connection Info | c9399a7 | scripts/devbox-status.sh |
| 2 | Document JupyterLab access flow in DEVELOPER-LIFECYCLE.md | a998629 | docs/DEVELOPER-LIFECYCLE.md |

## What Was Built

### Task 1 — scripts/devbox-status.sh

Added three `echo` lines to the Connection Info block (inside the `$STATE == "running"` guard, after the noVNC line). The new output reads:

```
JupyterLab (on-demand):  DEVBOX_USER=<user> ./run jupyter
                         then forward :8888 over SSM in a second shell
                         (127.0.0.1:8888 loopback-only; no password)
```

No `https://${PRIVATE_IP}:8888` URL is printed — Jupyter is loopback-only. Shellcheck clean.

### Task 2 — docs/DEVELOPER-LIFECYCLE.md

Two edits:

1. New `### JupyterLab (on demand, loopback-only)` subsection inserted between `### Browser IDE (code-server on :8080)` and `### Passwords`. Documents the three-step flow:
   - `./run jupyter` — leave running, note the `http://127.0.0.1:8888/lab?token=...` URL
   - Second terminal: `aws ssm start-session ... --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'`
   - Open `http://127.0.0.1:8888/lab?token=<token>` in the browser
   - States explicitly: **no Jupyter password** (loopback + SSM/IAM is the auth boundary)

2. Cheat-sheet table row: `| JupyterLab (on demand) | ./run jupyter |`

## Verification Results

All automated gates pass:

```
bash -n scripts/devbox-status.sh      → OK (syntax clean)
shellcheck scripts/devbox-status.sh   → OK (no warnings)
grep -i jupyter scripts/devbox-status.sh  → match in Connection Info block
grep 'run jupyter' scripts/devbox-status.sh → match
grep -E 'https://[^ ]*:8888' (negative) → no match (loopback model preserved)
grep -qi 'jupyter' docs/DEVELOPER-LIFECYCLE.md → match
grep -c 8888 docs/DEVELOPER-LIFECYCLE.md → 7 (>= 1)
grep 'run jupyter' docs/DEVELOPER-LIFECYCLE.md → match
grep -Eqi 'no.*password' docs/DEVELOPER-LIFECYCLE.md → match
```

Negative invariants confirmed:
- No `https://<ip>:8888` URL in either file
- No `jupyter password` or `secrets-show jupyter` references
- No SG/Terraform/workflow files touched
- Phase 8 loopback model intact

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Both edits are shell `echo` lines and Markdown prose. The threat model's T-09-01 mitigation (no network-reachable `:8888` URL) is confirmed in all files. T-09-02 (no SG/secrets scope creep) is confirmed — zero infrastructure files touched.

## Known Stubs

None.

## Self-Check: PASSED

- `scripts/devbox-status.sh` exists and contains `jupyter`: FOUND
- `docs/DEVELOPER-LIFECYCLE.md` exists and contains `jupyter`: FOUND
- Commit c9399a7 exists: FOUND
- Commit a998629 exists: FOUND
