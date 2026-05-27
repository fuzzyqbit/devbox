---
phase: 06-gitlab-ci-polish
reviewed: 2026-05-27T14:30:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - run
  - .gitlab-ci.yml
  - .pre-commit-config.yaml
findings:
  critical: 2
  warning: 3
  info: 2
  total: 7
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-05-27T14:30:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Three files reviewed: the `run` CLI entrypoint (523 lines), `.gitlab-ci.yml` (441 lines), and `.pre-commit-config.yaml` (163 lines). The implementation is generally solid -- well-documented, consistent naming, proper guards and validation. Two critical issues were found: a workflow rule that silently skips CI validation when pushes contain any markdown file alongside source files, and a missing protected-branch gate on scheduled bake pipelines. Three warnings cover a misleading comment about GitLab extends behavior, a temp-file leak path, and a grep-gates invariant that false-passes on missing files.

## Critical Issues

### CR-01: Workflow rule skips push pipelines containing any markdown file, not just markdown-only pushes

**File:** `.gitlab-ci.yml:129-132`
**Issue:** The `workflow:rules` block intended to skip pipelines for markdown-only pushes uses `changes: ['**/*.md']` combined with `when: never`. GitLab CI `changes:` evaluates to true when **any** changed file matches the pattern, not when **all** changed files match. Therefore, a push that modifies both `run` and `README.md` would trigger this rule (because `README.md` matches `**/*.md`) and the entire pipeline would be skipped -- no validation, no gates.

This means any commit to `main` that includes a markdown file alongside source changes silently bypasses all CI checks, violating the validation-gate contract.

**Fix:** Remove the markdown-only skip rule entirely, or invert the logic to list source file patterns that should trigger the pipeline:

```yaml
workflow:
  rules:
    # Push/MR pipelines: only run when source (non-markdown) files change.
    - if: $CI_PIPELINE_SOURCE == "push"
      changes:
        - '*.sh'
        - 'run'
        - 'packer/**/*'
        - 'terraform/**/*'
        - 'ansible/**/*'
        - 'scripts/**/*'
        - '.gitlab-ci.yml'
        - '.pre-commit-config.yaml'
        - '.checkov.yaml'
        - '.gitleaks.toml'
        - 'Makefile'
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    # Web-triggered and schedule rules unchanged...
    - if: $CI_PIPELINE_SOURCE == "web" && $PIPELINE_KIND == "bake"
    - if: $CI_PIPELINE_SOURCE == "web" && $PIPELINE_KIND == "deploy"
    - if: $CI_PIPELINE_SOURCE == "schedule" && $PIPELINE_KIND == "bake"
    - when: never
```

Alternatively, the simplest safe fix is to delete lines 129-132 entirely and accept that markdown-only pushes run the (cheap) validate stage:

```yaml
workflow:
  rules:
    # Push/MR pipelines run validate only (no PIPELINE_KIND required).
    - if: $CI_PIPELINE_SOURCE == "push"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    # ... rest unchanged
```

### CR-02: Scheduled bake pipeline missing protected-branch guard

**File:** `.gitlab-ci.yml:384`
**Issue:** The `bake:packer-build` job rule for web-triggered pipelines (line 383) requires `$CI_COMMIT_REF_PROTECTED == "true"`, but the schedule trigger rule on line 384 does not. A pipeline schedule misconfigured on a non-protected feature branch could bake and publish an AMI from unreviewed, untested code. Since bake produces a real AMI in AWS (the cost guardrail comment on lines 370-371 acknowledges this), the security posture should be symmetric.

**Fix:** Add the protected-branch guard to the schedule rule:

```yaml
  rules:
    - if: $CI_PIPELINE_SOURCE == "web" && $PIPELINE_KIND == "bake" && $CI_COMMIT_REF_PROTECTED == "true"
    - if: $CI_PIPELINE_SOURCE == "schedule" && $PIPELINE_KIND == "bake" && $CI_COMMIT_REF_PROTECTED == "true"
```

## Warnings

### WR-01: Misleading comment about GitLab extends behavior in deploy:tofu-apply

**File:** `.gitlab-ci.yml:418-419`
**Issue:** The comment states "The `!extends` of .aws-auth concatenates before_scripts, so this block executes first." This is incorrect. GitLab `extends:` does **not** concatenate `before_script` arrays -- it **overrides** at the key level. The job works correctly only because line 433 uses `!reference [.aws-auth, before_script]` to manually re-include the parent template's before_script. The misleading comment could lead a future maintainer to remove the `!reference` tag (believing `extends` handles the merge), which would silently break AWS authentication for the deploy job.

**Fix:** Correct the comment to explain the actual mechanism:

```yaml
    # DEVBOX_USER fail-fast. Must run BEFORE .aws-auth's before_script so we
    # don't waste an STS AssumeRole on a bad input. GitLab `extends:` OVERRIDES
    # before_script (does not merge); the !reference tag on the last line below
    # explicitly re-includes .aws-auth's before_script after this validation.
```

### WR-02: Temp file leak in cmd_secrets_show on unexpected exit

**File:** `run:403`
**Issue:** `cmd_secrets_show` creates a temp file via `mktemp` (line 403) and removes it on the two known error paths (lines 411, 420) and the success path (line 423). However, if the function exits unexpectedly due to `set -e` triggering on an unhandled failure between `mktemp` and the cleanup, the temp file is orphaned. The temp file may contain AWS CLI error output which could include account-scoped information.

**Fix:** Add a trap to ensure cleanup:

```bash
cmd_secrets_show() {
  _require_devbox_user
  echo "Resolving secrets for DEVBOX_USER=${DEVBOX_USER}..."
  local cs_pwd vnc_pwd
  local aws_err
  aws_err="$(mktemp)"
  trap 'rm -f "$aws_err"' RETURN
  # ... rest of function unchanged, remove the explicit rm -f lines
}
```

### WR-03: grep-gates invariant #2 silently passes when terraform.tfvars is missing

**File:** `.gitlab-ci.yml:266`
**Issue:** Invariant #2 (`! grep -E '...' terraform/terraform.tfvars`) will return exit code 2 (file not found) if `terraform/terraform.tfvars` does not exist. The `!` negation turns this into exit code 0, so the invariant passes silently. While the file exists today and other validate jobs (tofu-validate, tofu-fmt) would catch a missing tfvars, the grep gate would give a false green if the file were accidentally deleted. The same issue exists in the pre-commit mirror at `.pre-commit-config.yaml:107`.

**Fix:** Add a file-existence check before the grep:

```bash
# 2. No hand-copied AMI ID in terraform.tfvars (REP-05)
test -f terraform/terraform.tfvars
! grep -E '^[[:space:]]*ami_id[[:space:]]*=[[:space:]]*"ami-' terraform/terraform.tfvars
```

## Info

### IN-01: Redundant condition in _derive_tf_state_bucket

**File:** `run:220`
**Issue:** The condition `[[ "devimage-tfstate-${account_id}" == "devimage-tfstate-" ]]` is logically redundant with the preceding `[[ -z "$account_id" ]]` check. If `account_id` is empty, the first condition catches it; if non-empty, the second condition can never be true.

**Fix:** Simplify:

```bash
if [[ -z "$account_id" ]]; then
```

### IN-02: check-yaml excludes .gitleaks.toml unnecessarily

**File:** `.pre-commit-config.yaml:84`
**Issue:** The `check-yaml` hook excludes `\.gitleaks\.toml` from its file list. Since `check-yaml` only runs against YAML files (via its `types: [yaml]` default), a `.toml` file would never be passed to it. The exclusion is dead configuration.

**Fix:** Remove the `.gitleaks.toml` entry from the exclude pattern:

```yaml
      - id: check-yaml
        stages: [pre-commit]
        exclude: |
          (?x)^(
            ansible/.*\.yml
          )$
```

---

_Reviewed: 2026-05-27T14:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
