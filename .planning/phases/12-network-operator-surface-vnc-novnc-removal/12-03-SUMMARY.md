---
phase: 12-network-operator-surface-vnc-novnc-removal
plan: 03
subsystem: infra
tags: [ansible, vnc, novnc, tigervnc, xrdp, systemd, gnome, secrets, ssm, removal]

# Dependency graph
requires:
  - phase: 11-xrdp-remote-desktop
    provides: "xorgxrdp/Xorg backend (xrdp.service + xrdp-sesman.service), /etc/pam.d/xrdp-sesman PAM stack, startwm.sh session launcher — the RDP path that makes the VNC/noVNC stack redundant"
  - phase: 12-network-operator-surface-vnc-novnc-removal/12-01
    provides: "Terraform SG :3389 ingress + :6080 noVNC scrub; vnc-password SSM path retained as the RDP credential"
  - phase: 12-network-operator-surface-vnc-novnc-removal/12-02
    provides: "operator surface (./run, scripts, CLAUDE.md) pointed at native RDP-over-SSM :3389"
provides:
  - "desktop Ansible role with the entire VNC/noVNC stack removed (tigervnc-server, /etc/pam.d/vnc, VNC xstartup, ~/.vnc, the noVNC tarball/cert install, both systemd units, VNC defaults, the dead reload-systemd handler)"
  - "GNOME (@Desktop/gnome-shell/gnome-session) + dejavu fonts + mesa + ffmpeg + VLC + dconf lock-disable all intact (surviving features)"
  - "secrets bootstrap pointed at the RDP path: both baked artifacts (.sh.j2 restart loop + .service.j2 Before=/Description) name xrdp.service/xrdp-sesman.service, not the deleted vnc/novnc units"
  - "the RDP-login credential pipeline (generate desktop_vnc_password -> publish /devbox/<user>/vnc-password -> bootstrap fetch + chpasswd) fully retained, VNC labels reworded to RDP"
affects: [12-04, RDP-12, RDP-14, milestone-close-bake]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Surgical list-item removal: drop one package from a shared dnf list without touching siblings or the task"
    - "Relabel-not-rename: the vnc-password SSM param IS the RDP login password; human-facing labels change, the path/fact never does (locked credential model)"
    - "Baked-artifact twin maintenance: the .sh.j2 (script) and .service.j2 (systemd unit) are both rendered into the AMI, so a unit-name swap must be applied to both"

key-files:
  created: []
  modified:
    - ansible/roles/desktop/tasks/main.yml
    - ansible/roles/desktop/defaults/main.yml
    - ansible/roles/desktop/handlers/main.yml
    - ansible/roles/secrets/tasks/publish.yml
    - ansible/roles/secrets/defaults/main.yml
    - ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2
    - ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2
  deleted:
    - ansible/roles/desktop/templates/vncserver.service.j2
    - ansible/roles/desktop/templates/novnc.service.j2
    - ansible/roles/desktop/templates/xstartup.j2

key-decisions:
  - "Deleted (not kept) the bake-time D4 user-password task and the D1 desktop_vnc_password assert: the boot bootstrap is the authoritative runtime setter (chpasswd before first RDP login, research A1) and the assert is duplicated in the secrets role; removing D1 also clears one of three pre-existing no-changeme false-positives."
  - "Deleted python3-pip with the noVNC block: no surviving desktop task uses pip after websockify is gone (zero noVNC tasks may remain per the plan)."
  - "Deleted the reload-systemd handler entirely: it was notified only by the removed VNC/noVNC unit-install tasks; no surviving desktop task notifies a handler (research A2 verified)."
  - "Retained the vnc-password SSM param path, the desktop_vnc_password fact, generate/publish/fetch/chpasswd — it is the RDP/PAM login password (locked credential model), not a VNC orphan; only labels reworded."
  - "Applied the unit-name swap to BOTH baked bootstrap artifacts (.sh.j2 restart loop S6 AND .service.j2 Before=/Description S7 — the blocker the plan flagged) so no dead vnc/novnc unit name ships in the AMI."

patterns-established:
  - "Surgical dnf list-item removal proven by paired acceptance (remove tigervnc-server; positively grep gnome-shell/gnome-session/mesa/fonts survive)"
  - "Every irreversible removal-proof (! grep / ! test) paired with a surviving-feature positive check"

requirements-completed: [RDP-11]

# Metrics
duration: 9min
completed: 2026-06-16
---

# Phase 12 Plan 03: VNC/noVNC Stack Removal (RDP-11) Summary

**Surgically excised the entire VNC/noVNC stack (tigervnc-server, /etc/pam.d/vnc, VNC xstartup, ~/.vnc, the noVNC tarball+cert install, both systemd units + their templates, the VNC defaults, and the dead reload-systemd handler) from the desktop role, and swapped both baked secrets-bootstrap artifacts onto xrdp/xrdp-sesman — while keeping GNOME/fonts/mesa/ffmpeg/VLC and the entire RDP-login credential pipeline fully intact.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-06-16T02:30Z
- **Completed:** 2026-06-16T02:39Z
- **Tasks:** 2
- **Files modified:** 7 (+ 3 deleted templates)

## Accomplishments
- Removed every functional VNC/noVNC artifact from `ansible/roles/desktop/` (verified: `! grep -rEqi 'tigervnc|vncserver|novnc|securitytypes|pam.d/vnc|xstartup|/etc/novnc|websockify|6080|5901'` returns no matches).
- Avoided the over-removal trap: `tigervnc-server` dropped as a single dnf list item; `gnome-shell`, `gnome-session`, `dejavu-sans-fonts`, `dejavu-sans-mono-fonts`, `mesa-dri-drivers`, the ffmpeg static-build block, the VLC flatpak block, and the dconf lock-disable tasks all positively confirmed present.
- Fixed the BLOCKER the plan flagged: the AMI-baked `devbox-secrets-bootstrap.service.j2` `Before=` ordering and `Description` no longer carry dead `vncserver.service`/`novnc.service` names — both swapped to `xrdp.service`/`xrdp-sesman.service`, mirroring the `.sh.j2` restart-loop swap.
- Kept the RDP-login credential pipeline whole: `desktop_vnc_password` generation/assert, the `/devbox/<user>/vnc-password` SSM publish + fetch, and the `chpasswd` apply are untouched; only VNC-flavoured comments/labels were reworded to RDP.

## Task Commits

Each task was committed atomically:

1. **Task 1: Excise VNC/noVNC from the desktop role (D1-D10, D16, D17, D13-D15)** - `eba3017` (refactor)
2. **Task 2: Relabel the secrets RDP-password pipeline + swap both baked bootstrap artifacts (S6 .sh.j2 + S7 .service.j2) to xrdp** - `73761ba` (refactor)

## Files Created/Modified
- `ansible/roles/desktop/tasks/main.yml` - GNOME + media-only role; deleted the D1 assert, the tigervnc-server line, the VNC config dir / TigerVNC PAM-password / `/etc/pam.d/vnc` / xstartup / vncserver-unit tasks, the entire noVNC block (python3-pip, websockify, tarball, cert, novnc-unit); reworded the dconf lock-disable comment to RDP/headless rationale; ffmpeg + VLC kept.
- `ansible/roles/desktop/defaults/main.yml` - dropped the 6 VNC/noVNC keys (`desktop_vnc_display/_port`, `desktop_novnc_port`, `desktop_vnc_resolution/_depth`, `desktop_novnc_version`); kept `dev_user`/`dev_home`.
- `ansible/roles/desktop/handlers/main.yml` - deleted the dead `reload systemd` handler (no surviving notifier); file is now a comment-only stub.
- `ansible/roles/desktop/templates/vncserver.service.j2` - DELETED (git rm).
- `ansible/roles/desktop/templates/novnc.service.j2` - DELETED (git rm).
- `ansible/roles/desktop/templates/xstartup.j2` - DELETED (git rm).
- `ansible/roles/secrets/tasks/publish.yml` - reworded the SSM publish task name + description from "VNC password" to "RDP/desktop login password"; `secrets_ssm_vnc_param` value unchanged.
- `ansible/roles/secrets/defaults/main.yml` - reworded the `secrets_vnc_password_length` comment ("TigerVNC SecurityTypes=Plain" -> "ec2-user RDP PAM login password"); param path `/devbox/<user>/vnc-password` retained.
- `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2` - reworded the chpasswd comment (drop `/etc/pam.d/vnc` -> `/etc/pam.d/xrdp-sesman`); FUNCTIONAL restart-loop swap `vncserver.service novnc.service` -> `xrdp.service xrdp-sesman.service` (S6). Fetch + chpasswd kept.
- `ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2` - FUNCTIONAL (S7, the blocker): `Before=` swapped the dead vnc/novnc units for `xrdp.service xrdp-sesman.service`; `Description` dropped "VNC" -> "RDP". This file is baked into the AMI via install-oneshot.yml:12-13.

## Decisions Made
- **Deleted D4 (bake-time user-password) and D1 (assert), not kept.** Research A1 confirms the boot bootstrap re-applies the same password via `chpasswd` before any RDP login, so the bake-time setter is redundant; the assert is duplicated in the surviving secrets role. Side effect: removing D1 cleared one of three pre-existing `no-changeme` hook false-positives (two legitimate `!= "changeme"` asserts remain in `secrets/tasks/generate.yml`, untouched).
- **Deleted `python3-pip`** with the noVNC block: it was added solely before `websockify` and no surviving desktop task uses pip; the plan requires zero noVNC tasks remaining.
- **Deleted the `reload systemd` handler entirely** rather than leaving a stub handler: it was notified only by the removed unit-install tasks (verified no surviving `notify:` in the role).
- **Retained the vnc-password param/fact/pipeline** (relabel-not-rename) — it is the RDP/PAM login password per the locked credential model; renaming would orphan in-flight AMIs for zero benefit.

## Deviations from Plan

None - plan executed exactly as written. All removals (D1-D17), the three template deletions (D13-D15), and both functional swaps (S6, S7) match the `<interfaces>` removal map. No Rule 1-4 deviations were required.

Note on plan frontmatter: the plan's top-level `files_modified` listed `xstartup.j2` (implying edit), but the authoritative `<interfaces>` D15 and the Task 1 verify gate require it DELETED. Followed the interfaces map + verify gate (deleted it) — no behavioral divergence.

## Issues Encountered
- **Executor-shell errexit quirk (not a code issue):** the harness aborts a Bash invocation when any command (including a `grep -q` returning 1 = "no match", which is the desired outcome for `! grep` removal-proofs) exits non-zero, truncating compound `&&`/`if` chains. Worked around by capturing greps into a variable with `|| true` and testing emptiness. All acceptance gates ultimately printed PASS. No change to the committed code.
- **`ansible-lint` rc=3** is the known-broken `.ansible-lint` config (`'parseable' was unexpected`, recorded in STATE.md "Operator Next Steps"), not a finding on these changes — CI is authoritative. The pre-commit hooks ran on both commits (no `--no-verify`) and passed.

## Known Stubs
None. This is a removal plan — no stubbed/placeholder data was introduced. `handlers/main.yml` is intentionally a comment-only file (no handlers needed after the unit-install tasks were removed); this is correct, not a stub.

## Tech Debt / Carried Forward
- **WR-05 (pre-existing):** `devbox-secrets-bootstrap.sh.j2` is outside the CI `shellcheck` glob, so the S6 restart-loop edit is not shellcheck-gated. The edit is a literal token swap inside an existing, unchanged loop body (the `list-unit-files` guard is untouched), so the risk is nil. Carried forward unchanged.

## Next Phase Readiness
- RDP-11 complete: no dead VNC config will ship in the next-baked AMI; both baked bootstrap artifacts target the RDP units; surviving features intact.
- RDP-12 (revert `ansible/novnc-plain-username-fix.yml` + its `playbook.yml` import) is the remaining destructive item for this phase — owned by a subsequent 12-xx plan, untouched here.
- hardening-stays-last invariant verified (grep-gate = 1); xrdp role untouched (Xorg backend `param=/usr/libexec/Xorg` intact); the RDP-password path is referenced end-to-end across `run`, `terraform/outputs.tf`, and the secrets role.
- Final RDP-14 live-bake UAT (the runtime proof that GNOME-over-RDP + the chpasswd login still work after removal) is the milestone-close gate, not a Phase-12 implementation task.

## Self-Check: PASSED

- Commit `eba3017` (Task 1) — FOUND in git
- Commit `73761ba` (Task 2) — FOUND in git
- All 7 modified files exist on disk; all 3 deleted templates confirmed gone
- Overall gates: hardening-still-last (grep-gate=1), xrdp Xorg backend intact, RDP-password path referenced end-to-end, GNOME+mesa survive the tigervnc removal — all PASS

---
*Phase: 12-network-operator-surface-vnc-novnc-removal*
*Completed: 2026-06-16*
