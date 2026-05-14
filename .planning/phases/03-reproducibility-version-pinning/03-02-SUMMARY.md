---
phase: 03-reproducibility-version-pinning
plan: 02
subsystem: ami-bake-and-handoff
tags: [reproducibility, version-pinning, packer, ami-handoff, manifest, makefile, ssm-parameter-store]
requirements_closed: [REP-04, REP-05]
dependency_graph:
  requires:
    - packer/devimage.pkr.hcl (Phase 1 baseline — source_ami_filter with most_recent = true)
    - Makefile build target (Phase 1)
    - terragrunt.hcl inputs block (Phase 1, hand-copied ami_id literal)
    - Amazon Packer plugin >= 1.2.4 (already pinned at >= 1.3.0)
    - jq (already required by scripts/devbox-status.sh per STACK.md)
  provides:
    - packer/devimage.pkr.hcl — SSM-backed source AMI + manifest post-processor
    - packer/variables.pkr.hcl — new var.devbox_user for manifest custom_data
    - Makefile — packer-bake target (build + manifest parse + tfvars write)
    - .gitignore — packer-manifest.json and users/*.auto.tfvars entries
    - terragrunt.hcl — inputs block free of hand-copied AMI literal
  affects:
    - Operator workflow: `make build` superseded by `make packer-bake` for normal use
    - Phase 4 CI gates — three new grep guards (see "CI Hooks Needed in Phase 4" below)
    - Phase 03-01 (parallel-safe wave 1) — disjoint files; only .gitignore is shared,
      and the two plans touched disjoint sections of it. No merge conflict expected.
tech_stack:
  added: []  # No new tools; new uses of jq, packer, make, AWS SSM Parameter Store
  patterns:
    - Packer `amazon-parameterstore` data source against /aws/service/ami-amazon-linux-latest/
      (RESEARCH Pattern 4)
    - Packer `manifest` post-processor with `custom_data` recording operator + base AMI
      (RESEARCH Pattern 5)
    - Makefile-driven manifest → per-user *.auto.tfvars handoff with `jq` + `printf`
      (RESEARCH Pattern 5, Example E)
    - `sort_by(.build_time) | .[-1]` defense against stale-manifest pitfall
      (RESEARCH Pitfall 4)
key_files:
  created: []  # No new files committed; users/<USER>.auto.tfvars is generated at packer-bake time and gitignored
  modified:
    - .gitignore
    - packer/devimage.pkr.hcl
    - packer/variables.pkr.hcl
    - Makefile
    - terragrunt.hcl
decisions:
  - Used unversioned SSM parameter name (no trailing `:NN`) because the executor
    did not have AWS credentials available to resolve the live parameter version.
    Pin must be added BEFORE the next real `packer build` for true reproducibility.
    The file's comment block documents the bump procedure (`aws ssm
    get-parameter-history`).
  - Hardcoded the SSM parameter name in `devimage.pkr.hcl` instead of introducing
    a `var.source_ami_ssm_parameter` Packer input (per plan's KISS guidance);
    parameterizing is a Phase 4 follow-up if needed.
  - Added `var.devbox_user` to `packer/variables.pkr.hcl` (the plan flagged this as
    "possibly unchanged — only if needed"). It is needed because the manifest's
    `custom_data.devbox_user` field references it; without the var declaration
    `packer validate` errors with "Undefined -var variable".
  - Used `sort_by(.build_time) | .[-1]` in the `jq` invocation (defense in depth
    against the stale-manifest pitfall) on top of the pre-build `rm -f` guard.
  - Removed `terraform/.terraform.lock.hcl` deletion from the `clean` target
    (Plan 03-01 committed the lockfile; `clean` must not destroy it).
  - Kept the legacy `make build` target (calls `packer build` only, no handoff)
    for low-level bake-only flows; documented in `make help` that `packer-bake`
    is the preferred day-to-day flow.
metrics:
  duration_minutes: ~15
  completed_date: 2026-05-14
  task_count: 2
  file_count: 5
  commit_count: 2
---

# Phase 3 Plan 2: Pin Packer Source AMI + Automate AMI Handoff Summary

`packer/devimage.pkr.hcl` now resolves its source AMI via an `amazon-parameterstore` data source against the AWS-managed AL2023 minimal pointer, eliminating the `most_recent = true` glob anti-pattern (REP-04). A `manifest` post-processor emits `packer/packer-manifest.json` after each build; the new `make packer-bake` target parses it with `jq` and writes the just-built AMI ID into `users/${DEVBOX_USER}.auto.tfvars`, which Terraform auto-loads — removing the last hand-copied AMI ID from `terragrunt.hcl` (REP-05). Operator flow collapses from four steps to two.

## Files Modified

| File | Change | Purpose |
|------|--------|---------|
| `packer/devimage.pkr.hcl` | Replaced `source_ami_filter { ... most_recent = true ... }` (8 lines) with a top-level `data "amazon-parameterstore" "al2023_minimal" { ... }` block + `source_ami = data.amazon-parameterstore.al2023_minimal.value` inside the source block; added a `post-processor "manifest" { ... }` block to `build {}` with `custom_data { devbox_user, base_ami_id }` | REP-04 source-AMI pin + REP-05 emitter half of the handoff chain |
| `packer/variables.pkr.hcl` | Added `variable "devbox_user" { type = string; default = "" ... }` | The manifest's `custom_data.devbox_user` reference needed a declared variable; without it `packer validate` errors |
| `Makefile` | Added `packer-bake` to `.PHONY`; added `packer-bake` target (init dep, deletes stale manifest, runs `packer build -var devbox_user=$(DEVBOX_USER)`, parses manifest with `jq '.builds \| sort_by(.build_time) \| .[-1].artifact_id \| split(":") \| .[1]'`, writes `users/$(DEVBOX_USER).auto.tfvars`); updated `help` to advertise `packer-bake` and label `build` as legacy; removed `terraform/.terraform.lock.hcl` from `clean`, added `packer-manifest.json` and `users/*.auto.tfvars` to `clean` | REP-05 handoff target + protect Plan 03-01's lockfile commit |
| `terragrunt.hcl` | Removed `ami_id = "ami-0b7cfe2135f319a55"` line from `inputs`; added a comment block above `inputs =` explaining the new handoff path (auto.tfvars + loud-failure mode via no-default var.ami_id) | REP-05 hand-copy eliminated |
| `.gitignore` | Added `packer/packer-manifest.json` to the Packer section; added `*.auto.tfvars` and `users/*.auto.tfvars` (the bare rule was already present in main from Phase 2 but this worktree branched off an earlier commit, so both were added defensively) | Per-build manifest and per-operator handoff files stay local |

## Commits

| Hash | Subject | Files |
|------|---------|-------|
| `7afb759` | `feat(phase-03-02): pin Packer source AMI via SSM parameterstore + emit build manifest` | `packer/devimage.pkr.hcl`, `packer/variables.pkr.hcl` |
| `8112796` | `chore(phase-03-02): wire AMI handoff (REP-05) — packer-bake target, gitignore manifest, drop hand-copied ami_id` | `.gitignore`, `Makefile`, `terragrunt.hcl` |

## Resolved SSM Parameter Version

**Unresolved — pin must be added before next real `packer build`.**

The plan's Task 1 Step 1 required running `aws ssm get-parameter-history --name /aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64 --region us-east-1` to discover the live integer Version and bake it into the data source's `name` field as a trailing `:NN`. The executor invoked `aws sts get-caller-identity` to check credential status:

```
An error occurred (InvalidClientTokenId) when calling the GetCallerIdentity operation:
The security token included in the request is invalid.
```

Per the orchestrator-supplied constraint ("If `aws ssm get-parameter-history` fails (no creds), use the unversioned path and note in SUMMARY that the version must be pinned before merge"), the committed `name` is:

```
/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64
```

— without the `:NN` suffix. This is a valid SSM parameter name that resolves to whatever AWS publishes as the latest pointer at build time. **It is NOT a deterministic pin across days** — AWS may rotate the value silently. Resolving this and adding the `:NN` is a **prerequisite to declaring REP-04 fully closed** for real reproducibility.

### How to resolve and add the pin

```bash
# 1. Discover the live version (with valid AWS creds):
aws ssm get-parameter-history \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64 \
  --region us-east-1 \
  --query 'Parameters[-1].{Version: Version, LastModifiedDate: LastModifiedDate, Value: Value}' \
  --output table

# 2. Edit packer/devimage.pkr.hcl line 33; change:
#       name   = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64"
#    to:
#       name   = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64:NN"
#    where NN is the integer Version from step 1.
# 3. Commit as a separate reviewable diff: `chore(phase-03-02): pin SSM AMI parameter to version NN (ami-XXX)`
# 4. Re-run `cd packer && packer validate .` to confirm.
```

The file's own comment block (lines 19-31) documents this procedure inline so a future operator does not need to consult this SUMMARY to perform the bump.

The fallback (per RESEARCH Pattern 4 backup at line 289-291) — replacing the SSM lookup with a hardcoded `name = "al2023-ami-minimal-2026.XX.XX.X-kernel-default-x86_64"` filter against `owners = ["amazon"]` — remains available if SSM Parameter Store versioning proves unreliable.

## New Operator Flow

**Before this plan (4 steps, error-prone):**
1. `make build` (runs `packer build`, prints AMI ID at the end)
2. Copy the AMI ID by hand from the terminal output
3. Paste it into `terragrunt.hcl` `inputs.ami_id`
4. `make tg-apply DEVBOX_USER=$(whoami)`

**After this plan (2 steps, deterministic):**
1. `make packer-bake DEVBOX_USER=$(whoami)`
   - Runs `packer build` with `-var devbox_user=$(whoami)`
   - Emits `packer/packer-manifest.json` (gitignored)
   - Parses with `jq` and writes `users/$(whoami).auto.tfvars` containing `ami_id = "ami-XXX"`
2. `make tg-apply DEVBOX_USER=$(whoami)`
   - Terraform auto-loads `users/$(whoami).auto.tfvars` from the module directory and uses its `ami_id` value
   - `var.ami_id` has no default in `terraform/variables.tf`, so a missing handoff file fails loudly at `terragrunt plan` time

## Pin-Bump Procedure (Quarterly Cadence Recommended)

Per RESEARCH Pitfall 3 (lines 411-420), AMIs go through deprecated → disabled → deregistered lifecycle. SSM-parameter-pinned references can outlive the underlying AMI by months but not forever.

```bash
# Check whether the currently-pinned version still resolves:
aws ssm get-parameter-history \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64 \
  --region us-east-1 \
  --query 'Parameters[*].{Version: Version, LastModifiedDate: LastModifiedDate}' \
  --output table

# If the operator wants the newest pointer, pick the most recent row,
# edit the :NN suffix in packer/devimage.pkr.hcl, and commit the diff.
# The diff itself IS the reviewable bump audit trail.
```

## CI Hooks Needed in Phase 4

The Phase 4 (CI + pre-commit) planner should wire all of the following greps as hard gates so this plan's outcomes cannot regress:

| Check | Command | Catches |
|-------|---------|---------|
| Source AMI not floating | `! grep -rE 'most_recent\s*=\s*true' packer/` | Regression to glob-filter source AMI |
| Source AMI pinned to versioned SSM parameter | `grep -E '/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64:[0-9]+' packer/devimage.pkr.hcl` | Catches the unversioned-path state this plan currently leaves the file in; ALSO catches future regressions to unversioned form |
| No raw `<RESOLVED-VERSION>` placeholder | `! grep -- '<RESOLVED-VERSION>' packer/` | Catches accidental copy-paste of the plan's template placeholder text |
| No hand-copied AMI ID in terragrunt.hcl | `! grep -E '^\s*ami_id\s*=\s*"ami-' terragrunt.hcl` | Regression to hand-copy pattern |
| Packer config validates | `cd packer && packer init . && packer validate .` | Syntax/data-source regressions |
| Makefile target present | `make -n packer-bake DEVBOX_USER=test >/dev/null` | Catches accidental target removal or TAB→space corruption |
| Manifest gitignored | `grep -q 'packer-manifest\.json' .gitignore` | Catches accidental commit of the ephemeral artifact |

These hooks complement the ones Plan 03-01 surfaced (lockfile-readonly, no-bare-pins, etc.).

## Documentation Feed for Phase 4 DOC-01 (operator quickstart in CLAUDE.md)

Phase 4 will populate the currently-empty `CLAUDE.md` with operator-facing onboarding. Surfaces from this plan:

- **Primary AMI workflow:** `make packer-bake` → `make tg-apply`. The legacy `make build` is retained for advanced cases (just a Packer bake, no handoff) but is not the recommended day-to-day flow.
- **Quarterly bake cadence:** Run `make packer-bake` at least once per quarter to catch AWS AMI deprecation (Pitfall 3); the SSM parameter pin will eventually outlive its target AMI.
- **Multi-operator note:** The handoff is intentionally per-operator. If operator B needs to apply against operator A's freshly-baked AMI, B must either (a) re-bake themselves (`make packer-bake DEVBOX_USER=B`) or (b) ask A for the AMI ID and write it into B's own `users/B.auto.tfvars` manually. This single-operator-per-AMI design is per Pattern 5 trade-off at RESEARCH:306.
- **Migration:** Existing running devboxes (baked before this plan) keep running on their current AMI without re-baking. The new pinning + handoff take effect on the next `make packer-bake` cycle. To migrate immediately: `make packer-bake DEVBOX_USER=$(whoami) && make tg-apply DEVBOX_USER=$(whoami)`.
- **Operator pre-requisite:** `jq` must be on the operator workstation PATH. It is already required by `scripts/devbox-status.sh` (per STACK.md), so most operators already have it; Phase 4 should surface it explicitly in the operator-prerequisites section.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] Added `var.devbox_user` to `packer/variables.pkr.hcl`**
- **Found during:** Task 1 (`packer validate` failed with "Undefined -var variable")
- **Issue:** The plan's manifest-post-processor template includes `custom_data { devbox_user = var.devbox_user }`, but this worktree branched off a commit before Phase 1's secrets work landed, so `packer/variables.pkr.hcl` here does NOT declare `var.devbox_user`. The plan explicitly listed `packer/variables.pkr.hcl` in `files_modified` as "(possibly unchanged) — only modified if a new variable is needed".
- **Fix:** Declared `variable "devbox_user" { type = string; default = "" ... }` with a description explaining the manifest-custom_data use case.
- **Files modified:** `packer/variables.pkr.hcl`
- **Commit:** `7afb759`

**2. [Rule 3 — Blocking issue] Added `*.auto.tfvars` and `users/*.auto.tfvars` to `.gitignore`**
- **Found during:** Task 2 Step 1 (gitignore inspection)
- **Issue:** The plan's Step 1 said "Verify `.gitignore` from Plan 03-01 (Wave 1) preserved the `*.auto.tfvars` rule" — implying the rule existed pre-this-plan. In this worktree, `.gitignore` did NOT contain `*.auto.tfvars` because the worktree branched off main before Phase 2 landed the rule. Without it, the generated `users/<USER>.auto.tfvars` would be `git status`-noise on every operator workstation.
- **Fix:** Added both `*.auto.tfvars` and `users/*.auto.tfvars` (the latter is defensive — the bare rule covers it, but the explicit form is more discoverable).
- **Files modified:** `.gitignore`
- **Commit:** `8112796`

**3. [Rule 2 — Auto-add missing critical functionality] Pass `-var devbox_user=$(DEVBOX_USER)` in `make packer-bake`**
- **Found during:** Task 2 Step 3c (Makefile target authoring)
- **Issue:** The plan's Example E body of the `packer-bake` target ran `cd packer && packer build .` with no `-var` flags. With the new `var.devbox_user` declaration (deviation 1), the manifest's `custom_data.devbox_user` would silently be the empty string unless the Makefile passes it through.
- **Fix:** Changed the build invocation to `cd packer && DEVBOX_USER=$(DEVBOX_USER) packer build -var "devbox_user=$(DEVBOX_USER)" .` so the manifest carries operator provenance correctly.
- **Files modified:** `Makefile`
- **Commit:** `8112796`

### Auth Gates

**1. AWS credentials unavailable (could not resolve SSM parameter version)**
- **Where:** Task 1 Step 1
- **What was needed:** Valid AWS credentials with `ssm:GetParameterHistory` permission against the `/aws/service/...` namespace.
- **What happened:** `aws sts get-caller-identity` returned `InvalidClientTokenId`. Per the orchestrator constraint, the executor proceeded with the unversioned SSM parameter name and documented the pin requirement in this SUMMARY (see "Resolved SSM Parameter Version" above) and in an inline comment in `packer/devimage.pkr.hcl` (lines 19-31).
- **Resolution:** The operator must run `aws ssm get-parameter-history` and append the `:NN` suffix as a follow-up commit before the next real `packer build`. This is tracked as the single open follow-up of this plan and is captured by the Phase 4 CI grep gate `grep -E '/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64:[0-9]+'`.

## Threat Flags

None — no new security surface introduced. The plan's `<threat_model>` STRIDE register (T-03-08 through T-03-15) covers the trust boundaries this plan operates on; all mitigations are wired (manifest pre-delete, `sort_by(.build_time)` defense, generated-file comment header, gitignored handoff files, custom_data audit trail).

## Verification Evidence

Final smoke results (output trimmed for brevity):

```
$ grep -rE 'most_recent[[:space:]]*=[[:space:]]*true' packer/    # exit=1, no matches
$ grep -E '^[[:space:]]*ami_id[[:space:]]*=[[:space:]]*"ami-' terragrunt.hcl   # exit=1, no matches
$ grep -r 'RESOLVED-VERSION' packer/                              # exit=1, no matches
$ cd packer && packer validate .                                  # The configuration is valid. (exit=0)
$ make -n packer-bake DEVBOX_USER=test >/dev/null                 # exit=0
$ terragrunt hclfmt --check terragrunt.hcl                        # exit=0
$ grep 'packer-manifest.json' .gitignore                          # packer/packer-manifest.json (exit=0)
$ make help | grep packer-bake
  packer-bake  Build AMI + write users/$(DEVBOX_USER).auto.tfvars (handoff for tg-apply)
```

## Self-Check: PASSED

- `packer/devimage.pkr.hcl` modified, contains `amazon-parameterstore`, contains `post-processor "manifest"`, NO `most_recent = true`: verified
- `packer/variables.pkr.hcl` modified, declares `var.devbox_user`: verified
- `Makefile` modified, contains `packer-bake:` target on line 53, `.PHONY` includes `packer-bake`, `clean` no longer removes `terraform/.terraform.lock.hcl`: verified
- `terragrunt.hcl` modified, no `ami_id = "ami-..."` literal in `inputs`: verified
- `.gitignore` modified, contains `packer/packer-manifest.json` and `users/*.auto.tfvars`: verified
- Commits `7afb759` and `8112796` exist on branch `worktree-agent-a3ebac196f130d90b`: verified

## Verdict

**COMPLETE** (with one documented follow-up: append `:NN` parameter-version suffix to the SSM parameter `name` in `packer/devimage.pkr.hcl:33` once AWS credentials are available — this is required for REP-04's full reproducibility guarantee and is captured by the Phase 4 grep gate already specified above. All other plan deliverables met; both tasks committed atomically; all smoke gates pass.)
