# Phase 2 Plan Check — Network Exposure Remediation

**Checked:** 2026-05-13
**Phase goal:** Eliminate every `0.0.0.0/0` ingress on `aws_security_group.devbox` via the locked hybrid posture (SSM Session Manager for SSH; CIDR allowlist for :8080 + :6080).
**Plans checked:** `02-01-PLAN.md` (607 lines), `02-02-PLAN.md` (709 lines).

## Verdict

**PASS** — with two minor WARNs that do not block execution.

## Dimension Scores

| # | Dimension | Result | Note |
|---|-----------|--------|------|
| 1 | Coverage (NET-01..NET-04) | PASS | All four in `02-01` frontmatter `requirements:`. `02-02` `requirements: []` is correct: it is pure operator UX over 02-01's outputs (objective line 86 calls this out explicitly). |
| 2 | NET-01 re-interpretation | PASS | `02-01-PLAN.md:91-99` (Decision section) + Task 5 update to PROJECT.md Key Decisions row. Re-interpretation framed as "strictly more restrictive than narrowing." |
| 3 | Wave order | PASS | 02-01 wave 1 / `depends_on: []`; 02-02 wave 2 / `depends_on: ["02-01"]`. 02-02 legitimately consumes 02-01's new `ssm_start_session_command` output, the `*.auto.tfvars` gitignore entry, and (semantically) the SSM IAM policy attachment without which `make devbox-ssm` would fail at runtime. |
| 4 | Locked decisions honored | PASS | Hybrid posture, `AmazonSSMManagedInstanceCore` attached to existing `aws_iam_role.devbox`, single managed-policy attachment, default `allowed_web_cidrs = []`, `allow_open_ingress = false` escape hatch, validation fires on `length(...) > 0 || allow_open_ingress`. All present in `02-01-PLAN.md:186-208` (Task 1) and `:240-243` (Task 2 part a). |
| 5 | No new bake-time dependency | PASS | Neither plan touches `ansible/`. No `amazon-ssm-agent` install role added. RESEARCH.md:72 confirms it is preinstalled in AL2023. |
| 6 | Operator prereq surfaced | PASS | `02-02-PLAN.md:22-28` `user_setup` frontmatter names `session-manager-plugin`. `command -v session-manager-plugin` pre-flight present in `scripts/devbox-ssm.sh` (Task 1 lines 184-199) and again inline in the `devbox-port-forward` recipe (Task 4 lines 506-510). |
| 7 | Lockout recovery | WARN | Validation runs at plan-time (`02-01-PLAN.md:210-212` cites RESEARCH.md:218) so empty-list mistakes fail before apply. The specific lockout sequence ("set `allow_open_ingress=true`, deploy with `[]`, then flip escape hatch to false") is NOT spelled out explicitly — though it is implicitly plan-time-safe because the validation will fire on the next apply. Migration steps for in-flight devboxes appear only in the `<output>` SUMMARY instructions (`02-01-PLAN.md:604`, `02-02-PLAN.md:706`), not in the plan body itself. |
| 8 | Threat model | PASS | Both plans ship `<threat_model>` with STRIDE entries (T-02-01..T-02-09 in 02-01; T-02-10..T-02-16 in 02-02). Spot-checked 3 from each: every mitigation cited is concretely visible in a task action, frontmatter, or verify block (not just stated). |
| 9 | `devbox-port-forward` :6080 trade-off | PASS | `02-02-PLAN.md:528-538` documents the single-port limitation and operator escape paths (run a second session OR add :6080 IP to allowlist via `make devbox-allowlist-me`). Inline comment added at top of recipe. |
| 10 | Verification commands | PASS | 02-01 `<verification>` (lines 519-584) covers `tofu plan`/`tofu validate`, no-0.0.0.0/0 grep, no-:22 grep, SSM policy grep, empty-list rejection, non-empty-list acceptance, PROJECT.md update, post-apply `aws ssm describe-instance-information ... Online` smoke. 02-02 `<verification>` (lines 633-688) covers shellcheck/bash -n on all four scripts, `make -n` dry-runs on all three new targets, `make help` enumeration, live `make devbox-ssm` smoke. |
| 11 | Migration for in-flight devboxes | WARN | RESEARCH.md migration section (599-635) is exhaustive: existing TCP sessions survive; new SSH reconnects fail; `make tg-apply` tightens the SG via `create_before_destroy`. This is referenced from 02-01 but the specific behaviour ("existing SSH sessions stay open until disconnect; future reconnects fail unless allowlist updated or operator uses SSM") is NOT echoed into the 02-01 plan body or task notes — only into the `<output>` SUMMARY-writing instruction. Acceptable but a sharper edge would help the executor surface it during apply. |
| 12 | Task completeness | PASS | All 10 tasks have `<files>`, `<action>`, `<verify>` with `<automated>`, `<done>`. |
| 13 | Scope sanity | WARN | Both plans carry 5 tasks each — at the upper edge of the warning band (target 2-3, warning 4, blocker 5+). Mitigating factor: each task is genuinely small and single-file, dependencies are linear, and the plans went through one round of planner self-review. Not blocking, but worth noting that 02-01 could plausibly fold Tasks 1+2 (variables.tf + main.tf in one auto edit) without quality loss. |
| 14 | Architectural tier compliance | PASS | Every capability in RESEARCH.md Responsibility Map (56-64) lands in the tier the map assigns: SSM in AWS control plane (02-01 Task 2), CIDR allowlist on the EC2 SG (02-01 Task 2), IP discovery on operator workstation (02-02 Task 2 `scripts/devbox-allowlist-me.sh`), connection-info on `scripts/devbox-status.sh` (02-02 Task 3). |
| 15 | Cross-plan data contracts | PASS | 02-01 produces `instance_id`, `aws_region`, `ssm_start_session_command` outputs + `*.auto.tfvars` gitignore + `var.allowed_web_cidrs` input contract; 02-02 consumes these via `terragrunt output -raw` (existing `scripts/_common.sh` API) and `./allowlist.auto.tfvars` (the file the scripts write). No conflicting transforms. The `<interfaces>` blocks in both plans (02-01 lines 117-173, 02-02 lines 105-129) explicitly enumerate the contract. |
| 16 | CLAUDE.md compliance | SKIPPED | Top-level `CLAUDE.md` is empty (per PROJECT.md "Active" item DOC-01, deferred to Phase 4). No project-level directives to violate. Global user rules apply transitively; no contradiction observed. |
| 17 | Research resolution | WARN | RESEARCH.md `## Open Questions` section header at line 563 lacks the `(RESOLVED)` suffix mandated by the gate protocol, even though every individual question has a `Recommendation:` line resolving it. Substance is fine; the section heading needs `(RESOLVED)` appended. Not blocking because the resolutions are present inline. |
| 18 | Scope reduction detection | PASS | Scans for "v1"/"static for now"/"placeholder"/"future enhancement" return only legitimate YAGNI / scope-boundary calls (e.g., 02-02 Task 3 leaving redundant `KEY_NAME` queries in scripts as out-of-scope cleanup; 02-02 Task 4 shipping single-port port-forward for :8080 with documented escape). No NET-* requirement is silently reduced. |
| 19 | Pattern compliance | SKIPPED | No `02-PATTERNS.md` exists. RESEARCH.md Patterns 1-5 serve the same function and are referenced from both plans (02-01 lines 184, 222, 232, 297-301; 02-02 lines 155, 216, 338-340). |

## Findings

### WARN — Dimension 7 (Lockout recovery): escape-hatch flip sequence not called out

- **File:** `02-01-PLAN.md`
- **Where:** Threat model T-02-02 (around line 509), Decision section (lines 91-99).
- **Issue:** The plan documents that empty `allowed_web_cidrs` fails at plan-time (good) and that `allow_open_ingress = true` is the only way to bypass it (good). It does NOT explicitly call out the specific lockout sequence: (a) operator sets `allow_open_ingress = true` with empty `allowed_web_cidrs`, applies (no public web ingress, SSM still works); (b) operator later flips `allow_open_ingress` back to `false`. Result is a plan-time failure (validation), not a runtime lockout — which is the safe outcome — but the planner never says so out loud, so an executor or future operator might worry about it.
- **Recommended revision:** Append one bullet to 02-01's Decision section (after line 99): *"Escape-hatch flip safety: if `allow_open_ingress = true` is used to deploy an empty `allowed_web_cidrs`, flipping the bool back to `false` later is plan-time-safe — Terraform's variable validation fires before any apply, so the operator cannot accidentally lock themselves out of `:8080`/`:6080`. They can still reach the host via SSM Session Manager."*

### WARN — Dimension 11 (Migration): in-flight-devbox behaviour not echoed into plan body

- **File:** `02-01-PLAN.md`
- **Where:** The plan body (tasks 1-5). Migration content currently lives only in `<output>` SUMMARY-writing instructions (line 604) and in RESEARCH.md:599-635.
- **Issue:** The executor reads tasks and verification blocks. They do NOT necessarily read SUMMARY-writing instructions before running. The "existing SSH sessions stay open until disconnect; new reconnects fail; one-shot `make tg-apply` tightens the SG via `create_before_destroy`" behaviour is operationally important during apply (operator may have an active SSH session and not realise it will be the last one).
- **Recommended revision:** Add a `<migration>` block to `02-01-PLAN.md` (between `<threat_model>` and `<verification>`) that copies the four bullets from RESEARCH.md:627-635 verbatim: in-flight TCP behaviour, browser-tab behaviour, apply cost, lockout-recovery via EC2 Console Session Manager.

### WARN — Dimension 13 (Scope sanity): both plans at 5-task upper edge

- **Files:** `02-01-PLAN.md` (5 tasks), `02-02-PLAN.md` (5 tasks).
- **Issue:** Five tasks per plan is exactly at the warning threshold per the plan-checker scoring guide. Each task is small and single-file, dependencies are linear, but executor context burn is real.
- **Recommended revision (optional, not blocking):** In 02-01, consider folding Task 1 (variables.tf) into Task 2 (main.tf) — both are inside `terraform/`, both are required for `tofu validate` to pass, and the verify steps overlap. Same shape applies to 02-02 Task 5 ("smoke-test gate") which is really a verify pass rather than an action task; it could be merged into Task 4's `<verify>` and `<done>` blocks.

### WARN — Dimension 17 (Research resolution): Open Questions header missing `(RESOLVED)` marker

- **File:** `02-RESEARCH.md:563`
- **Issue:** Section heading reads `## Open Questions` rather than `## Open Questions (RESOLVED)`. All three listed questions carry inline `Recommendation:` resolutions, so the substance is present; the protocol marker is not.
- **Recommended revision:** Edit `02-RESEARCH.md:563` from `## Open Questions` to `## Open Questions (RESOLVED)`. No other content change required.

## Recommended next step

**Proceed to `/gsd-execute-phase 2`.** Verdict is PASS. The four WARNs are documentation/hygiene refinements that the executor can land alongside the implementation work (a brief paragraph in 02-01-SUMMARY can absorb the migration + escape-hatch notes; the RESEARCH.md heading is a one-character edit). None of them blocks the executor from delivering NET-01..NET-04 against the hybrid posture.
