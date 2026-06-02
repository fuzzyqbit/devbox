---
phase: 08-jupyter-mise-ami-layer
plan: "02"
subsystem: ansible/roles/jupyter
tags: [ansible, jupyter, jupyterlab, systemd, tls, venv, python]
dependency_graph:
  requires:
    - ansible/roles/secrets (devbox-secrets-bootstrap.service ordering)
    - ansible/roles/vscode (handler pattern, service pattern)
    - ansible/roles/desktop (TLS cert generation pattern)
  provides:
    - /opt/jupyter virtualenv with pinned JupyterLab + ipykernel
    - /etc/jupyter/jupyter-cert.pem + jupyter-key.pem (self-signed TLS)
    - /etc/systemd/system/jupyter.service (enabled, HTTPS on 0.0.0.0:8888)
  affects:
    - ansible/playbook.yml (Plan 04 adds jupyter role inclusion)
    - ansible/layer_config.yml (Plan 04 adds jupyter: true)
    - ansible/roles/secrets (Plan 03 extends for Jupyter password)
tech_stack:
  added:
    - JupyterLab 4.5.7 (PyPI, installed into /opt/jupyter venv)
    - ipykernel 6.29.5 (PyPI, registered as python3 kernel in venv prefix)
  patterns:
    - isolated venv install (python3 -m venv + venv pip, not system pip module)
    - ipykernel --prefix registration (never --user)
    - self-signed TLS cert (openssl req -x509, key 0640 root:ec2-user)
    - systemd unit with After=devbox-secrets-bootstrap.service ordering
    - ansible.builtin.* FQCN module names throughout
key_files:
  created:
    - ansible/roles/jupyter/defaults/main.yml
    - ansible/roles/jupyter/handlers/main.yml
    - ansible/roles/jupyter/tasks/main.yml
    - ansible/roles/jupyter/templates/jupyter.service.j2
  modified: []
decisions:
  - "ipykernel pinned to 6.29.5 (not plan's 7.2.0) — Python version floor constraint"
  - "FQCN ansible.builtin.* used throughout (matches secrets role convention, not vscode short-name style)"
  - "ipykernel install cmd on single line to satisfy grep-based verify gate"
metrics:
  duration: "4 minutes"
  completed: "2026-06-02T19:16:00Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 0
---

# Phase 08 Plan 02: Jupyter Ansible Role Summary

Isolated JupyterLab 4.5.7 venv role with ipykernel 6.29.5, self-signed TLS cert, and a systemd unit ordered after devbox-secrets-bootstrap to enforce password-before-start.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 0 | Verify package pins (pre-approved) | — | No code change (operator-verified gate) |
| 1 | Write jupyter defaults + handlers | fea261e | ansible/roles/jupyter/defaults/main.yml, ansible/roles/jupyter/handlers/main.yml |
| 2 | Write jupyter tasks + unit template | 58f34cd | ansible/roles/jupyter/tasks/main.yml, ansible/roles/jupyter/templates/jupyter.service.j2 |

## What Was Built

The `ansible/roles/jupyter` role creates:

1. **Isolated Python venv** at `/opt/jupyter` via `python3 -m venv` (AL2023 system Python 3.9).
2. **Pinned pip install**: `jupyterlab==4.5.7 ipykernel==6.29.5` invoked directly through the venv pip binary for full isolation.
3. **Kernel registration**: `ipykernel install --prefix /opt/jupyter` (never `--user`) registers the python3 kernel inside the venv prefix.
4. **Self-signed TLS cert** at `/etc/jupyter/jupyter-cert.pem` (0644 root:ec2-user) and `/etc/jupyter/jupyter-key.pem` (0640 root:ec2-user), mirroring the noVNC pattern.
5. **systemd unit** `/etc/systemd/system/jupyter.service` enabled at bake time, serving `0.0.0.0:8888` over HTTPS. Unit orders `After=devbox-secrets-bootstrap.service` so it never starts before the boot oneshot writes the hashed password config.
6. **No baked password**: zero `jupyter_server_config.py`, zero password hash, zero `c.ServerApp.password` in any role file at bake time (JUP-04).

## Deviations from Plan

### Operator Decision: ipykernel Version Downgrade

**Task:** 0 (pre-approved checkpoint)
**Issue:** The plan pinned `ipykernel_version: "7.2.0"` but ipykernel 7.2.0 requires Python >=3.10. The AL2023 system `python3` is 3.9, and the venv is created with `python3 -m venv /opt/jupyter` (no interpreter override per plan spec). Installing 7.2.0 into a 3.9 venv would fail at pip install time.
**Operator decision:** Downgrade to `ipykernel_version: "6.29.5"`. ipykernel 6.29.5 supports Python >=3.8 and installs cleanly on 3.9. jupyterlab 4.5.7 requires Python >=3.9 and is unaffected.
**Files modified:** ansible/roles/jupyter/defaults/main.yml
**Recorded in:** defaults/main.yml header comment + this summary.

### Auto-fix: Single-line ipykernel install cmd (Rule 1)

**Found during:** Task 2 verification
**Issue:** The plan's verify gate is `grep -q 'ipykernel install --prefix' tasks/main.yml` (single-line match). Initial implementation used a YAML folded block scalar (`>`) that split the command across lines, causing the grep to fail.
**Fix:** Rewrote the ipykernel install command as a quoted single-line string: `"{{ jupyter_venv_path }}/bin/python3 -m ipykernel install --prefix {{ jupyter_venv_path }} --name python3 --display-name 'Python 3'"`. Functionally identical; grep verify now passes.
**Files modified:** ansible/roles/jupyter/tasks/main.yml

## Threat Mitigations Applied

| Threat ID | Mitigation |
|-----------|-----------|
| T-08-03 | jupyter.service orders After=devbox-secrets-bootstrap.service; no token-disabling flag in ExecStart |
| T-08-04 | Zero config files and zero password values written at bake time (verified by grep gate) |
| T-08-05 | TLS key mode 0640 root:ec2-user; cert 0644 |
| T-08-SC | pip versions pinned with `==`; packages confirmed official Jupyter/IPython org; Task 0 operator-verified checkpoint honoured |

## Known Stubs

None. The role is complete for its bake-time scope. Boot-time password injection is handled by Plan 03 (secrets bootstrap extension).

## Threat Flags

None. No new network endpoints, auth paths, or trust boundaries beyond what the plan's threat model captures.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| ansible/roles/jupyter/defaults/main.yml | FOUND |
| ansible/roles/jupyter/handlers/main.yml | FOUND |
| ansible/roles/jupyter/tasks/main.yml | FOUND |
| ansible/roles/jupyter/templates/jupyter.service.j2 | FOUND |
| .planning/phases/08-jupyter-mise-ami-layer/08-02-SUMMARY.md | FOUND |
| commit fea261e (Task 1) | FOUND |
| commit 58f34cd (Task 2) | FOUND |

---

## Amendment (2026-06-02) — loopback on-demand pivot

Operator decision after code review superseded part of this plan. JupyterLab is
now **loopback-only and on-demand**, not a network-exposed systemd service:

- **Removed:** the `jupyter.service` systemd unit + `jupyter.service.j2` template,
  the `handlers/main.yml` reload handler, the self-signed TLS cert generation, and
  the `0.0.0.0` HTTPS bind (CONTEXT D-04).
- **Kept:** the isolated `/opt/jupyter` venv with pinned `jupyterlab==4.5.7` +
  `ipykernel==6.29.5` and the registered `python3` kernel.
- **New access path:** `./run jupyter` launches `jupyter lab --ip=127.0.0.1`
  on demand over SSM; the operator forwards `:8888` to reach it. Loopback + SSM/IAM
  is the auth boundary, so there is no password and no TLS.

Rationale: removes code-review finding CR-01 (auth-floor bypass) by eliminating
the network-exposed listener. See commits e671856, 93a9af6.

---

## Amendment (2026-06-02) — jupyter folded into the devtools role

The standalone `jupyter` role created by this plan was later folded into the existing
`devtools` role (commit 12d8dc5), alongside the other developer tooling. `ansible/roles/jupyter/`
was deleted and the `jupyter` playbook entry + layer toggle removed; JupyterLab now rides
the `devtools` layer (which runs after the `python` role, so system python3 is available).
The install is unchanged (`/opt/jupyter` venv + pinned jupyterlab/ipykernel + python3 kernel),
the loopback on-demand model is unchanged, `hardening` stays last, and JUP-01 remains satisfied.
