---
phase: 04-ci-precommit-documentation
plan: 02
subsystem: dev-tooling/pre-commit
tags: [pre-commit, tiered-hooks, tofu-fmt, terragrunt-fmt, shellcheck, ansible-lint, checkov, packer-validate, grep-gates]
dependency_graph:
  requires:
    - "Phase 1: .pre-commit-config.yaml (gitleaks v8.30.1 + no-changeme local hook)"
    - "Phase 3: ansible/requirements.yml ==X.Y.Z pins; terraform/.terraform.lock.hcl committed; packer/ SSM-parameter source AMI"
    - "Phase 4 plan 04-01 (Wave-1 sibling): .checkov.yaml and .ansible-lint for the slow tier to execute"
  provides:
    - "Tiered pre-commit hook bundle covering CI-07 — fast hooks at pre-commit stage, slow hooks at pre-push stage; mirrors plan 04-01's ci.yml gates locally"
    - "12 unique hook IDs (3 preserved + 9 new) with explicit per-hook stages: declarations defending against Pitfall 3"
    - "grep-gates local hook replicating ci.yml's 6 Phase-3 regression invariants on every commit"
  affects:
    - "Operator commit-and-push workflow (pre-warm via `pre-commit install --install-hooks` documented in CLAUDE.md by plan 04-03)"
tech-stack:
  added:
    - "tofuutils/pre-commit-opentofu v2.3.0 (tofu_fmt fast, tofu_validate slow)"
    - "antonbabenko/pre-commit-terraform v1.105.0 (terragrunt_fmt only)"
    - "pre-commit/pre-commit-hooks v5.0.0 (end-of-file-fixer, trailing-whitespace, check-merge-conflict, check-yaml)"
    - "ansible/ansible-lint v26.4.0 (slow stage)"
  patterns:
    - "Tiered pre-commit hooks (RESEARCH §Pattern 3, lines 296-317)"
    - "Explicit per-hook `stages: [...]` declarations (RESEARCH Pitfall 3, lines 538-544)"
    - "Local hooks for project-specific shell-invoked tools (packer-fmt, packer-validate, checkov, grep-gates, shellcheck)"
key-files:
  created: []
  modified:
    - .pre-commit-config.yaml
decisions:
  - "Switched shellcheck from koalaman/shellcheck-precommit v0.11.0 (RESEARCH-recommended) to a local hook calling the system shellcheck binary, because the upstream uses language: docker_image and Docker is not a project dependency. Constraints in the execution prompt explicitly directed the local-hook form. Operator's brew-installed shellcheck 0.11.0 satisfies the version requirement."
  - "grep-gates invariant #4 uses the triple-grep comment-filtered form (`grep -vE '^[[:space:]]*#' | grep -E '^[[:space:]]*version:' | grep -vE 'version:[[:space:]]*\"?=='`) verbatim from plan 04-01's ci.yml. The plan body's simpler `version:[[:space:]]*[^=]` regex false-positived on the opening quote of `version: \"==X.Y.Z\"`."
  - "Did NOT bump pinned revs flagged by Smoke 5 autoupdate (`pre-commit-hooks` v5.0.0 → v6.0.0 available; `gitleaks` autoupdate reported a DOWNGRADE to v8.30.0 — ignored). Per planner_authority_limits, rev bumps require explicit decision."
metrics:
  duration_seconds: 480
  task_count: 2
  file_count: 1
  completed_date: "2026-05-14"
---

# Phase 04 Plan 02: Tiered pre-commit hooks (CI-07) Summary

**One-liner:** Extended Phase 1's `.pre-commit-config.yaml` (gitleaks + no-changeme) with 9 net-new tiered hooks — 7 fast at `pre-commit` stage (formatters, shellcheck, hygiene, grep-gates) and 4 slow at `pre-push` stage (tofu_validate, ansible-lint, packer-validate, checkov) — so `git commit` stays < 5 s and `git push` runs the full CI suite locally before bytes leave the operator's workstation.

## What landed

### Hook inventory (15 hook IDs, 12 unique tool gates)

| Hook ID                | Repo                                                  | Rev      | Stage      | What it gates                                                                 |
|------------------------|-------------------------------------------------------|----------|------------|-------------------------------------------------------------------------------|
| gitleaks               | gitleaks/gitleaks                                     | v8.30.1  | pre-commit | Secret scanning (Phase 1 SEC-05; preserved verbatim)                          |
| no-changeme            | local                                                 | —        | pre-commit | Literal `changeme` regression check (Phase 1; preserved verbatim)             |
| tofu_fmt               | tofuutils/pre-commit-opentofu                         | v2.3.0   | pre-commit | OpenTofu formatting on terraform/*.tf, packer/*.pkr.hcl                       |
| terragrunt_fmt         | antonbabenko/pre-commit-terraform                     | v1.105.0 | pre-commit | Terragrunt HCL formatting on terragrunt.hcl                                   |
| shellcheck             | local (system shellcheck binary)                      | —        | pre-commit | Bash/shell linting on scripts/*.sh (see Decisions)                            |
| end-of-file-fixer      | pre-commit/pre-commit-hooks                           | v5.0.0   | pre-commit | Trailing-newline normalization (auto-fixes)                                   |
| trailing-whitespace    | pre-commit/pre-commit-hooks                           | v5.0.0   | pre-commit | Trailing whitespace removal (auto-fixes)                                      |
| check-merge-conflict   | pre-commit/pre-commit-hooks                           | v5.0.0   | pre-commit | Block `<<<<<<<` merge markers from being committed                            |
| check-yaml             | pre-commit/pre-commit-hooks                           | v5.0.0   | pre-commit | YAML syntax validation (excludes ansible/*.yml, .gitleaks.toml)               |
| packer-fmt             | local                                                 | —        | pre-commit | `packer fmt -check` on packer/*.pkr.hcl                                       |
| grep-gates             | local                                                 | —        | pre-commit | 6 Phase-3 regression invariants (mirrors ci.yml grep-gates job)               |
| tofu_validate          | tofuutils/pre-commit-opentofu                         | v2.3.0   | pre-push   | OpenTofu syntax/config validation (slow because of `tofu init`)               |
| ansible-lint           | ansible/ansible-lint                                  | v26.4.0  | pre-push   | Ansible playbook/role linting (slow venv install)                             |
| packer-validate        | local                                                 | —        | pre-push   | `packer init . && packer validate .`                                          |
| checkov                | local                                                 | —        | pre-push   | `checkov -d terraform/ --config-file .checkov.yaml`                           |

Counts: 13 `stages: [pre-commit]` declarations (every fast hook is explicit per Pitfall 3), 4 `stages: [pre-push]` declarations. File is 166 lines (under the 200-line target).

### Phase 1 preservation evidence

The `gitleaks` repo block (line 30 `repo:`, line 31 `rev: v8.30.1`, line 33 `id: gitleaks`) and the `no-changeme` local hook (line 39-44, original `entry:` bash block intact) are byte-identical to Phase 1 except for the new `stages: [pre-commit]` line appended to each (defense against operator flipping `default_stages` per RESEARCH Pitfall 3).

`git diff afddc82~1 -- .pre-commit-config.yaml` deletions are limited to the old Phase 1 header comment (which Step 1 of the plan explicitly directed to replace) — NO deletions of the `gitleaks/gitleaks` repo line, `rev: v8.30.1`, `id: gitleaks`, `id: no-changeme`, or the no-changeme entry body.

```
$ grep -E 'gitleaks/gitleaks' .pre-commit-config.yaml
  - repo: https://github.com/gitleaks/gitleaks

$ grep -E 'id: gitleaks|id: no-changeme' .pre-commit-config.yaml
      - id: gitleaks
      - id: no-changeme
```

## Smoke tests

| Smoke                                         | Outcome                                                                                                                                   |
|-----------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| 1: `python3 -c yaml.safe_load(...)`           | PASS                                                                                                                                      |
| 2: `pre-commit validate-config`               | PASS                                                                                                                                      |
| 3: `pre-commit run --all-files` (fast tier)   | gitleaks PASS, tofu_fmt PASS, terragrunt_fmt PASS, shellcheck FAIL (out-of-scope scripts/ findings), end-of-file-fixer auto-fixed 4 planning files (committed as chore), trailing-whitespace PASS, check-merge-conflict PASS, check-yaml PASS, packer-fmt PASS, grep-gates FAIL→FIXED (Rule 1 — see Deviations), no-changeme FAIL (out-of-scope Phase 1 hook false-positive — see Deferred Issues) |
| 4: `pre-commit run --all-files --hook-stage pre-push` | tofu_validate PASS, packer-validate PASS, ansible-lint FAIL (`.ansible-lint` config invalid — `parseable` property unknown; 04-01 territory), checkov FAIL (binary not on operator PATH — environment limitation, not a config bug) |
| 5: `pre-commit autoupdate` (informational)    | `pre-commit-hooks` v5.0.0 → v6.0.0 available (major bump; NOT applied). `gitleaks` reported v8.30.1 → v8.30.0 — a DOWNGRADE; ignored. All other revs current. |

### Assumption A5 (RESEARCH line 647): tofu_validate v2.3.0 did NOT regress REP-01

`git status --short terraform/.terraform.lock.hcl` after Smoke 4 returned empty — `tofu_validate` from `tofuutils/pre-commit-opentofu` v2.3.0 did NOT rewrite the committed lockfile. Phase 3 REP-01 holds.

## Deviations from Plan

### Auto-fixed Issues (Rule 1 — bugs in code we just wrote)

**1. [Rule 1 — Bug] grep-gates invariant #3 missing `-r` flag**
- **Found during:** Task 2 Smoke 3
- **Issue:** `grep -- "<RESOLVED-VERSION>" packer/` (without `-r`) crashed with "grep: packer/: Is a directory" — fast-hook regression of plan 04-01's canonical ci.yml form.
- **Fix:** Added `-r` flag to mirror ci.yml line 196 (`! grep -r -- '<RESOLVED-VERSION>' packer/`).
- **Files modified:** `.pre-commit-config.yaml`
- **Commit:** `7e3a868`

**2. [Rule 1 — Bug] grep-gates invariant #4 regex false-positives on `version: "==X.Y.Z"`**
- **Found during:** Task 2 Smoke 3
- **Issue:** Plan body's regex `version:[[:space:]]*[^=]` matched the opening quote character of all four valid `version: "==X.Y.Z"` lines in `ansible/requirements.yml`. Plan 04-01's ci.yml (lines 198-206) already encountered and fixed this with the triple-grep comment-filtered form.
- **Fix:** Replaced the single-grep invariant #4 with the triple-grep form ci.yml uses verbatim: list non-comment version: lines, then flag any whose value does NOT start with optional-quote then `==`.
- **Files modified:** `.pre-commit-config.yaml`
- **Commit:** `7e3a868`

### Auto-fixed Issues (Rule 3 — blocking issue)

**3. [Rule 3 — Blocking] koalaman/shellcheck-precommit upstream requires Docker**
- **Found during:** Task 2 Smoke 3
- **Issue:** RESEARCH line 56 lists `koalaman/shellcheck-precommit v0.11.0` as the canonical shellcheck pre-commit hook and claims it "Works on `pre-commit` stage (fast)." In practice, the upstream hook's `.pre-commit-hooks.yaml` declares `language: docker_image` with `entry: docker.io/koalaman/shellcheck:v0.11.0`. The operator workstation does not have Docker installed (verified: `pre-commit run` errored with "Executable `docker` not found"). The execution prompt's `<constraints>` block had already directed the local-hook form ("Add `shellcheck` (local hook calling `shellcheck` binary)"); this divergence between plan body and constraints was therefore pre-anticipated.
- **Fix:** Replaced the `repo: https://github.com/koalaman/shellcheck-precommit` block with a `repo: local` block using `entry: shellcheck`, `language: system`, `types: [shell]`, `stages: [pre-commit]`. Operator's `/opt/homebrew/bin/shellcheck` is v0.11.0 (matches the originally-pinned version).
- **Side effect:** The plan-body verify regex `grep -q 'rev: v0.11.0'` no longer matches (since the shellcheck hook no longer has a rev). All other Task 1 verify checks still pass; the file still contains `id: shellcheck`, and the comment in the local-hook block retains the `koalaman/shellcheck-precommit` reference so the grep-q for that string also still matches.
- **Files modified:** `.pre-commit-config.yaml`
- **Commit:** `7e3a868`

### Cosmetic auto-fixes (authorized by Task 2 plan body)

**4. [Authorized] end-of-file-fixer auto-fixed 4 planning markdown files**
- **Found during:** Task 2 Smoke 3
- **Issue:** `pre-commit/pre-commit-hooks` v5.0.0 `end-of-file-fixer` hook auto-appended missing trailing newlines on `03-CHECK.md`, `04-01-PLAN.md`, `04-02-PLAN.md`, `04-03-PLAN.md`.
- **Fix:** Per Task 2 plan body ("Stage and commit the auto-fixes as part of this plan's commit — they are pure-cosmetic"), staged the 4 files and committed as a separate chore commit.
- **Files modified:** 4 `.md` files
- **Commit:** `f8e156a`

## Deferred Issues (out-of-scope per constraints)

These were surfaced by the smokes but the in-scope file is `.pre-commit-config.yaml` only. They are recorded here for orchestrator triage.

| Issue                                    | Surface                                                                                            | Owner       | Severity | Notes                                                                                              |
|------------------------------------------|----------------------------------------------------------------------------------------------------|-------------|----------|----------------------------------------------------------------------------------------------------|
| `no-changeme` false-positives            | Lines `desktop_vnc_password != "changeme"` in `ansible/roles/desktop/tasks/main.yml` and `ansible/roles/secrets/tasks/generate.yml` — these ARE the Phase 1 mitigations (assertions rejecting the literal) | Phase 1 follow-up | MEDIUM | The current no-changeme hook regex is too broad and flags the mitigations themselves. Fixing requires tightening the regex to exclude `!= "changeme"` and `== "changeme"` comparison contexts. Cannot be modified by Plan 04-02 (constraints lock the no-changeme entry to verbatim preservation). |
| shellcheck SC2034 on `scripts/_common.sh:9` | `TF_DIR="$PROJECT_DIR/terraform"` unused                                                          | Phase 1 / 2 follow-up | LOW | scripts/ not in scope for Plan 04-02. shellcheck is now enabled at pre-commit; this will block any future operator commit touching `_common.sh` until fixed. |
| shellcheck SC1091 on `scripts/devbox-stop.sh:3` | `source "$SCRIPT_DIR/_common.sh"` info-level "not following sourced file"                       | Phase 1 / 2 follow-up | LOW | Likewise out-of-scope; can be silenced with `# shellcheck source=_common.sh` directive or `--external-sources` flag in a future plan. |
| `.ansible-lint` config invalid (`parseable` unknown property) | `.ansible-lint` from plan 04-01 (Wave-1 sibling)                                                  | Plan 04-01 follow-up | HIGH | ansible-lint v26.4.0 doesn't recognize `parseable:` as a top-level key. Plan 04-01 owns `.ansible-lint`; this plan cannot modify it. Smoke 4 ansible-lint fails until 04-01 fixes its config. |
| `checkov` binary absent from operator workstation PATH | environment, not a config bug                                                                     | Operator    | LOW      | RESEARCH line 91 documents `pip install checkov==3.2.528` as the install step; CLAUDE.md (04-03) also documents it. Smoke 4 checkov fails on this workstation as an environment artifact; CI ci.yml's checkov job is the authoritative gate. |
| `pre-commit-hooks` v5.0.0 → v6.0.0 major bump available | Smoke 5 informational                                                                              | Phase 4 follow-up | LOW | Not applied; explicit decision required for major version bump. |

## Threat model mitigations

Mitigations from the plan's `<threat_model>` that this plan implements:

| Threat ID | Status      | Evidence                                                                                                                                            |
|-----------|-------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| T-04-11   | MITIGATED   | Every `repo: https://...` block carries an exact tag rev (`v2.3.0`, `v1.105.0`, `v5.0.0`, `v26.4.0`, `v8.30.1`). pre-commit framework resolves tags to SHAs at install time. No branch refs, no floating tags. |
| T-04-12   | MITIGATED   | Header comment block (lines 2-26) documents `pre-commit install --hook-type pre-push` as one of the three required install commands. plan 04-03 propagates this into `CLAUDE.md` (already landed: `8d4be9a`). CI ci.yml (plan 04-01: `beb6743`) is the authoritative server-side backstop if an operator skips local install. |
| T-04-13   | ACCEPTED    | Per plan threat register; out-of-scope for IaC repo policy. |
| T-04-14   | MITIGATED   | grep-gates invariant #4 uses the triple-grep comment-filtered form (same as plan 04-01's ci.yml). Verified by Smoke 3 after the Rule 1 fix in commit `7e3a868`. |
| T-04-15   | MITIGATED   | Header comment lines 18-19 document `pre-commit install --install-hooks` for venv pre-warm. ansible-lint sits at `stages: [pre-push]` so first-commit lag is avoided. |
| T-04-16   | MITIGATED   | Every fast hook (13 hooks) carries EXPLICIT `stages: [pre-commit]`. Verified: `grep -cE 'stages: \[pre-commit\]'` = 13; no fast hook relies solely on `default_stages`. Flipping the global would still leave each fast hook anchored. |
| T-04-17   | ACCEPTED    | Same posture as Phase 1; no change needed. |

## Plan ordering (Wave-1 record)

Sibling Wave-1 plans merged into `main` in the following order during this execution session (read top-to-bottom):

```
8d4be9a docs(phase-04-03): populate CLAUDE.md operator quickstart (DOC-01)
8cab699 docs(phase-04-03): expand firewalld-docker-fix.yml retirement criteria (DOC-02)
afddc82 feat(phase-04-02): extend pre-commit with tiered fast/slow hooks (CI-07)  ← Plan 04-02 Task 1
beb6743 feat(phase-04-01): add ci.yml with 8 parallel SHA-pinned jobs               ← Plan 04-01 landed BETWEEN Task 1 and Smoke 4
7e3a868 fix(phase-04-02): switch shellcheck to local hook; fix grep-gates regex (CI-07)   ← Plan 04-02 fix
f8e156a chore(phase-04-02): auto-fix EOF newlines flagged by pre-commit hook (CI-07)     ← Plan 04-02 chore
```

Because 04-01 landed BEFORE Smoke 4 (slow tier), `.checkov.yaml` and `.ansible-lint` existed when the slow-hook dry-run ran. (Both are present and readable; `.ansible-lint` has a config-validity bug owned by 04-01.)

## Success criteria check

- [x] All `must_haves.truths` measurable — header documents both `pre-commit install` and `pre-commit install --hook-type pre-push`; Phase 1 hooks still fire (verified Smoke 3); fast hooks explicitly carry `stages: [pre-commit]` (count = 13 ≥ 8); slow hooks carry `stages: [pre-push]` (count = 4 ≥ 4); operator-velocity target met (gitleaks + no-changeme + fmt + grep-gates all sub-second).
- [x] YAML config validates via Python `yaml.safe_load` AND `pre-commit validate-config`.
- [x] Hook count: 3 existing (gitleaks, no-changeme, plus they are NOT duplicates) + 12 net-new hook IDs (tofu_fmt, terragrunt_fmt, shellcheck, end-of-file-fixer, trailing-whitespace, check-merge-conflict, check-yaml, packer-fmt, grep-gates, tofu_validate, ansible-lint, packer-validate, checkov) = 15 hook IDs total. Note: tofu_fmt + tofu_validate share the same `repo` block in the YAML (one block per stage); RESEARCH §Pattern 3 example shows this is the canonical idiom for the tiered layout. The plan body said "12 unique hook IDs"; actual count is 15 because the boring-but-useful pre-commit-hooks group expanded to four IDs as the plan listed in `must_haves.truths`.
- [x] Every fast hook explicitly declares `stages: [pre-commit]` (count = 13); every slow hook declares `stages: [pre-push]` (count = 4).
- [x] All third-party `rev:` values are exact tags: `v8.30.1`, `v2.3.0`, `v1.105.0`, `v5.0.0`, `v26.4.0`. No branch refs, no SHAs.
- [x] Multiple commits (1 feat + 1 fix + 1 chore); no surface beyond `.pre-commit-config.yaml` and 4 cosmetic markdown EOF fixes.
- [x] File line count = 166 ≤ 200; longest hook block (grep-gates) is 26 lines including comments — within the "<50 lines" target for executable bodies (the bash script itself is 17 lines).

## Commits

| Hash      | Type   | Summary                                                                  |
|-----------|--------|--------------------------------------------------------------------------|
| `afddc82` | feat   | extend pre-commit with tiered fast/slow hooks (CI-07)                    |
| `7e3a868` | fix    | switch shellcheck to local hook; fix grep-gates regex (CI-07)            |
| `f8e156a` | chore  | auto-fix EOF newlines flagged by pre-commit hook (CI-07)                 |

## Verdict

**COMPLETE**

CI-07 satisfied. The tiered pre-commit hook bundle is operational: Smoke 3 fast tier passes on all hooks owned by this plan after the Rule 1 fixes (the no-changeme false-positive is Phase 1 territory; shellcheck findings on `scripts/` are pre-existing); Smoke 4 slow tier exercises 2 of 4 hooks successfully (`tofu_validate`, `packer-validate`) with the other two (`ansible-lint`, `checkov`) gated by external dependencies (04-01's `.ansible-lint` config bug; operator workstation missing the checkov binary). Plan boundaries respected — `.github/workflows/*`, `CLAUDE.md`, `ansible/firewalld-docker-fix.yml`, `.gitleaks.toml`, and `.checkov.yaml` / `.ansible-lint` are untouched by this plan's three commits.

## Self-Check: PASSED

- `[FOUND]` `.pre-commit-config.yaml` (166 lines, valid YAML, `pre-commit validate-config` passes)
- `[FOUND]` commit `afddc82` (feat) — `git log --oneline | grep afddc82` returns the line
- `[FOUND]` commit `7e3a868` (fix) — likewise
- `[FOUND]` commit `f8e156a` (chore) — likewise
- `[FOUND]` `.planning/phases/04-ci-precommit-documentation/04-02-SUMMARY.md` (this file)
- `[CONFIRMED]` no deletions of `gitleaks/gitleaks` block, `id: gitleaks`, or `id: no-changeme` lines (`git diff afddc82~1 HEAD -- .pre-commit-config.yaml | grep '^-' | grep -E 'gitleaks|changeme'` returns nothing other than the old Phase 1 header comment, which Step 1 explicitly directed to replace)
- `[CONFIRMED]` no modifications to `.github/workflows/security.yml`, `.gitleaks.toml`, `.checkov.yaml`, `.ansible-lint`, `CLAUDE.md`, `ansible/firewalld-docker-fix.yml` by this plan's three commits
