---
phase: 12-network-operator-surface-vnc-novnc-removal
plan: 04
subsystem: infra
tags: [ansible, xrdp, firewalld, novnc-removal, rdp, hardening-invariant]

# Dependency graph
requires:
  - phase: 12-network-operator-surface-vnc-novnc-removal (12-01)
    provides: EC2 SG :3389 ingress gated on var.allowed_web_cidrs (the perimeter this host-firewall task complements)
  - phase: 12-network-operator-surface-vnc-novnc-removal (12-03)
    provides: desktop-role VNC/noVNC stack excision + baked secrets-bootstrap RDP retargeting (the residue this plan's repo-wide gate backstops)
provides:
  - RDP-12 reverted — noVNC username-injection workaround playbook deleted and unimported
  - RDP-09-adjacent — idempotent host-firewalld :3389/tcp allow inside the xrdp role, safe under both container modes
  - RDP-11 phase-level sign-off — repo-wide completeness gate proves zero functional VNC/noVNC residue across ansible/ terraform/ run scripts/
  - stale noVNC/xstartup provenance comments scrubbed from the xrdp role
affects: [phase-12-verification, RDP-14-live-uat, milestone-v3.2-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Host-firewall robustness task lives INSIDE an existing pre-hardening role (xrdp), never as a new trailing role/import — preserves the hardening-stays-last invariant (Pitfall 5)"
    - "Idempotent firewall-cmd via command module: --state guard (failed_when:false) + --query-port skip + --permanent/runtime add + conditional --reload — no community.general dependency, mirrors firewalld-docker-fix.yml + the role's semanage approach"
    - "Phase-level repo-wide completeness grep as the final acceptance of the last Wave-2 plan — backstops the subtree-scoped per-plan greps that let the baked-AMI .service.j2 residue hide"

key-files:
  created: []
  modified:
    - ansible/playbook.yml (dropped novnc-plain-username-fix import + FIXME block; firewalld-docker-fix import kept; hardening still last)
    - ansible/firewalld-docker-fix.yml (comment reworded: noVNC :6080 -> code-server :8080, RDP :3389)
    - ansible/roles/xrdp/tasks/main.yml (added guarded idempotent firewalld :3389/tcp task; scrubbed line ~199 noVNC TLS-cert provenance comment)
    - ansible/roles/xrdp/templates/startwm.sh.j2 (scrubbed line 2 dead xstartup.j2 provenance pointer)
  deleted:
    - ansible/novnc-plain-username-fix.yml (86-LOC noVNC VeNCrypt-Plain username-injection workaround, commit 29de35b)

key-decisions:
  - "RDP-09-adjacent host-firewall task added (not deferred): the research flagged it as a planner decision (Q1/A3); chose the ~5-line idempotent xrdp-role task over a documented caveat because the containers:false bake would otherwise silently drop :3389 (11-VERIFICATION:66) and 11-03 SUMMARY explicitly assigned the :3389 firewalld allow to Phase 12."
  - "Firewall rule added to the DEFAULT zone (not a named zone): under containers:true the default is `docker` (target=ACCEPT, harmless belt-and-braces); under containers:false it is `public` (target=DROP, where the add is load-bearing). Targeting the default zone covers both modes with one task."
  - "Command-only firewall-cmd (no community.general firewalld module): keeps parity with firewalld-docker-fix.yml and this role's existing semanage command-only approach; no new collection/package dependency (airgap-safe — firewalld already installed for CIS scans)."
  - "Stale noVNC/xstartup provenance comments scrubbed rather than allowlisted: rewording tasks:199 + startwm:2 keeps the phase-level repo-wide grep clean with no allowlist entries for noVNC/xstartup tokens."

patterns-established:
  - "Pre-hardening robustness-task placement: any host-posture task that hardening might re-tighten goes inside a role already ordered before hardening, never as a new trailing role/import."
  - "Negated-grep verification under an errexit harness: count-based grep (grep -c) and pipe-to-cat instead of `! grep -q` chains, so a desired no-match (rc 1) does not abort the gate."

requirements-completed: [RDP-12, RDP-09, RDP-11]

# Metrics
duration: ~6min
completed: 2026-06-16
---

# Phase 12 Plan 04: noVNC Workaround Revert + Host-Firewalld :3389 + RDP-11 Completeness Gate Summary

**Reverted the noVNC VeNCrypt-Plain username-injection workaround (RDP-12), closed the `containers:false` host-firewall edge case with an idempotent, guarded firewalld :3389/tcp allow inside the xrdp role (RDP-09-adjacent), scrubbed the last stale noVNC/xstartup comments, and signed off the milestone's VNC/noVNC removal with a green repo-wide RDP-11 completeness gate.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-06-16T02:27Z (approx)
- **Completed:** 2026-06-16T02:34Z
- **Tasks:** 2 completed
- **Files modified:** 4 modified + 1 deleted

## Accomplishments

### Task 1 — RDP-12 revert + RDP-11 W3 comment scrubs (commit `dee1121`)

- `git rm ansible/novnc-plain-username-fix.yml` — deleted the entire 86-LOC noVNC username-injection workaround (introduced by commit `29de35b`). The workaround pre-filled the constant `ec2-user` username into the served noVNC client; with noVNC gone (12-03) it is dead.
- Dropped its `- import_playbook: novnc-plain-username-fix.yml` line + the FIXME comment block from `ansible/playbook.yml`. The `firewalld-docker-fix.yml` import directly above it is KEPT intact.
- Reworded `ansible/firewalld-docker-fix.yml:6` — `(noVNC :6080, code-server :8080)` → `(code-server :8080, RDP :3389)`. Comment-only; the play body (sets default zone to docker) is unchanged.
- Scrubbed two stale provenance comments that pointed at files 12-03 deleted and whose tokens would trip the repo-wide gate:
  - `ansible/roles/xrdp/tasks/main.yml:199` — `--- TLS cert (RDP-04) — mirrors the desktop role noVNC openssl pattern ---` → `--- TLS cert (RDP-04) — self-signed cert pattern ---`.
  - `ansible/roles/xrdp/templates/startwm.sh.j2:2` — dead `# Source: ansible/roles/desktop/templates/xstartup.j2 ...` pointer → `# GNOME Xorg session launcher for xrdp (Phase 11 RDP-07).` The script body (`unset SESSION_MANAGER`, `XDG_SESSION_TYPE=x11`, the GNOME launch) is untouched.

### Task 2 — host firewalld :3389/tcp + phase-level RDP-11 completeness gate (commit `33c757d`)

- Added a four-task idempotent, guarded firewalld block to `ansible/roles/xrdp/tasks/main.yml` (after the service-enable tasks, before the SELinux fcontext section — well before hardening):
  1. `firewall-cmd --state` with `failed_when: false` — a host WITHOUT firewalld no-ops rather than aborting the bake.
  2. `firewall-cmd --query-port=3389/tcp` (gated on firewalld running) — idempotency probe.
  3. `firewall-cmd --permanent --add-port=3389/tcp` + runtime add — only when firewalld is running AND :3389 not already allowed.
  4. `firewall-cmd --reload` — only when the add actually changed.
- Adds to the DEFAULT zone, covering BOTH container modes: `docker` zone (containers:true, already permissive) and `public` zone (containers:false, where this is load-bearing — the 11-VERIFICATION:66 edge case).
- Command-only (no community.general dependency); mirrors `firewalld-docker-fix.yml`'s firewall-cmd style and the role's existing semanage approach. No new package — firewalld is already installed by the CIS/firewalld-docker-fix path (airgap-safe).
- Task lives INSIDE the xrdp role (Pitfall 5) — the hardening-stays-last grep-gate still prints `1`.

## Phase-Level RDP-11 Completeness Gate (sign-off)

This was the LAST Wave-2 plan, so the authoritative repo-wide grep ran as the final acceptance criterion. It is the backstop the subtree-scoped per-plan greps cannot provide (exactly how the baked-AMI `.service.j2` residue hid from per-plan checks).

Command and result:

```
$ git grep -nE 'tigervnc|vncserver|novnc|pam\.d/vnc|SecurityTypes|6080|5901|websockify|xstartup' \
    -- ansible/ terraform/ run scripts/ | grep -vE 'vnc-password|vnc_param|!= .changeme.'
(empty — exit 1, no matches)
```

The RAW grep (before the allowlist filter) also returned nothing across `ansible/ terraform/ run scripts/` — the deliberately-kept `vnc-password` credential identifiers contain none of the matched tokens, so they never even appeared. **Zero functional VNC/noVNC residue remains.** RDP-11 is complete milestone-wide.

## Verification

| Check | Result |
|-------|--------|
| `! test -f ansible/novnc-plain-username-fix.yml` (RDP-12) | PASS (absent) |
| `! grep -q novnc-plain-username-fix ansible/playbook.yml` (import dropped) | PASS (0 matches) |
| `! grep -Eqi '6080\|novnc' ansible/firewalld-docker-fix.yml` | PASS (0 matches) |
| `! grep -qi novnc ansible/roles/xrdp/tasks/main.yml` | PASS (0 matches) |
| `! grep -q xstartup ansible/roles/xrdp/templates/startwm.sh.j2` | PASS (0 matches) |
| `grep -q firewalld-docker-fix ansible/playbook.yml` (kept) | PASS (2 matches) |
| hardening-last grep-gate `== 1` | PASS (1) |
| `grep -q 3389 ansible/roles/xrdp/tasks/main.yml` + firewall guard | PASS (3389 + firewall-cmd --state present) |
| `grep -q 'param=/usr/libexec/Xorg' sesman.ini.j2` (Xorg backend intact) | PASS |
| `grep -q 'name: xrdp' xrdp/tasks/main.yml` (service enables intact) | PASS |
| startwm body `XDG_SESSION_TYPE=x11` intact | PASS |
| YAML parse (playbook, firewalld-docker-fix, xrdp tasks) | PASS (all OK) |
| `git diff --cached` for new `changeme` lines | PASS (0) |
| **PHASE-LEVEL RDP-11 repo-wide completeness gate** | **GREEN (empty)** |
| `ansible-lint ansible/playbook.yml` | rc=3 — known-broken `.ansible-lint` config (`'parseable' was unexpected`); CI authoritative (per STATE.md). NOT a finding against these changes. |

## Deviations from Plan

None — plan executed exactly as written. Both tasks' automated verify gates printed PASS; the firewall task landed inside the xrdp role (no new trailing role/import); the hardening-stays-last invariant held at every step.

**Harness note (not a deviation):** the executor shell runs with errexit, which aborts on the desired no-match (`grep` rc 1) of the plan's `! grep -q` acceptance chains. Verification was run with count-based grep (`grep -c`) and pipe-to-`cat` so a no-match does not abort the gate — same workaround recorded for 12-02/12-03. The Task 2 commit message was passed via `git commit -F <file>` because the harness's quoting layer choked on an apostrophe inside the inline heredoc.

## Known Stubs

None. No placeholder/empty-value patterns introduced — all changes are deletions, comment scrubs, and a functional firewall task.

## Self-Check: PASSED

- `12-04-SUMMARY.md` — FOUND
- commit `dee1121` (Task 1, RDP-12 revert + comment scrubs) — FOUND
- commit `33c757d` (Task 2, host firewalld :3389 + RDP-11 gate) — FOUND
- `ansible/novnc-plain-username-fix.yml` — confirmed absent (deleted as expected)
