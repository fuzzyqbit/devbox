# Phase 3 Plan-Checker Verdict

**Checked:** 2026-05-13
**Plans verified:** 2 (03-01, 03-02)
**Phase goal:** Every dependency version explicit + committed, no `most_recent = true`, AMI handoff automated (no hand-copy).
**Stance:** FORCE — start from "these plans will not deliver" and look for disqualifying gaps.

---

## Verdict

**PASS** (with two WARNINGs — execution can proceed; warnings should be addressed by the executor in-flight or surfaced in the SUMMARYs).

---

## Dimension Scores

| # | Dimension | Status | Note |
|---|-----------|--------|------|
| 1 | Coverage (REP-01..REP-05, exactly once) | PASS | 03-01 frontmatter `requirements: [REP-01, REP-02, REP-03]`; 03-02 frontmatter `requirements: [REP-04, REP-05]`. Five IDs, five hits, zero overlap. |
| 2 | REP-03 reduction (no Galaxy roles → satisfied by absence) | PASS | Verified by inspecting `ansible/requirements.yml` (only `name:`+`version:` collection entries, no `src:`/role entries) and `ansible/roles/AMAZON2023-CIS/collections/requirements.yml` (only collections, type: git). Plan 03-01 success-criteria explicitly documents this and instructs SUMMARY to record it (03-01-PLAN.md:428). |
| 3 | Lock file 4-platform coverage | PASS | 03-01 Task 2 Step 4 (03-01-PLAN.md:321-326) invokes `tofu providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64`. Verify block counts `h1:` ≥ 4 (03-01-PLAN.md:370-371). |
| 4 | Exact-version `==` syntax | PASS | Final-state YAML at 03-01-PLAN.md:228-235 uses `"==12.6.0"`, `"==3.2.0"`, `"==2.1.0"`, `"==9.0.0"`. Verify gate uses `yq` to reject any collection without `^==` prefix (03-01-PLAN.md:280-281). |
| 5 | SSM parameter path correctness | PASS | 03-02-PLAN.md:241 uses `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64:<RESOLVED-VERSION>` (exactly the canonical AL2023 minimal x86_64 path). Matches PROJECT.md constraint "Amazon Linux 2023 minimal x86_64". |
| 6 | AMI handoff: no hand-copy | PASS | 03-02 Task 1 adds `post-processor "manifest"`; Task 2 wires the Makefile target with jq parse + tfvars write; Task 2 Step 4 explicitly REMOVES `ami_id = "ami-0b7cfe2135f319a55"` from terragrunt.hcl:45. Verify grep `! grep -E '^\s*ami_id\s*=\s*"ami-[0-9a-f]+"' terragrunt.hcl` (03-02-PLAN.md:517). |
| 7 | `.gitignore` coordination (both plans, Wave 1) | **WARN** | See Finding W-1 below. Disjoint content but 03-01 references hard-coded line numbers that will drift if 03-02 lands first. |
| 8 | `<RESOLVED-VERSION>` placeholder hygiene | PASS | 03-02-PLAN.md:286 explicitly warns: "Do NOT leave the literal `<RESOLVED-VERSION>` placeholder — that will fail `packer validate`." Verify block at 03-02-PLAN.md:316-318 greps for the literal `:[0-9]+` pattern (so a leftover `<RESOLVED-VERSION>` would NOT match → fails verify). Plus `packer validate .` runs at 03-02-PLAN.md:325. Two independent gates. |
| 9 | Provider tighten to `~> 6.0` (not `>= 6.0`) | PASS | 03-01-PLAN.md:212-214: `version = "~> 6.0"`. Verify uses `grep -E 'version\s*=\s*"~>\s*6\.0"'` (03-01-PLAN.md:275). Floating `>= 5.0` rejected explicitly (03-01-PLAN.md:276). |
| 10 | Threat model | PASS | Both plans ship `<threat_model>` with STRIDE rows. Spot-check: 03-01 T-03-01 (lockfile hashes vs binary tampering), T-03-02 (`==` pin + offline cache vs Galaxy replacement), T-03-03 (residual risk on git-tag mutability, documented). 03-02 T-03-08 (AWS SSM trust boundary), T-03-11 (manifest stale guard), T-03-14 (no untrusted intermediary in handoff). Supply-chain compromise: pin + lockfile mitigation documented in both plans. |
| 11 | Phase 4 CI signals | PASS | 03-01 `<output>` lists `tofu init -lockfile=readonly` + `ansible-galaxy collection install --offline` for SUMMARY (03-01-PLAN.md:441). 03-02 `<output>` lists `packer validate`, `! grep -E 'most_recent\s*=\s*true' packer/`, and `! grep -E '^\s*ami_id\s*=\s*"ami-' terragrunt.hcl` (03-02-PLAN.md:595-598). All Phase 4 grep gates accounted for. |
| 12 | Verification commands present + concrete | PASS | Both plans have `<verify><automated>` per task AND a top-level `<verification>` list (03-01-PLAN.md:413-422; 03-02-PLAN.md:562-574). Commands are runnable, use absolute paths, exit non-zero on failure. |
| Bonus | CLAUDE.md compliance | SKIPPED | Repo-root CLAUDE.md is empty (0 bytes, scheduled for Phase 4 DOC-01 per ROADMAP.md and 03-RESEARCH.md:679-688). User-global rules apply and plans honor them (immutability of generated artifacts, KISS in choosing manifest-to-tfvars over SSM-write coupling, error handling in Makefile guards). |
| Bonus | Architectural Tier Compliance | PASS | 03-RESEARCH.md has an Architectural Responsibility Map; every task lands in the right tier (lockfile in Terraform/git, Galaxy pins in ansible/, source AMI in packer/, handoff in Makefile + tfvars). No cross-tier leakage. |
| Bonus | Cross-plan data contracts | PASS | The one shared file is `.gitignore`; the contract is "Plan 03-01 removes lockfile-exclusion lines; Plan 03-02 adds manifest + users/*.auto.tfvars exclusions; both must preserve `*.auto.tfvars` and `.terragrunt-cache/`". 03-02 Step 1 explicitly defensively re-checks `*.auto.tfvars` survived (03-02-PLAN.md:348). 03-01's success-criteria preserves `*.auto.tfvars` (03-01-PLAN.md:431). No transform conflict on the entity. |

---

## Findings

### Warnings (should fix; not blocking)

#### W-1 [scope: dimension 7] — Plan 03-01 references hard-coded `.gitignore` line numbers; Wave-1 parallel execution with Plan 03-02 can cause line-number drift

**Severity:** WARNING
**File:** `.planning/phases/03-reproducibility-version-pinning/03-01-PLAN.md:188-194`

**Detail:** Plan 03-01 Task 1 Step 2 instructs the executor to "Delete these THREE specific lines: Line 7: `terraform/.terraform.lock.hcl`; Line 26: `# Root-level Terraform lock ...` (comment header for the next line); Line 27: `.terraform.lock.hcl`". Plan 03-02 Task 2 Step 2 inserts a new line `packer/packer-manifest.json` AFTER current line 2 (inside the `# Packer` block at the very top of the file). Both plans declare `depends_on: []` and `wave: 1`, i.e. they are eligible to execute in either order or in parallel.

If 03-02 lands first, `.gitignore` line numbering shifts by +1 below line 3 — so the executor of 03-01, reading "Line 7" literally, would be editing `terraform/.terraform.lock.hcl` at line 8, and "Line 27" would be at line 28. The current actual file has these lines at 7/26/27 (verified just now in this check), so a serial 03-01→03-02 order is safe; an unlucky reverse order is not.

**Why this is a WARNING, not a BLOCKER:** The verify blocks in both plans are content-grep (`grep -E '^[^#]*terraform/\.terraform\.lock\.hcl' .gitignore`), so a mis-targeted edit will fail the verify and the executor will self-correct in-loop. The likely outcome is "executor edits wrong line, verify fails, executor re-reads file by content, fixes it" — a minor revision cycle inside the plan, not a phase-goal failure.

**Concrete revision (optional, for cleanliness — not required to ship):**
1. In 03-01-PLAN.md:188, replace "Line 7", "Line 26", "Line 27" with content-based instructions: "Delete the line that contains exactly `terraform/.terraform.lock.hcl`. Delete the line that contains exactly `.terraform.lock.hcl` (the root-level entry, distinct from the `terraform/` prefixed one). Delete the preceding comment `# Root-level Terraform lock (terragrunt generates this at project root)` if it directly precedes the deleted line."
2. OR: add `depends_on: ["01"]` to 03-02-PLAN.md frontmatter to force serial execution. This downgrades parallelism but removes the race entirely. The orchestrator brief explicitly says "parallel-safe (disjoint files except `.gitignore` on disjoint lines)" — content is disjoint, but the line-number framing is the source of the risk.

**Recommended fix:** Option 1 (content-based edit instructions) — cheaper than serializing, and idiomatic for `.gitignore` edits.

---

#### W-2 [scope: dimension 8] — `<RESOLVED-VERSION>` placeholder relies on executor manually substituting before validation runs

**Severity:** WARNING
**File:** `.planning/phases/03-reproducibility-version-pinning/03-02-PLAN.md:241, 286`

**Detail:** Plan 03-02 Task 1 Step 2 places a literal `<RESOLVED-VERSION>` placeholder in the proposed HCL block and instructs the executor to substitute it with the integer Version surfaced by `aws ssm get-parameter-history` from Step 1. The plan explicitly warns at line 286: "Do NOT leave the literal `<RESOLVED-VERSION>` placeholder — that will fail `packer validate`."

This is well-guarded — `packer validate` (Task 1 Step 3) will reject the file because `<RESOLVED-VERSION>` is not an integer, AND the verify grep `:[0-9]+` would not match the placeholder. So the gate exists. The WARNING is that the plan asks the executor to interleave a live `aws` API call result into a static file edit, which is an unusual coupling for an "auto" task. If the executor's AWS credentials don't have `ssm:GetParameterHistory`, the fallback (Step 1 failure modes at 03-02-PLAN.md:211) is `aws ssm get-parameter` (current value only). The plan covers this, but the executor must read the failure-modes section.

**Why this is a WARNING:** Two independent gates (packer validate + grep `:[0-9]+`) will catch any leftover placeholder, so the worst case is a verify failure surfacing the issue immediately. The risk is the executor spending time confused about the AWS error rather than the goal being missed.

**Concrete revision (optional):** Add a Step 1.5 to Task 1 that explicitly stores the resolved version in an environment variable and uses it in the file-edit step:
```
SSM_VERSION=$(aws ssm get-parameter-history ... --query 'Parameters[-1].Version' --output text)
[ -n "$SSM_VERSION" ] && [[ "$SSM_VERSION" =~ ^[0-9]+$ ]] || { echo "ERROR: did not resolve a numeric SSM parameter version"; exit 1; }
sed -i.bak "s|<RESOLVED-VERSION>|${SSM_VERSION}|" packer/devimage.pkr.hcl
```
This eliminates the manual-substitution failure mode entirely.

**Recommended fix:** Not strictly necessary — the existing two-gate verification will catch it. Surface this in the 03-02-SUMMARY as a noted in-flight care point if the executor hit the AWS-creds path.

---

### Info (suggestions; no action required)

- **I-1:** The Makefile `clean` target rewrite in Plan 03-02 (03-02-PLAN.md:416-428) correctly stops deleting `terraform/.terraform.lock.hcl`. If Plan 03-02 runs BEFORE Plan 03-01, the new `clean` target removes a no-op delete (`terraform/.terraform.lock.hcl` doesn't exist yet, `rm -rf` is silent). Safe in both orders. No action needed.
- **I-2:** Plan 03-02 verification depends on network (`packer init` downloads the Amazon plugin). If the executor environment lacks network, the verify will fail with a plugin-fetch error rather than a plan defect. The plan acknowledges this implicitly. Phase 4 CI will rerun this from a clean runner, which is the right place to gate it.
- **I-3:** Both plans cite `03-RESEARCH.md` line ranges in `<research_pointers>` — the citations are accurate (verified line numbers against the actual RESEARCH file).

---

## Recommended next step

Proceed to execution. The phase goal is structurally achievable from these plans:
- REP-01 closed by 03-01 Task 2 (multi-platform lockfile committed).
- REP-02 closed by 03-01 Task 1 (`==X.Y.Z` syntax on every collection).
- REP-03 closed by 03-01 (vendored CIS collections pinned to git tag refs) + SUMMARY documenting "no Galaxy roles exist in this repo".
- REP-04 closed by 03-02 Task 1 (SSM parameter version pin, `most_recent = true` deleted).
- REP-05 closed by 03-02 Task 2 (manifest → Makefile → tfvars → terragrunt auto-load).

Optional pre-execution polish (executor or planner can pick):
- Apply W-1's content-based edit instructions to make `.gitignore` edits order-independent.
- Apply W-2's `sed`-based placeholder substitution to make the SSM-version pin substitution mechanical instead of manual.

No re-planning required.

