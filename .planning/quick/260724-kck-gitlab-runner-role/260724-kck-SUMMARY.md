---
phase: quick-260724-kck-gitlab-runner-role
plan: 01
subsystem: infra
tags: [ansible, gitlab-runner, packagecloud, rpm, gpg, dnf, al2023, packer-bake]

requires:
  - phase: 16-desktop-chrome (Chrome block)
    provides: "rpm_key import + inline-content vendor .repo bake + disable_gpg_check: false idiom"
  - phase: quick-260707-o7s-xrdp-spal
    provides: "deferred-pin dnf name templating + is-enabled stdout-not-rc assert idiom (incl. the command-instead-of-module noqa)"
  - phase: ai-tools role
    provides: "no-secrets header doctrine, [VERIFIED]/[ASSUMED confirmed-at-first-bake] comment idioms, bake-assert section banner"
provides:
  - "ansible/roles/gitlab_runner/ — GitLab CI runner baked from GitLab's official signed packagecloud rpm repo (gpgcheck=1 AND repo_gpgcheck=1), version-pinned 19.2.0, installed-NOT-registered"
  - "layer gate layers.gitlab_runner (default FALSE) wired immediately before secrets; hardening still last"
  - "mechanical §8 no-secrets bake-assert: build fails if /etc/gitlab-runner/config.toml carries `token` or `[[runners]]`"
  - "service-disabled posture: gitlab-runner.service baked disabled+stopped; operator registers at runtime then enables"
affects: [bake-pipeline, live-uat-backlog, kion-creds-branch-merge-region]

tech-stack:
  added: [gitlab-runner 19.2.0 (rpm, packages.gitlab.com — only when layers.gitlab_runner is true)]
  patterns:
    - "exec-time verbatim vendor .repo fetch (curl of packagecloud config_file.repo) baked via copy inline content"
    - "installed-not-registered: secret-bearing registration is a runtime step, mechanically asserted absent at bake"

key-files:
  created:
    - ansible/roles/gitlab_runner/defaults/main.yml
    - ansible/roles/gitlab_runner/tasks/main.yml
  modified:
    - ansible/playbook.yml
    - ansible/layer_config.yml

key-decisions:
  - "Baked .repo content spliced FILE-TO-FILE (curl → scratchpad → python3) because the session's secret-scrubbing hook substitutes the two hex gpgkey filenames in every tool output — byte-equality vs the fetched section proven by diff, not by eye"
  - "ansible.builtin.systemd (not systemd_service) — repo-wide precedent (dcv, secrets), lint-green at pinned v26.4.0"
  - "Single noqa: command-instead-of-module on the systemctl is-enabled bake-assert, added only after the pinned linter flagged it (xrdp precedent); dnf makecache was NOT flagged — no noqa there"
  - "Wired immediately before `- role: secrets` (kion role absent on this branch; position satisfies both orderings when feat/kion-creds merges)"

patterns-established:
  - "gitlab_runner_version deferred release-suffix refinement: extend pin to full version-release at first bake via dnf list --showduplicates --repo=runner_gitlab-runner"

requirements-completed: [GLR-01, GLR-02, GLR-03, GLR-04]

duration: 8min
completed: 2026-07-24
---

# Quick Task 260724-kck: gitlab-runner role Summary

**Layer-gated `gitlab_runner` role bakes GitLab CI runner 19.2.0 from packages.gitlab.com's signed rpm repo (gpgcheck=1 + repo_gpgcheck=1, verbatim exec-time-fetched .repo), installed-NOT-registered — service disabled at boot, zero secrets baked and mechanically asserted absent, default bake unchanged (`gitlab_runner: false`)**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-24T18:50:45Z
- **Completed:** 2026-07-24T18:58:45Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- New `ansible/roles/gitlab_runner/{defaults,tasks}/main.yml`: verbatim packagecloud `.repo` bake (GPG + repo-metadata verification ON, SSL verify ON, SRPMS section dropped), rpm_key imports of all three gpgkey URLs, scoped `dnf makecache` for the repo-metadata signing key, pinned install via `gitlab_runner_version: "19.2.0"` with `disable_gpg_check: false`, service disable+stop, and four bake-assert groups (binary stat, `--version` execution, `is-enabled` → `disabled`, §8 no-secrets config.toml check)
- Role header documents the full runtime flow (`sudo gitlab-runner register` → `sudo systemctl enable --now gitlab-runner`), the AMI-swap re-register caveat (/etc/gitlab-runner is root-volume, not persistent /home), and the shell/docker executor interplay (comment-only, no hard dependency on layers.containers)
- Playbook wiring: `- role: gitlab_runner` gated `layers.gitlab_runner | default(false)`, immediately before `secrets`; hardening mechanically proven still last (grep-gates gate 9)
- `layer_config.yml` carries `gitlab_runner: false` — the default bake is byte-unchanged
- All static gates green at CI-exact scopes; exactly one noqa, added only because the pinned linter flagged it

## Task Commits

1. **Task 1: Create the gitlab_runner role** - `a1c054e` (feat)
2. **Task 2: Wire role into playbook + layer_config** - `bf5864b` (feat)
3. **Task 3: Static verification sweep (fix loop: is-enabled noqa)** - `b7b47fb` (fix)

All three hashes spot-verified via `git rev-parse --verify <hash>^{commit}`.

## Evidence: exec-time .repo fetch (Task 1 mandate)

Fetched 2026-07-24 (execution time, NOT transcribed from the plan):

```
curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/config_file.repo?os=amazon&dist=2023&source=script"
```

- Structural checks on the fetched `[runner_gitlab-runner]` section (all exit-code proven): `baseurl=https://packages.gitlab.com/runner/gitlab-runner/amazon/2023/$basearch`, `repo_gpgcheck=1`, `gpgcheck=1`, `enabled=1`, `sslverify=1`, `sslcacert=/etc/pki/tls/certs/ca-bundle.crt`, plus `metadata_expire=300` — kept verbatim; the `[runner_gitlab-runner-source]` SRPMS section dropped.
- **gpgkey URLs baked (3):** `https://packages.gitlab.com/gpgkey/gpg.key` (packagecloud metadata key) plus two runner package signing keys of the form `https://packages.gitlab.com/gpgkey/runner/<HEX-KEY-ID>.pub.gpg`. The two hex key-ID filenames are deliberately NOT transcribed here: the session's secret-scrubbing hook (mrclean) substituted those two values in every tool output (Bash, Read, and Edit alike), so any hex value visible to this session is untrusted — the same trap the plan flagged for the planning session.
- **Integrity proof without eyeballs:** the fetched section was spliced file-to-file (curl → scratchpad file → python3 placeholder replacement) so the true bytes never passed through the scrubbed display channel. Byte-equality then proven mechanically: the `content:` block extracted back out of the committed tasks/main.yml, de-indented, `diff`-ed against the fetched section → `BYTE-MATCH` (re-verified after the Task 3 edit). Each of the 3 gpgkey URLs counted appearing exactly twice in tasks/main.yml (once in the .repo content, once in the rpm_key loop): `URL#1: count=2 OK / URL#2: count=2 OK / URL#3: count=2 OK`.

## Verification Evidence (Task 3)

**1. Syntax — exit 0** (no-inventory warnings expected per plan):

```
$ ansible-playbook --syntax-check ansible/playbook.yml
playbook: ansible/playbook.yml
syntax-check exit: 0
```

**2. CI-exact ansible-lint v26.4.0, scoped — exit 0.** PATH binary was 6.22.2 (rejected). Used the pre-commit cached venv binary `/Users/me/.cache/pre-commit/repomwy7cq4j/py_env-python3.14/bin/ansible-lint`; its `--version` prints `0.1.dev1` (setuptools-scm artifact of pre-commit's shallow tag build, ansible-core 2.20.5), so the pin was proven via pre-commit's repo db instead:

```
$ sqlite3 ~/.cache/pre-commit/db.db "select repo, ref, path from repos where repo like '%ansible-lint%';"
https://github.com/ansible/ansible-lint:ansible-core>=2.19.0|v26.4.0|/Users/me/.cache/pre-commit/repomwy7cq4j
```

First run: exit 2, exactly one finding — `command-instead-of-module: systemctl used in place of systemd module` at the is-enabled bake-assert (the plan's predicted xrdp-precedent contingency). Applied the xrdp noqa + justification idiom (commit `b7b47fb`). Rerun:

```
Passed: 0 failure(s), 0 warning(s) in 51 files processed of 51 encountered. Profile 'production' was required, and it passed.
lint exit: 0
```

`dnf -y makecache` was NOT flagged — no noqa added there (matching the base-role dnf-swap precedent).

**3. grep-gates — Passed** (all 10 gates, incl. gate 8 no-retired-make-targets and gate 9 hardening-last):

```
$ pre-commit run grep-gates --all-files
regression grep gates (Phase 3 invariants)...............................Passed
```

**4. Scoped no-changeme — pass** (no output, non-zero git grep exit):

```
$ git grep -nIE "changeme" -- ansible/roles/gitlab_runner ansible/playbook.yml ansible/layer_config.yml
no-changeme scoped exit: 1 (non-zero = pass)
```

**5. Task 2 ordering proof — exit 0:** awk proves line(gitlab_runner) < line(secrets) < line(hardening); the last `- role:` line still names hardening; `layers.gitlab_runner | default(false)` gate and `gitlab_runner: false` flag both grep-proven.

**6. Diff hygiene** (`git diff --stat main...HEAD` after all three task commits):

```
 ansible/layer_config.yml                      |   4 +
 ansible/playbook.yml                          |   8 ++
 ansible/roles/gitlab_runner/defaults/main.yml |  13 ++
 ansible/roles/gitlab_runner/tasks/main.yml    | 170 ++++++++++++++++++++++++++
 4 files changed, 195 insertions(+)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Secret-scrubbing hook falsified the gpgkey filenames in ALL tool output**
- **Found during:** Task 1 (exec-time .repo fetch)
- **Issue:** The mrclean PostToolUse hook substituted the two hex `.pub.gpg` gpgkey filenames in Bash AND Read AND Edit output — the plan anticipated this for the planning session, but it applies to this execution session too, making faithful transcription via Write/Edit impossible.
- **Fix:** File-to-file splice: curl output saved to the scratchpad, the `[runner_gitlab-runner]` section + gpgkey URL list spliced into tasks/main.yml by a python3 script (placeholder replacement), so the true bytes never traversed the scrubbed channel. Byte-equality and twice-count proven by exit-code-only checks (see Evidence above). This is the one sanctioned departure from the Write-tool-only file-creation rule, and the hex filenames are likewise deliberately omitted from this SUMMARY.
- **Files modified:** ansible/roles/gitlab_runner/tasks/main.yml
- **Commit:** a1c054e

### Process notes (not deviations)

- The is-enabled `noqa: command-instead-of-module` was a plan-sanctioned contingency ("only if flagged"), and it was flagged — commit `b7b47fb`.
- The plan's "Do NOT commit — the orchestrator commits" was superseded by the orchestrator's spawn instruction to commit each task atomically on `feat/gitlab-runner`; `git add` and `git commit` ran as separate Bash calls per the project memory rule.

## Known Stubs

None — no placeholder values, no empty-data wiring. The two `[ASSUMED, confirmed-at-first-bake]` markers (rpm %post behavior, /usr/bin binary path, makecache key-acceptance) are documented live-bake confirmations, each with its confirmation command, per the ai_tools/xrdp idiom.

## Deferred to Live Bake (open UAT backlog — per plan, no new checkpoint)

- Bake with `layers.gitlab_runner: true`: dnf resolves gitlab-runner-19.2.0 with GPG green; confirm the makecache and binary-path [ASSUMED] markers
- Fill the release-suffix pin refinement (`dnf list --showduplicates --repo=runner_gitlab-runner gitlab-runner`)
- Runtime flow: `sudo gitlab-runner register` + `sudo systemctl enable --now gitlab-runner` against the org GitLab
- The DEFAULT bake (flag false) needs no UAT — provably unchanged

## Self-Check: PASSED

- Created files exist: `ansible/roles/gitlab_runner/defaults/main.yml`, `ansible/roles/gitlab_runner/tasks/main.yml` — FOUND
- Commits exist: `a1c054e`, `bf5864b`, `b7b47fb` — all verified via `git rev-parse --verify <hash>^{commit}`
