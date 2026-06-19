---
phase: 14-direct-connect-sg-removal-cis-revert-operator
plan: 04
subsystem: verification-gate
tags: [verification, completeness-gate, dcv, grep-battery]
requires: ["14-01", "14-02", "14-03", "14-05"]
provides: ["DCV-09 repo-wide completeness gate GREEN"]
affects: [ansible/roles/desktop/handlers/main.yml, ansible/roles/desktop/tasks/main.yml]
tech-stack:
  added: []
  patterns: ["delimiter-bound port tokens", "path-exclude the kept dcv role + .gitlab-ci digest"]
key-files:
  created: []
  modified: [ansible/roles/desktop/handlers/main.yml, ansible/roles/desktop/tasks/main.yml]
decisions:
  - "Two documented gate exemptions: (a) path-exclude ansible/roles/dcv/** (the kept Phase-13 role legitimately carries ~8 xrdp provenance comments); (b) exclude .gitlab-ci.yml (its checkov image digest contains the substring 6080)"
  - "Relabeled 3 stale RDP provenance comments in the KEPT desktop role (RDP-11 / GNOME-over-RDP / headless RDP) → DCV so even the unbounded-RDP form of the gate is GREEN"
metrics:
  duration: ~10m (combined wave)
  completed: 2026-06-19
---

# Phase 14 Plan 04: Repo-Wide Completeness Gate Summary

The DCV-09 verification wave: proved that zero functional xrdp/:3389/RDP/VNC/noVNC residue survives outside the deliberately-kept `dcv` role and the `.gitlab-ci.yml` checkov digest. Found and fixed three stale `RDP` provenance comments in the kept `desktop` role.

## DCV-09 evidence — gate commands + (empty) output

**Canonical objective gate (word-bounded RDP):**
```
git grep -nIE 'xrdp|xorgxrdp|:3389|\bRDP\b|tigervnc|vncserver|novnc|SecurityTypes' \
  -- ':!.planning/**' ':!ansible/roles/dcv/**' ':!.gitlab-ci.yml'
→ EMPTY (exit 1)
```

**Stricter unbounded-RDP gate (after the desktop-role fix):**
```
git grep -nIE 'xrdp|xorgxrdp|:3389|RDP|tigervnc|vncserver|novnc|SecurityTypes' \
  -- ':!.planning/**' ':!ansible/roles/dcv/**' ':!.gitlab-ci.yml'
→ EMPTY (exit 1)
```

**Plan-04 battery (all GREEN):**
- xrdp/:3389 (credential-allowlisted): EMPTY
- VNC/noVNC/:6080 (credential-allowlisted, delimiter-bound): EMPTY
- docs RDP-prose supplement: EMPTY

## Two documented exemptions (BLOCKER 3)

1. **`ansible/roles/dcv/**` path-exclusion** — the kept Phase-13 dcv role legitimately contains `xrdp` in ~8 provenance comments (e.g. "ported from the proven xrdp...", "Modeled on the xrdp-sesman PAM file"). Path-exclusion is zero-churn on the verified role; it is the ONE place `xrdp` is allowed.
2. **`.gitlab-ci.yml` exclusion** — its checkov image digest `sha256:...446c6080d...` contains the substring `6080`. The objective gate path-excludes the file; the plan-04 battery additionally uses delimiter-bound port tokens (`:6080`, `port 6080`, `6080/(tcp|udp)`) so the bare digit run does not false-positive.

## Structural battery (research §6) — all pass

- `ansible/roles/xrdp` removed; `ansible/test-xrdp.yml` removed.
- hardening-last grep-gate = 1.
- SG `:8443` TCP+UDP gated; `protocol = "(tcp|udp)"` count = 3; zero `3389` in main.tf.
- CIS 2.2.1 override absent (`amzn2023cis_rule_2_2_1` not in hardening/defaults).
- Xdcv guard present in playbook.yml (4 refs).
- Surviving features: `output "dcv_endpoint"`, `dcvserver.service` in secrets bootstrap, `desktop-password` path, `docs/HOWTO-ACCESS-CODE-SERVER-DCV.md` present + `-RDP.md` gone, `secrets_desktop_password_length: 20` kept.
- `tofu validate` clean; shellcheck clean; YAML parses.

## Deviations from Plan

**1. [Rule 1 - Bug] Three stale RDP provenance comments in the KEPT desktop role**
- **Found during:** Task 1 (running the unbounded-RDP form of the gate post-commit)
- **Issue:** `ansible/roles/desktop/handlers/main.yml` and `.../tasks/main.yml` carried stale prose: "RDP-11", "GNOME-over-RDP session (RDP-07)", "headless RDP connection". The canonical `\bRDP\b` gate passed on them, but the unbounded form (and the objective's "zero RDP residue" goal) flagged them. The desktop role is kept (not the removed xrdp role); the remote-desktop layer is Amazon DCV now.
- **Fix:** Comment-only relabel RDP→DCV/Amazon DCV (no functional change); YAML re-validated.
- **Files modified:** ansible/roles/desktop/handlers/main.yml, ansible/roles/desktop/tasks/main.yml
- **Commit:** e4d2ab2

## Coverage proof

The dcv-role pathspec is the ONLY path exemption. B1 (docs/) and B2 (secrets/defaults) residue live OUTSIDE the exempted path — they WOULD have been flagged had Waves 1-2 not fixed them. The just-fixed desktop-role comments are also outside the dcv exemption, demonstrating the gate catches real residue in kept roles.

## Self-Check: PASSED
- ansible/roles/desktop/{handlers,tasks}/main.yml modified — confirmed in commit e4d2ab2.
- Commit e4d2ab2 verified via `git rev-parse`.
- Both gate forms return empty post-fix.
