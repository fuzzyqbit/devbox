---
status: partial
phase: 08-jupyter-mise-ami-layer
source: [08-VERIFICATION.md]
started: 2026-06-02T00:00:00Z
updated: 2026-06-02T00:00:00Z
---

## Current Test

[awaiting human testing — requires a live AMI bake: `DEVBOX_USER=$(whoami) ./run build` then `./run tf-apply && ./run start`]

## Tests

### 1. JupyterLab venv functional after bake
expected: On a freshly baked + running instance, `/opt/jupyter/bin/jupyter --version` succeeds and `/opt/jupyter/bin/jupyter kernelspec list` shows the `python3` kernel. Confirms `pip install jupyterlab==4.5.7 ipykernel==6.29.5` succeeds on AL2023 system Python 3.9 and kernel registration completed. Then `./run jupyter` launches it on `127.0.0.1:8888`; reach it via a `:8888` SSM port-forward.
result: [pending]

### 2. mise binary + shell activation after bake
expected: On a baked instance, `bash -l -c 'mise --version'` succeeds (login shell sources `/etc/profile.d/mise.sh`). Confirms the checksum-verified GitHub download (`cfac…4a84` for v2026.5.18 linux-x64) passed at bake time and system-wide activation works.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
