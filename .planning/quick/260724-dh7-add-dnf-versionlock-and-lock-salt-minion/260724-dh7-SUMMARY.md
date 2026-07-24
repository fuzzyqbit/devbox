---
phase: quick-260724-dh7-add-dnf-versionlock-and-lock-salt-minion
plan: 01
subsystem: infra
tags: [ansible, dnf, versionlock, salt-minion, al2023, packer-bake]

requires:
  - phase: quick-260707-o7s-xrdp-spal
    provides: "SPAL package_facts gather precedent in roles/base (the POST-update gather this task must not deduplicate)"
provides:
  - "dnf versionlock plugin (python3-dnf-plugin-versionlock) installed as the FIRST task of roles/base — before the full-image update"
  - "salt-minion locked to its bake-start version via conditional lock loop (dnf_versionlock_packages)"
  - "clean no-op path on salt-minion-less AMIs (per-item presence gate + debug note)"
  - "lock baked into /etc/dnf/plugins/versionlock.list — runtime dnf update on launched instances also excludes salt-minion"
affects: [base-role, bake-pipeline, live-uat-backlog]

tech-stack:
  added: [python3-dnf-plugin-versionlock]
  patterns:
    - "versionlock block pinned FIRST in roles/base (ordering-critical: lock precedes full-image update)"
    - "register + changed_when substring + tolerant failed_when idiom (mirrors curl-swap)"
    - "dual package_facts gathers: pre-update (versionlock gate) vs post-update (SPAL floor) — intentionally not deduplicated"

key-files:
  created: []
  modified:
    - ansible/roles/base/tasks/main.yml
    - ansible/roles/base/defaults/main.yml

key-decisions:
  - "Lock loop is ansible.builtin.command (no dnf-module support for versionlock); no noqa needed — pinned v26.4.0 lint green, matching the dnf-swap precedent"
  - "changed_when keyed on dnf4 'Adding versionlock on:' stdout line = idempotency guard (already-locked re-run reports ok)"
  - "Per-item `item in ansible_facts.packages` gate makes public-minimal-AMI bakes no-op cleanly instead of failing rc!=0"

patterns-established:
  - "dnf_versionlock_packages role default: extend the list to freeze more source-AMI packages at bake start"

requirements-completed: [VLOCK-01, VLOCK-02, VLOCK-03]

duration: 3min
completed: 2026-07-24
---

# Quick Task 260724-dh7: Add dnf versionlock and lock salt-minion Summary

**dnf versionlock plugin + conditional salt-minion lock inserted as the FIRST tasks of roles/base — ahead of the full-image update — so salt-minion is frozen at its bake-start version and baked into /etc/dnf/plugins/versionlock.list**

## Performance

- **Duration:** 3 min
- **Started:** 2026-07-24T13:51:07Z
- **Completed:** 2026-07-24T13:54:05Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Versionlock block (comment header, plugin install, pre-update package_facts, conditional lock loop, absent-package debug) is now the first content of `ansible/roles/base/tasks/main.yml`, above "Update all packages" — ordering mechanically proven by the awk check
- `dnf_versionlock_packages: [salt-minion]` added to role defaults with the source-AMI story documented
- Idempotency + safety wired: `changed_when` on the dnf4 `Adding versionlock on:` line, tolerant `failed_when`, per-item presence gate for salt-minion-less AMIs
- GPG posture untouched (no `disable_gpg_check` anywhere in the new block — dnf default ON, CLAUDE.md §8)
- All static gates green at CI-exact scopes; zero new noqa comments

## Task Commits

1. **Task 1: Insert the versionlock block + dnf_versionlock_packages default** - `91c9e93` (feat)
2. **Task 2: Static verification sweep** - no commit (read-only verification; no fix-loop edits were needed)

## Files Created/Modified

- `ansible/roles/base/tasks/main.yml` - versionlock block as first tasks: plugin install, pre-update package_facts gather, conditional lock loop, absent-package debug note
- `ansible/roles/base/defaults/main.yml` - `dnf_versionlock_packages` list (salt-minion) with ordering + source-AMI comments

## Verification Evidence (Task 2)

**1. Syntax check — exit 0** (no-inventory warnings expected per plan):

```
$ ansible-playbook --syntax-check ansible/playbook.yml
playbook: ansible/playbook.yml
SYNTAX-EXIT:0
```

**2. CI-exact ansible-lint v26.4.0, scoped — exit 0, zero findings.** PATH binary was 6.22.2 (not the pin), so the pre-commit cached venv binary was used. Pin proven via the pre-commit db:

```
$ sqlite3 ~/.cache/pre-commit/db.db "SELECT repo, ref, path FROM repos WHERE repo LIKE '%ansible-lint%';"
https://github.com/ansible/ansible-lint:ansible-core>=2.19.0|v26.4.0|/Users/me/.cache/pre-commit/repomwy7cq4j
```

(The binary self-reports `0.1.dev1` — a setuptools-scm artifact of pre-commit's git-checkout install at rev v26.4.0, commit `5fac056c455`; runtime stack `ansible-core:2.20.5 ansible-compat:26.3.0`.)

```
$ /Users/me/.cache/pre-commit/repomwy7cq4j/py_env-python3.14/bin/ansible-lint ansible/playbook.yml
Passed: 0 failure(s), 0 warning(s) in 49 files processed of 49 encountered. Profile 'production' was required, and it passed.
LINT-EXIT:0
```

**3. Grep gates — passed** (all gates incl. gate 9 hardening-last, gate 8 no-retired-make-targets):

```
$ pre-commit run grep-gates --all-files
regression grep gates (Phase 3 invariants)...............................Passed
```

**4. Scoped no-changeme — clean** (git grep exit 1 = no matches):

```
$ git grep -nIE "changeme" -- ansible/roles/base
NOCHANGEME-EXIT:1 (non-zero = pass, no matches)
```

**5. Diff hygiene — exactly the two intended files, insertions only:**

```
$ git diff --stat HEAD~1 HEAD
 ansible/roles/base/defaults/main.yml |  8 +++++++
 ansible/roles/base/tasks/main.yml    | 46 ++++++++++++++++++++++++++++++++++++
 2 files changed, 54 insertions(+)
```

**Task 1 structural proofs** (all exit 0): awk ordering check (both lock tasks precede "Update all packages"), plugin-name grep, `Adding versionlock on:` changed_when key, `item in ansible_facts.packages` + `item not in ansible_facts.packages` gates, defaults list grep, `ansible.builtin.package_facts` count == 2 (pre-update gather added, SPAL gather preserved), no `disable_gpg_check: true`.

## Decisions Made

- No noqa added: the pinned v26.4.0 linter did not flag `command-instead-of-module` on the `dnf versionlock` command task (same as the dnf-swap precedent), so the contingency stayed unused
- Used the pre-commit cached venv binary for CI-exact lint after confirming the PATH binary (6.22.2) diverges from the v26.4.0 pin

## Deviations from Plan

**1. [Process] Executor committed per-task instead of leaving the tree dirty for the orchestrator**
- **Found during:** Task 1 completion
- **Issue:** The plan's task actions say "Do NOT commit — the orchestrator commits", but the spawning orchestrator prompt explicitly mandates atomic per-task commits by the executor
- **Fix:** Followed the orchestrator instruction (it supersedes plan prose); Task 1 committed as `91c9e93`
- **Impact:** Task 2's working-tree diff-hygiene check adapted to the commit diff (`git diff --name-only HEAD~1 HEAD`) — same two-file scope proof, identical result

No code deviations — the implementation matches the plan exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Bake-time behavior lands on the operator's next `./run build` (open live-UAT backlog). Deferred live checks: on an org source AMI, `dnf versionlock list` shows the salt-minion entry at the pre-update version and `rpm -q salt-minion` is unchanged after the full-image update; on the public minimal AMI, the bake log shows the per-item skip + debug note and the bake succeeds.
- To freeze additional source-AMI packages later, extend `dnf_versionlock_packages` — the block generalizes.

## Self-Check: PASSED

- FOUND: .planning/quick/260724-dh7-add-dnf-versionlock-and-lock-salt-minion/260724-dh7-SUMMARY.md
- FOUND: ansible/roles/base/tasks/main.yml
- FOUND: ansible/roles/base/defaults/main.yml
- FOUND-COMMIT: 91c9e93

---
*Phase: quick-260724-dh7-add-dnf-versionlock-and-lock-salt-minion*
*Completed: 2026-07-24*
