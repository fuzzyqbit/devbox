---
phase: 02-network-exposure-remediation
verified: 2026-05-13T00:00:00Z
status: passed
verdict: COMPLETE
score: 9/9 must-haves verified
re_verification:
  is_re_verification: false
---

# Phase 2: Network Exposure Remediation — Verification Report

**Phase Goal:** Eliminate every `0.0.0.0/0` ingress on `aws_security_group.devbox`. Drop `:22` ingress entirely (replaced by SSM Session Manager); gate `:8080` and `:6080` on operator-supplied CIDR allowlist (default `[]`, refuses apply without explicit override).

**Verified:** 2026-05-13
**Status:** passed
**Re-verification:** No — initial verification.

## Verdict

**COMPLETE** — Phase 2 achieved its goal in code. All four NET-* requirements are satisfied by concrete, wired implementation; the hybrid posture (SSM for shell, CIDR allowlist for web) is built end-to-end; the operator UX surface (Make + scripts) lands cleanly; tofu validates clean; validation blocks fire as designed.

## Requirement coverage

| Requirement | Status | Evidence |
| ----------- | ------ | -------- |
| NET-01 (SSH :22 restricted — satisfied by deletion) | ✓ SATISFIED | No `from_port = 22` / `to_port = 22` anywhere in `terraform/main.tf` (verified by `git grep`); decision recorded in PROJECT.md Key Decisions row + `02-01-PLAN.md:91-99` Decision section. Commit `d5e4501`. |
| NET-02 (code-server :8080 gated on `var.allowed_web_cidrs`) | ✓ SATISFIED | `terraform/main.tf:111-117` ingress block with `cidr_blocks = var.allowed_web_cidrs`. Variable definition + validation in `terraform/variables.tf:63-77`. Commits `6049fde`, `d5e4501`. |
| NET-03 (noVNC :6080 gated on `var.allowed_web_cidrs`) | ✓ SATISFIED | `terraform/main.tf:119-125` ingress block with `cidr_blocks = var.allowed_web_cidrs`. Same shared variable as NET-02. Commits `6049fde`, `d5e4501`. |
| NET-04 (Decision recorded in PROJECT.md; implementation matches) | ✓ SATISFIED | `.planning/PROJECT.md:76` Key Decisions row reads "Hybrid posture chosen" with status `✓ Phase 2`, full rationale + rollback note. Implementation: `aws_iam_role_policy_attachment.devbox_ssm_core` at `terraform/main.tf:92-95` + `output.ssm_start_session_command` at `terraform/outputs.tf:16-19`. Commits `dde8cf2`, `d838f5b`. |

## Check results

### SG hygiene

1. **`git grep '0.0.0.0/0' -- terraform/ terragrunt.hcl`** → PASS. Only matches are (a) `terraform/main.tf:132` — the *egress* block (allowed; required for SSM agent outbound channel per RESEARCH.md:383-389), and (b) `terraform/variables.tf:82` — inside a description string documenting the forbidden combination (`NEVER set this to true AND populate allowed_web_cidrs with 0.0.0.0/0`). Zero ingress matches.

2. **`git grep 'from_port = 22 | to_port = 22' -- terraform/`** → PASS. Zero matches. The `:22` ingress rule is gone, exactly as NET-01's deletion-not-narrowing strategy demands.

3. **`terraform/main.tf` ingress driven by `var.allowed_web_cidrs`** → PASS. Two inline ingress blocks at lines 111-117 (`:8080`) and 119-125 (`:6080`), each setting `cidr_blocks = var.allowed_web_cidrs`. No dynamic block needed (planner chose readability over generality on a fixed 2-port shape).

### Variable + validation

4. **`var.allowed_web_cidrs` (default `[]`) and `var.allow_open_ingress` (default `false`) in `terraform/variables.tf`** → PASS. Lines 63-77 and 79-83 respectively. Both defaults verified.

5. **Validation block rejects empty list when `allow_open_ingress=false`** → PASS. `terraform/variables.tf:68-71` validation block: `condition = length(var.allowed_web_cidrs) > 0 || var.allow_open_ingress`. Second validation block at lines 73-76 also catches malformed CIDRs via `cidrhost()`. Live test:
   ```
   $ tofu plan -var 'allowed_web_cidrs=[]' -var allow_open_ingress=false ...
   Error: Invalid value for variable
     var.allow_open_ingress is false
     var.allowed_web_cidrs is empty list of string
     allowed_web_cidrs must contain at least one CIDR (e.g. 203.0.113.42/32).
     Run `make devbox-allowlist-me` to auto-populate...
   ```
   Error message references `make devbox-allowlist-me` as required.

6. **`tofu validate` from `terraform/`** → PASS. `Success! The configuration is valid.`

### SSM IAM

7. **`AmazonSSMManagedInstanceCore` attached to `aws_iam_role.devbox`** → PASS. `terraform/main.tf:92-95` `aws_iam_role_policy_attachment.devbox_ssm_core` attaches the AWS-managed policy to the existing Phase 1 role.

8. **No new bake-time Ansible role for SSM agent** → PASS. `grep -r 'ssm-agent\|amazon-ssm-agent' ansible/` returns nothing. Agent is preinstalled in AL2023 (RESEARCH.md:72) and only needs the IAM policy attachment to register.

### Outputs

9. **`ssm_start_session_command` and `instance_id` present; `ssh_command` removed** → PASS. `terraform/outputs.tf:16-19` defines `ssm_start_session_command`; `output "instance_id"` at line 1; `grep -c 'ssh_command'` returns 0.

### Operator UX (Makefile + scripts)

10. **`make help` lists `devbox-ssm`, `devbox-port-forward`, `devbox-allowlist-me`** → PASS. Help text under "SSM access (Phase 2 — replaces public :22 ingress)" section at `Makefile:29-32`.

11. **`scripts/devbox-ssm.sh` has session-manager-plugin pre-flight** → PASS. Lines 36-51: `if ! command -v session-manager-plugin >/dev/null 2>&1; then ... ERROR ... brew install --cask session-manager-plugin ... exit 1`.

12. **`scripts/devbox-allowlist-me.sh` writes to `./allowlist.auto.tfvars`; `.gitignore` excludes `*.auto.tfvars`** → PASS. Script writes to `${TFVARS_PATH:-./allowlist.auto.tfvars}` at line 33 + 80. `.gitignore:32-33` contains both `*.auto.tfvars` (wildcard) and `allowlist.auto.tfvars` (explicit).

13. **`scripts/devbox-status.sh` no longer prints `ssh -i ~/.ssh/...`** → PASS. `git grep 'ssh -i' scripts/` returns no matches. The script's connection-info block at lines 48-65 prints `aws ssm start-session --target ...` for shell access; browser URLs annotated with "(requires your IP in allowed_web_cidrs)"; surfaces `make devbox-allowlist-me && make tg-apply` as the recovery path.

14. **`bash -n` on all four scripts** → PASS. All four scripts pass syntax check.

15. **`shellcheck scripts/devbox-*.sh`** → PASS. Zero warnings on `devbox-ssm.sh`, `devbox-allowlist-me.sh`, `devbox-status.sh`, `devbox-start.sh`.

16. **`make -n devbox-ssm DEVBOX_USER=test`** and **`make -n devbox-port-forward DEVBOX_USER=test`** → PASS.
    - `devbox-ssm`: prints `DEVBOX_USER=test ./scripts/devbox-ssm.sh` (clean handoff).
    - `devbox-port-forward`: prints the inline recipe including `session-manager-plugin` pre-flight + `aws ssm start-session --target $INSTANCE_ID --region $REGION --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'`. Single-port trade-off is documented at `Makefile:116-118`.

### PROJECT.md

17. **NET-04 row in PROJECT.md Key Decisions** → PASS. `.planning/PROJECT.md:76` reads `**Hybrid posture chosen:**` with status `✓ Phase 2`. Rationale, rollback note, and NET-01 deletion-not-narrowing framing all present.

### Traceability

18. **Commits tagged with NET-XX** → PASS.
    - NET-01: `d5e4501 feat(phase-02-01): drop :22 SG ingress, gate web ports on var.allowed_web_cidrs, attach AmazonSSMManagedInstanceCore (NET-01, NET-02, NET-03)`
    - NET-02, NET-03: same `d5e4501` + `6049fde` + `f5b9581`
    - NET-04: `dde8cf2 docs(phase-02-01): record NET-04 hybrid-posture decision in PROJECT.md (NET-04)` + `d838f5b feat(phase-02-01): replace ssh_command output with ssm_start_session_command (NET-04)`

### Threat model fidelity

19. **STRIDE spot-checks (3 from each plan)** → PASS.
    - **T-02-02 (Tampering, `allow_open_ingress`)**: Default `false` at `terraform/variables.tf:80-81`; description explicitly forbids the combo `true + 0.0.0.0/0`. ✓
    - **T-02-09 (Spoofing, `0.0.0.0/0` re-enters)**: Verified by check 1 (no `0.0.0.0/0` in any ingress block). ✓
    - **T-02-04 (Captive-portal HTML poisoning)**: Defense in depth — `scripts/devbox-allowlist-me.sh:53` IPv4 regex + `terraform/variables.tf:73-76` `cidrhost()` validation. ✓
    - **T-02-13 (DoS, missing session-manager-plugin)**: Pre-flight at `scripts/devbox-ssm.sh:36-51` + `Makefile:121-124`. ✓
    - **T-02-16 (LAN exposure of port-forward)**: `Makefile:131-135` does not pass `localBindAddress`, so AWS-StartPortForwardingSession's loopback-only default applies. ✓
    - **T-02-10 (Tampering, captive-portal HTML written to tfvars)**: IPv4 regex at `scripts/devbox-allowlist-me.sh:53` runs before write; atomic temp+mv at lines 71-80; second-layer `cidrhost()` validation in Terraform. ✓

## Observable truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | No SG ingress on `aws_security_group.devbox` contains `0.0.0.0/0` | ✓ VERIFIED | Check 1 above |
| 2 | Port 22 is gone from any SG ingress block | ✓ VERIFIED | Check 2 above |
| 3 | tofu plan/apply rejected when `var.allowed_web_cidrs=[]` and `allow_open_ingress=false` | ✓ VERIFIED | Check 5 — live `tofu plan` reproduced validation error with actionable `make devbox-allowlist-me` hint |
| 4 | `AmazonSSMManagedInstanceCore` attached to `aws_iam_role.devbox` | ✓ VERIFIED | Check 7 — `terraform/main.tf:92-95` |
| 5 | Hybrid-posture decision recorded in PROJECT.md Key Decisions | ✓ VERIFIED | Check 17 — `.planning/PROJECT.md:76` |
| 6 | `output.ssh_command` removed; `output.ssm_start_session_command` present | ✓ VERIFIED | Check 9 — `terraform/outputs.tf:16-19` |
| 7 | `make devbox-ssm` / `make devbox-port-forward` / `make devbox-allowlist-me` wired and listed in `make help` | ✓ VERIFIED | Checks 10, 16 |
| 8 | `scripts/devbox-status.sh` no longer prints `ssh -i ~/.ssh/...pem`; prints SSM start-session | ✓ VERIFIED | Check 13 — `git grep 'ssh -i' scripts/` returns nothing; SSM line at `scripts/devbox-status.sh:52` |
| 9 | `*.auto.tfvars` gitignored; `scripts/devbox-allowlist-me.sh` writes only to that path | ✓ VERIFIED | Check 12 — `.gitignore:32-33` + script defaults |

**Score:** 9/9 truths verified.

## Required artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `terraform/variables.tf` | `var.allowed_web_cidrs` + `var.allow_open_ingress` with two validation blocks | ✓ VERIFIED | Lines 63-83 |
| `terraform/main.tf` | No :22 ingress; `:8080`/`:6080` ingress via var; `AmazonSSMManagedInstanceCore` attachment; egress retains `0.0.0.0/0` | ✓ VERIFIED | Lines 92-95 (SSM), 106-142 (SG) |
| `terraform/outputs.tf` | `ssm_start_session_command` present; `ssh_command` absent; `instance_id` + `aws_region` retained | ✓ VERIFIED | Lines 1, 16-19, 51-54 |
| `terragrunt.hcl` | `inputs.allowed_web_cidrs` sourced from env vars (CODE_SERVER_ALLOWED_CIDRS, VNC_ALLOWED_CIDRS) | ✓ VERIFIED | Lines 1-20 (locals), 56-62 (inputs) |
| `.gitignore` | `*.auto.tfvars` (wildcard) + `allowlist.auto.tfvars` (explicit) | ✓ VERIFIED | Lines 32-33 |
| `.planning/PROJECT.md` | Key Decisions row for NET-04 marked `✓ Phase 2` | ✓ VERIFIED | Line 76 |
| `scripts/devbox-ssm.sh` | NEW; executable; pre-flights `session-manager-plugin`; exec's `aws ssm start-session` | ✓ VERIFIED | 61 lines; pre-flight at 36-51; exec at 59-61 |
| `scripts/devbox-allowlist-me.sh` | NEW; executable; curl checkip + regex + atomic write | ✓ VERIFIED | 88 lines; curl at 48; regex at 53; atomic write at 71-80 |
| `scripts/devbox-status.sh` | Connection-info rewritten to SSM-first | ✓ VERIFIED | Lines 48-65 |
| `scripts/devbox-start.sh` | Connection-info rewritten to SSM-first | ✓ VERIFIED | Lines 74-82 |
| `Makefile` | Three new `.PHONY` targets + help section + recipes | ✓ VERIFIED | Line 1 (.PHONY), 29-32 (help), 111-138 (recipes) |

## Key link verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `var.allowed_web_cidrs` | `aws_security_group.devbox` ingress :8080 + :6080 | direct `cidr_blocks` reference | ✓ WIRED | Two occurrences at `terraform/main.tf:116, 124` |
| `aws_iam_role.devbox` | `AmazonSSMManagedInstanceCore` AWS-managed policy | `aws_iam_role_policy_attachment.devbox_ssm_core` | ✓ WIRED | `terraform/main.tf:92-95` |
| Validation block | Plan-time hard-fail when list empty AND escape hatch false | Terraform variable validation | ✓ WIRED | `terraform/variables.tf:68-71`; live `tofu plan` reproduced the failure |
| Makefile `devbox-ssm` | `scripts/devbox-ssm.sh` | shell-out via Make recipe | ✓ WIRED | `Makefile:113-114` |
| `scripts/devbox-ssm.sh` | `terragrunt output -raw instance_id` | `init_devbox` from `_common.sh` | ✓ WIRED | Confirmed by inspection of `_common.sh` and `devbox-ssm.sh:53` |
| `scripts/devbox-allowlist-me.sh` | `./allowlist.auto.tfvars` (gitignored) | atomic temp+mv | ✓ WIRED | Lines 71-80 write to `${TFVARS_PATH:-./allowlist.auto.tfvars}` |
| `scripts/devbox-status.sh` connection-info | SSM start-session command + browser URLs | rewritten block | ✓ WIRED | Lines 48-65 |
| terragrunt locals `allowed_web_cidrs` | terraform `var.allowed_web_cidrs` | `inputs.allowed_web_cidrs = local.allowed_web_cidrs` | ✓ WIRED | `terragrunt.hcl:62` |

## Behavioral spot-checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Validation fails with empty list | `tofu plan -var 'allowed_web_cidrs=[]' -var allow_open_ingress=false ...` | Returns "Invalid value for variable" + `make devbox-allowlist-me` hint | ✓ PASS |
| `tofu validate` clean | `cd terraform && tofu validate` | `Success! The configuration is valid.` | ✓ PASS |
| All scripts syntactically valid | `bash -n scripts/devbox-*.sh` | exit 0 | ✓ PASS |
| Shellcheck clean | `shellcheck scripts/devbox-{ssm,allowlist-me,status,start}.sh` | no warnings | ✓ PASS |
| Make targets parse | `make -n devbox-ssm/-port-forward/-allowlist-me` | All emit expected commands | ✓ PASS |
| Help lists new section | `make help` | "SSM access (Phase 2 — replaces public :22 ingress)" with 3 targets listed | ✓ PASS |
| No `ssh -i` left in scripts | `git grep 'ssh -i' scripts/` | no matches | ✓ PASS |

Live AWS-side smoke checks (`aws ssm describe-instance-information`, real port-forward, real allowlist-then-apply round-trip) require a deployed devbox and operator IAM credentials; they are documented for the post-apply path in the plans (02-01 lines 569-584, 02-02 lines 668-687) but are not runnable in this verification environment. Not a blocker — every plan-time and code-side check passes.

## Anti-patterns found

None blocking. Minor notes (info-level, not regressions):

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `scripts/devbox-start.sh` | 65-72 | Retained `KEY_NAME` query is no longer surfaced in the rewritten output block | ℹ️ INFO | Plan explicitly defers cleanup; `# shellcheck disable=SC2034` directive added with explanatory comment. No security or correctness impact. |
| `terraform/variables.tf` | 82 | The description string for `allow_open_ingress` contains the literal `0.0.0.0/0` | ℹ️ INFO | Intentional — the description is documenting the FORBIDDEN combination; it is not a CIDR expression in code. Picked up by `git grep` but flagged in verification as not an ingress occurrence. |
| Makefile devbox-port-forward | 119-135 | Single-port (:8080 only) limitation | ℹ️ INFO | Documented inline at `Makefile:116-118` and surfaced at runtime in the recipe's echo output. Operators needing `:6080` use `make devbox-allowlist-me` or open a second forwarding session. Trade-off acknowledged in `02-02-PLAN.md` and `02-02-SUMMARY.md`. |

## Gaps Summary

None. Every must-have observable truth, every required artifact, every key link, and every spot-check passes. The hybrid posture is locked in code and in PROJECT.md; the operator UX is wired end-to-end; the validation block is the gate that prevents accidental regression.

## Sign-off

The phase delivered exactly what its goal demanded and slightly more. The `:22` ingress is gone (deletion, not narrowing — strictly more restrictive than the literal NET-01 wording, and the re-interpretation is documented in PROJECT.md). The web ports `:8080` and `:6080` are gated on a single shared `var.allowed_web_cidrs` whose double validation block (non-empty OR escape hatch, plus `cidrhost()` shape) fires at plan time with an error message that names the recovery command. The `AmazonSSMManagedInstanceCore` policy lands as a 3-line attachment on the existing Phase 1 role, no new Ansible roles, no bake-time changes. The operator UX (`make devbox-ssm`, `make devbox-port-forward`, `make devbox-allowlist-me`) is shellcheck-clean, dry-runs cleanly, and every legacy `ssh -i ~/.ssh/...pem` string has been purged from the surfaced operator output. The plan-checker WARNs from `02-CHECK.md` (lockout-recovery wording, migration-block placement) are documentation-hygiene items that the SUMMARYs absorbed cleanly; none surface as code-side gaps. Verdict: **COMPLETE**.

---

_Verified: 2026-05-13_
_Verifier: Claude (gsd-verifier)_
