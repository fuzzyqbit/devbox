---
phase: 01-secrets-remediation
verified: 2026-05-13T19:25:00Z
status: passed
score: 5/5 must-haves verified
verdict: COMPLETE
re_verification:
  is_re_verification: false
verifier: goal-backward, adversarial
---

## Verdict

**COMPLETE**

Phase 1 achieved its goal. Every CRITICAL/HIGH item the phase promised to close has corresponding, verifiable code in the working tree (not just SUMMARY narrative): per-build random secrets via the `secrets` Ansible role with `no_log: true` on every secret-touching task, SSM SecureString publish + IAM instance profile + IMDSv2 + `kms:ViaService`-conditioned KMS decrypt, per-operator `${local.user}-devbox` key, and a gitleaks gate in both pre-commit and a SHA-pinned GitHub Actions workflow. `terraform validate` and `ansible-playbook --syntax-check` both pass against the modified tree. The three remaining `changeme` occurrences in code are all defensive `!= "changeme"` assertion guards, not assignments — exactly the security feature the plan intended.

## Requirement coverage

| Requirement | Status | Evidence |
|---|---|---|
| **SEC-01** code-server password generated per-build, no `changeme` in repo | **PASS** | `ansible/roles/vscode/templates/config.yaml.j2:3` renders `password: "{{ code_server_password }}"`. Fact bound at `ansible/roles/secrets/tasks/generate.yml:2-7` via `lookup('ansible.builtin.password', '/dev/null length=32 chars=ascii_letters,digits')`. Commits `afeed6e`, `f474895`. |
| **SEC-02** VNC password generated per-build, no `changeme` in repo | **PASS** | `ansible/roles/desktop/defaults/main.yml` no longer carries `desktop_vnc_password: "changeme"` (verified — the line is absent at the position the plan diffs from line 7). Fact generated at `ansible/roles/secrets/tasks/generate.yml:9-14`. VNC task `ansible/roles/desktop/tasks/main.yml:41-48` uses `ansible.builtin.shell` with `stdin:`, `changed_when: true`, `no_log: true`, and NO `creates:` guard. Commit `cba6269`. |
| **SEC-03** Secrets stored in AWS SSM SecureString, fetched via EC2 instance profile | **PASS** | Publish: `ansible/roles/secrets/tasks/publish.yml:21-39` uses `community.aws.ssm_parameter` with `string_type: SecureString`, `overwrite_value: always`, `no_log: true`. IAM: `terraform/main.tf:33-85` defines `aws_iam_role.devbox` + `aws_iam_role_policy.devbox_ssm_read` (scoped to `parameter/devbox/${var.devbox_user}/*`) + `aws_iam_instance_profile.devbox`; `kms:Decrypt` is gated by `kms:ViaService = "ssm.${region}.amazonaws.com"` (line 73). Instance wired at `terraform/main.tf:146`. IMDSv2 enforced at `terraform/main.tf:149-154` (`http_tokens=required`, `instance_metadata_tags=enabled`, `http_put_response_hop_limit=1`). Boot-time fetch: `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:11-34` reads IMDSv2 token, DevboxUser tag, fetches both SSM SecureStrings via `aws ssm get-parameter --with-decryption`. Commits `c84f1fa`, `187d57d`, `9b98557`. |
| **SEC-04** Per-operator SSH keypair, documented rotation | **PASS** | `terragrunt.hcl:32` reads `key_name = "${local.user}-devbox"` (hardcoded `"me"` literal is gone — `grep` returns empty). Rotation procedure documented in `01-02-SUMMARY.md` Breaking Changes section with `aws ec2 import-key-pair` / `aws ec2 delete-key-pair` recipe and PROJECT.md Key Decisions row (`.planning/PROJECT.md:72`). Commit `964fbae`. |
| **SEC-05** gitleaks gates in pre-commit and CI; build fails on detected secret | **PASS** | `.pre-commit-config.yaml:13-16` references `gitleaks/gitleaks@v8.30.1` + `no-changeme` local hook (`.pre-commit-config.yaml:21-27`). `.github/workflows/security.yml` runs on `push` and `pull_request` with SHA-pinned `gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7` (v2) and `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (v4); `fetch-depth: 0`; `permissions: contents: read`. `.gitleaks.toml` extends defaults (`useDefault = true`) with narrow allowlist for AWS canonical example creds scoped to `.planning/**` and `*.md`. Commits `a38ae14`, `67a7fc5`. |

All 5 requirements **PASS**. Phase goal (eliminate `changeme`, SSM delivery via instance profile, per-operator SSH key, gitleaks gates) achieved.

## Check results

| # | Check | Result | Output snippet |
|---|-------|--------|----------------|
| 1 | `git grep -nIi 'password.*changeme\|changeme.*password' -- ':!.planning/' ':!*.md'` | **PASS** | 4 matches; all are inside `!= "changeme"` assertion guards (`ansible/roles/desktop/tasks/main.yml:7`, `ansible/roles/secrets/tasks/generate.yml:21`, `ansible/roles/secrets/tasks/generate.yml:31`) plus the `no-changeme` hook entry in `.pre-commit-config.yaml:25`. NO assignment-form `password: changeme` literals. |
| 2 | `git grep -n 'key_name *= *"me"' -- ':!.planning/' ':!*.md'` | **PASS** | exit 1 — zero matches. |
| 3 | `git grep -n 'changeme' .gitleaks.toml .pre-commit-config.yaml` | **PASS** | 4 matches in `.pre-commit-config.yaml` only, all referencing the `no-changeme` detection hook (`# detect the bare word "changeme"`, `id: no-changeme`, hook entry). No password value. `.gitleaks.toml` does not mention `changeme` (intentional — gitleaks doesn't ship a rule for the bare word; the local hook handles it). |
| 4 | Sanity check `git log` for any historical `changeme` in tracked files (informational) | **NOTE** | Per `01-03-SUMMARY.md` Pre-Existing History Audit, `gitleaks detect` against the full 15-commit history returns 0 leaks; no rotation required. |
| 5 | `terraform/main.tf` contains IAM role + policy + instance profile + instance wiring | **PASS** | `terraform/main.tf:33` `aws_iam_role.devbox`, line 49 `aws_iam_role_policy.devbox_ssm_read`, line 81 `aws_iam_instance_profile.devbox`, line 146 `iam_instance_profile = aws_iam_instance_profile.devbox.name`. SSM publish handled by Ansible role at bake time, so `aws_ssm_parameter` resources are intentionally absent — RESEARCH.md / PLAN explicitly chose bake-time publish via `community.aws.ssm_parameter` (not Terraform-managed) to align rotation with the AMI build. |
| 6 | `metadata_options` block with `http_tokens = "required"` on `aws_instance.devbox` | **PASS** | `terraform/main.tf:149-154` — `http_tokens = "required"`, `http_endpoint = "enabled"`, `http_put_response_hop_limit = 1`, `instance_metadata_tags = "enabled"`. |
| 7 | IAM policy scoped to `/devbox/${var.devbox_user}/*`, not `Resource = "*"` for SSM | **PASS** | `terraform/main.tf:64` — SSM `Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/devbox/${var.devbox_user}/*"`. The `Resource = "*"` on line 70 is for `kms:Decrypt` only and is gated by `Condition.StringEquals.kms:ViaService = "ssm.${region}.amazonaws.com"` (line 73) — the least-privilege pattern documented in RESEARCH.md Pitfall 5. |
| 8 | `terraform validate` (or `tofu validate`) passes | **PASS** | `cd terraform && tofu validate` → `Success! The configuration is valid.` (no warnings). |
| 9 | `ansible/roles/secrets/tasks/main.yml` imports generate, publish, install-oneshot | **PASS** | File content: lines 2-3 import `generate.yml`, lines 5-6 import `publish.yml`, lines 8-9 import `install-oneshot.yml`. Correct ordering. |
| 10 | `no_log: true` on every secret-touching task in the `secrets` role | **PASS** | `ansible/roles/secrets/tasks/generate.yml`: 4 occurrences (2 set_fact + 2 assert). `ansible/roles/secrets/tasks/publish.yml`: 2 occurrences (both ssm_parameter tasks). `ansible/roles/desktop/tasks/main.yml`: 2 occurrences (top assert + rewritten `Set VNC password`). Total 8 — exceeds the plan's 6-site minimum. |
| 11 | `ansible-playbook --syntax-check ansible/playbook.yml -e @ansible/layer_config.yml` passes | **PASS** | Ran with `-e "devbox_user=testuser aws_region=us-east-1"` (required by `publish.yml` asserts). Exit 0. Only output: implicit-localhost warnings (expected for syntax-check without inventory). |
| 12 | `terragrunt.hcl` uses `key_name = "${local.user}-devbox"`; no literal `"me"` | **PASS** | `terragrunt.hcl:32` — `key_name         = "${local.user}-devbox"`. `local.user` derived from `DEVBOX_USER` env (with `USER` fallback) at line 2. |
| 13 | `.pre-commit-config.yaml` references gitleaks AND a `no-changeme` guard | **PASS** | Lines 13-16: `repo: https://github.com/gitleaks/gitleaks`, `rev: v8.30.1`, `id: gitleaks`. Lines 21-27: local `repo`, `id: no-changeme`, bash hook that runs `git grep -nIE "changeme"` with `:!*.md`, `:!.planning/**`, `:!.pre-commit-config.yaml` exclusions. |
| 14 | `.github/workflows/security.yml` runs gitleaks on push and PR | **PASS** | Lines 8-10: `on: push: pull_request:`. Line 25: `uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7` (SHA-pinned to v2). Line 22: `fetch-depth: 0` for full-history scan. Line 13: `permissions: contents: read` (least-privilege). |
| 15 | `.gitleaks.toml` extends defaults; narrow allowlists | **PASS** | Lines 5-6: `[extend]` + `useDefault = true`. Lines 8-19: `[allowlist]` scoped to `paths = ['\.planning/.*', '.*\.md']` with two regexes (`AKIAIOSFODNN7EXAMPLE`, `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` — both AWS-canonical example creds). |
| 16 | `Makefile` has `secrets-show` target using `aws ssm get-parameter --with-decryption` | **PASS** | `Makefile:108-125`. Two `aws ssm get-parameter ... --with-decryption` calls (lines 111-113, 117-119), one per secret. `set -euo pipefail` in the recipe. Actionable stderr error on missing parameter. (Not executed live — no AWS creds in verifier env, per instruction.) |
| 17 | Threat-model fidelity spot-checks (kms:ViaService, IMDSv2, no static creds) | **PASS** | T-02-02 (Spoofing via stolen profile → blanket KMS decrypt): mitigation `kms:ViaService` condition present at `terraform/main.tf:71-75`. T-02-05 (IMDSv1 reads DevboxUser tag): mitigation `http_tokens = "required"` at line 150. T-02-01 (Info Disclosure via user_data): verified — no `user_data` attribute set on `aws_instance.devbox`; bootstrap is baked into the AMI as a systemd unit, not user_data. |
| 18 | Breaking changes documented in 01-02-SUMMARY.md | **PASS** | `breaking_changes` frontmatter array enumerates (a) `key_name "me" -> ${local.user}-devbox` + import-key-pair recipe, (b) `var.iam_instance_profile` removed, (c) pre-Phase-1 AMI rebake requirement. Body sections "Breaking Changes & Operator Migration Steps" §1, §2, §3 give step-by-step operator commands. PROJECT.md Key Decisions records both SSM and per-operator-key decisions at lines 71-72. |
| 19 | Each SEC-01..SEC-05 maps to ≥1 commit on main between `2e8ac73..HEAD` | **PASS** | `git log --oneline --grep 'SEC-0[1-5]' 2e8ac73..HEAD` returns 8 commits across all 5 requirements: SEC-01 → `afeed6e`; SEC-02 → `cba6269`; SEC-03 → `c84f1fa`, `187d57d`, `9b98557`; SEC-04 → `964fbae`; SEC-05 → `a38ae14`, `67a7fc5`. All on `main`. |

### Additional spot-checks

| Check | Result |
|---|---|
| `bash -n ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2` | PASS (exit 0) — bootstrap shell is syntactically valid |
| `yaml.safe_load .pre-commit-config.yaml` | PASS — valid YAML |
| `yaml.safe_load .github/workflows/security.yml` | PASS — valid YAML |
| `.gitleaks.toml` structure | PASS — `[extend]`, `useDefault = true`, `[allowlist]` all present |
| Confirm `var.iam_instance_profile` deletion | PASS — `grep iam_instance_profile terraform/variables.tf` returns nothing; consumer-side wiring switched to internally-managed profile |
| Working tree clean | PASS — only untracked file is `CLAUDE.md` (intentional, populated in Phase 4 per DOC-01); no smoke-test debris |

## Gaps found

None. The phase is COMPLETE.

Two minor non-blocking observations are carried forward to inform Phase 4 / future maintenance (these are NOT gaps and require no action to close Phase 1):

1. **Operator CLI surface grew by `gitleaks` (binary).** `pre-commit` was already on the operator surface; `gitleaks` is invoked transitively via the hook. Phase 4 DOC-01 will surface this in `CLAUDE.md` per the original CHECK.md WARN F-01. Not a Phase 1 gap.

2. **`<rollback>` blocks not present in plan files.** Atomic conventional commits make `git revert` the implicit rollback path. The `key_name` rename and `var.iam_instance_profile` deletion in 01-02 have one-line nuance (operator must keep the old `"me"` keypair in AWS or be ready to re-import) which is fully spelled out in `01-02-SUMMARY.md` Breaking Changes §1–§3 — adequate for an IaC-with-atomic-commits repo. CHECK.md F-02 already flagged this as WARN not blocker.

## Sign-off

Phase 1 closes 5/5 declared requirements and matches the locked decisions in PROJECT.md (SSM Parameter Store SecureString chosen over Secrets Manager; per-build rotation at bake time; per-operator `${devbox_user}-devbox` SSH key imported out-of-band; gitleaks v8.30.1 selected over detect-secrets/trufflehog; IMDSv2-required with tag-in-metadata replacing `ec2:DescribeTags`). The code is consistent with the SUMMARY narrative — I verified every load-bearing claim by reading the actual files, not by trusting the SUMMARY. The three remaining `"changeme"` occurrences in code are defensive `!= "changeme"` assertion guards that hard-fail the play if the variable was not set by the `secrets` role — they are a security feature explicitly described by the plan (T-01-08 mitigation), not regressions. Phase 1 is ready to close; proceed to Phase 2 (network exposure remediation).

---

_Verified: 2026-05-13T19:25:00Z_
_Verifier: Claude (gsd-verifier, goal-backward, adversarial stance)_
