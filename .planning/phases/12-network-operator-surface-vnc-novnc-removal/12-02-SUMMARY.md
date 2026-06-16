---
phase: 12-network-operator-surface-vnc-novnc-removal
plan: 02
subsystem: operator-surface
tags: [rdp, ssm-port-forward, operator-surface, docs, novnc-removal]
requires:
  - "12-01 (Terraform SG :3389 + noVNC scrub) — network half of RDP-09"
provides:
  - "operator surface (./run, scripts) and docs point at native RDP-over-SSM :3389"
  - "zero :6080/noVNC reference in run, scripts/, CLAUDE.md"
affects:
  - run
  - scripts/devbox-start.sh
  - scripts/devbox-status.sh
  - CLAUDE.md (on-disk only; git-ignored)
tech-stack:
  added: []
  patterns:
    - "RDP login credential model: /devbox/<user>/vnc-password SSM param IS the ec2-user PAM/RDP password — relabel human surfaces only, never rename/remove the path"
    - "generic ./run devbox-port-forward port parser already supports any numeric PORT — 3389 works with no code change (R1)"
key-files:
  created:
    - .planning/phases/12-network-operator-surface-vnc-novnc-removal/12-02-SUMMARY.md
  modified:
    - run
    - scripts/devbox-start.sh
    - scripts/devbox-status.sh
    - CLAUDE.md
decisions:
  - "Retained the /devbox/${DEVBOX_USER}/vnc-password SSM fetch path unchanged in run — it is the RDP/PAM login password (locked credential model); only the human-facing label changed."
  - "No logic change to cmd_devbox_port_forward — locked decision D4: the generic parser already forwards 3389; only help text edited."
  - "CLAUDE.md edited on-disk for the operator but NOT committed — it is git-ignored (commit effde0f); authoritative committed record lives in run/scripts + this SUMMARY."
metrics:
  duration: ~4min
  tasks: 3
  files: 4
  completed: 2026-06-16
requirements: [RDP-10]
---

# Phase 12 Plan 02: Operator Surface — Native RDP over SSM Summary

Pointed the `./run` operator surface and operator docs at native RDP-over-SSM `:3389` and
scrubbed every `:6080`/noVNC reference from `run`, the two delegated `scripts/`, and the
on-disk `CLAUDE.md` — operator-surface half of RDP-10, with no code change to the generic
port-forward parser (locked decision D4).

## What Was Built

- **`run`** — port-forward inline help (`6080 -> noVNC` example replaced with `3389 -> RDP`;
  combined example `8080 6080` -> `8080 3389`); `_error` spec example `6080` -> `3389`;
  `cmd_secrets_show` printed label `VNC / noVNC (https://<host>:6080) password:` ->
  `RDP login (ec2-user @ <host>:3389) password:`; secrets-show error message relabelled
  (the `/devbox/${DEVBOX_USER}/vnc-password` SSM fetch path **unchanged** — it is the RDP
  login password); help block example `8080 6080 8888:18888` -> `8080 3389 8888:18888` and
  `code-server and VNC passwords` -> `code-server and RDP login passwords`. No change to
  `cmd_devbox_port_forward` logic or `DEVBOX_FORWARD_DEFAULT_PORT`.
- **`scripts/devbox-start.sh`** — connection-info `noVNC :6080` line replaced with an
  `RDP desktop: <ip>:3389` line; off-VPC hint now mentions `./run devbox-port-forward 3389`.
- **`scripts/devbox-status.sh`** — connection-info `noVNC (browser) :6080` line replaced with
  `RDP desktop: <ip>:3389`; off-VPC port-forward hint now points at an RDP client on
  `localhost:3389`. code-server, JupyterLab, SSM, and allowed_web_cidrs lines left intact.
- **`CLAUDE.md` (on-disk only — git-ignored, NOT committed)** — §1 (`noVNC on :6080` ->
  `an RDP desktop on :3389`), §2 Step-2 heading + restriction line (`code-server / noVNC`,
  `:6080 (noVNC)` -> `code-server / RDP`, `:3389 (RDP)`), §5 daily-flow (added a
  `./run devbox-port-forward 3389` -> native RDP client step + relabelled the browser line +
  annotated the vnc-password param as the RDP/PAM login password), §7 troubleshooting (added
  an "RDP client can't connect to :3389" entry). §8 invariants untouched.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Relabel run — port-forward help, secrets-show RDP label, help descriptions (vnc-password path kept) | `1393b15` | run |
| 2 | Relabel scripts/devbox-start.sh + devbox-status.sh — RDP :3389 connection info | `60b409c` | scripts/devbox-start.sh, scripts/devbox-status.sh |
| 3 | Update CLAUDE.md (§1/§2/§5/§7) — RDP over SSM; ON-DISK ONLY, not committed | (no commit — git-ignored) | CLAUDE.md |

## Verification Results

- `! grep -Eqi '6080\|novnc' run scripts/devbox-start.sh scripts/devbox-status.sh CLAUDE.md` — **0 residue** PASS
- `grep -cF '/devbox/${DEVBOX_USER}/vnc-password' run` = **2** (RDP-password fetch path retained) PASS
- `grep -c 'devbox-port-forward 3389' CLAUDE.md` = **2** (RDP-over-SSM documented) PASS
- `shellcheck run scripts/devbox-start.sh scripts/devbox-status.sh` — **rc=0** PASS
- `git ls-files CLAUDE.md` — **EMPTY** (file remains untracked, never committed) PASS
- SURVIVING-FEATURE: code-server label intact in run; `:8080`+JupyterLab intact in scripts; `:8080`+`hardening` §8 intact in CLAUDE.md — PASS
- No `changeme` literal introduced in committed files (run/scripts count = 0) — PASS

## Deviations from Plan

None — plan executed exactly as written. The three `type="auto"` tasks ran in order; every
automated verify gate printed its expected result before each commit.

> Tooling note: the executor's Bash shell runs with `errexit` active, so a bare
> `grep` returning non-zero (no match = clean) aborted the plan's combined `&&` gate
> mid-stream. Re-ran each acceptance check independently with `set +e` and fixed-string
> matching (`grep -cF`) for the `/devbox/${DEVBOX_USER}/vnc-password` path (the literal `{`
> is a BRE metachar). All gates pass; this is a harness artifact, not a code issue.

## Known Stubs

None.

## Threat Flags

None — this plan only changes label/help/comment text. No new network endpoint, auth path,
or trust-boundary surface. The `secrets-show` disclosure surface (T-12-04, disposition
`accept`) is unchanged: it still prints the SSM SecureString to the operator's terminal on
explicit request, under the operator's own AWS creds.

## Notes for Downstream

- The Ansible VNC/noVNC stack removal (RDP-11) and the `novnc-plain-username-fix.yml` revert
  (RDP-12) are owned by plan 12-03 — the desktop/secrets role residue + the
  `firewalld-docker-fix.yml` comment `:6080` mention are NOT in this plan's scope.
- CLAUDE.md changes are on the operator's disk only. Any authoritative, committed record of
  the RDP-over-SSM operator flow lives in `run`/`scripts` and this SUMMARY.
- `./run secrets-show` now prints exactly two lines: code-server (:8080) and
  `RDP login (ec2-user @ <host>:3389)`.

## Self-Check: PASSED

- FOUND: `.planning/phases/12-network-operator-surface-vnc-novnc-removal/12-02-SUMMARY.md`
- FOUND commit `1393b15` (Task 1 — run relabel)
- FOUND commit `60b409c` (Task 2 — scripts relabel)
- CLAUDE.md intentionally has no commit (git-ignored; edited on-disk only)
