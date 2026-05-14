---
phase: 04-ci-precommit-documentation
plan: 01
subsystem: ci
tags: [ci, github-actions, fmt-check, tofu-validate, packer-validate, ansible-lint, shellcheck, checkov, grep-gates]
requirements: [CI-01, CI-02, CI-03, CI-04, CI-05, CI-06]
dependency-graph:
  requires:
    - .github/workflows/security.yml (Phase 1 SEC-05; reused checkout SHA)
    - terraform/.terraform.lock.hcl (Phase 3 REP-01; tofu init -lockfile=readonly anchor)
    - ansible/requirements.yml (Phase 3 REP-02; collection version-pin source)
    - packer/devimage.pkr.hcl (Phase 3 REP-04; source AMI pinning)
  provides:
    - server-side CI gate that runs every push and PR (CI-01)
    - format check across tofu/packer/terragrunt (CI-02)
    - validate gates across tofu/packer/ansible (CI-02..CI-04)
    - shellcheck on scripts/*.sh (CI-05)
    - Checkov HIGH-fail security scan (CI-06)
    - 7 grep-gates enforcing Phase 3 invariants + action-SHA pin policy
  affects:
    - Phase 4 plan 04-02 (.pre-commit-config.yaml will mirror these gates locally)
    - Phase 4 plan 04-03 (CLAUDE.md documents the CI contract)
tech-stack:
  added:
    - opentofu/setup-opentofu@v2.0.0
    - hashicorp/setup-packer@v3.2.0
    - bridgecrewio/checkov-action@v12.1347.0
    - actions/setup-python@v5
    - ansible-lint==26.4.0
    - terragrunt v0.81.10 (binary install in fmt-check job)
  patterns:
    - SHA-pinned third-party actions (RESEARCH Pattern 1)
    - many small parallel jobs (RESEARCH Pattern 2)
    - paths-ignore for planning-doc churn (RESEARCH Pattern 4)
    - Checkov config with hard-fail-on HIGH (RESEARCH Pattern 5)
    - ansible-lint config with production profile + exclude_paths (RESEARCH Pattern 6)
key-files:
  created:
    - .github/workflows/ci.yml (224 lines, 8 jobs)
    - .checkov.yaml (35 lines)
    - .ansible-lint (26 lines)
  modified: []
decisions:
  - Use Checkov over Trivy/tfsec/KICS — Trivy was supply-chain-compromised March 2026 (TeamPCP); Checkov was never affected
  - 8 parallel jobs over 1 sequential job — wall-time 90s vs 6 min; cost neutral on personal repo
  - Separate ansible-lint and ansible-syntax-check jobs (RESEARCH Open Question 1) — both satisfy CI-04 and catch different bug classes
  - Use bridgecrewio/checkov-action default checkov version — version-pin input not relied on (RESEARCH Pitfall 2)
  - Bug-fix to grep-gates invariant 4 — plan's grep was self-invalidating; corrected form requires "==" prefix explicitly
metrics:
  duration: 292s (~5 min)
  completed-date: 2026-05-14
  tasks-completed: 3
  files-created: 3
  files-modified: 0
  commits: 2
---

# Phase 4 Plan 01: CI Workflow with 8 Parallel SHA-pinned Jobs — Summary

8 parallel-job GitHub Actions CI workflow with Checkov, ansible-lint, shellcheck, tofu/packer/terragrunt fmt+validate, and a single fail-fast grep-gates job protecting every Phase 3 invariant — every third-party action SHA-pinned to a 40-character commit hash.

## Outcome

Closed CI-01..CI-06 with three pure-additive files at the repo root:

- `.github/workflows/ci.yml` — 8 parallel jobs, all on `ubuntu-latest`, triggered on `push` and `pull_request` with `paths-ignore` for `.planning/**`, `**/*.md`, and `CLAUDE.md`. `permissions: contents: read` at workflow level.
- `.checkov.yaml` — `framework: terraform`, `hard-fail-on: HIGH`, `soft-fail-on: MEDIUM`, empty `skip-check:` list (no preemptive suppressions per RESEARCH Assumption A3).
- `.ansible-lint` — `profile: production`, `exclude_paths` for the vendored CIS role, the firewalld-docker-fix workaround, `.planning/`, and `.github/`.

Two atomic conventional commits:

| Hash      | Task   | Files                                           |
|-----------|--------|-------------------------------------------------|
| `6d75f0c` | Task 1 | `.checkov.yaml`, `.ansible-lint`                |
| `beb6743` | Task 2 | `.github/workflows/ci.yml`                      |

## Jobs and requirement coverage

| Job                    | Requirement | Action SHA / Tool                                                     |
|------------------------|-------------|------------------------------------------------------------------------|
| `fmt-check`            | CI-02       | `tofu fmt -check -recursive` + `packer fmt -check .` + `terragrunt hclfmt --check` |
| `tofu-validate`        | CI-02       | `tofu init -lockfile=readonly && tofu validate` (Phase 3 REP-01 anchor) |
| `packer-validate`      | CI-03       | `packer init . && packer validate .`                                   |
| `ansible-lint`         | CI-04       | `pip install ansible-lint==26.4.0`, `ansible-galaxy collection install -r ansible/requirements.yml`, `ansible-lint ansible/playbook.yml` |
| `ansible-syntax-check` | CI-04       | `ansible-playbook --syntax-check ansible/playbook.yml -i localhost,`   |
| `shellcheck`           | CI-05       | `shellcheck scripts/*.sh` (pre-installed on `ubuntu-latest`)           |
| `checkov`              | CI-06       | `bridgecrewio/checkov-action@99bb2caf247dfd9f03cf984373bc6043d4e32ebf` with `config_file: .checkov.yaml` (HIGH-fail) |
| `grep-gates`           | CI-01..06   | 7 invariants (Phase 3 + CI hardening) — see below                      |

`CI-01` (push + PR triggers) is satisfied by the workflow header. All 8 jobs run in parallel with no `needs:` dependencies; expected wall time ~90s.

## Action SHAs pinned

| Action                              | Tag        | SHA                                          |
|-------------------------------------|------------|----------------------------------------------|
| `actions/checkout`                  | v4.3.1     | `34e114876b0b11c390a56381ad16ebd13914f8d5` (reused from Phase 1 `security.yml`) |
| `opentofu/setup-opentofu`           | v2.0.0     | `fc711fa910b93cba0f3fbecaafc9f42fd0c411cb`   |
| `hashicorp/setup-packer`            | v3.2.0     | `c3d53c525d422944e50ee27b840746d6522b08de`   |
| `actions/setup-python`              | v5         | `a26af69be951a213d495a4c3e4e4022e16d87065` (**resolved at execution time** — was placeholder in plan) |
| `bridgecrewio/checkov-action`       | v12.1347.0 | `99bb2caf247dfd9f03cf984373bc6043d4e32ebf`   |

Resolution method for `actions/setup-python@v5`:
```
curl -sL https://api.github.com/repos/actions/setup-python/git/refs/tags/v5 \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['object']['sha'])"
```
Returned `a26af69be951a213d495a4c3e4e4022e16d87065` (lightweight tag pointing directly at the commit object, type=commit).

## Grep-gates invariants

The `grep-gates` job runs a single `bash -euo pipefail` block asserting seven invariants:

| # | Invariant                                          | Source                  |
|---|----------------------------------------------------|-------------------------|
| 1 | No `most_recent = true` in `packer/`               | REP-04 (Phase 3 plan 02)|
| 2 | No `ami_id = "ami-..."` in `terragrunt.hcl`        | REP-05                  |
| 3 | No `<RESOLVED-VERSION>` placeholder in `packer/`   | REP-06                  |
| 4 | All `version:` lines in `ansible/requirements.yml` use `==X.Y.Z` (quoted or unquoted) | REP-02 |
| 5 | `terraform/.terraform.lock.hcl` is tracked         | REP-01                  |
| 6 | No `terraform/.terraform.lock.hcl` line in `.gitignore` | REP-01 defense      |
| 7 | Every `uses:` in `.github/workflows/` SHA-pinned (40-char hex) | CI hardening |

## Threat mitigations applied

| Threat ID | Disposition | Implementation                                                |
|-----------|-------------|---------------------------------------------------------------|
| T-04-01   | mitigate    | Every `uses:` SHA-pinned to 40-char hex; grep-gates #7 enforces; reused Phase 1 `actions/checkout` SHA per RESEARCH Pitfall 6 |
| T-04-02   | mitigate    | `ansible-lint==26.4.0` exact pin; checkov inherits action's bundled version (TODO: pin once action input verified) |
| T-04-03   | mitigate    | Used plain `pull_request` event (never `pull_request_target`); fork PRs run with read-only token |
| T-04-04   | mitigate    | `permissions: contents: read` at workflow level — no push-back token |
| T-04-05   | accept      | No `${{ secrets.* }}` referenced in `ci.yml`; gitleaks job in `security.yml` is separate |
| T-04-06   | mitigate    | Did not set `checkov_version` input (compatibility uncertain across v12 minors); added TODO comment + follow-up plan to pivot to `pip install checkov==3.2.528` if input proves unstable |
| T-04-07   | mitigate    | `paths-ignore: ['.planning/**', '**/*.md', 'CLAUDE.md']` skips ci.yml on planning-doc commits |
| T-04-08   | mitigate    | Invariant 4 uses explicit `==` requirement (Rule 1 bug fix below) — no self-invalidating-grep-gate |
| T-04-09   | mitigate    | `tofu init -lockfile=readonly` only; lockfile cannot be silently rewritten in CI |
| T-04-10   | accept      | `runs-on: ubuntu-latest` only; no self-hosted runners |

## Smoke test results

| Smoke | Result | Notes |
|-------|--------|-------|
| 1 — YAML parse on all 3 files | PASS | `python3 -c "import yaml; yaml.safe_load(...)"` for `.github/workflows/ci.yml`, `.checkov.yaml`, `.ansible-lint`; all loaded clean |
| 2 — grep-gates locally against HEAD | PASS | All 7 invariants pass (1=no match, 2=no match, 3=no match, 4=no match after correction, 5=tracked, 6=no match, 7=no leaks) |
| 3 — checkov dry-run | SKIPPED | `checkov` not installed on operator workstation; informational-only per plan; first CI run will surface findings |
| 4 — action-SHA invariant on new file | PASS | `grep -hE 'uses: ... @(v[0-9]+\|main\|master\|HEAD)\b' .github/workflows/ci.yml \| grep -v '@[a-f0-9]\{40\}'` produced empty output |

`yamllint` (with relaxed line-length and disabled `truthy` rule — `on:` parses as Python `True` in YAML 1.1) reported zero errors and zero warnings on all three files.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Corrected self-invalidating grep-gate invariant #4**

- **Found during:** Pre-Task-2 smoke run of the plan's literal grep invariant against HEAD
- **Issue:** The plan (and the underlying RESEARCH lines 273-280 + Phase 3 plan 03-01 SUMMARY line 141) specified invariant 4 as:
  ```
  ! grep -vE '^[[:space:]]*#' ansible/requirements.yml | grep -E '^[[:space:]]*version:[[:space:]]*[^=]'
  ```
  This is the canonical self-invalidating-grep-gate antipattern. The actual `ansible/requirements.yml` content is `    version: "==12.6.0"` — the first non-whitespace char after `version: ` is `"`, NOT `=`. The grep matches the legal quoted form and the gate "fails-on-pass" (exits 0 instead of 1).
- **Fix:** Replaced with an explicit-permit form that requires `==` (quoted or unquoted) to appear immediately after the value:
  ```
  if grep -vE '^[[:space:]]*#' ansible/requirements.yml \
       | grep -E '^[[:space:]]*version:' \
       | grep -vE 'version:[[:space:]]*"?==' ; then
    echo "FAIL: bare-version pin found in ansible/requirements.yml (REP-02)" >&2
    exit 1
  fi
  ```
  Verified against current HEAD (empty output → gate passes) and against a synthetic fixture with a bare `version: 1.2.3` line (matches → gate fails as intended).
- **Files modified:** `.github/workflows/ci.yml` (grep-gates job) — bundled into the Task 2 commit.
- **Commit:** `beb6743`

No other deviations. No architectural changes. No auth gates encountered.

## Plan boundary check

- `.github/workflows/security.yml` byte-identical to HEAD before this plan started (confirmed via `git diff 521a70b -- .github/workflows/security.yml` returns empty).
- `.pre-commit-config.yaml` not modified by this plan's two commits (`git show --stat <hash> -- .pre-commit-config.yaml` empty for both). `.pre-commit-config.yaml` IS modified by parallel-wave plan 04-02 (commit `afddc82`) but that is the correct ownership.
- `CLAUDE.md` and `ansible/firewalld-docker-fix.yml` not modified by this plan (commits `8d4be9a` and `8cab699` are plan 04-03's work, sandwiched between this plan's two commits — expected in Wave-1 parallel execution).

## Follow-ups for downstream plans

- **Plan 04-02 (pre-commit):** When wiring `tofuutils/pre-commit-opentofu` v2.3.0 `tofu_validate` hook, verify it honors `tofu init -lockfile=readonly` (RESEARCH Assumption A5) — if it rewrites the lockfile silently, fall back to a `local` hook that calls `tofu init -lockfile=readonly` directly.
- **Plan 04-02:** Mirror these 7 grep-gates into a `local` pre-commit hook so the gate runs at commit time too (pre-commit + CI tier). Use the same corrected invariant-4 form.
- **First CI run (post-merge):** Capture any HIGH Checkov findings on the post-Phase-3 tree and triage with an explicit follow-up commit. Per RESEARCH Assumption A3, this is the moment they surface; do NOT pre-suppress in `.checkov.yaml`.
- **`checkov_version` input verification:** First CI run will show the bundled Checkov version in the action log. If it diverges from `3.2.528`, switch the checkov job to a `pip install checkov==3.2.528 && checkov -d terraform/ --config-file .checkov.yaml` script step (RESEARCH Pitfall 2).
- **`actions/setup-python` SHA-pin documentation:** The plan's `<interfaces>` left this SHA as a placeholder. Future plans that touch CI should reuse `a26af69be951a213d495a4c3e4e4022e16d87065` (v5) until v6 is current.

## Self-Check: PASSED

| Claim                                    | Verification                                                | Result |
|------------------------------------------|-------------------------------------------------------------|--------|
| `.checkov.yaml` exists                   | `test -f .checkov.yaml`                                     | FOUND  |
| `.ansible-lint` exists                   | `test -f .ansible-lint`                                     | FOUND  |
| `.github/workflows/ci.yml` exists        | `test -f .github/workflows/ci.yml`                          | FOUND  |
| Commit `6d75f0c` exists                  | `git log --oneline --all | grep -q 6d75f0c`                 | FOUND  |
| Commit `beb6743` exists                  | `git log --oneline --all | grep -q beb6743`                 | FOUND  |
| 8 jobs in ci.yml                         | `awk '/^jobs:/{f=1;next} f && /^  [a-z-]+:$/' counts to 8`  | 8      |
| `.github/workflows/security.yml` untouched | `diff <(git show 521a70b:.github/workflows/security.yml) .github/workflows/security.yml` | IDENTICAL |
| All action SHAs are 40-char hex          | `grep -E '@[0-9a-f]{40}' ci.yml \| wc -l`                   | 15     |
| Grep-gates locally PASS                  | bash inline run of all 7 invariants                         | PASS   |

**Verdict: COMPLETE**
