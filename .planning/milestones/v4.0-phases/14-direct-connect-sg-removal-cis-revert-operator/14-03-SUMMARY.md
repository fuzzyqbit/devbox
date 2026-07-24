---
phase: 14-direct-connect-sg-removal-cis-revert-operator
plan: 03
subsystem: ansible
tags: [xrdp-removal, cis-revert, dcv, hardening, secrets-bootstrap, destructive-cleanup]
requires:
  - "Phase 13 dcv role (install/config/virtual-session/cert/SELinux/bake-assert) — fills the playbook slot xrdp vacated"
  - "dcv role ships its own ansible/roles/dcv/files/45-allow-colord.rules (Assumption A3 confirmed)"
provides:
  - "xrdp role/wiring/toggle/test-xrdp/xorg.conf GONE from the bake (DCV-07)"
  - "CIS 2.2.1 reverted to vendored default true — single accepted Level-2 deviation closed (DCV-08)"
  - "post-hardening X-server regression guard RETARGETED to /usr/bin/Xdcv (loud bake failure if a bad CIS revert deletes the DCV X server)"
  - "secrets-bootstrap unit + script order/restart dcvserver.service (CRITICAL-1 from Phase 13 closed)"
affects:
  - "ansible/playbook.yml (role list + post_tasks guard)"
  - "ansible/roles/hardening/defaults/main.yml (CIS override removed)"
  - "ansible/roles/secrets (bootstrap unit/script/defaults comments)"
tech-stack:
  added: []
  patterns:
    - "post-hardening assert as regression net (retarget, not delete — research §1 Pitfall A)"
    - "parent-role CIS default revert by removing the override (returns to vendored true)"
key-files:
  created: []
  modified:
    - ansible/playbook.yml
    - ansible/layer_config.yml
    - ansible/roles/hardening/defaults/main.yml
    - ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2
    - ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2
    - ansible/roles/secrets/defaults/main.yml
  deleted:
    - ansible/roles/xrdp/ (12 files incl. vendored xorg.conf, xrdp-sesman.pam, xrdp(.|-sesman).service, 45-allow-colord.{pkla,rules}, sesman.ini.j2, startwm.sh.j2, xrdp.ini.j2)
    - ansible/test-xrdp.yml
decisions:
  - "Retargeted (NOT deleted) the post-hardening guard to /usr/bin/Xdcv gated on layers.dcv+desktop — converts a wrong CIS revert from a silent blank desktop into a loud, self-documenting bake failure (research §1 VERDICT)."
  - "Reverted CIS 2.2.1 in code now; runtime safety (repoquery --requires nice-xdcv + live render) is the Phase-15 UAT (DCV-11). Documented fallback in the guard fail_msg: re-add amzn2023cis_rule_2_2_1: false."
  - "Restart loop kept minimal (code-server.service dcvserver.service) — DCV authentication=system reads the live PAM password at connect, so no virtual-session restart on rotation (KISS/YAGNI, Assumption A4)."
  - "secrets-bootstrap fetches /devbox/<user>/desktop-password (NOT vnc-password as the 14-02 plan-prose verify strings assumed); the actual variable is secrets_desktop_password_length / secrets_ssm_desktop_param — preserved verbatim, only xrdp/RDP labels swapped to DCV."
metrics:
  duration: ~12m
  completed: 2026-06-19
---

# Phase 14 Plan 03: xrdp Removal + CIS 2.2.1 Revert + Xdcv Guard Retarget Summary

Tore the obsolete xrdp/xorgxrdp role and all its bake wiring out of the playbook, reverted the single accepted CIS Level-2 deviation (2.2.1), and retargeted the post-hardening X-server regression guard from the system `/usr/libexec/Xorg` to DCV's bundled `/usr/bin/Xdcv` — leaving the playbook fully consistent (no dangling `layers.xrdp`, Xorg, or dead-unit references), hardening still LAST, and the dcv role + the `desktop-password` SSM credential intact. Also folded in 14-02 Task 1's CRITICAL-1 secrets-bootstrap `xrdp → dcvserver` swap so no dead xrdp.service ordering/restart references survive.

## What Was Built

### DCV-07 — xrdp removal (Task 1)
- `git rm -r ansible/roles/xrdp/` — 12 files including the vendored `files/xorg.conf` (XDummy, xrdp-only; DCV virtual uses Xdcv), the xrdp PAM/systemd units, and `files/45-allow-colord.{pkla,rules}`. Safe because the Phase-13 dcv role ships its own `ansible/roles/dcv/files/45-allow-colord.rules` (confirmed present, untouched — Pitfall D resolved).
- `git rm ansible/test-xrdp.yml`.
- `ansible/playbook.yml`: deleted the `- role: xrdp` block + its `when:`/comment. Remaining order is `desktop → dcv → hardening`; **hardening stays last** (invariant grep-gate = 1, verified in the committed tree).
- `ansible/layer_config.yml`: removed the `# xrdp ...` comment + `xrdp: true`; `dcv: true` retained.

### DCV-08 — CIS 2.2.1 revert + guard retarget (Task 2)
- `ansible/roles/hardening/defaults/main.yml`: deleted the entire CIS-2.2.1 comment block + `amzn2023cis_rule_2_2_1: false`. The rule reverts to the vendored AMAZON2023-CIS default (`true`, removes `xorg-x11-server-common`). All other overrides (`amzn2023cis_rule_3_4_*`, journal, logrotate, AIDE) untouched (3_4_1_1 still present).
- `ansible/playbook.yml` post_tasks: **RETARGETED** the W1 guard (stat + assert) — `path: /usr/libexec/Xorg → /usr/bin/Xdcv`, `when:` gate `layers.xrdp → layers.dcv` (still AND `layers.desktop`), and reworded the explanatory comment + `fail_msg` to the DCV/Xdcv framing with the exact remediation (re-add the override / `rpm -qR nice-xdcv` at Phase-15 UAT). Structure preserved (stat → register → assert on `.stat.exists`).

### CRITICAL-1 — secrets-bootstrap xrdp → dcvserver (from 14-02 Task 1)
- `devbox-secrets-bootstrap.service.j2`: `Before=code-server.service xrdp.service xrdp-sesman.service → Before=code-server.service dcvserver.service`; Description `code-server / RDP → code-server / DCV`.
- `devbox-secrets-bootstrap.sh.j2`: restart loop `xrdp.service xrdp-sesman.service → dcvserver.service`; reworded the chpasswd comment + the restart-loop comment to DCV `authentication=system` framing. The `/devbox/$DEVBOX_USER/desktop-password` SSM fetch and `printf | chpasswd` logic are unchanged.
- `ansible/roles/secrets/defaults/main.yml`: relabelled the `secrets_desktop_password_length` comment (`xrdp`/`RDP` → DCV `authentication=system`); length value `20` unchanged.

## Verification

| Check | Result |
|-------|--------|
| hardening last (`tail -1` role line) | `1` (PASS) |
| `! test -d ansible/roles/xrdp` / `! test -f ansible/test-xrdp.yml` | both gone (PASS) |
| `\bxrdp\b` in playbook/layer_config/hardening-defaults/secrets/ | none (PASS) |
| guard retargeted: `/usr/bin/Xdcv` present | 4 hits; `/usr/libexec/Xorg` = 0 (PASS) |
| CIS override gone: `amzn2023cis_rule_2_2_1` | 0; `amzn2023cis_rule_3_4_1_1` = 1 (PASS) |
| dcv role + wiring intact | dir present; `role: dcv` = 1; `dcv: true` = 1 (PASS) |
| desktop-password credential intact | present in `secrets/` + `run` (PASS) |
| `Before=code-server.service dcvserver.service` / restart loop | both present (PASS) |
| `ansible-playbook --syntax-check playbook.yml` | parses clean (PASS) |
| `changeme` in changed files | none (PASS) |

## Deviations from Plan

### Auto-fixed / scope-clarified

**1. [Rule 3 - Blocking consistency] Relabelled `secrets/defaults/main.yml` comment to remove the last `xrdp` token in scope.**
- **Found during:** post-edit residue scan — the `<verify_before_commit>` gate `! grep -RnE '\bxrdp\b' ... ansible/roles/secrets/` would have failed on the `secrets_desktop_password_length` comment ("the credential xrdp authenticates against").
- **Fix:** comment-only relabel to DCV `authentication=system`; length value unchanged. This is 14-02 Task 1 part (d) (BLOCKER 2), in-scope for the secrets-bootstrap swap.
- **Commit:** caacb14

**Note on the 14-02 plan's `vnc-password` verify strings:** the 14-02 PLAN prose repeatedly references a `vnc-password` SSM param, but the actual tree uses `desktop-password` (`secrets_ssm_desktop_param`, `secrets_desktop_password_length`, `/devbox/<u>/desktop-password`). I preserved the real credential verbatim and only swapped xrdp/RDP labels — the objective's "desktop-password credential" is the authoritative identifier.

## Residual RDP/:3389 surface for the FOLLOW-UP pass (explicitly NOT touched here)

Per the objective, the operator-surface relabel and the SG/terraform/repo-wide gate are separate passes. The following xrdp/RDP/:3389/VNC residue remains for them:

- **`ansible/roles/secrets/tasks/publish.yml:39,42`** — task name + SSM param `description` still read "RDP/desktop login password". Label-only (no dead unit ref); belongs to the operator-surface relabel (14-02 Task 1 did not list publish.yml).
- **`run`** — `cmd_secrets_show` label `RDP login (ec2-user @ <host>:3389)` (run:470) + error string (run:462); `cmd_devbox_port_forward` `3389`/RDP examples (run:392-395), the invalid-port `_error` `3389` token (run:404); `cmd_help` (run:518,522). → 14-02 Task 2.
- **`scripts/devbox-start.sh:70,72`, `scripts/devbox-status.sh:54,61`** — RDP :3389 desktop banner + port-forward-3389 hints. → 14-02 Task 3.
- **`ansible/firewalld-docker-fix.yml:6`** — comment `(code-server :8080, RDP :3389)`. → 14-02 Task 3.
- **`CLAUDE.md`** (git-ignored) — multiple RDP/:3389/xrdp references + the §8 invariant note (CIS 2.2.1 now re-enabled). → 14-02 Task 3.
- **`terraform/`** — SG `:3389` ingress (main.tf:119-125) → drop + add `:8443` TCP+UDP; `rdp_endpoint` output → `dcv_endpoint`; variable/output descriptions. → 14-01 (SG) + outputs.
- **Repo-wide completeness gate (DCV-09)** — the §6 `git grep` battery (xrdp/xorgxrdp/3389/VNC/noVNC/6080, allowlisting `vnc-password`/`VNC_PWD`) → 14-04/14-05.

## Carried to Phase 15 (note only)
- Independent proof the CIS revert is safe: `repoquery --requires nice-xdcv | grep -i xorg-x11-server-common` + `rpm -qR nice-xdcv` on a baked box, plus the live render/AVC/FIPS/license/QUIC checks (DCV-11). At bake time the retargeted `/usr/bin/Xdcv` stat is the proof-by-survival; documented fallback if it fires is re-adding `amzn2023cis_rule_2_2_1: false`.

## Commits
- `caacb14` — refactor(14): remove xrdp role + wiring, revert CIS 2.2.1, retarget X guard to Xdcv (DCV-07/08)

## Self-Check: PASSED
- File `14-03-SUMMARY.md` created at `.planning/phases/14-direct-connect-sg-removal-cis-revert-operator/`.
- Commit `caacb14` present in git history (`git rev-parse --short caacb14` → caacb14).
- Committed playbook tail confirms `desktop → dcv → hardening` (hardening last).
