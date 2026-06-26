---
phase: 14-direct-connect-sg-removal-cis-revert-operator
plan: 05
subsystem: docs
tags: [docs, dcv, operator-guides]
requires: []
provides: ["docs/HOWTO-ACCESS-CODE-SERVER-DCV.md", "DCV :8443 direct-connect docs"]
affects: [docs/DEVELOPER-LIFECYCLE.md, docs/HOWTO-ACCESS-CODE-SERVER-DCV.md]
tech-stack:
  added: []
  patterns: ["git mv preserves history on the HOWTO rename"]
key-files:
  created: [docs/HOWTO-ACCESS-CODE-SERVER-DCV.md]
  modified: [docs/DEVELOPER-LIFECYCLE.md]
decisions:
  - "DCV desktop documented as direct connect in-CIDR (no port-forward step); code-server :8080 SSM port-forward + Jupyter :8888 flows retained unchanged"
metrics:
  duration: ~20m (combined wave)
  completed: 2026-06-19
---

# Phase 14 Plan 05: Docs DCV Cutover Summary

Rewrote both operator docs from RDP/:3389/port-forward to Amazon DCV direct `https://<host>:8443`, and `git mv`'d the HOWTO from `-RDP.md`→`-DCV.md` (history preserved).

## What changed

- **docs/DEVELOPER-LIFECYCLE.md**: "Graphical desktop (RDP on :3389)" section → "Graphical desktop (Amazon DCV on :8443)" with the off-VPC port-forward-3389 subsection deleted and an explicit "no port-forward for the desktop" note; Jupyter aside reworded ("same SSM pattern as the code-server :8080 forward"); passwords paragraph RDP→DCV; cheat-sheet row `RDP desktop off-VPC | ./run devbox-port-forward 3389` → `DCV desktop (in-CIDR) | https://<private-ip>:8443`. code-server/:8080/SSM/Jupyter content untouched.
- **docs/HOWTO-ACCESS-CODE-SERVER-RDP.md → -DCV.md** (`git mv`): full rewrite — title, intro bullet, ingress mentions, prerequisites (DCV client/browser instead of native RDP client), Step 1 (DCV desktop password), Step 2 (code-server keeps on-VPC + SSM port-forward; DCV is a new direct-connect `:8443` section, Option-B-for-desktop deleted), Step 3 login, troubleshooting (DCV `:8443` direct-connect row), quick reference (dropped "Forward RDP :3389", rewrote "DCV desktop (in-CIDR)").

## Verification

- `docs/HOWTO-ACCESS-CODE-SERVER-DCV.md` exists; `-RDP.md` gone (rename in commit 2dcbe60).
- `! grep -riE ':3389|\bRDP\b|xrdp' docs/` → empty.
- Both docs still reference `:8080` and `secrets-show`.
- `git grep 'HOWTO-ACCESS-CODE-SERVER-RDP' -- ':!.planning/**'` → empty (no stale link to old filename).

## Deviations from Plan

None — docs rewrite executed as written. (NOTE the plan correctly flagged the 14-RESEARCH §5 "no docs/ dir" claim as false; the docs were present and tracked.)

## Self-Check: PASSED
- docs/HOWTO-ACCESS-CODE-SERVER-DCV.md created, -RDP.md removed, DEVELOPER-LIFECYCLE.md modified — confirmed in commit 2dcbe60.
- Commit 2dcbe60 verified via `git rev-parse`.
