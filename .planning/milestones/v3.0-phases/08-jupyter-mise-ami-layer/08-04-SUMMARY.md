---
phase: 08-jupyter-mise-ami-layer
plan: "04"
subsystem: ansible/build-wiring
tags: [ansible, playbook, grep-gates, jupyter, mise, hardening, invariants]
dependency_graph:
  requires: ["08-01", "08-02", "08-03"]
  provides: ["active-jupyter-mise-build", "hardening-last-ratchet", "no-mise-toml-ratchet"]
  affects: ["ansible/playbook.yml", "ansible/layer_config.yml", ".pre-commit-config.yaml", ".github/workflows/ci.yml"]
tech_stack:
  added: []
  patterns:
    - "Role ordering invariant enforced by tail-1 grep on YAML role list"
    - "Pre-commit + CI grep-gate mirroring (CI authoritative, pre-commit local feedback)"
key_files:
  created: []
  modified:
    - ansible/playbook.yml
    - ansible/layer_config.yml
    - .pre-commit-config.yaml
    - .github/workflows/ci.yml
decisions:
  - "Extend secrets role when: using >- block scalar (multi-line folded) for readability"
  - "Invariant 9 (hardening-last) uses tail -1 extraction on all '- role:' lines — comment-safe since YAML role entries are never comments"
  - "Invariant 10 (no .mise.toml) uses find + grep -q so it works both in bash one-liner (pre-commit) and multi-statement (CI) styles"
  - "ci.yml header updated to enumerate all 10 invariants (was 7; invariant 8 was added in Phase 7 but header was never updated)"
metrics:
  duration: "~20 minutes"
  completed: "2026-06-02T19:31:53Z"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 8 Plan 04: Wire jupyter + mise roles into the build + ratchet invariants Summary

Wire jupyter and mise Ansible roles into playbook.yml (before hardening), extend the secrets role when: for the jupyter layer, add layer toggles to layer_config.yml, and add grep-gates (mirrored in pre-commit + CI) that mechanically enforce the hardening-last and no-.mise.toml invariants (JUP-08, MISE-03).

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Wire jupyter + mise roles into playbook.yml and layer_config.yml | ae5aac6 | ansible/playbook.yml, ansible/layer_config.yml |
| 2 | Add hardening-last + no-.mise.toml grep gates (pre-commit + CI) | a608595 | .pre-commit-config.yaml, .github/workflows/ci.yml |

## What Was Built

**Task 1 — Role wiring:**
- Added `role: jupyter` (gated on `layers.jupyter | default(false)`) and `role: mise` (gated on `layers.mise | default(false)`) to `ansible/playbook.yml`, placed after `desktop` and before `hardening`
- Extended the `secrets` role `when:` from a two-condition boolean to a three-condition block scalar that also fires when `layers.jupyter` is true (jupyter needs the Jupyter password from secrets)
- Added inline comment on the `hardening` role entry citing JUP-08 / CLAUDE.md §8
- Added `jupyter: true` and `mise: true` to `ansible/layer_config.yml` before `hardening: true`, matching playbook ordering

**Task 2 — Grep-gate invariants:**
- Invariant 9 (JUP-08): asserts `hardening` is the last `- role:` line in `ansible/playbook.yml` using `grep -E '^[[:space:]]*-[[:space:]]*role:' | tail -1 | grep -c 'role:[[:space:]]*hardening'`
- Invariant 10 (MISE-03): asserts no `.mise.toml` exists in the tracked tree using `find . -name '.mise.toml' -not -path './.git/*' | grep -q .`
- Both invariants mirrored identically in `.pre-commit-config.yaml` (pre-commit hook) and `.github/workflows/ci.yml` (authoritative CI gate)
- Gate sanity-verified: appending a dummy role after hardening trips invariant 9; removing it restores green

## Deviations from Plan

**1. [Rule 2 - Missing critical functionality] Updated ci.yml header comment**
- **Found during:** Task 2
- **Issue:** ci.yml header enumerated only 7 invariants; Phase 7 added invariant 8 (no retired make targets) but the header was never updated; this plan adds 9 and 10
- **Fix:** Updated header comment to enumerate all 10 invariants (8 from pre-existing work + 2 new)
- **Files modified:** .github/workflows/ci.yml

## Verification Results

```
pre-commit run grep-gates --all-files: Passed
hardening is last role in playbook.yml: CONFIRMED (line 66)
no .mise.toml in tree: CONFIRMED
jupyter + mise role entries before hardening: CONFIRMED (lines 60, 63, 66)
secrets when: includes layers.jupyter: CONFIRMED
layer_config.yml jupyter: true + mise: true: CONFIRMED
Gate ratchet verification: dummy role after hardening FAIL (gate bites); removal PASS
```

## Known Stubs

None — all wiring is functional; roles are defined in prior plans (08-01 mise, 08-02/03 jupyter).

## Threat Flags

None — no new network endpoints, auth paths, or schema changes introduced. The grep-gates close T-08-12 and T-08-13 from the plan's threat register.

## Self-Check

### Files exist
- ansible/playbook.yml — FOUND (modified)
- ansible/layer_config.yml — FOUND (modified)
- .pre-commit-config.yaml — FOUND (modified)
- .github/workflows/ci.yml — FOUND (modified)

### Commits exist
- ae5aac6 — feat(08-04): wire jupyter + mise roles into playbook.yml and layer_config.yml
- a608595 — feat(08-04): add hardening-last + no-.mise.toml grep gates to pre-commit and CI

## Self-Check: PASSED
