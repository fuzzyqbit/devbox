---
phase: 08-jupyter-mise-ami-layer
plan: "01"
subsystem: ansible/roles/mise
tags: [ansible, mise, version-manager, ami, profile.d]
dependency_graph:
  requires: []
  provides: [mise-role-defaults, mise-role-tasks]
  affects: [ansible/playbook.yml (wave 2 plan 04 will add role invocation)]
tech_stack:
  added: [mise 2026.5.18]
  patterns: [get_url checksum verification, /etc/profile.d system-wide activation, FQCN ansible.builtin.*]
key_files:
  created:
    - ansible/roles/mise/defaults/main.yml
    - ansible/roles/mise/tasks/main.yml
  modified: []
decisions:
  - "Used FQCN ansible.builtin.get_url and ansible.builtin.copy per secrets-role convention (not vscode-role short names)"
  - "mise_install_dir set to /usr/local/bin (direct binary, no subdirectory — no PATH manipulation needed)"
  - "Included dev_user/dev_home in defaults per role convention even though mise tasks do not use them (allows future reference)"
  - "SSM non-login shell caveat (RESEARCH Pitfall 6) documented in comment within /etc/profile.d/mise.sh"
metrics:
  duration: "3m"
  completed: "2026-06-02T19:14:14Z"
  tasks_completed: 2
  tasks_total: 3
  files_created: 2
  files_modified: 0
---

# Phase 8 Plan 01: mise Ansible Role Summary

**One-liner:** New `mise` Ansible role installs the version-pinned, checksum-verified mise 2026.5.18 binary to `/usr/local/bin/mise` and writes a system-wide bash activation hook at `/etc/profile.d/mise.sh`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 0 | Verify mise package legitimacy (pre-approved) | — | — |
| 1 | Write mise/defaults/main.yml | 126fe5c | ansible/roles/mise/defaults/main.yml |
| 2 | Write mise/tasks/main.yml | 839da7a | ansible/roles/mise/tasks/main.yml |

## What Was Built

**`ansible/roles/mise/defaults/main.yml`** — Role defaults with:
- `mise_version: "2026.5.18"` (quoted string, no floating `latest`)
- `mise_checksum_sha256: "cfac593469d028d7ae5fe36e37bd7c59118b5238e92d8a876209578464f24a84"` — operator-verified against the upstream SHASUMS256.txt for the official `jdx` org release v2026.5.18 (49 assets confirmed present)
- `mise_install_dir: /usr/local/bin`
- `dev_user: ec2-user` / `dev_home: /home/ec2-user` per role convention

**`ansible/roles/mise/tasks/main.yml`** — Two tasks, both FQCN-prefixed:
1. `ansible.builtin.get_url` — Downloads `mise-v{{ mise_version }}-linux-x64` from the official GitHub release URL to `{{ mise_install_dir }}/mise` with `mode: "0755"` and `checksum: "sha256:{{ mise_checksum_sha256 }}"` (checksum verification is mandatory, not optional)
2. `ansible.builtin.copy` — Writes `/etc/profile.d/mise.sh` with `mode: "0644"` and inline content invoking `eval "$(mise activate bash)"` with a comment noting RESEARCH Pitfall 6 (SSM non-login shells require `bash -l`)

## Decisions Made

1. **FQCN prefix for all modules** — Followed the `secrets` role convention (`ansible.builtin.*`) rather than the `vscode` role's short-name pattern. The PATTERNS.md explicitly calls this out as the convention for new roles.
2. **Direct binary, no PATH manipulation** — Since `/usr/local/bin` is already on the system PATH, no `export PATH=...` line was needed in the profile.d script. The activation hook uses `eval "$(mise activate bash)"` directly (MISE-02).
3. **No cleanup task** — Unlike the golang role which cleans up a `/tmp` tarball, the mise binary is downloaded directly to its final location; no intermediate file to remove.

## Deviations from Plan

None — plan executed exactly as written. Task 0 was pre-approved by the operator.

**Operator-verified checksum (Task 0):** The operator confirmed the mise package is the official `jdx` org artifact at github.com/jdx/mise/releases, release v2026.5.18 (49 assets), and provided the canonical SHA-256 from upstream SHASUMS256.txt:
- `mise_checksum_sha256: cfac593469d028d7ae5fe36e37bd7c59118b5238e92d8a876209578464f24a84`

## Known Issues (Pre-existing, Out of Scope)

**ansible-lint config invalid in worktree:** The `.ansible-lint` file contains `parseable: true` which is not accepted by the installed ansible-lint version. This causes the `pre-commit run ansible-lint` hook to exit with code 3 ("Invalid configuration file"). This is a pre-existing issue unrelated to this plan's changes — the YAML syntax of the new role files is correct and uses the required FQCN pattern. Deferred to `deferred-items.md` for tracking.

## Threat Model Compliance

| Threat ID | Mitigation | Status |
|-----------|------------|--------|
| T-08-01 (Tampering: mise binary download) | `checksum: "sha256:{{ mise_checksum_sha256 }}"` wired in get_url task; no `latest` redirect | MITIGATED |
| T-08-02 (Tampering: eval in profile.d) | mise binary is checksum-pinned from official jdx org; eval runs verified binary's activation output | ACCEPTED |
| T-08-SC (Supply chain: GitHub Releases artifact) | Operator-verified against SHASUMS256.txt at plan execution time | RESOLVED |

## Known Stubs

None — no placeholder values, no hardcoded empty data, no TODO/FIXME markers in produced files.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary surface introduced beyond what was planned (the get_url download is explicitly in the threat model).

## Self-Check: PASSED

- `ansible/roles/mise/defaults/main.yml` — confirmed present
- `ansible/roles/mise/tasks/main.yml` — confirmed present
- Commit 126fe5c — confirmed in git log
- Commit 839da7a — confirmed in git log
- No `.mise.toml` in tree
- No `latest` in mise role files
- Per-language roles (python, golang, rust, java) untouched
