# Phase 8 Discussion Log

**Date:** 2026-06-02
_Human-reference record of the discuss-phase session. Not consumed by downstream agents._

## Areas discussed

All four presented gray areas were selected and resolved in a single decision pass.

### Jupyter flavor + kernels
- **Options:** JupyterLab + Python-only / JupyterLab + multi-language kernels / Classic Notebook + Python-only
- **Chosen:** JupyterLab + Python kernel only
- **Note:** Multi-language kernels deferred (own phase).

### Python environment backing the kernel
- **Options:** Dedicated venv / system python interpreter
- **Chosen:** Dedicated venv (e.g. `/opt/jupyter`), isolated from system Python.

### TLS posture for :8888
- **Options:** Self-signed HTTPS mirroring code-server / plain HTTP behind CIDR gate
- **Chosen:** Self-signed HTTPS, `0.0.0.0:8888` — consistent with code-server's `cert: true`.

### mise activation breadth
- **Options:** system-wide /etc/profile.d / ec2-user bashrc only
- **Chosen:** system-wide /etc/profile.d (bash); zero tools pre-installed, no committed `.mise.toml`.

## Deferred ideas
- Multi-language Jupyter kernels.
- Committed `.mise.toml` with pinned tool versions.
- Migrating per-language layers to be mise-managed.

## Claude's discretion (noted in CONTEXT.md)
- Exact venv path, mise install method, version pins (must follow repo pinning invariants), cert source, notebook root dir.
