---
phase: quick-260611-jq2
plan: "01"
subsystem: ansible/roles/dcv
tags: [ansible, dcv, amazon-dcv, remote-desktop, systemd, pam]
dependency_graph:
  requires: [ansible/roles/desktop, ansible/roles/secrets]
  provides: [ansible/roles/dcv]
  affects: [ansible/playbook.yml, ansible/layer_config.yml]
tech_stack:
  added: [Amazon DCV 2025.0, NICE GPG key, dcv-virtual-session systemd unit]
  patterns: [role-defaults-handlers-templates, deferred-pin-sha256, PAM-reuse, oneshot-systemd-session]
key_files:
  created:
    - ansible/roles/dcv/defaults/main.yml
    - ansible/roles/dcv/tasks/main.yml
    - ansible/roles/dcv/handlers/main.yml
    - ansible/roles/dcv/templates/dcv.conf.j2
    - ansible/roles/dcv/templates/dcv-virtual-session.service.j2
  modified:
    - ansible/playbook.yml
    - ansible/layer_config.yml
decisions:
  - "Install DCV from AWS tarball (not AL2023 repos) pinned at 2025.0-20103"
  - "Reuse desktop role PAM password via assert — no new secret or SSM parameter"
  - "Headless virtual session via oneshot systemd unit After=dcvserver.service"
  - "dcv_tarball_sha256 left empty (deferred-pin, matches CLAUDE.md §9 posture)"
  - "No firewall changes — access via SSM port-forward of :8443"
metrics:
  duration_minutes: 20
  completed_date: "2026-06-11"
  tasks_completed: 3
  tasks_total: 3
  files_created: 5
  files_modified: 2
---

# Phase quick-260611-jq2 Plan 01: Amazon DCV Ansible Role Summary

**One-liner:** Amazon DCV 2025.0 role installing server/xdcv/web-viewer RPMs from the pinned AWS tarball with PAM auth reuse and a headless virtual session auto-started via systemd.

## What Was Built

Created the complete `ansible/roles/dcv/` Ansible role that installs and configures Amazon DCV server on the AL2023 devbox AMI, coexisting with the existing TigerVNC/noVNC stack.

The role:
- Imports the NICE GPG key before any RPM install
- Downloads the pinned DCV tarball (2025.0-20103) from the AWS CDN with optional sha256 checksum verification
- Installs exactly three RPMs: `nice-dcv-server`, `nice-xdcv`, `nice-dcv-web-viewer` (no gl/gltest)
- Configures `/etc/dcv/dcv.conf` with PAM system authentication and the templated web-port (8443)
- Installs and enables `dcv-virtual-session.service` — a oneshot systemd unit that creates a headless virtual DCV session for the dev user at boot
- Enables `dcvserver.service`
- Cleans up the downloaded tarball and extract directory

The role is wired into `ansible/playbook.yml` after `desktop` and before `hardening` (CI invariant preserved), gated on `layers.dcv and layers.desktop`. `dcv: true` added to `layer_config.yml`.

## Commits

| Task | Description | Commit |
|------|-------------|--------|
| 1 | dcv role scaffold — defaults, handlers, templates | df9f098 |
| 2 | dcv role tasks — GPG, download, install, config, session, cleanup | 67faeb3 |
| 3 | Wire dcv role into playbook.yml and layer_config.yml | 8538ef3 |

## Verification Results

- `ansible-playbook --syntax-check playbook.yml -e @layer_config.yml` PASSED
- Role layout complete: all 5 files present under `ansible/roles/dcv/`
- Last `- role:` in playbook.yml is `hardening` (CI invariant intact)
- `dcv: true` present in layer_config.yml after `desktop: true`
- `role: dcv` gated on `(layers.dcv | default(false)) and (layers.desktop | default(false))`
- VNC/noVNC stack (ansible/roles/desktop/) untouched — 0 diff lines
- No `changeme` introduced as a credential default anywhere in new files

## Deviations from Plan

None — plan executed exactly as written. The `!= "changeme"` comparison in the assert block follows the same pattern as `ansible/roles/desktop/tasks/main.yml` (pre-existing committed pattern).

## Known Stubs

- `dcv_tarball_sha256: ""` in `defaults/main.yml` — intentional deferred-pin, matching CLAUDE.md §9 posture. Pin after first bake by running `sha256sum` on the downloaded tarball and setting the variable in defaults.

## Threat Flags

None — no new network endpoints beyond the pre-planned DCV web port 8443, no new auth paths (reuses existing PAM stack), no new secrets introduced.

## Self-Check: PASSED

All 5 role files exist. All 3 task commits verified in git log. `ansible-playbook --syntax-check` exits 0. Hardening is last role. Desktop role untouched.
