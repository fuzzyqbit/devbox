---
phase: 03-reproducibility-version-pinning
verified: 2026-05-14T00:00:00Z
status: gaps_found
score: 4/5 requirements verified (REP-01, REP-02, REP-03, REP-05 PASS; REP-04 PARTIAL — SSM `:NN` pin absent)
verdict: GAPS
overrides_applied: 1
overrides:
  - must_have: "Packer source AMI no longer uses `most_recent = true` for unpinned filters; uses `amazon-parameterstore` data source"
    reason: "Anti-pattern eliminated and SSM data source wired; the trailing `:NN` parameter-version suffix is deferred per orchestrator instruction (executor lacked AWS credentials at bake time). Reproducibility regression risk is documented in SUMMARY and tracked by a Phase 4 grep gate."
    accepted_by: "orchestrator"
    accepted_at: "2026-05-14T00:00:00Z"
gaps:
  - truth: "Packer source AMI is pinned deterministically (SSM parameter resolves to a single AMI ID across days)"
    status: partial
    reason: "The `amazon-parameterstore` data source is wired and `most_recent = true` is removed, but the parameter name omits the trailing `:NN` version suffix, so AWS may rotate the resolved value silently between bakes."
    artifacts:
      - path: "packer/devimage.pkr.hcl"
        issue: "Line 33: `name = \"/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64\"` — no `:NN` suffix."
    missing:
      - "Append `:NN` to the SSM parameter name in packer/devimage.pkr.hcl line 33 once AWS credentials are available (`aws ssm get-parameter-history --name <path> --region us-east-1`). The inline comment block (lines 19-31) already documents the procedure."
  - truth: "`packer validate packer/` exits 0 against the post-edit config (PLAN <verify> automated block at 03-02 line 326; SUMMARY 03-02 line 240)"
    status: failed
    reason: "`var.devbox_user` has `default = \"\"` AND a regex validation `^[a-z_][a-z0-9_-]*$`. The empty string fails the regex, so `packer validate .` errors with `Invalid value for default variable` unless a `-var \"devbox_user=...\"` is supplied. The 03-02 SUMMARY claims this passes (line 240) — that claim is false for the bare invocation."
    artifacts:
      - path: "packer/variables.pkr.hcl"
        issue: "Lines 46-54: empty-string default fails the validation regex; `packer validate` (no `-var`) cannot succeed."
    missing:
      - "Either remove the `default = \"\"` (forcing operators to pass `-var`), or relax the validation to allow the empty default, or change the validation to skip when var is empty. The Makefile already passes `-var \"devbox_user=$(DEVBOX_USER)\"` in `packer-bake` so the runtime path is unaffected — only the CI gate `packer validate packer/` is broken."
human_verification:
  - test: "Run `make packer-bake DEVBOX_USER=$(whoami)` end-to-end against a real AWS account once credentials are available; confirm packer-manifest.json is emitted, jq parse succeeds, users/<USER>.auto.tfvars is written with a valid `ami_id = \"ami-...\"`, and `make tg-apply` consumes it."
    expected: "AMI built, manifest written, auto.tfvars created and auto-loaded by terragrunt; EC2 instance launches from the just-built AMI."
    why_human: "Requires AWS credentials with EC2/SSM/IAM permissions and an EC2 build (~$0.50, ~20 min). Cannot be exercised in a credential-less verifier sandbox."
  - test: "After AWS credentials are obtained, resolve the live SSM parameter version with `aws ssm get-parameter-history --name /aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64 --region us-east-1` and append `:NN` to packer/devimage.pkr.hcl line 33."
    expected: "A reviewable diff that pins the parameter to a single version; `packer validate -var devbox_user=test packer/` still passes after the edit."
    why_human: "Requires live AWS credentials with `ssm:GetParameterHistory`."
---

# Phase 3: Reproducibility & version pinning — Verification Report

**Phase Goal:** Every dependency version is explicit + committed; no `most_recent = true` for unpinned filters; AMI handoff is automated.
**Verified:** 2026-05-14
**Status:** GAPS (REP-04 partial; REP-01/02/03/05 complete; one new gap in REP-04: `packer validate` bare invocation fails)

## Verdict

**GAPS** — two related issues:
1. REP-04 is partially closed (anti-pattern eliminated, SSM data source wired, but the `:NN` pin is absent — already accepted by orchestrator as a known follow-up).
2. `packer validate packer/` (the explicit Plan 03-02 verification + a Phase 4 CI gate) errors because `var.devbox_user` has an empty default that fails its own regex validation. The runtime path (`make packer-bake`) is unaffected, but the CI gate the SUMMARY surfaces (line 178 of 03-02-SUMMARY) is currently broken.

All other deliverables — lockfile committed across 4 platforms, Galaxy collections pinned, hand-copy removed from terragrunt.hcl, manifest post-processor + Makefile target, merge integrity — verified PASS.

## Requirement coverage

| Requirement | Status | Evidence |
|---|---|---|
| REP-01 — Lock committed; .gitignore updated; 4 platforms | PASS | `git ls-files terraform/.terraform.lock.hcl` returns path; `.gitignore` no longer excludes `terraform/.terraform.lock.hcl` (the root-level `.terraform.lock.hcl` entry at line 38 is intentional, terragrunt-generated); 4 `h1:` hashes in lockfile (one per platform — darwin_arm64, darwin_amd64, linux_amd64, linux_arm64); `tofu init -lockfile=readonly` exits 0 |
| REP-02 — Collections pinned `==X.Y.Z` | PASS | All 4 collections in `ansible/requirements.yml` use `version: "==X.Y.Z"` (community.general==12.6.0, community.crypto==3.2.0, ansible.posix==2.1.0, community.aws==9.0.0); CIS file uses bare git tag refs per Pattern 3 (correct for `type: git` sources) |
| REP-03 — Galaxy roles pinned | PASS (by absence) | `grep -c '^roles:'` returns 0 across both requirements.yml files; SUMMARY 03-01 documents the "satisfied by absence" disposition at lines 112-120 |
| REP-04 — Packer source AMI not floating | PARTIAL (override applied) | `most_recent = true` removed; `amazon-parameterstore` data source wired; SSM parameter name OMITS the trailing `:NN` (executor lacked AWS creds — documented inline at devimage.pkr.hcl:19-31 and in SUMMARY 03-02:93-131). Orchestrator-accepted deferral. |
| REP-05 — AMI handoff automated | PASS | `terragrunt.hcl` `inputs` block contains no `ami_id = "ami-..."` literal; `Makefile` `packer-bake` target parses manifest with `jq` and writes `users/$(DEVBOX_USER).auto.tfvars`; `post-processor "manifest"` block present in `packer/devimage.pkr.hcl`; `packer/packer-manifest.json` and `users/*.auto.tfvars` are gitignored |

## Check results

| # | Check | Status | Evidence |
|---|---|---|---|
| 1 | `git ls-files terraform/.terraform.lock.hcl` returns the file | PASS | Returns `terraform/.terraform.lock.hcl` |
| 2 | `.gitignore` excludes only root-level lock (intentional), not `terraform/.terraform.lock.hcl` | PASS | Line 38: `.terraform.lock.hcl` (root, terragrunt-generated, intentional comment at line 36-37); no `terraform/.terraform.lock.hcl` entry anywhere |
| 3 | 4 platforms recorded in lockfile (`h1:` hashes) | PASS | `grep -c 'h1:'` returns `4`; provider block at line 4: `registry.opentofu.org/hashicorp/aws` version `6.45.0`, constraints `~> 6.0`; 4 `h1:` + 16 `zh:` hashes |
| 4 | `tofu init -lockfile=readonly` succeeds without rewrite | PASS | "OpenTofu has been successfully initialized!" — exit 0, no diff |
| 5 | Every collection uses `==X.Y.Z` (zero "bare version" matches in `ansible/requirements.yml`) | PASS (intent) | Literal regex `^\s*version:\s*[^=]` matches quoted `"==X.Y.Z"` values (quote is first char), but inspection confirms all 4 collections in `ansible/requirements.yml` are `version: "==X.Y.Z"`; the CIS file's bare-version entries are git refs per Pattern 3 (correct, not unpinned) |
| 6 | Expected collection versions present | PASS | `community.aws==9.0.0`, `community.general==12.6.0`, `community.crypto==3.2.0`, `ansible.posix==2.1.0` all in `ansible/requirements.yml` |
| 7 | `roles:` key absent (or pinned) | PASS | `grep -c '^roles:'` returns 0 in both files — satisfied by absence |
| 8 | `most_recent = true` eliminated from `packer/devimage.pkr.hcl` | PASS | `grep -nE 'most_recent\s*=\s*true' packer/devimage.pkr.hcl` returns no matches |
| 9 | `amazon-parameterstore` data source with AL2023 minimal x86_64 path | PASS | Lines 32-35: `data "amazon-parameterstore" "al2023_minimal"` resolving `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64` |
| 10 | `<RESOLVED-VERSION>` placeholder removed; SSM `:NN` suffix check | NOTE (acceptable gap) | Placeholder is gone (good); but the `:NN` suffix is also missing — the parameter name has no version pin. Per orchestrator: NOTE not FAIL. Inline comment at lines 19-31 documents the bump procedure |
| 11 | `packer validate packer/` exits 0 | FAIL | Bare `packer validate .` errors: "The devbox_user value must match the regex ^[a-z_][a-z0-9_-]*$" (line 50 validation rejects the empty-string default at line 48). Passes only when `-var "devbox_user=test"` is supplied. SUMMARY 03-02:240 claim "`packer validate .` exit=0" is false for the bare invocation. |
| 12 | Hand-copied `ami_id = "ami-..."` removed from `terragrunt.hcl` | PASS | `grep -E '^\s*ami_id\s*=\s*"ami-' terragrunt.hcl` returns no matches; only comment-level mentions at lines 43, 52 |
| 13 | `Makefile` `packer-bake` target references manifest + writes `users/$(DEVBOX_USER).auto.tfvars` | PASS | Lines 61-69: target with `rm -f packer/packer-manifest.json`, `packer build -var "devbox_user=$(DEVBOX_USER)"`, jq parse with `sort_by(.build_time) \| .[-1].artifact_id`, `printf` into `users/$(DEVBOX_USER).auto.tfvars` |
| 14 | `packer-manifest.json` in `.gitignore` | PASS | Line 3: `packer/packer-manifest.json` |
| 15 | `post-processor "manifest"` block present | PASS | Line 90 of `packer/devimage.pkr.hcl` |
| 16 | `make -n packer-bake DEVBOX_USER=test` parses cleanly | PASS | Dry-run prints expected command sequence: `packer init`, `rm -f manifest`, `cd packer && DEVBOX_USER=test packer build -var ...`, jq + printf chain. No "missing separator" — tab indentation correct |
| 17 | No leftover merge conflict markers | PASS | `git grep -nE '<<<<<<\|>>>>>>'` exits 1 (no matches) |
| 18 | `terragrunt.hcl` preserves `key_name = "${local.user}-devbox"` AND removes hand-copied `ami_id` | PASS | Line 59: `key_name = "${local.user}-devbox"`; no `ami_id` literal in `inputs` |
| 19 | `Makefile` `.PHONY` includes Phase 2 + Phase 3 targets | PASS | Line 1 lists: `devbox-ssm`, `devbox-port-forward`, `devbox-allowlist-me`, `secrets-show`, `packer-bake` (and all tg-* / tf-* targets) |
| 20 | `var.devbox_user` has regex validation + description noting REP-05 manifest provenance | PASS | `packer/variables.pkr.hcl:46-54`: regex `^[a-z_][a-z0-9_-]*$` + description "recorded in packer-manifest custom_data for the AMI handoff" |
| 21 | `git log --oneline --grep 'REP-0[1-5]'` shows REP coverage | PASS | Commits: `7bea740` (REP-01), `4bca849` (REP-02/03), `7afb759` (REP-04), `8112796` (REP-05), `ae87ccc` (merge). Note: `--grep` doesn't always match (some subjects use phase number not REP-XX), but body+subject inspection confirms each REP is closed in ≥1 commit |
| 22 | SUMMARYs surface Phase 4 grep gates | PASS | SUMMARY 03-01 has "Phase 4 CI Gates to Wire In" section (lines 136-147 with 6 gates); SUMMARY 03-02 has "CI Hooks Needed in Phase 4" section (lines 169-183 with 7 gates) |

## Gaps found

### Gap 1 — REP-04 partial: SSM parameter `:NN` version suffix absent (NOTE, orchestrator-accepted)

`packer/devimage.pkr.hcl:33` resolves `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64` without the trailing `:NN`. AWS may silently rotate the resolved AMI between bakes — eliminating the "byte-identical AMI from a re-bake on day N+30" guarantee that REP-04 is supposed to deliver. The anti-pattern (`most_recent = true`) is gone, the data-source plumbing is correct, only the version suffix is missing.

**Disposition:** NOTE (not FAIL) per orchestrator instruction — executor had no AWS creds available; SUMMARY 03-02 lines 93-131 + inline comment block at `packer/devimage.pkr.hcl:19-31` document the bump procedure; Phase 4 grep gate `grep -E '/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64:[0-9]+'` is already specified to catch unpinned state going forward.

### Gap 2 — `packer validate packer/` fails on bare invocation (NEW, not surfaced in SUMMARY)

`packer validate .` (no `-var`) errors with:
```
Error: Invalid value for default variable
  on variables.pkr.hcl line 48:
The devbox_user value must match the regex ^[a-z_][a-z0-9_-]*$
```

Root cause: `variable "devbox_user" { default = "" ... validation { condition = can(regex("^[a-z_][a-z0-9_-]*$", var.devbox_user)) ... } }` — the empty-string default fails its own regex.

Impact:
- Runtime path (`make packer-bake DEVBOX_USER=foo`) is unaffected — the Makefile passes `-var "devbox_user=$(DEVBOX_USER)"` explicitly.
- Plan-defined verification gate `cd packer && packer validate .` (03-02-PLAN.md line 326) is broken.
- Phase 4 CI gate "Packer config validates" (SUMMARY 03-02 line 179) is broken — it would need to invoke `packer validate -var "devbox_user=ci" .` to succeed.
- SUMMARY 03-02 line 240 contains a false claim that bare `packer validate .` exits 0.

Suggested fixes (executor's choice):
1. Drop `default = ""` from `var.devbox_user`. Operators/CI would need to pass `-var` explicitly. This is the most honest fix because the variable IS required.
2. Relax the validation to `condition = var.devbox_user == "" || can(regex("^[a-z_][a-z0-9_-]*$", var.devbox_user))`.
3. Always pass `-var "devbox_user=ci"` in the Phase 4 CI gate and update the SUMMARY-recommended grep gate.

Recommend option 1: matches the description "Required" and prevents accidental "empty operator" bakes.

## Sign-off

This phase is **functionally complete** for the operator-facing day-to-day flow (manifest handoff works, all dependencies are pinned with the one known SSM-version follow-up). The gap is in a validation gate that the next phase (Phase 4 CI) will trip over on first run unless Gap 2 is closed first. Recommend a small fix to `packer/variables.pkr.hcl` (option 1 above) before declaring this phase shippable to Phase 4. The SSM `:NN` follow-up remains tracked through Phase 4 CI grep gates as designed.

---

_Verified: 2026-05-14_
_Verifier: Claude (gsd-verifier)_
