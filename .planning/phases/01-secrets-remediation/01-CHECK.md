# Phase 1 Plan Check — Secrets remediation

**Checked:** 2026-05-13
**Plans verified:** 01-01-PLAN.md, 01-02-PLAN.md, 01-03-PLAN.md
**Method:** Goal-backward verification against ROADMAP.md Phase 1 success criteria + the ten dimensions specified in the check brief.

## Verdict

**PASS** (with two non-blocking WARN findings that should be addressed during execution but do not require re-planning)

## Dimension Scores

| # | Dimension | Score | Note |
|---|-----------|-------|------|
| 1 | Coverage | PASS | SEC-01..02 → 01-01; SEC-03..04 → 01-02; SEC-05 → 01-03. Each requirement appears in `requirements:` frontmatter of exactly one plan; all four ROADMAP success criteria are addressed (per-build secret generation, instance-profile fetch, per-operator key, gitleaks gate). |
| 2 | Wave order | PASS | 01-01 (Wave 1, deps=[]) and 01-03 (Wave 1, deps=[]) touch disjoint file domains (`ansible/` vs `.pre-commit-config.yaml`/`.github/`/`.gitleaks.toml`). 01-02 (Wave 2, deps=["01"]) genuinely extends `ansible/roles/secrets/tasks/main.yml` created by 01-01 — real dependency, not contrived. |
| 3 | Executability | PASS | Every task has concrete file paths with line-number anchors (e.g. `ansible/roles/desktop/tasks/main.yml:29-33`, `terragrunt.hcl:30`, `terraform/variables.tf:51-55`); each action includes verbatim before/after snippets and explicit `<verify>` shell commands. A downstream executor can mechanically apply each change. |
| 4 | Threat model | PASS | All three plans contain a detailed `<threat_model>` with Trust Boundaries + STRIDE register: 01-01 has 9 threats (T-01-01..09), 01-02 has 12 (T-02-01..12), 01-03 has 7 (T-03-01..07). Each threat carries a disposition (mitigate/accept) and a concrete mitigation path or process control. Not perfunctory. |
| 5 | Locked decisions honored | PASS | SSM Parameter Store SecureString (01-02 publish.yml `string_type: SecureString`); `auth: password` retained in code-server template (01-01 Task 2 explicitly rejects `auth: none`); VNC password length 8 (01-01 defaults `secrets_vnc_password_length: 8`); systemd oneshot baked into AMI, NOT user_data (01-02 Task 3); gitleaks v8.30.1 (01-03 Task 1, NOT detect-secrets/trufflehog); per-operator SSH key via `${local.user}-devbox` import-key-pair (01-02 Task 4). |
| 6 | IMDSv2 enforced | PASS | `terraform/main.tf` `aws_instance.devbox` `metadata_options { http_tokens = "required"; instance_metadata_tags = "enabled"; http_put_response_hop_limit = 1 }` — all three IMDSv2 settings present in 01-02 Task 2. Bootstrap script uses `X-aws-ec2-metadata-token` PUT for session tokens. |
| 7 | No new operator deps | WARN | `gitleaks` is a new CLI required on the operator workstation for pre-commit (`brew install gitleaks pre-commit`). It is transitively invoked by `pre-commit` (already in scope per the dimension's allowlist), so it is a hook implementation detail rather than a `make`-target dependency. Surface this explicitly in CLAUDE.md (Phase 4 DOC-01) so operators are not surprised. Not a blocker. |
| 8 | Rollback | WARN | No explicit `<rollback>` block in any plan. Implicit rollback = `git revert` per commit + `make tg-apply` to redeploy. Adequate for an IaC repo with atomic conventional commits (the plans produce 4/4/2 atomic commits respectively), but the rollback story is not spelled out and the `key_name` rename in 01-02 makes "git revert + apply" insufficient on its own — the operator must also keep the old AWS keypair `"me"` registered until they have imported the new one. Recommend adding a one-line `<rollback>` to each plan during execution. |
| 9 | Documented breaking changes | PASS | 01-02 Task 4 explicitly flags the `key_name = "me"` → `${local.user}-devbox` rename as breaking, documents the two operator-side remediation paths (re-import under new name OR keep `DEVBOX_USER=me` and import `me-devbox`), surfaces the requirement in `user_setup` frontmatter, and references T-02-04 in the threat model. The `iam_instance_profile` variable deletion is justified inline (Task 2 step 3) by reading the actual consumer at `terragrunt.hcl:27-37` and confirming it is unset — observably safe. |
| 10 | Verification commands | PASS | Every plan ships a `<verification>` section with executable smoke commands. 01-01: localhost smoke + no-`changeme` git grep + 5×`no_log: true` count. 01-02: `terraform validate` + `packer validate -var devbox_user=...` + `ansible-playbook --syntax-check` + `make secrets-show DEVBOX_USER=__nonexistent__` error-path test. 01-03: planted-secret human-verify checkpoint covering both pre-commit and CI gates. |

## Findings

### F-01 (WARN) — gitleaks introduces a new operator dependency

- **Where:** `.planning/phases/01-secrets-remediation/01-03-PLAN.md` (Task 1 + Checkpoint Task 3)
- **What:** `.pre-commit-config.yaml` pins `repo: https://github.com/gitleaks/gitleaks` at `rev: v8.30.1`. The checkpoint task instructs operators to `brew install gitleaks pre-commit`. PROJECT.md constraint at line 59 says "Operator surface: Must remain `make <target>` — no GUI, no extra CLI tools beyond what's already required (aws, jq, packer, tofu/terraform, terragrunt, ansible)." `pre-commit` and `git` are reasonably implied; `gitleaks` is genuinely new.
- **Severity:** WARN — gitleaks is the literal SEC-05 deliverable; replacing it would violate the locked decision. The dependency is transitive through `pre-commit`, which is already on the operator surface.
- **Recommended revision:** During Phase 4 (DOC-01), add a one-liner to CLAUDE.md under "Operator one-time setup": `brew install gitleaks pre-commit && pre-commit install`. The 01-03 plan already documents this in the Task 1 header comment and the checkpoint's `<how-to-verify>`; carry it forward to CLAUDE.md. No change to Phase 1 plans required.

### F-02 (WARN) — Plans lack explicit `<rollback>` sections

- **Where:** All three plans (`01-01-PLAN.md`, `01-02-PLAN.md`, `01-03-PLAN.md`).
- **What:** Every plan produces atomic conventional commits (4 + 4 + 2), and "rollback = git revert + redeploy" is the implicit posture. But:
  - 01-02's `key_name` rename is not reversible by `git revert` alone if the operator has already destroyed the old `"me"` keypair in AWS; the operator must keep `"me"` registered until they have imported the new key, OR be prepared to re-import `"me"` from a local backup.
  - 01-02 also deletes `var.iam_instance_profile` — reverting requires re-declaring the variable AND re-wiring its consumer.
  - The systemd-oneshot in 01-02 is one-shot per instance via `ConditionPathExists=!/var/lib/devbox/secrets-applied`; rolling back the AMI does not roll back the marker on existing instances.
- **Severity:** WARN — execution can proceed because the rollback path *exists*, it just isn't written down.
- **Recommended revision:** Before executing 01-02, add a `<rollback>` block to its plan body with three steps: (a) `git revert <commit-SHA-for-feat(terragrunt)>` to restore `key_name = "me"`; (b) ensure the AWS keypair named `"me"` still exists or re-import it via `aws ec2 import-key-pair`; (c) `make tg-apply` to push the reverted config. Mirror the pattern in 01-01 (revert four commits, no AWS-side action required) and 01-03 (revert two commits, then `pre-commit uninstall` if desired). One paragraph per plan is sufficient; no need to re-plan.

## Side-bar: deletion of `var.iam_instance_profile`

Verified safe. The Terragrunt consumer `terragrunt.hcl:27-37` does not currently set `iam_instance_profile`, the Terraform default is `null`, and PROJECT.md "Multi-tenant / shared infrastructure: out of scope" confirms single-consumer. Plan 01-02 Task 2 step 3 documents this inline with the exact reasoning, and `terraform/outputs.tf:36-39` is updated to reference the managed profile rather than the deleted variable. No further action required.

## Recommended next step

`proceed to /gsd-execute-phase 1`

The two WARN findings (F-01, F-02) should be addressed *during* execution as one-line edits to the plan files or as commit-message annotations — they are documentation gaps, not structural defects. No re-planning is required. The plans, as written, will deliver SEC-01..SEC-05 in full alignment with the locked decisions in `01-RESEARCH.md`.
