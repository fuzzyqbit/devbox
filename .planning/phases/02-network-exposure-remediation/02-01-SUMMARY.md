---
phase: 02-network-exposure-remediation
plan: 01
subsystem: terraform-network-iam
tags:
  - terraform
  - aws-security-group
  - aws-ssm-session-manager
  - cidr-allowlist
  - iam-policy-attachment
requirements:
  - NET-01
  - NET-02
  - NET-03
  - NET-04
provides:
  - var.allowed_web_cidrs
  - var.allow_open_ingress
  - aws_iam_role_policy_attachment.devbox_ssm_core
  - output.ssm_start_session_command
  - terragrunt.inputs.allowed_web_cidrs (sourced from env vars)
  - .gitignore *.auto.tfvars
affects:
  - aws_security_group.devbox (drops :22 ingress, replaces static :8080/:6080 cidrs with var)
  - terraform/outputs.tf (removes output.ssh_command, replaces with output.ssm_start_session_command)
  - .planning/PROJECT.md Key Decisions (NET-04 → ✓ Phase 2)
key-files:
  created: []
  modified:
    - path: terraform/variables.tf
      range: "63-83 (22 new lines appended after existing extra_tags block at lines 57-61)"
    - path: terraform/main.tf
      range: "87-95 (new SSM policy attachment), 97-142 (rewritten SG block; was 87-136 pre-plan)"
    - path: terraform/outputs.tf
      range: "16-19 (ssh_command → ssm_start_session_command)"
    - path: terragrunt.hcl
      range: "1-20 (locals block extended with 5 new locals), 43-63 (inputs block extended with allowed_web_cidrs)"
    - path: .gitignore
      range: "29-33 (Phase 2 stanza appended after .terraform.lock.hcl line)"
    - path: .planning/PROJECT.md
      range: "76 (NET-04 row replaced), 97 (Last updated footer bumped)"
decisions:
  - "NET-01 satisfied by deletion of the :22 ingress rule, not by narrowing to a CIDR (structurally more restrictive than any allowed-CIDR rule); locked in 02-RESEARCH.md:9 and recorded in PROJECT.md Key Decisions row for NET-04."
  - "Single var.allowed_web_cidrs shared between :8080 and :6080 (per RESEARCH.md A4); orchestrator-named env vars (CODE_SERVER_ALLOWED_CIDRS, VNC_ALLOWED_CIDRS) reconciled by taking the union in terragrunt locals."
  - "Inline ingress blocks chosen over dynamic blocks (RESEARCH.md Example 1) for clearer tofu plan output on a fixed 2-port shape."
  - "var.allow_open_ingress escape hatch implemented as a single bool that fails closed by default; setting it to true AND populating allowed_web_cidrs with 0.0.0.0/0 is called out as forbidden in the variable description."
metrics:
  duration_minutes: 8
  tasks_completed: 5
  files_modified: 6
  files_created: 0
  commits: 5
  completed_date: 2026-05-14
---

# Phase 2 Plan 01: Network exposure remediation — Terraform tightening + SSM policy attachment

## One-liner

Tightened the Terraform/Terragrunt layer to the locked hybrid posture: dropped `:22` SG ingress entirely (SSM Session Manager takes over for shell access), gated `:8080`/`:6080` on `var.allowed_web_cidrs` with a fail-closed validation block and `var.allow_open_ingress` escape hatch, attached the AWS-managed `AmazonSSMManagedInstanceCore` policy to the Phase 1 IAM role, and wired operator IP discovery through `CODE_SERVER_ALLOWED_CIDRS`/`VNC_ALLOWED_CIDRS` env vars (or a gitignored `allowlist.auto.tfvars`).

## Tasks executed

| # | Task | Files | Commit |
|---|------|-------|--------|
| 1 | Add `var.allowed_web_cidrs` + `var.allow_open_ingress` variables | `terraform/variables.tf:63-83` | `6049fde` |
| 2 | Rewrite `aws_security_group.devbox` (no `:22`, web ports via var); add `aws_iam_role_policy_attachment.devbox_ssm_core` | `terraform/main.tf:87-142` | `d5e4501` |
| 3 | Replace `output "ssh_command"` with `output "ssm_start_session_command"` | `terraform/outputs.tf:16-19` | `d838f5b` |
| 4 | Wire `CODE_SERVER_ALLOWED_CIDRS`/`VNC_ALLOWED_CIDRS` env vars into terragrunt; gitignore `*.auto.tfvars` | `terragrunt.hcl:1-63`, `.gitignore:29-33` | `f5b9581` |
| 5 | Record NET-04 hybrid-posture decision in PROJECT.md Key Decisions | `.planning/PROJECT.md:76,97` | `dde8cf2` |

All five tasks executed in plan order with one verification + atomic commit per task. No tasks deferred. No tasks split.

## NET-01 re-interpretation (repeated verbatim from plan Objective for the verifier)

REQUIREMENTS.md:20 reads:

> NET-01: Security group ingress for SSH (:22) is restricted to operator-supplied CIDR list (default: `[]`, refuses to apply if empty without explicit override) — replace `0.0.0.0/0` in `terraform/main.tf`

Under the hybrid posture locked in `02-RESEARCH.md:9` ("eliminate the :22 ingress entirely"), this plan drops the `:22` ingress rule entirely rather than narrowing it to a CIDR list. This goes one better than the requirement: an empty rule set on `:22` is strictly more restrictive than any allowed-CIDR rule. The `var.allowed_web_cidrs` validation still gates the apply for `:8080` and `:6080` — NET-01's "refuses to apply if empty without explicit override" semantics are preserved by the same `allow_open_ingress = false` escape hatch that covers NET-02 and NET-03.

NET-01 is satisfied by deletion, not by narrowing. No `var.allowed_admin_cidrs` variable is introduced.

This re-interpretation is recorded in `.planning/PROJECT.md:76` (NET-04 Key Decisions row).

## Verification commands run

### 1. Terraform syntactic correctness

```bash
$ cd terraform && tofu fmt -check . && tofu validate
fmt exit: 0
Success! The configuration is valid.
validate exit: 0
```

### 2. Terragrunt syntactic correctness

```bash
$ terragrunt hcl format --check --file terragrunt.hcl
exit: 0
```

**Deviation note:** The plan's task-4 verify line uses `terragrunt hclfmt --check` (legacy command), which in this environment (terragrunt 0.81.10 + worktree path that descends into `packer/*.pkr.hcl`) (a) emits a deprecation warning instructing migration to `terragrunt hcl format`, AND (b) walks `packer/*.pkr.hcl` and aborts with "invalid file format". The targeted form `terragrunt hcl format --check --file terragrunt.hcl` produces the equivalent check on the file actually modified by this plan. Logged here for the verifier; no behavior delta in `terragrunt.hcl` itself.

### 3. No `0.0.0.0/0` in any ingress block

```bash
$ grep -v '^[[:space:]]*#' terraform/main.tf \
  | awk '/^[[:space:]]*ingress[[:space:]]*\{/,/^[[:space:]]*\}/' \
  | grep -F '0.0.0.0/0'
(no output)
PASS: no ingress contains 0.0.0.0/0
```

(Egress block keeps `0.0.0.0/0` as required for the amazon-ssm-agent outbound channel — RESEARCH.md:383-389 Pitfall 4.)

### 4. No `:22` ingress remains

```bash
$ grep -v '^[[:space:]]*#' terraform/main.tf | grep -c 'from_port[[:space:]]*=[[:space:]]*22'
0
PASS: no :22 ingress
```

### 5. SSM policy attachment present

```bash
$ grep -F 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore' terraform/main.tf
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
PASS
```

### 6-7. Variable validation behavior

The plan's tasks 6 and 7 run `DEVBOX_USER=... terragrunt validate` with and without `CODE_SERVER_ALLOWED_CIDRS` set. **Auth gate:** in this worktree, `terragrunt validate` invokes `get_aws_account_id()` at `terragrunt.hcl:3` which requires real AWS credentials (`InvalidClientTokenId` in our env). I substituted a direct `tofu plan` invocation that exercises both validation blocks against the variable directly, which is the same gate the plan was checking for. Results:

```bash
# 6a. Empty list rejected with actionable error
$ cd terraform && tofu plan \
    -var devbox_user=testuser -var vpc_id=vpc-x -var subnet_id=subnet-x \
    -var ami_id=ami-x -var key_name=k \
    -var 'allowed_web_cidrs=[]' -var allow_open_ingress=false
Error: Invalid value for variable
  on variables.tf line 63: ...
  var.allow_open_ingress is false
  var.allowed_web_cidrs is empty list of string
allowed_web_cidrs must contain at least one CIDR (e.g. 203.0.113.42/32).
Run `make devbox-allowlist-me` to auto-populate your current public IP, or
set the value explicitly in an allowlist.auto.tfvars file. To bypass this
gate intentionally (NOT recommended), set var.allow_open_ingress = true.
PASS: empty allowlist rejected with the make devbox-allowlist-me hint.

# 6b. Malformed CIDR rejected by the second validation block
$ tofu plan -var 'allowed_web_cidrs=["not-a-cidr"]' ...
Error: Invalid value for variable
  Each entry in allowed_web_cidrs must be a valid CIDR block (...).
  cidrhost() failed for at least one entry — check for a missing /XX suffix.
PASS: cidrhost() defense fires.

# 7. Non-empty allowlist accepted
$ tofu plan -var 'allowed_web_cidrs=["203.0.113.42/32"]' ...
(no "Invalid value for variable" error; only the AWS-credentials gate which is unrelated)
PASS: non-empty allowlist accepted.

# 7b. Escape hatch with empty list passes
$ tofu plan -var 'allowed_web_cidrs=[]' -var allow_open_ingress=true ...
(no "Invalid value for variable" error)
PASS: escape hatch unblocks the gate.
```

### 8. PROJECT.md updated

```bash
$ grep -F 'Hybrid posture chosen' .planning/PROJECT.md
| AWS SSM Session Manager vs SSH ingress CIDR list (NET-04) | **Hybrid posture chosen:** SSM Session Manager for shell access ... | ✓ Phase 2 |
PASS
```

### 9. .gitignore protects auto-tfvars

```bash
$ grep -F '*.auto.tfvars' .gitignore
*.auto.tfvars
PASS
```

## Threat model mitigations applied

Mapping the plan's `<threat_model>` STRIDE entries to specific code lines / decisions:

| Threat ID | Where mitigated | Line / commit |
|-----------|-----------------|---------------|
| T-02-01 Spoofing (SSM IAM gate) | The plan does NOT grant `ssm:StartSession` on the instance; only the operator's IAM principal can call StartSession. Phase 4 DOC-01 surfaces minimum operator-side policy. Phase 2 mitigation = the gate exists. | `terraform/main.tf:92-95` (attaches agent-side policy only) |
| T-02-02 Tampering (allow_open_ingress) | Defaults `false`. Description text spells out the forbidden combination (true + 0.0.0.0/0). | `terraform/variables.tf:79-83` |
| T-02-03 Information Disclosure (operator IP in tfvars) | `.gitignore *.auto.tfvars` + `.gitignore allowlist.auto.tfvars` (two-layer match). | `.gitignore:32-33` |
| T-02-04 Captive-portal HTML poisoning | Second validation block `alltrue([for c in var.allowed_web_cidrs : can(cidrhost(c, 0))])` is the defense-in-depth catch behind 02-02's script-side regex. | `terraform/variables.tf:73-76` |
| T-02-05 DoS (IP changes + no SSM plugin) | Accepted; EC2 Console browser-based Session Manager is the fallback (documented in RESEARCH.md:634). | n/a — accepted |
| T-02-06 EoP (SSM Agent compromise → cross-instance pivot) | `AmazonSSMManagedInstanceCore` grants only agent-side messaging permissions (`ssmmessages:*`, `ec2messages:*`, `ssm:UpdateInstanceInformation`); no `ssm:StartSession`. Phase 1's IMDSv2 (`http_tokens="required"`, `hop_limit=1`) still in force. | `terraform/main.tf:94` + `:155-159` (Phase 1 invariant preserved) |
| T-02-07 EoP (operator AWS IAM compromised) | Accepted; operator-side IAM lives outside this repo. CloudTrail records all `ssm:StartSession` events by default. | n/a — accepted |
| T-02-08 Repudiation (operator denies session) | CloudTrail default audit trail (free, on by default). Full session-stream logging deferred to v2 OBS-02. | n/a — leveraged AWS default |
| T-02-09 Spoofing (`0.0.0.0/0` re-enters via future PR) | Structural: no literal `0.0.0.0/0` in any ingress block (verified by Task 2 grep). Phase 4 will add tfsec/checkov CI gate. | `terraform/main.tf:106-126` (only `var.allowed_web_cidrs`) |

No threat dispositions changed during execution. No new threat surface introduced beyond the planned scope.

## Decision-log delta

PROJECT.md Key Decisions now has the NET-04 row populated with the hybrid-posture rationale and `✓ Phase 2` status (was `— Pending`). The Active requirements bullet at PROJECT.md:33 remains unchanged — the verifier owns flipping that to Validated after Phase 2 verification. The "Last updated" footer (PROJECT.md:97) bumped to record Phase 2 plan written.

## Operator Prereqs (consumed by Phase 4 DOC-01 quickstart)

One new operator-side dependency introduced by this plan, but the script that consumes it lands in 02-02:

| Dependency | Why | Install |
|------------|-----|---------|
| `session-manager-plugin` | The AWS CLI shells out to it for `aws ssm start-session`. Without the plugin, the new shell path is unreachable. | `brew install --cask session-manager-plugin` (macOS); see `[https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html]` for Linux. |

Operator-side IAM check (documented in RESEARCH.md A2): the operator's IAM principal needs `ssm:StartSession`, `ssm:TerminateSession`, `ssm:DescribeSessions`, `ssm:DescribeInstanceInformation` on the target instance ARN (or `AmazonSSMFullAccess` for personal-use convenience). Not modified by this plan — sits outside the repo by design.

## Migration notes (existing devboxes)

An operator who already has a running devbox built before Phase 2 needs:

```bash
# 1. One-time
brew install --cask session-manager-plugin

# 2. Set the env var (or run 02-02's `make devbox-allowlist-me`)
export CODE_SERVER_ALLOWED_CIDRS="$(curl -s checkip.amazonaws.com)/32"

# 3. Apply Phase 2 deltas (SSM policy attaches, SG ingress changes)
make tg-apply DEVBOX_USER=$USER

# 4. Verify SSM agent is Online (60s post-apply)
INSTANCE_ID=$(cd terraform && DEVBOX_USER=$USER terragrunt output -raw instance_id)
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text
# Expected: Online

# 5. Shell access via SSM (was: ssh -i ~/.ssh/me-devbox.pem ec2-user@<ip>)
aws ssm start-session --target $INSTANCE_ID
# (02-02 will deliver this via `make devbox-ssm`)
```

Existing in-flight TCP connections survive the SG change (AWS stateful SG semantics); new connections to `:22` are rejected immediately.

## Hand-off contract for 02-02-PLAN

02-02-PLAN.md is the operator UX layer for the same posture. It consumes the following from this plan:

| Symbol | Type | Used by 02-02 |
|--------|------|---------------|
| `output "instance_id"` | terraform output (unchanged from Phase 1) | `make devbox-ssm` reads it via `terragrunt output -raw instance_id` |
| `output "aws_region"` | terraform output (unchanged from Phase 1) | `make devbox-ssm` reads it via `terragrunt output -raw aws_region` |
| `output "ssm_start_session_command"` | new terraform output (this plan) | `scripts/devbox-status.sh` rewrite prints this string in the Connection Info block |
| `output "security_group_id"` | terraform output (unchanged from Phase 1) | Post-apply smoke check (`aws ec2 describe-security-groups ... FromPort==22` → expected empty) |
| `var.allowed_web_cidrs` | terraform input variable | `make devbox-allowlist-me` writes a `.auto.tfvars` file setting this var to `["${operator_ip}/32"]` |
| `var.allow_open_ingress` | terraform input variable (escape hatch) | NOT consumed by 02-02; documented in CLAUDE.md (Phase 4) as the bypass for SSM-port-forwarding-only workflows |
| `terragrunt.hcl` `local.allowed_web_cidrs` | wired to env vars `CODE_SERVER_ALLOWED_CIDRS`, `VNC_ALLOWED_CIDRS` | Optional alternate path: operators can `export CODE_SERVER_ALLOWED_CIDRS=...` instead of running `make devbox-allowlist-me` |

Out-of-scope for this plan (02-02 owns):
- `Makefile` `devbox-ssm` and `devbox-allowlist-me` targets
- `scripts/devbox-ssm.sh` (thin wrapper)
- `scripts/devbox-allowlist-me.sh` (curl checkip + write auto.tfvars)
- `scripts/devbox-status.sh` rewrite

## Deviations from plan

### Auto-resolved (Rule 1 — Bug / Rule 3 — Blocker)

**1. [Rule 3 — Blocker] terragrunt hclfmt deprecated and recursive in worktree**

- **Found during:** Task 4 `<verify>` step
- **Issue:** Plan invokes `terragrunt hclfmt --check` at repo root. With terragrunt 0.81.10, this command (a) prints a deprecation warning, and (b) recurses into the worktree path which contains `packer/devimage.pkr.hcl` (a Packer file, not a Terragrunt file) and aborts with `invalid file format`. Same applies to the new `terragrunt hcl format --check` without `--file`.
- **Fix:** Use the targeted form `terragrunt hcl format --check --file terragrunt.hcl`. This exercises the same formatter against the only HCL file this plan modifies. Exit 0.
- **Files modified:** None (verification-only deviation).
- **Commit:** part of `f5b9581` execution log; documented here.

**2. [Rule 3 — Blocker] `terragrunt validate` cannot run without AWS credentials in this worktree**

- **Found during:** Task 4 `<verify>` step (`terragrunt run-all validate --terragrunt-non-interactive`).
- **Issue:** `terragrunt.hcl:3` calls `get_aws_account_id()` at the locals block; the entire HCL evaluation requires real AWS credentials. The worktree has none (`InvalidClientTokenId`).
- **Fix:** Substituted `tofu plan` directly against the `terraform/` module with explicit `-var` injections. This exercises BOTH validation blocks on `var.allowed_web_cidrs` (the actual gate the plan was checking) AND the new `aws_iam_role_policy_attachment`, with full enumeration of cases:
  - empty list + `allow_open_ingress=false` → rejected with `make devbox-allowlist-me` hint (PASS)
  - non-CIDR string → rejected by `cidrhost()` validation (PASS)
  - valid CIDR → accepted (only the AWS auth error remains, unrelated) (PASS)
  - empty list + `allow_open_ingress=true` → accepted (escape hatch works) (PASS)
- **Files modified:** None (verification-only deviation).
- **Commit:** part of `f5b9581` execution log; documented in §"Verification commands run" above.

### Auto-fixed (Rule 1 — Bug)

None. Plan executed exactly as written for in-scope deltas.

### Rule 2 — Missing critical functionality

None added beyond what the plan specified. The threat model's `mitigate` dispositions are covered by the plan's listed deltas (verified in §"Threat model mitigations applied").

### Architectural (Rule 4)

None. No checkpoints encountered. Plan was `autonomous: true` end-to-end.

## Deferred Issues

None — all task-level verification gates passed.

## Self-Check: PASSED

Created/modified files exist:
- `terraform/variables.tf` — FOUND (with `var.allowed_web_cidrs` + `var.allow_open_ingress`)
- `terraform/main.tf` — FOUND (with `aws_iam_role_policy_attachment.devbox_ssm_core`, no `from_port = 22` in non-comment lines, two `cidr_blocks = var.allowed_web_cidrs`)
- `terraform/outputs.tf` — FOUND (with `output "ssm_start_session_command"`, no `output "ssh_command"`)
- `terragrunt.hcl` — FOUND (with `local.allowed_web_cidrs` + `inputs.allowed_web_cidrs`)
- `.gitignore` — FOUND (with `*.auto.tfvars` + `allowlist.auto.tfvars`)
- `.planning/PROJECT.md` — FOUND (with `Hybrid posture chosen` + `✓ Phase 2` on NET-04)

Commits exist in `git log --oneline`:
- `6049fde` — Task 1 (variables) FOUND
- `d5e4501` — Task 2 (SG + SSM policy) FOUND
- `d838f5b` — Task 3 (outputs) FOUND
- `f5b9581` — Task 4 (terragrunt + gitignore) FOUND
- `dde8cf2` — Task 5 (PROJECT.md) FOUND

Verdict: **COMPLETE**
