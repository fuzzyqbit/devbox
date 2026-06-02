---
phase: 08-jupyter-mise-ami-layer
plan: "03"
subsystem: secrets/ansible
tags: [jupyter, secrets, ansible, ssm, boot-oneshot, security]

dependency_graph:
  requires: ["08-02"]
  provides: ["08-04"]
  affects:
    - ansible/roles/secrets/

tech_stack:
  added: []
  patterns:
    - "in-memory secret generation via Ansible password lookup (no_log)"
    - "SSM SecureString publish (community.aws.ssm_parameter)"
    - "boot-time argon2 hash with sha256 FIPS fallback via /opt/jupyter venv"
    - "systemd Before= / After= ordering to enforce password-before-service"

key_files:
  modified:
    - ansible/roles/secrets/defaults/main.yml
    - ansible/roles/secrets/tasks/generate.yml
    - ansible/roles/secrets/tasks/publish.yml
    - ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2
    - ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2

decisions:
  - "Used /opt/jupyter/bin/python3 for hashing — consistent with Plan 02 venv contract; avoids system Python version uncertainty"
  - "Kept single combined empty-password guard covering all three SSM values (CS_PWD, VNC_PWD, JUPYTER_PWD) per PATTERNS.md guidance"
  - "Wrote mode 0700 for ~/.jupyter dir and mode 0600 for jupyter_server_config.py — tighter than code-server (0755/0600) matching T-08-08 threat mitigation"
  - "Argon2-first with sha256 fallback: handles FIPS environments where argon2 may be unavailable (Pitfall 5 from RESEARCH.md)"

metrics:
  duration: "4m"
  completed: "2026-06-02T19:24:46Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 5
---

# Phase 8 Plan 03: Jupyter Password Secret — Extend secrets Role Summary

**One-liner:** Per-build Jupyter cleartext generated in-memory via Ansible password lookup, published to SSM SecureString, and hashed at boot via `/opt/jupyter` venv into a 0600 `c.PasswordIdentityProvider.hashed_password` config with argon2/sha256-fallback and systemd ordering.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extend secrets defaults + generate + publish for jupyter_password | 4accbc8 | defaults/main.yml, tasks/generate.yml, tasks/publish.yml |
| 2 | Extend boot oneshot script + unit to inject hashed Jupyter password | 7ac23c4 | templates/devbox-secrets-bootstrap.sh.j2, templates/devbox-secrets-bootstrap.service.j2 |

## What Was Built

**Task 1 — Ansible-side (bake time):**

- `secrets/defaults/main.yml`: Added `secrets_jupyter_password_length: 32` and `secrets_ssm_jupyter_param: "{{ secrets_ssm_prefix }}/jupyter-password"`.
- `secrets/tasks/generate.yml`: Added `set_fact` to generate `jupyter_password` via `lookup('ansible.builtin.password', ...)` + `assert` verifying non-empty and not `"changeme"`. Both tasks carry `no_log: true`.
- `secrets/tasks/publish.yml`: Added `community.aws.ssm_parameter` task publishing `jupyter_password` as a SecureString to `/devbox/{{ devbox_user }}/jupyter-password` with `no_log: true`.

**Task 2 — Boot oneshot (runtime):**

- `devbox-secrets-bootstrap.sh.j2`: Four coordinated edits:
  1. Added `JUPYTER_PWD` SSM fetch after VNC fetch.
  2. Extended the combined empty-password guard to `|| -z "$JUPYTER_PWD"`.
  3. Added Jupyter hash block: argon2 via `/opt/jupyter/bin/python3`, unconditional sha256 fallback, empty-hash guard, `install -d -m 0700` for `~/.jupyter`, heredoc writing only `c.PasswordIdentityProvider.hashed_password` to `jupyter_server_config.py` (0600, ec2-user owned). No `.json` file written.
  4. Extended restart loop: `for svc in code-server.service vncserver.service novnc.service jupyter.service`.
- `devbox-secrets-bootstrap.service.j2`: Updated Description to mention JupyterLab; appended `jupyter.service` to `Before=`.

## Deviations from Plan

None — plan executed exactly as written. All four extension points in the bootstrap script were applied precisely at the documented locations. All `no_log: true` guards are in place.

## Known Stubs

None. The config written at boot is functional — `c.PasswordIdentityProvider.hashed_password` is the live key for jupyter-server 2.x password authentication.

## Threat Surface Scan

All security surfaces are within the plan's `<threat_model>`:

| Threat ID | Mitigation Applied |
|-----------|--------------------|
| T-08-07 | `no_log: true` on all three new Ansible tasks (set_fact, assert, ssm_parameter) |
| T-08-08 | `~/.jupyter` mode 0700, `jupyter_server_config.py` mode 0600, owned ec2-user |
| T-08-09 | Boot script writes only `.py`; comment warns against creating `.json` |
| T-08-10 | Unconditional sha256 fallback on hash failure; empty-hash guard exits non-zero |
| T-08-11 | `Before=...jupyter.service` in unit + Plan 02's `After=...bootstrap.service` |

No new threat surface introduced beyond the plan's threat register.

## Self-Check: PASSED

Files verified:
- FOUND: ansible/roles/secrets/defaults/main.yml
- FOUND: ansible/roles/secrets/tasks/generate.yml
- FOUND: ansible/roles/secrets/tasks/publish.yml
- FOUND: ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2
- FOUND: ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2

Commits verified:
- FOUND: 4accbc8 (feat(08-03): extend secrets role defaults + generate + publish for jupyter_password)
- FOUND: 7ac23c4 (feat(08-03): extend boot oneshot to inject hashed Jupyter password at first boot)
