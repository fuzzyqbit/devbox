---
phase: 08-jupyter-mise-ami-layer
verified: 2026-06-02T00:00:00Z
status: human_needed
score: 5/5
overrides_applied: 0
human_verification:
  - test: "Bake the AMI and run: /opt/jupyter/bin/jupyter --version"
    expected: "Command succeeds and prints a JupyterLab 4.x version string; kernel list includes python3"
    why_human: "Static analysis confirms the venv install tasks are correct, but only a live bake can confirm the pip install and ipykernel registration actually succeed on AL2023's Python 3.9"
  - test: "On a baked instance, run: source /etc/profile.d/mise.sh && mise --version"
    expected: "Prints mise 2026.5.18 or similar; no error; command succeeds"
    why_human: "The profile.d activation hook and binary are structurally correct, but the checksum and binary download can only be confirmed against the live GitHub release endpoint during a real bake"
---

# Phase 8: Jupyter + mise AMI Layer — Verification Report

**Phase Goal:** The baked AMI ships JupyterLab in an isolated /opt/jupyter venv, launchable on demand bound to loopback (127.0.0.1:8888) via `./run jupyter` over SSM — no systemd service, no password, no TLS (SSM/IAM is the auth boundary) — and ships the mise binary ready for ec2-user.
**Verified:** 2026-06-02
**Status:** human_needed — all static checks pass; two items require a live AMI bake to confirm
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | /opt/jupyter venv with pinned JupyterLab + registered python3 kernel; /opt/jupyter/bin/jupyter --version succeeds | VERIFIED (static) | `ansible/roles/jupyter/tasks/main.yml`: creates venv at `{{ jupyter_venv_path }}` (`/opt/jupyter`), installs `jupyterlab==4.5.7 ipykernel==6.29.5`, registers kernel via `ipykernel install --prefix /opt/jupyter`. All three `creates:` guards present. Runtime confirmation requires live bake — see Human Verification. |
| 2 | JupyterLab launched on demand via `./run jupyter`, binds 127.0.0.1 only, NOT a systemd service | VERIFIED | `scripts/devbox-jupyter.sh` runs `jupyter lab --ip=127.0.0.1 --port=8888 --no-browser`; `./run` dispatcher wires `jupyter)` → `cmd_jupyter()` → the script (run:521); no `jupyter.service` file exists anywhere in the tracked tree (`git ls-files | grep jupyter.service` returns empty). |
| 3 | No Jupyter password, no SSM jupyter-password param, no TLS cert, no 0.0.0.0 listener | VERIFIED | `ansible/roles/secrets/tasks/generate.yml` and `publish.yml` contain zero Jupyter references; `devbox-secrets-bootstrap.sh.j2` contains no `JUPYTER_PWD` and no `jupyter.service` in its restart loop; `ansible/roles/jupyter/` contains only `defaults/` and `tasks/` (no `templates/` with a service or TLS cert); commit 988115a explicitly reverted all password machinery; commit e671856 removed systemd unit and TLS. |
| 4 | mise --version works for ec2-user in a new login shell; no .mise.toml committed; Python/Go/Rust/Java/Node Ansible layers unmodified | VERIFIED | `ansible/roles/mise/tasks/main.yml` installs checksum-verified binary to `/usr/local/bin/mise` and writes `eval "$(mise activate bash)"` to `/etc/profile.d/mise.sh`; no `.mise.toml` exists in the tree (grep-gate 10 passes); language role dirs (python, golang, rust, java) show no Phase 8 commits (`git log` confirms unchanged since initial commit). Runtime `mise --version` confirmation requires live bake — see Human Verification. |
| 5 | hardening is the last role in ansible/playbook.yml; CI grep-gates mirror the invariant | VERIFIED | `grep -E '^[[:space:]]*-[[:space:]]*role:' ansible/playbook.yml | tail -1` returns `- role: hardening  # MUST remain last — invariant (JUP-08 / CLAUDE.md §8)` — grep-gate assertion passes. `.github/workflows/ci.yml` invariant 9 (lines 231–237) and `.pre-commit-config.yaml` invariant 9 mirror the same assertion. |

**Score:** 5/5 truths verified (two require live-bake confirmation)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `ansible/roles/jupyter/defaults/main.yml` | JupyterLab + ipykernel version pins, venv path | VERIFIED | `jupyterlab_version: "4.5.7"`, `ipykernel_version: "6.29.5"`, `jupyter_venv_path: /opt/jupyter` |
| `ansible/roles/jupyter/tasks/main.yml` | venv create, pip install, kernel register; no systemd, no TLS | VERIFIED | 4 tasks: venv create, pip upgrade, jupyterlab+ipykernel install, kernel register. No service/cert tasks. Header comment confirms loopback-only design. |
| `ansible/roles/mise/defaults/main.yml` | Pinned version + SHA-256 checksum | VERIFIED | `mise_version: "2026.5.18"`, `mise_checksum_sha256: "cfac593...a84"` (64-char SHA-256), `mise_install_dir: /usr/local/bin` |
| `ansible/roles/mise/tasks/main.yml` | get_url with checksum + /etc/profile.d activation | VERIFIED | `ansible.builtin.get_url` with `checksum: "sha256:{{ mise_checksum_sha256 }}"`, `ansible.builtin.copy` writes `eval "$(mise activate bash)"` to `/etc/profile.d/mise.sh` |
| `scripts/devbox-jupyter.sh` | SSM on-demand launcher, --ip=127.0.0.1, no 0.0.0.0 | VERIFIED | `exec aws ssm start-session ... --parameters "{\"command\":[\"${JUPYTER_VENV}/bin/jupyter lab --ip=127.0.0.1 --port=8888 --no-browser ...]}"`. Seven references to `127.0.0.1`; none to `0.0.0.0`. |
| `ansible/playbook.yml` | jupyter + mise before hardening; hardening last | VERIFIED | Lines 59/62/65: `role: jupyter`, `role: mise`, `role: hardening` in that order. Grep-gate confirmed. |
| `ansible/layer_config.yml` | jupyter: true + mise: true | VERIFIED | Both toggles present, ordered before `hardening: true`. |
| `.pre-commit-config.yaml` | Invariants 9 (hardening-last) + 10 (no .mise.toml) | VERIFIED | grep-gate hook extended with two chained assertions; both assertions match CI wording exactly. |
| `.github/workflows/ci.yml` | CI invariants 9 + 10; header updated | VERIFIED | Lines 231–243 contain both invariants; header comment at lines 24–25 names them. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `./run` | `scripts/devbox-jupyter.sh` | `cmd_jupyter()` at run:372, dispatcher at run:521 | WIRED | `run:521: jupyter) cmd_jupyter "$@";;` — wired and dispatched |
| `scripts/devbox-jupyter.sh` | EC2 instance via SSM | `aws ssm start-session --document-name AWS-StartInteractiveCommand` | WIRED | Uses `AWS-StartInteractiveCommand` with inline command; binds `--ip=127.0.0.1` |
| `ansible/playbook.yml` | `ansible/roles/jupyter/` | `- role: jupyter when: layers.jupyter \| default(false)` | WIRED | Line 59–60; `layer_config.yml` has `jupyter: true` |
| `ansible/playbook.yml` | `ansible/roles/mise/` | `- role: mise when: layers.mise \| default(false)` | WIRED | Line 62–63; `layer_config.yml` has `mise: true` |
| `ansible/roles/jupyter/tasks/main.yml` | `ansible/roles/jupyter/defaults/main.yml` | `{{ jupyterlab_version }}`, `{{ ipykernel_version }}`, `{{ jupyter_venv_path }}` | WIRED | All three variables referenced in tasks; defaults file provides values |
| `ansible/roles/mise/tasks/main.yml` | `ansible/roles/mise/defaults/main.yml` | `{{ mise_version }}`, `{{ mise_checksum_sha256 }}`, `{{ mise_install_dir }}` | WIRED | All variables referenced in tasks; defaults provide values |
| `.pre-commit-config.yaml` grep-gate | `ansible/playbook.yml` | tail-1 grep asserting `role: hardening` is last | WIRED | Gate verifies playbook ordering at commit time |
| `.github/workflows/ci.yml` grep-gate | `ansible/playbook.yml` + tree | Invariants 9 + 10 mirror pre-commit assertions | WIRED | CI gate confirmed at lines 231–243 |

---

### Data-Flow Trace (Level 4)

Not applicable — this is an IaC/Ansible phase. No React components, no API routes rendering dynamic data. The "data flow" is: Ansible defaults → tasks → baked AMI filesystem. Verified via static analysis of defaults/tasks wiring above.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `./run jupyter` dispatches to script | `grep 'jupyter)' run` | `jupyter) cmd_jupyter "$@" ;;` at line 521 | PASS |
| jupyter script binds loopback | `grep 'ip=127.0.0.1' scripts/devbox-jupyter.sh` | 1 match: `--ip=127.0.0.1` | PASS |
| No jupyter.service tracked | `git ls-files \| grep jupyter.service` | Empty output | PASS |
| No JUPYTER in bootstrap script | `grep -c "JUPYTER" .../devbox-secrets-bootstrap.sh.j2` | 0 matches | PASS |
| No jupyter in generate.yml / publish.yml | `grep -c "jupyter" .../generate.yml` | 0 matches | PASS |
| hardening last in playbook | `grep -E '^[[:space:]]*-[[:space:]]*role:' ansible/playbook.yml \| tail -1` | `- role: hardening  # MUST remain last...` | PASS |
| No .mise.toml in tree | `find . -name ".mise.toml" -not -path "./.git/*" \| grep -q .` | No output (exit 1 = not found) | PASS |
| Language layers untouched | `git log --oneline -- ansible/roles/{python,golang,rust,java}/` | Only pre-Phase-8 commits (2e8ac73, 48e2634) | PASS |
| ipykernel version pin is 6.29.5 (Python 3.9 compat) | `grep 'ipykernel_version' .../defaults/main.yml` | `ipykernel_version: "6.29.5"` | PASS |
| mise SHA-256 checksum is 64 chars | `echo -n "cfac...a84" \| wc -c` | 64 | PASS |

---

### Probe Execution

Step 7c: SKIPPED — no `scripts/*/tests/probe-*.sh` found for this phase. IaC repo with no runnable unit-test suite; verification is structural/static.

---

### Requirements Coverage

| REQ-ID | Phase | Description | Status | Evidence |
|--------|-------|-------------|--------|----------|
| JUP-01 | Phase 8 | JupyterLab installed in baked AMI via Ansible | SATISFIED | `ansible/roles/jupyter/tasks/main.yml` installs jupyterlab==4.5.7 + ipykernel==6.29.5 into /opt/jupyter venv |
| JUP-02 | Phase 8 | SUPERSEDED — no systemd service | CORRECT | No `jupyter.service` file exists; amendment correctly removed it |
| JUP-03 | Phase 8 | SUPERSEDED — no SSM password | CORRECT | No Jupyter password machinery in secrets role; commit 988115a confirmed revert |
| JUP-04 | Phase 8 | SUPERSEDED — loopback + SSM/IAM auth boundary | CORRECT | `--ip=127.0.0.1` in `devbox-jupyter.sh`; no password config |
| JUP-08 | Phase 8 | hardening remains last role in ansible/playbook.yml | SATISFIED | Grep-gate 9 passes; hardening at line 65, last `- role:` entry |
| MISE-01 | Phase 8 | mise binary installed via Ansible | SATISFIED | `ansible/roles/mise/tasks/main.yml` downloads mise-v2026.5.18-linux-x64 with SHA-256 checksum |
| MISE-02 | Phase 8 | mise shell activation for ec2-user interactive shells | SATISFIED | `/etc/profile.d/mise.sh` written with `eval "$(mise activate bash)"` |
| MISE-03 | Phase 8 | No committed .mise.toml; language layers untouched | SATISFIED | Grep-gate 10 passes; language role dirs unchanged since pre-Phase-8 commits |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `ansible/playbook.yml` | 90 | `# FIXME: see firewalld-docker-fix.yml header` | INFO (pre-existing) | FIXME predates Phase 8 — present in commit 649ce1b (Phase 7). Phase 8 preserved it without modification. Not a Phase 8 blocker. Retirement criteria documented in `ansible/firewalld-docker-fix.yml` header (3 conditions). |

No `TBD`, `XXX`, or unresolved `FIXME` markers introduced by Phase 8 in any Phase 8 implementation files (`ansible/roles/jupyter/`, `ansible/roles/mise/`, `scripts/devbox-jupyter.sh`).

---

### Human Verification Required

#### 1. JupyterLab venv functional after bake

**Test:** On a freshly baked instance, run: `/opt/jupyter/bin/jupyter --version` and `/opt/jupyter/bin/jupyter kernelspec list`
**Expected:** Version command prints JupyterLab 4.5.7; kernelspec list shows a `python3` kernel at `/opt/jupyter/share/jupyter/kernels/python3`
**Why human:** Static analysis confirms the Ansible tasks are structurally correct and that the `creates:` guard allows re-runs to be idempotent, but pip install success on AL2023 Python 3.9 and correct kernel registration can only be confirmed against a real bake. The ipykernel 6.29.5 pin was chosen for Python 3.9 compatibility — a real bake validates that assumption.

#### 2. mise binary and shell activation functional after bake

**Test:** SSH/SSM into a freshly baked instance and run: `bash -l -c 'mise --version'`
**Expected:** Prints `mise 2026.5.18` or similar; exit code 0. Note: `bash -l` (login shell) is required to source `/etc/profile.d/mise.sh` — SSM non-login shells will not have mise on PATH without it (RESEARCH Pitfall 6, documented in the activation script comment).
**Why human:** The `get_url` task with SHA-256 checksum will be verified at bake time against the live GitHub release. Only a real bake confirms: (a) the binary downloads successfully from the release URL, (b) the checksum matches, and (c) the profile.d hook actually activates mise in a login shell.

---

### Gaps Summary

No gaps blocking goal achievement. All five ROADMAP success criteria are met by the static codebase:

1. **SC1 (venv + kernel):** `/opt/jupyter` venv with pinned versions, kernel registered — Ansible tasks confirmed correct.
2. **SC2 (loopback on-demand):** `./run jupyter` dispatches to `scripts/devbox-jupyter.sh` which runs `--ip=127.0.0.1`; no systemd service.
3. **SC3 (no password/TLS/0.0.0.0):** All Jupyter password machinery reverted in commits 988115a and e671856; confirmed absent from all secrets role files and bootstrap script.
4. **SC4 (mise --version; no .mise.toml; language layers untouched):** Role structurally complete; grep-gate 10 passes; language dirs unchanged.
5. **SC5 (hardening last; CI grep-gates):** Grep-gate 9 passes; invariant mirrored in both pre-commit and CI.

The two human verification items are confirmations, not gap closures — they verify runtime behavior of correctly-structured Ansible tasks on a real AMI.

---

**Notable: secrets role `when:` did NOT include `layers.jupyter`**

The 08-04-PLAN.md and 08-04-SUMMARY.md both describe extending the `secrets when:` to include `layers.jupyter`. The actual `ansible/playbook.yml` does NOT include this extension. This is NOT a gap — commit 988115a explicitly reverted the `secrets when:` extension as part of the amendment cleanup: "Also revert the secrets-role 'when:' jupyter gate in playbook.yml." After the amendment, the Jupyter role has no password and does not need the secrets role to fire. The PLAN/SUMMARY describe the pre-amendment design; the actual code correctly implements the post-amendment design.

---

_Verified: 2026-06-02_
_Verifier: Claude (gsd-verifier)_
