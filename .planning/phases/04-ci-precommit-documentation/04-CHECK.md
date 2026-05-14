# Phase 4: CI, pre-commit, and documentation — Plan Check

**Checked:** 2026-05-14
**Plans verified:** 04-01-PLAN.md, 04-02-PLAN.md, 04-03-PLAN.md
**Phase goal:** Full CI + tiered pre-commit + operator docs (final milestone phase)

## Verdict

**PASS**

All 9 requirements (CI-01..07, DOC-01/02) covered exactly once across 3 Wave-1 plans with disjoint file scopes. Every load-bearing technical decision from RESEARCH (Checkov over Trivy/tfsec, SHA-pinning, OpenTofu-native pre-commit hook, paths-ignore on ci.yml only, comment-filtered grep gates, lockfile=readonly, galaxy install before lint, security.yml untouched) is correctly wired into the plan tasks and verified by automated checks. Plans are execution-ready.

## Dimension Scores

| # | Dimension | Result | Note |
|---|-----------|--------|------|
| 1 | Coverage (CI-01..07, DOC-01/02 exactly once) | PASS | 04-01:CI-01..06, 04-02:CI-07, 04-03:DOC-01/02. Frontmatter `requirements:` matches REQUIREMENTS.md + ROADMAP.md mapping (table line 149-157). |
| 2 | Parallel safety (3 plans Wave 1, disjoint files) | PASS | `files_modified` sets disjoint: 04-01={ci.yml, .checkov.yaml, .ansible-lint}; 04-02={.pre-commit-config.yaml}; 04-03={CLAUDE.md, ansible/firewalld-docker-fix.yml}. All `wave: 1`, `depends_on: []`. |
| 3 | Checkov over tfsec/Trivy/KICS | PASS | 04-01 uses `bridgecrewio/checkov-action@99bb2caf...` (line 93, 258); no tfsec/Trivy/KICS in execution scope. Sole mention of "Trivy" is in T-04-03 (04-01:415) documenting attack-vector avoidance. |
| 4 | Action SHA pinning (40-char hex) | PASS | All third-party actions pinned: actions/checkout `34e114876b0b11c390a56381ad16ebd13914f8d5`, opentofu/setup-opentofu `fc711fa9...`, hashicorp/setup-packer `c3d53c52...`, bridgecrewio/checkov-action `99bb2caf...` (04-01:88-93). actions/setup-python correctly flagged as RESOLVE AT EXECUTION TIME with curl + jq command (04-01:94-96). grep-gates invariant #7 enforces (04-01:120). |
| 5 | paths-ignore on ci.yml only | PASS | ci.yml gets `paths-ignore: ['.planning/**', '**/*.md', 'CLAUDE.md']` on push + pull_request (04-01:198-207, 319). security.yml explicitly NOT modified — boundary asserted in must_haves (04-01:26), three smoke tests (04-01:311-312, 377, 385), and verification block (04-01:435). |
| 6 | Tiered pre-commit (fast/slow) | PASS | 04-02 keeps `default_stages: [pre-commit]` (line 161); puts gitleaks/no-changeme/tofu_fmt/terragrunt_fmt/shellcheck/pre-commit-hooks/packer-fmt/grep-gates at `stages: [pre-commit]` (≥8 explicit per verify line 339); puts tofu_validate/ansible-lint/packer-validate/checkov at `stages: [pre-push]` (≥4 explicit per verify line 338). Documents the three `pre-commit install` invocations in header (04-02:135-138, 158). |
| 7 | OpenTofu-native pre-commit hook | PASS | 04-02 uses `tofuutils/pre-commit-opentofu v2.3.0` for `tofu_fmt` (line 186-190) and `tofu_validate` (line 264-268). Uses `antonbabenko/pre-commit-terraform v1.105.0` ONLY for `terragrunt_fmt` (line 192-196) — correctly scoped to terragrunt since the OpenTofu fork delegates terragrunt to upstream. Rationale: `terragrunt.hcl:22 terraform_binary = "tofu"`. |
| 8 | Grep gates duplication + comment-filter | PASS | All 6 Phase-3 invariants appear in BOTH ci.yml grep-gates job (04-01:110-116, 267) AND .pre-commit-config.yaml local hook (04-02:114-120, 236-246). Invariant #4 uses comment-filtered form `! grep -vE '^[[:space:]]*#' ansible/requirements.yml \| grep -E '^[[:space:]]*version:[[:space:]]*[^=]'` in both locations (04-01:113, 04-02:117, 242) — self-invalidation defense explicit. ci.yml carries the additional action-SHA invariant #7 (04-01:120); deliberately scoped server-side only per 04-02:122. |
| 9 | `tofu init -lockfile=readonly` | PASS | tofu-validate job uses `tofu init -lockfile=readonly` (04-01:226, 301 verify, 321 done) per RESEARCH Pitfall 4. Phase 3 REP-01 protection asserted in must_haves (04-01:23). |
| 10 | ansible-galaxy install before lint | PASS | Both ansible-lint job (04-01:239) AND ansible-syntax-check job (04-01:247) run `ansible-galaxy collection install -r ansible/requirements.yml` BEFORE the lint/syntax invocations. Verify command `grep -q 'ansible-galaxy collection install'` (04-01:302). Cites RESEARCH Pitfall 5. |
| 11 | CLAUDE.md scope (9 sections + UX tools) | PASS | 04-03 lists all 9 RESEARCH sections in <interfaces> (lines 82-92) and verify block greps for `session-manager-plugin`, `ssh-keygen`, `aws ec2 import-key-pair`, `make secrets-show`, `make packer-bake`, `make devbox-ssm`, `make devbox-port-forward`, `make devbox-allowlist-me`, 3x `pre-commit install` invocations, `terraform/.terraform.lock.hcl`, `SSM`, hardening, invariants, follow-up (lines 196-216). Phase 2 hybrid posture + Phase 3 REP-04 deferred follow-up explicitly required (04-03:106-113). |
| 12 | firewalld-docker doc (3 retirement criteria) | PASS | 04-03 Task 2 inserts retirement block with all 3 OR-joined criteria (CIS lifted, containers layer removed, per-port allowances in roles/hardening) (04-03:115-119, 245-269), verification command `firewall-cmd --get-default-zone` (04-03:264), and bidirectional cross-ref to CLAUDE.md (04-03:268-269). Append-only: existing 26-line header preserved verbatim (04-03:236-240). |
| 13 | Threat models (spot-check 3 entries/plan) | PASS | 04-01: T-04-01 SHA-pin mitigation, T-04-04 contents:read permission, T-04-08 self-invalidation defense — all map to visible plan content. 04-02: T-04-11 rev-pin, T-04-12 server-side ci.yml backstop, T-04-16 explicit per-hook stages — all map to plan tasks. 04-03: T-04-18 gitleaks example-cred allowlist (Smoke 4), T-04-19 Smoke 2 Makefile-target reality check, T-04-22 OR-joined testable criteria — all map to plan tasks. |
| 14 | Verification commands present | PASS | Each plan has `<verify><automated>` block per task + Smoke 1-N enumerated. 04-01 has 3 tasks with verify blocks (lines 161-172, 280-313, 380-388) plus 4 smokes. 04-02 has 2 tasks with verify blocks (lines 313-341, 428-435) plus 5 smokes. 04-03 has 3 tasks with verify blocks (lines 188-217, 287-300, 377-388) plus 6 smokes. |
| 15 | No regressions on Phase 1 locked files | PASS | security.yml: 04-01 asserts byte-identical to HEAD via 4 different checks; 04-02 asserts via `git diff HEAD~1`; 04-03 asserts via `git diff HEAD~2 -- .github/workflows/`. .pre-commit-config.yaml: 04-01 asserts `git diff HEAD~2 -- .pre-commit-config.yaml` empty (boundary at 04-01:378, 386). 04-02 explicitly APPENDS — preserves existing gitleaks rev v8.30.1 and no-changeme `entry:` verbatim (04-02:149, 153, 179). default_stages: [pre-commit] preserved (04-02:161). |

## Findings

No BLOCKERs. No WARNINGs material to phase delivery. The minor-quality observations below are INFO only and do not impede execution:

- **INFO** (04-03:107) — The SSM `:NN` follow-up text quotes a forward reference: "the Phase 4 grep gate `grep -E '/aws/service/ami-amazon-linux-latest/.*:[0-9]+'` will start failing once :NN is added". That gate is not currently in plan 04-01's grep-gates job (only the 6 RESEARCH-listed invariants + action-SHA invariant). Not a blocker — the follow-up text is forward-looking documentation, not a contract; if the executor wants this ratchet, it would be a future-phase addition. Recommend either dropping the quoted regex from CLAUDE.md or adding it to a future ratchet plan.
- **INFO** (04-01:94-96) — `actions/setup-python` SHA marked "RESOLVE AT EXECUTION TIME". This is acceptable per the planner-authority limit (RESEARCH did not pre-resolve it), but the executor must remember to do it. Output template (04-01:457) does capture this in SUMMARY.
- **INFO** (04-02:301) — Comment notes that `tofuutils/pre-commit-opentofu` v2.3.0 "appears TWICE in `repos:`" (once for tofu_fmt fast, once for tofu_validate slow). pre-commit framework does support this idiom, but some operators consolidate into a single repo block with two hook entries. The split form here is clearer for stage-tier diffing — acceptable as-is.
- **INFO** (04-02:304) — `checkov` local pre-push hook depends on `.checkov.yaml` from 04-01. Plan 04-02 documents the order-of-merge consequence in SUMMARY but does not formally depend_on 04-01 since both are Wave 1 with disjoint `files_modified`. Acceptable — operator UX recovery is clear (pull main with both landed before `pre-commit install --hook-type pre-push`).

## Recommended next step

Plans pass pre-execution check. Run `/gsd-execute-phase 04` to land all three plans in parallel (Wave 1). After execution:
1. 04-01's SUMMARY captures `actions/setup-python` resolved SHA + first-run Checkov findings (Assumption A3).
2. 04-02's SUMMARY captures Smoke 4 (Assumption A5: did `tofu_validate` rewrite the lockfile? — Phase 3 REP-01 silent-regression check) and Smoke 5 (autoupdate dry-run diffs).
3. 04-03's SUMMARY captures Smoke 2 Makefile-target reality check (zero MISSING lines).
4. Phase transition closes Milestone 1.
