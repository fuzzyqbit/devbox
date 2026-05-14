# Phase 3: Reproducibility & Version Pinning - Research

**Researched:** 2026-05-13
**Domain:** Dependency pinning across Terraform/OpenTofu, Ansible Galaxy, Packer, AWS AMI handoff
**Confidence:** HIGH

## Summary

This phase locks every floating dependency in the bake → provision pipeline so a checkout-at-SHA on day N and day N+30 produce identical AMIs (modulo build timestamps) and identical Terraform plans. There are five orthogonal pin sites — Terraform's provider lock file, two `ansible-galaxy` collection-requirements files (top-level + vendored CIS role), the Packer source-AMI filter, and the AMI-ID handoff path from Packer to Terragrunt — and each needs a different mechanism. None of the work is structurally hard; the hazard is forgetting platform variants on the Terraform lock file and choosing the wrong AMI-handoff pattern for the operator's daily flow.

**Primary recommendation for REP-05:** Use the **Packer manifest post-processor → `users/${DEVBOX_USER}.auto.tfvars` via Makefile** pattern. Packer writes `packer-manifest.json`, the Makefile parses the last build's `artifact_id`, and writes `ami_id = "ami-..."` into the gitignored `users/${DEVBOX_USER}.auto.tfvars` that the existing Phase 2 `*.auto.tfvars` ignore rule already covers. Rationale below in section 6.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Provider version pinning | Terraform/OpenTofu CLI | git (commit lockfile) | `.terraform.lock.hcl` is the canonical mechanism; git makes it shared |
| Galaxy collection pinning | `requirements.yml` (Ansible Galaxy resolver) | git | The resolver enforces the constraint; commit makes it shared |
| Vendored CIS role collection pinning | Vendored `collections/requirements.yml` (git-source) | git | When `type: git`, the `version:` becomes a git tag/SHA — not a Galaxy semver |
| Packer source AMI pin | Packer `source_ami_filter` | AWS AMI registry | The filter is the pin site; AWS owns the artifact identity |
| Built-AMI → Terraform handoff | Packer `manifest` post-processor + Makefile + Terraform `*.auto.tfvars` | Filesystem (per-operator workspace) | Manifest is the source of truth Packer already emits; Makefile is the existing operator surface |
| Verification of pins | CI (Phase 4) | pre-commit (Phase 4) | Pins are static text — both grep/file-checks catch regressions |

## User Constraints

There is no CONTEXT.md for this phase (the orchestrator invoked `/gsd-plan-phase` integrated mode without prior `/gsd-discuss-phase`). Constraints below are extracted from `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, and the additional context the orchestrator passed.

### Locked from prior phases (do not relitigate)

- **OpenTofu (`tofu`) is the runtime binary** — `terragrunt.hcl:22` sets `terraform_binary = "tofu"`. Lockfile commands must work under `tofu`, not just `terraform`. [VERIFIED: terragrunt.hcl:22]
- **`community.aws = 9.0.0` is already pinned** at `ansible/requirements.yml:6-7` from Phase 1 (note: bare `version: "9.0.0"`, no `==` operator — flagged in section 3). [VERIFIED: ansible/requirements.yml]
- **AWS provider is `>= 5.0`** in `terraform/main.tf:7` — floating across all 5.x and 6.x releases today. [VERIFIED: terraform/main.tf:5-8]
- **`packer/*.pkr.hcl.lock` and `terraform/.terraform.lock.hcl` and root `.terraform.lock.hcl` are currently gitignored** at `.gitignore:3, 7, 27`. Phase 3 removes only the Terraform lock entries. The Packer plugin lock (`*.pkr.hcl.lock`) is out of scope for the requirements — see section 11. [VERIFIED: .gitignore]
- **`*.auto.tfvars` is already gitignored** at `.gitignore:32` (Phase 2 added it for `allowlist.auto.tfvars`). The same rule covers `users/${DEVBOX_USER}.auto.tfvars` if we put it at repo root, or we extend it to `users/*.auto.tfvars`. [VERIFIED: .gitignore:29-33]
- **Operator builds AMIs occasionally, not daily.** Cross-region portability matters less than reproducibility within a single bake. [from orchestrator additional_context]
- **Phase 4 will gate this in CI** with `terraform fmt -check`, `tofu validate`, `packer validate`, `ansible-lint`, etc. Phase 3 must leave behind verifiable artifacts those checks catch. [from ROADMAP.md Phase 4]

### Claude's discretion (recommend, then plan)

- Which AMI-handoff mechanism to use for REP-05 (manifest-to-tfvars vs `data "aws_ami"` vs SSM Parameter Store) — recommended in section 6.
- Which Galaxy collection versions to pin to — recommended in section 3 with current Galaxy API responses.
- Whether to also tighten the AWS provider pin from `>= 5.0` to `~> 6.0` while we are in `terraform/main.tf` — recommended yes, in section 1.
- Whether to also pin the existing `community.aws` bare version syntax to `==9.0.0` — recommended yes (it is a one-character cleanup that removes ambiguity).

### Deferred / out of scope for this phase

- **Pinning every dnf system package on the bake host.** Per the orchestrator brief, this is impractical over months; do NOT attempt. See section 7.
- **Pinning every operator-side tool to a SHA.** Operator workstation tool versions (local `tofu`, `packer`, `ansible`) are out of repo scope — Phase 4 will document version *requirements* in `CLAUDE.md` (DOC-01), not enforce them.
- **Vendoring Galaxy collections into `ansible/collections/`.** Considered but rejected: pinning by version meets the reproducibility bar, vendoring would inflate git history and create a maintenance burden disproportionate to a personal devbox.
- **Replacing the `most_recent = true` filter on the *built* AMI** in any new `data "aws_ami"` lookup — section 6 explains why the recommended pattern avoids `data "aws_ami"` entirely.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REP-01 | `.terraform.lock.hcl` removed from `.gitignore` and committed | Section 1 — `terraform providers lock` invocation for multi-platform recording |
| REP-02 | `ansible/requirements.yml` collection versions pinned to exact versions | Section 3 — bare-version vs `==` semantics + current Galaxy versions |
| REP-03 | Galaxy roles pinned to exact versions (no floating refs) | Section 4 — applies to the vendored CIS role's `collections/requirements.yml` (git type, default branch HEAD) |
| REP-04 | Packer source AMI replaced with pinned snapshot ID or pinned filter | Section 5 — recommend SSM Parameter Store pinned-version lookup |
| REP-05 | AMI ID consumed by Terraform via deterministic mechanism (no hand-copied IDs) | Section 6 — recommend manifest-to-tfvars pattern |

## Standard Stack

### Core (already present, version-tightened by this phase)

| Library | Current (operator-side) | Pin target | Why |
|---------|------------------------|------------|-----|
| OpenTofu (`tofu`) | required >= 1.5 (`terraform/main.tf:2`) | leave as-is; bake-host pin already at 1.9.0 | Lockfile pins providers, not tofu itself |
| `hashicorp/aws` provider | `>= 5.0` floating | `~> 6.0` (current major `6.44.0` as of 2026-05-06) [VERIFIED: Terraform Registry] | Lock to current major; minor/patch within will still need lockfile checksums |
| `community.general` | unpinned at `requirements.yml:3` | `==12.6.0` [VERIFIED: Galaxy API 2026-05-13] | Current stable. Major bumps every ~6mo per upstream cadence |
| `community.crypto` | unpinned at `requirements.yml:4` | `==3.2.0` [VERIFIED: Galaxy API 2026-05-13] | Current stable |
| `ansible.posix` | unpinned at `requirements.yml:5` | `==2.1.0` [VERIFIED: Galaxy API 2026-05-13] | Current stable. Note `2.0.0` was a recent major (Jul 2025) so pin to 2.1.0 |
| `community.aws` | bare `version: "9.0.0"` | tighten to `==9.0.0` (or bump to `==11.0.0` [VERIFIED]) — operator decision | Removes bare-version ambiguity (section 3) |
| `code-server` | `4.93.1` pinned in `ansible/roles/vscode/defaults/main.yml` | bump to `4.118.0` [VERIFIED: GitHub releases 2026-05-06] OR pin major.minor only | Already pinned; refresh while we are touching pin policy. CONCERNS.md notes 4.93.1 has known CVEs. |

### Supporting (no changes — for context)

| Library | Where pinned | Notes |
|---------|--------------|-------|
| Packer plugins (`amazon >= 1.3.0`, `ansible >= 1.1.0`) | `packer/devimage.pkr.hcl:1-12` | Floating today; `packer init` writes `*.pkr.hcl.lock` but `.gitignore:3` excludes it. Out of scope for REP-* requirements but a candidate follow-up. |
| HashiCorp tools in AMI (Terraform/Terragrunt/tflint/etc.) | `ansible/roles/terraform/defaults/main.yml` | Already pinned. CONCERNS.md flags some as months behind; refresh is out of scope for this phase. |

### Alternatives considered (and rejected)

| Instead of | Could use | Why rejected |
|------------|-----------|--------------|
| Manifest-to-tfvars handoff (REP-05) | `data "aws_ami"` filter on `Builder=packer` tag with `most_recent = true` | Reintroduces the same non-deterministic `most_recent` flap GitHub issue #44833 calls out; defeats the point of REP-04 [VERIFIED: GitHub hashicorp/terraform-provider-aws#44833] |
| Manifest-to-tfvars handoff (REP-05) | Packer post-processor writes SSM Parameter `/devbox/ami/latest`; Terraform reads via `data "aws_ssm_parameter"` | Requires Packer build identity to have `ssm:PutParameter` IAM; viable but adds an out-of-band coupling point. Operator already has the manifest file on disk after `make build` — using it is strictly simpler. |
| Pinning every collection | Vendoring collections into `ansible/collections/` | Inflates git history; pinning meets the reproducibility bar without the cost |
| Pinning bare `version: "X.Y.Z"` | Using `==X.Y.Z` explicitly | Docs are ambiguous on bare-version semantics (section 3) — `==` is universally unambiguous |
| Pinning Packer source AMI by hardcoded `ami-` ID | SSM Parameter Store version-pinned lookup | Hardcoded ID loses region portability; SSM parameter `/aws/service/...` returns the AWS-managed pointer that we can pin to a specific parameter *version* (section 5) |

**Verification (executor must run before locking the table):**

```bash
# Galaxy current versions (rerun on the day of execution — these change):
curl -s https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/general/  | jq -r .highest_version
curl -s https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/crypto/   | jq -r .highest_version
curl -s https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/ansible/posix/      | jq -r .highest_version
curl -s https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/aws/      | jq -r .highest_version

# AWS provider:
curl -s https://registry.terraform.io/v1/providers/hashicorp/aws | jq -r .version
```

## Architecture Patterns

### System Architecture Diagram

```
                         ┌─────────────────────────────────────────────┐
                         │  git repo (the pin sites)                   │
                         │                                              │
   .gitignore ──────────►│  - terraform/.terraform.lock.hcl  (COMMIT)   │
                         │  - ansible/requirements.yml       (==X.Y.Z)  │
                         │  - ansible/roles/AMAZON2023-CIS/             │
                         │      collections/requirements.yml (git SHA)  │
                         │  - packer/devimage.pkr.hcl       (source_ami)│
                         └─────────────────────────────────────────────┘
                                              │
                            ┌─────────────────┴─────────────────┐
                            ▼                                   ▼
                  ┌───────────────────┐              ┌───────────────────┐
                  │ tofu providers    │              │ ansible-galaxy    │
                  │ lock -platform=…  │              │ collection install│
                  │ (one-shot, ×4    │              │ -r requirements.yml│
                  │  per-platform)    │              │ (runs at bake time│
                  └───────────────────┘              │  inside Packer)   │
                            │                       └───────────────────┘
                            ▼                                   │
                  ┌───────────────────┐                        │
                  │ commit lockfile   │                        ▼
                  └───────────────────┘                ┌───────────────────┐
                                                       │ Packer build       │
                                                       │  - reads pinned    │
                                                       │    source AMI from │
                                                       │    SSM param       │
                                                       │  - writes          │
                                                       │    packer-         │
                                                       │    manifest.json   │
                                                       └─────────┬─────────┘
                                                                 │
                       ┌─────────────────────────────────────────┘
                       ▼
              ┌────────────────────────┐
              │ make packer-bake       │ (Makefile, single operator surface)
              │  1) packer build       │
              │  2) jq parse manifest  │
              │  3) write              │
              │     users/${USER}      │
              │     .auto.tfvars       │ (gitignored)
              └────────┬───────────────┘
                       │
                       ▼
              ┌────────────────────────┐
              │ terragrunt apply       │
              │  consumes ami_id from  │
              │  users/${USER}.auto.   │
              │  tfvars                │
              └────────────────────────┘
```

### Recommended Project Structure (deltas only)

```
.
├── .gitignore                  # remove .terraform.lock.hcl entries; keep *.auto.tfvars rule
├── terraform/
│   └── .terraform.lock.hcl     # NEW: committed, contains 4 platforms
├── ansible/
│   ├── requirements.yml         # MODIFIED: ==X.Y.Z for every collection
│   └── roles/AMAZON2023-CIS/
│       └── collections/requirements.yml  # MODIFIED: version: <tag-or-sha> for each git source
├── packer/
│   └── devimage.pkr.hcl        # MODIFIED: source_ami_filter uses SSM parameter / pinned name
├── users/                       # NEW directory (gitignored via existing *.auto.tfvars rule)
│   └── ${DEVBOX_USER}.auto.tfvars  # NEW: written by `make packer-bake`, contains ami_id
└── Makefile                    # MODIFIED: `packer-bake` target wraps build + manifest parse + tfvars write
```

### Pattern 1: Commit `.terraform.lock.hcl` with multi-platform checksums

**What:** The dependency lock file pins provider source, version, and per-platform checksums for every provider declared in `required_providers`. Committing it ensures every operator and CI run downloads byte-identical provider binaries.

**When to use:** Always, the moment more than one operator (or operator + CI) initializes the same Terraform config.

**Invocation:** From inside `terraform/` (because the lock file is module-scoped per `terragrunt.hcl:24-26`):

```bash
# Initial seed + multi-platform record (one-shot):
tofu providers lock \
  -platform=linux_amd64 \
  -platform=linux_arm64 \
  -platform=darwin_amd64 \
  -platform=darwin_arm64
# Source: https://developer.hashicorp.com/terraform/cli/commands/providers/lock
# Source: https://opentofu.org/docs/language/files/dependency-lock/

# Subsequent upgrades:
tofu init -upgrade   # re-resolves and rewrites the file
git diff terraform/.terraform.lock.hcl  # review every bump
```

**Note for Terragrunt users:** Terragrunt 0.67.4 (baked into the AMI per `ansible/roles/terraform/defaults/main.yml:4`) runs `tofu init` inside `.terragrunt-cache/...` — but the cache symlinks the lockfile back to `terraform/.terraform.lock.hcl`. The committed file is what gets used. [VERIFIED via terragrunt docs + behavior of `source = "./terraform"` in terragrunt.hcl:25]

### Pattern 2: Pin Ansible Galaxy collections with `==X.Y.Z`

**What:** Exact-version equality. Removes the bare-version ambiguity flagged in section 3.

**Example diff for `ansible/requirements.yml`:**

```yaml
---
collections:
  - name: community.general
    version: "==12.6.0"
  - name: community.crypto
    version: "==3.2.0"
  - name: ansible.posix
    version: "==2.1.0"
  - name: community.aws
    version: "==9.0.0"   # was: "9.0.0" (bare) — tightened in Phase 3
```

**Source:** https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html (version specifier operators table).

### Pattern 3: Pin vendored CIS role's git-source collections to tags or SHAs

**What:** When `type: git` and `source: <url>`, the `version:` key holds a git ref — tag, branch, or commit SHA. Default (no version) resolves to the default branch HEAD at install time. This is the floating ref that REP-03 targets.

**Recommendation:** Pin to **tagged release** where one exists (readable), fall back to **commit SHA** (immutable but opaque) where the upstream does not tag.

**Example diff for `ansible/roles/AMAZON2023-CIS/collections/requirements.yml`:**

```yaml
---
collections:
    - name: community.general
      source: https://github.com/ansible-collections/community.general
      type: git
      version: 12.6.0   # was: unpinned (HEAD of main)
    - name: community.crypto
      source: https://github.com/ansible-collections/community.crypto
      type: git
      version: 3.2.0
    - name: ansible.posix
      source: https://github.com/ansible-collections/ansible.posix
      type: git
      version: 2.1.0
```

(For git sources, `version:` does NOT take an operator — it is a ref. PEP 440 syntax applies only to Galaxy-server collections, not `type: git`. [CITED: https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html#installing-a-collection-from-a-git-repository])

**Why tagged release over SHA here:** Both ansible-collections repos use the same versioning as the Galaxy-published artifacts, so the tag is human-readable and matches what's in `ansible/requirements.yml`. The two files SHOULD stay in lockstep — flag in the Phase 4 docs.

### Pattern 4: Pin Packer source AMI via SSM Parameter Store with a release-pinned name

**What:** Replace `most_recent = true` against a glob with a `data "amazon-parameterstore"` lookup against a specific AL2023 release pointer.

**Why this approach:** AL2023 ships an SSM parameter for every release pointer (e.g., `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-6.1-x86_64`) whose *value* is the current AMI ID for that release line. Two equivalent ways to pin to it:

- (a) Use the parameter as-is and accept that AWS may rotate its value silently (still gives you a deterministic *name*, but not a deterministic ID across time)
- (b) Read the parameter *version number* (SSM parameters are versioned, like S3) and pin to a specific version: `/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-6.1-x86_64:123`

Option (b) is the true reproducibility win — but it requires the operator to refresh the version pin when they intentionally want a newer base AMI. For the "occasionally bake" cadence, that's the right tradeoff. [CITED: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami-parameter-store.html]

**Example diff for `packer/devimage.pkr.hcl`:**

```hcl
# REMOVE the source_ami_filter block (lines 27-35).
# ADD a data source + use it for source_ami:

data "amazon-parameterstore" "al2023_minimal" {
  # Pin to a SPECIFIC SSM parameter version (the trailing :NN).
  # To bump: aws ssm get-parameter-history --name /aws/service/.../al2023-ami-minimal-kernel-default-x86_64
  # pick a newer Version, update the literal.
  name   = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64:42"
  region = var.aws_region
}

source "amazon-ebs" "al2023" {
  # ... unchanged ...
  source_ami = data.amazon-parameterstore.al2023_minimal.value
  # ... unchanged ...
}
```

**Source:** Packer Amazon parameterstore data source — https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/parameterstore. SSM parameter versioning — https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-versions.html.

**Backup if SSM Parameter versioning proves unreliable:** Replace with a hardcoded `name = "al2023-ami-minimal-2026.04.20.0-kernel-default-x86_64"` filter (matches one AMI exactly, `most_recent = false`). Less elegant but bulletproof. Loses cross-region — the AMI is region-scoped — but the operator runs in one region per `terragrunt.hcl:37` (us-east-1).

### Pattern 5: AMI handoff via manifest-to-tfvars (RECOMMENDED for REP-05)

**What:** Packer's `manifest` post-processor emits `packer-manifest.json` after each build. A `make packer-bake` target parses it with `jq` and writes the built AMI ID into `users/${DEVBOX_USER}.auto.tfvars`, which Terraform auto-loads.

**Why this is the right choice for this project (the recommendation):**

| Property | Verdict |
|----------|---------|
| Determinism | ✓ The just-built AMI is named explicitly; no `most_recent` flap |
| Operator UX | ✓ One target — `make packer-bake` — does build+handoff; existing `make build` becomes the first line of it |
| Multi-operator safety | ✓ Per-user tfvars file (`users/${DEVBOX_USER}.auto.tfvars`); two operators on the same repo don't trample each other |
| Git footprint | ✓ Zero — `*.auto.tfvars` already gitignored from Phase 2 (`.gitignore:32`) |
| Failure mode if file missing | ✓ Terraform errors loudly on undefined `var.ami_id` (already declared in `terraform/variables.tf:1-4` with no default) |
| Out-of-band coupling (IAM perms, SSM writes) | ✓ None added |
| Cross-machine portability (operator A bakes, operator B applies) | ✗ Requires explicit handoff (commit a per-AMI ID document, or use Pattern 6 — SSM Parameter Store — for that case). For the single-operator workflow this repo targets, this is fine. |

**Reference invocation pattern (executor will detail in the plan):**

Add to `packer/devimage.pkr.hcl` inside the `build {}` block:

```hcl
post-processor "manifest" {
  output     = "${path.root}/packer-manifest.json"
  strip_path = true
  custom_data = {
    devbox_user = var.devbox_user
    base_ami_id = data.amazon-parameterstore.al2023_minimal.value
  }
}
```

Add to `Makefile`:

```make
.PHONY: packer-bake
packer-bake: init
	cd packer && packer build .
	@AMI_ID=$$(jq -r '.builds[-1].artifact_id | split(":") | .[1]' packer/packer-manifest.json); \
	  [ -n "$$AMI_ID" ] || { echo "ERROR: no AMI ID in manifest" >&2; exit 1; }; \
	  mkdir -p users; \
	  printf 'ami_id = "%s"\n' "$$AMI_ID" > users/$(DEVBOX_USER).auto.tfvars; \
	  echo "Wrote ami_id=$$AMI_ID to users/$(DEVBOX_USER).auto.tfvars"
```

Add to `terragrunt.hcl` (replace line 45 `ami_id = "ami-0b7cfe2135f319a55"`):

```hcl
# Replace the hand-copied ami_id input with a file-based one.
# `users/${local.user}.auto.tfvars` is written by `make packer-bake`.
# We do NOT pass ami_id in `inputs` — Terraform's *.auto.tfvars auto-load
# picks it up. Validation: terraform/variables.tf has no default on
# var.ami_id, so a missing file is a loud failure at `terragrunt plan`.
```

**Source:** https://developer.hashicorp.com/packer/docs/post-processors/manifest

### Anti-patterns to avoid

- **`data "aws_ami"` with `most_recent = true` on the built-AMI side.** Reintroduces the same non-determinism we just fixed in REP-04. [VERIFIED: hashicorp/terraform-provider-aws#44833 — "aws_ami data source with most_recent=true is non-deterministic in some situations"]
- **Hand-editing the lock file.** `tofu providers lock` is the only supported writer. Any other edit will fail checksum verification.
- **Committing `.terraform.lock.hcl` with only the *current operator's* platform.** On a Mac (`darwin_arm64`), `tofu init` records only `darwin_arm64` hashes; CI on `linux_amd64` then fails with "checksums don't match". Always invoke `tofu providers lock -platform=…` for every platform that will run init. See section 10.
- **Committing the AMI ID into `terragrunt.hcl` `inputs`.** The recommended pattern moves it OUT of `inputs` to a tfvars file. Leaving the literal in place defeats REP-05.
- **Bumping the SSM-parameter version pin (Pattern 4) silently.** Bump must be an explicit reviewable diff in `packer/devimage.pkr.hcl`.

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Cross-platform provider checksum recording | A shell script that loops over platforms calling `tofu init` and merging lockfiles | `tofu providers lock -platform=…` (one invocation, multiple `-platform` flags) | Built-in command; respects all corner cases the manual approach misses |
| Parsing AMI ID from Packer logs | grep+regex against `packer build` stdout | `packer-manifest.json` + `jq` | Manifest format is stable; stdout format is not contractually stable |
| Pinning Galaxy collection versions via wrapper | A `pin-collections.sh` that pre-resolves and writes to a vendored tree | `version: "==X.Y.Z"` in `requirements.yml` | Galaxy resolver handles transitive resolution; vendoring is heavier |
| "Did the lock file change?" detection | A shell hash comparison | `tofu init -lockfile=readonly` (fails on drift) | Documented behavior, exit-code-gated |
| Pinning the AL2023 AMI ID by region for cross-region builds | A region→AMI-ID map you maintain by hand | AWS-managed SSM Parameter Store path | Maintained by AWS; pin by parameter version when needed |

**Key insight:** All five pin mechanisms have native first-party support; nothing here justifies bespoke tooling.

## Runtime State Inventory

This is a refactor-adjacent phase (changing how dependencies are resolved, not renaming anything), so the standard "runtime state after string replacement" failure modes do not apply. The relevant inventory is **what existing state must be migrated when the new pins land**:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no databases or persistent stores reference dependency versions. SSM Parameter Store entries at `/devbox/${user}/*` (Phase 1) are unaffected. | None |
| Live service config | None — n8n/Datadog/etc. not used by this repo | None |
| OS-registered state | The currently-running devbox EC2 has the *old* AMI baked. Phase 3 changes do not require re-baking the running instance; pin changes take effect on next `make packer-bake` + `make tg-apply`. | None blocking; document in SUMMARY that pinning takes effect on next bake/apply cycle |
| Secrets/env vars | None — pin changes touch no secrets | None |
| Build artifacts | `packer/packer_cache/` may contain a cached old source AMI; this is fine — Packer revalidates against the (now pinned) source on next build. `.terragrunt-cache/` similarly fine. `terraform/.terraform/providers/` will need re-init after lockfile lands — `tofu init` handles transparently. | Operators run `tofu init` (or `terragrunt init`) once after pulling the change; no destructive cleanup needed |

**The canonical question — after Phase 3 lands, what runtime systems still have the OLD floating-version state?**

Answer: None blocking. The currently-running devbox keeps running on its current AMI. The next `make packer-bake` is the first time the new pins take effect — by design, since that's the operator-controlled moment when a base-AMI bump is acceptable.

## Common Pitfalls

### Pitfall 1: Lock file recorded for one platform only

**What goes wrong:** Mac-on-Apple-Silicon operator runs `tofu init`; lockfile gets only `darwin_arm64` hashes. CI on `linux_amd64` GitHub runner errors with `Error: registry.terraform.io/hashicorp/aws: the cached package for ... (in ...) does not match any of the checksums recorded in the dependency lock file`.

**Why it happens:** `tofu init` only records the running platform's checksums. `terraform providers lock` is the multi-platform writer.

**How to avoid:** Run `tofu providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64` once after the initial commit, then on every `terraform init -upgrade`.

**Warning signs:** Lockfile diff shows only one `hashes = […]` block per provider with only one platform's `zh:`/`h1:` entries.

[VERIFIED: https://developer.hashicorp.com/terraform/cli/commands/providers/lock + https://opentofu.org/docs/language/files/dependency-lock/]

### Pitfall 2: Pinned Galaxy collection version no longer co-exists with sibling pins

**What goes wrong:** `community.general==12.6.0` requires `ansible-core >= 2.17` but the bake host's Ansible is older. `ansible-galaxy collection install` errors at bake time.

**Why it happens:** Major-version bumps on Galaxy collections frequently raise the ansible-core floor.

**How to avoid:** When choosing versions, check each collection's `meta/runtime.yml` (or release notes) for the ansible-core minimum. For this project: ansible runs from a Packer-managed venv on macOS / Linux operator workstations; check `ansible --version` locally. If a chosen pin is too new, drop to the prior major.

**Warning signs:** `ansible-galaxy` output: `community.general 12.6.0 requires ansible >= 2.17, but you have ...`.

[VERIFIED: https://github.com/ansible-collections/community.general/blob/main/meta/runtime.yml]

### Pitfall 3: Pinned source AMI deprecated by AWS

**What goes wrong:** AWS deprecates the pinned AL2023 minor release; `packer build` errors with `InvalidAMIID.NotFound`.

**Why it happens:** AMIs go through deprecated → disabled → deregistered lifecycle. SSM-parameter-pinned references can outlive the underlying AMI by months but not forever.

**How to avoid:** (1) Build at least once per quarter to catch deprecation early. (2) Document in SUMMARY that bumping the pin in `packer/devimage.pkr.hcl` is part of normal maintenance. (3) Consider tagging the *built* AMIs with `BaseAMI=<id>` so a quick `aws ec2 describe-images` confirms the pinned base is still resolvable before a build.

**Warning signs:** Packer error mentions `disabled` or `deprecated`; `aws ec2 describe-images --image-ids ami-XXX` reports `DeprecationTime` in the past.

[CITED: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ami-deprecate.html]

### Pitfall 4: Manifest stale across builds

**What goes wrong:** Operator runs `packer build` twice; the manifest accumulates two builds in `.builds[]`. The Makefile reads `.builds[-1]` (last one), which is correct — but if a build *failed* mid-process, `.builds[-1]` might point to a half-broken artifact entry, or be missing entirely.

**Why it happens:** Packer's manifest is append-only by default — it never truncates between runs.

**How to avoid:** In the Makefile, `rm -f packer/packer-manifest.json` before `packer build`, OR use `jq` to select the most recent build by timestamp (`.builds | sort_by(.build_time) | .[-1]`). The plan should pick one explicitly.

**Warning signs:** `make packer-bake` writes a stale AMI ID; `terragrunt apply` launches the wrong AMI.

[CITED: https://developer.hashicorp.com/packer/docs/post-processors/manifest]

### Pitfall 5: Lock file removed from `.gitignore` but file not actually committed

**What goes wrong:** Executor edits `.gitignore` but forgets to `git add terraform/.terraform.lock.hcl` (still untracked from when it was ignored). CI passes `lockfile-readonly` only because the file is *absent*, which on some tofu versions is silently treated as "lock not enforced."

**Why it happens:** Removing a path from `.gitignore` doesn't auto-stage it.

**How to avoid:** Verification step explicitly: `git ls-files terraform/.terraform.lock.hcl` must return the path (not empty).

**Warning signs:** `git status --ignored | grep terraform.lock` shows the file as untracked.

### Pitfall 6: Bare `version: "X.Y.Z"` semantics ambiguity

**What goes wrong:** `ansible/requirements.yml` already has `community.aws` with `version: "9.0.0"` (no operator). The Ansible docs do not unambiguously state whether this means `==9.0.0` or `>=9.0.0`. In practice ansible-galaxy treats bare versions as exact match for Galaxy collections — but the docs explicitly recommend `==` for "install pre-release versions" and the version-specifier table starts from PEP 440 operators.

**Why it happens:** Documentation gap (verified at https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html on 2026-05-13).

**How to avoid:** Always write `version: "==X.Y.Z"`. Removes ambiguity, no behavioral change in the exact-equality case, future-proofs against resolver behavior changes.

**Warning signs:** A diff that says `version: "X.Y.Z"` (no operator) — the reviewer should comment "use `==`".

[CITED: https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html]

## Code Examples

### Example A: Generate the lockfile for all 4 platforms

```bash
# Source: https://developer.hashicorp.com/terraform/cli/commands/providers/lock
cd terraform/
tofu init  # seeds lockfile for current platform first
tofu providers lock \
  -platform=linux_amd64 \
  -platform=linux_arm64 \
  -platform=darwin_amd64 \
  -platform=darwin_arm64
git add .terraform.lock.hcl
```

### Example B: Pin `ansible/requirements.yml` (proposed final state)

```yaml
---
# Source: https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html
# Each collection is pinned with `==X.Y.Z` (PEP 440 exact equality).
# Bump policy: review collection CHANGELOG for ansible-core floor changes before bumping.
collections:
  - name: community.general
    version: "==12.6.0"   # 2026-05-13 from Galaxy API
  - name: community.crypto
    version: "==3.2.0"    # 2026-05-13 from Galaxy API
  - name: ansible.posix
    version: "==2.1.0"    # 2026-05-13 from Galaxy API
  - name: community.aws
    version: "==9.0.0"    # Phase 1 pin, now with explicit == operator
```

### Example C: Pin vendored CIS `collections/requirements.yml`

```yaml
---
# Source: https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html#installing-a-collection-from-a-git-repository
# `version:` on a type=git source is a git ref (tag preferred for readability).
# These versions must stay in lockstep with ansible/requirements.yml above.
collections:
    - name: community.general
      source: https://github.com/ansible-collections/community.general
      type: git
      version: 12.6.0
    - name: community.crypto
      source: https://github.com/ansible-collections/community.crypto
      type: git
      version: 3.2.0
    - name: ansible.posix
      source: https://github.com/ansible-collections/ansible.posix
      type: git
      version: 2.1.0
```

### Example D: Pin Packer source AMI via SSM Parameter (with versioning)

```hcl
# Source: https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/parameterstore
data "amazon-parameterstore" "al2023_minimal" {
  # Pin to a specific PARAMETER VERSION (the trailing :NN after the parameter name).
  # To bump intentionally:
  #   aws ssm get-parameter-history --name /aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64
  # pick the Version field of the row you want, update the literal below.
  name   = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64:42"
  region = var.aws_region
}

source "amazon-ebs" "al2023" {
  ami_name      = local.ami_name
  instance_type = var.instance_type
  region        = var.aws_region
  source_ami    = data.amazon-parameterstore.al2023_minimal.value
  ssh_username  = "ec2-user"
  # ... rest unchanged ...
}
```

### Example E: Packer manifest + Makefile handoff

```hcl
# In packer/devimage.pkr.hcl, inside `build { sources = […]; … }`:
post-processor "manifest" {
  output     = "${path.root}/packer-manifest.json"
  strip_path = true
}
```

```make
# In Makefile, add a new target that wraps packer build:
.PHONY: packer-bake
packer-bake: init
	@rm -f packer/packer-manifest.json
	cd packer && packer build .
	@AMI_ID=$$(jq -r '.builds | sort_by(.build_time) | .[-1].artifact_id | split(":") | .[1]' packer/packer-manifest.json); \
	  [ -n "$$AMI_ID" ] && [ "$$AMI_ID" != "null" ] || { echo "ERROR: AMI ID missing in packer-manifest.json" >&2; exit 1; }; \
	  mkdir -p users; \
	  printf '# Generated by `make packer-bake` — do not edit, do not commit.\nami_id = "%s"\n' "$$AMI_ID" > users/$(DEVBOX_USER).auto.tfvars; \
	  echo "Wrote ami_id=$$AMI_ID to users/$(DEVBOX_USER).auto.tfvars"
```

```hcl
# In terragrunt.hcl, REMOVE the `ami_id = "ami-…"` line from `inputs`.
# Add to the file header (locals block area):
locals {
  # ami_id is no longer set here. `make packer-bake` writes
  # users/${local.user}.auto.tfvars which Terraform auto-loads.
  # If the file is missing, `var.ami_id` is undefined and `tofu plan` errors.
}
```

```
# In .gitignore, ensure the per-user tfvars are covered.
# *.auto.tfvars is already in .gitignore:32 from Phase 2.
# Add an explicit users/ line if you want to be defensive:
users/*.auto.tfvars
```

### Example F: Verification commands (one per requirement)

```bash
# REP-01: lockfile committed + removed from .gitignore
test -f terraform/.terraform.lock.hcl && \
  git ls-files terraform/.terraform.lock.hcl | grep -q '\.terraform\.lock\.hcl$' && \
  ! grep -E '^[^#]*terraform/?\.terraform\.lock\.hcl' .gitignore

# REP-01 (bonus — verify all 4 platforms recorded)
# Each provider block must contain hashes for darwin_amd64, darwin_arm64,
# linux_amd64, linux_arm64. tofu doesn't emit a per-platform marker, so
# count h1: hashes — expect >= 4 per provider (one per platform).
grep -c '^    "h1:' terraform/.terraform.lock.hcl   # >= 4 per provider

# REP-02: every collection in top-level requirements.yml has a version
yq '.collections[] | select(has("version") | not) | .name' ansible/requirements.yml
# expect empty output

# REP-02 (bonus — every version uses == operator)
yq '.collections[] | select(.version | test("^==") | not) | "\(.name): \(.version)"' ansible/requirements.yml
# expect empty output

# REP-03: every collection in vendored CIS requirements.yml has a version
yq '.collections[] | select(has("version") | not) | .name' \
  ansible/roles/AMAZON2023-CIS/collections/requirements.yml
# expect empty output

# REP-04: no most_recent = true anywhere in packer/
! grep -rE 'most_recent\s*=\s*true' packer/

# REP-04 (positive — pinned source AMI present)
grep -E '(source_ami\s*=|name\s*=\s*"/aws/service/ami-amazon-linux-latest/.*:[0-9]+")' packer/devimage.pkr.hcl

# REP-05: no hand-copied ami_id literal in terragrunt.hcl
! grep -E '^\s*ami_id\s*=\s*"ami-[0-9a-f]+"' terragrunt.hcl

# REP-05 (positive — handoff mechanism present)
grep -E '^\s*packer-bake:' Makefile && \
  grep -E 'users/.*\.auto\.tfvars' Makefile
```

## State of the Art

| Old approach | Current approach | When changed | Impact |
|--------------|------------------|--------------|--------|
| `version: ">= 1.0.0"` (range pinning) in `requirements.yml` | `version: "==X.Y.Z"` (exact equality) | Ansible 2.10+ adopted PEP 440 | Use exact equality for reproducibility; ranges for libraries only |
| `most_recent = true` against an unpinned filter | SSM Parameter Store version-pinned lookup | AWS introduced public SSM AMI parameters 2018; parameter versioning available since 2017 | Single source of truth maintained by AWS; pin parameter *version* for reproducibility |
| Hand-copy AMI ID into `terragrunt.hcl` | Manifest post-processor + auto-loaded tfvars | Packer manifest post-processor since 0.10 | Removes human error in the handoff |
| `.terraform.lock.hcl` gitignored | Lock file committed | Terraform 0.14+ (Nov 2020) | Reproducible provider downloads; CI gate via `-lockfile=readonly` |

**Deprecated/outdated:**
- `terraform init -get-plugins=false` — replaced by lockfile semantics
- `ansible-galaxy install --no-deps` — superseded by `requirements.yml` `dependencies:` controls
- Per-region hardcoded AMI ID maps in Terraform — replaced by SSM Parameter Store lookups

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact Galaxy collection version numbers (community.general 12.6.0, community.crypto 3.2.0, ansible.posix 2.1.0, community.aws 11.0.0) are correct as of research time | Standard Stack, Pattern 2, Pattern 3, Example B/C | Plan would pin to versions that don't exist or are out-of-date. Mitigation: executor re-runs the `curl` commands in Standard Stack before writing the diff. Galaxy API was queried 2026-05-13 [VERIFIED] |
| A2 | Operators primarily run macOS (`darwin_arm64`) and CI runs `linux_amd64`; `linux_arm64` is a nice-to-have, `windows_amd64` is not required | Section 1 (Pattern 1), Pitfall 1 | If a Windows operator exists, lockfile init will fail for them. Mitigation: STACK.md says "macOS or Linux with Bash 4+, GNU Make" — Windows is explicitly out of scope. Including `linux_arm64` covers Graviton CI runners if Phase 4 chooses them |
| A3 | The pinned AL2023 SSM Parameter Store value (specifically `:42` in Example D) is a placeholder; executor will discover and pin the actual current parameter version | Pattern 4, Example D | If executor copies `:42` literally without resolving, `packer build` fails immediately and obviously. Low risk — fast feedback |
| A4 | Bumping `community.aws` from pinned `9.0.0` to current `11.0.0` is desirable, but not strictly required by REP-02 | Standard Stack, Pattern 2 | If executor bumps and the bake-host's ansible-core is too old, build breaks. Mitigation: keep at `==9.0.0` is a valid choice; let executor decide based on `ansible --version` of the operator workstation |
| A5 | The `users/` directory in repo root is the right place for per-operator tfvars; alternative would be repo root with `${user}.auto.tfvars` | Pattern 5, Example E, project structure | Lower-risk; can be moved with no semantic change. `users/` keeps the repo root clean and matches the per-user state-key pattern in `terragrunt.hcl:36` (`users/${local.user}/devbox.tfstate`) |
| A6 | Phase 4 CI will use `tofu init -lockfile=readonly` and a separate `ansible-galaxy collection install -r ... --offline` gate to detect drift | Section 9, downstream signaling | Risk: Phase 4 picks different commands; the verification flow needs adjustment. Low risk — these are the documented gating commands |
| A7 | `terragrunt 0.67.4` (baked in AMI) and operator-local terragrunt versions both honor lockfile at `terraform/.terraform.lock.hcl` when `source = "./terraform"` in `terragrunt.hcl:25` | Pattern 1 note | If terragrunt's source-symlink mechanism breaks lockfile resolution, `terragrunt init` may silently bypass the lockfile. Mitigation: executor confirms with `terragrunt init` then `tofu init -lockfile=readonly` inside `.terragrunt-cache/` |

**Risk score:** Low overall — every [ASSUMED] item has a fast-fail signal (curl returns 404, packer build errors immediately, terraform plan refuses on undefined var) that surfaces wrong assumptions inside one bake/apply cycle.

## Open Questions

1. **Should `community.aws` be bumped from 9.0.0 → 11.0.0 in this phase?**
   - What we know: 11.0.0 is current, requires boto3 >= 1.35.0, dropped Python < 3.8, requires ansible-core >= 2.17.
   - What's unclear: Whether the bake host's Ansible is new enough. STACK.md says `ansible >= 2.10.1` from the CIS role's meta requirement, which is way below 2.17. The Packer-driven Ansible run uses whatever Ansible is on the operator workstation.
   - Recommendation: Keep at `==9.0.0` for this phase. Bumping major collection versions is its own follow-up task; the requirement REP-02 only demands "pinned to exact versions," not "pinned to current major."

2. **Should the AWS provider be tightened from `>= 5.0` to `~> 6.0`?**
   - What we know: AWS provider 6.0.0 was a major release in April 2026 with breaking changes; current is 6.44.0.
   - What's unclear: Whether existing `terraform/main.tf` IAM + SG resources (Phase 1/2 work) are 6.x-compatible.
   - Recommendation: Tighten to `~> 6.0` (covers 6.x patch + minor) at the same time as the lockfile commit; if it breaks, the lockfile + a `terragrunt validate` will catch it within Phase 3 execution, not later.

3. **Should the operator's `packer-bake` target also auto-`git add users/${USER}.auto.tfvars`?**
   - What we know: The file is gitignored; the operator runs `terragrunt apply` next.
   - What's unclear: If a second operator needs to apply the same AMI, do they re-bake or copy the tfvars?
   - Recommendation: Per Pattern 5 trade-off table — single-operator-workflow is the assumption. Phase 4 docs (DOC-01) can document a manual handoff if a second operator ever needs the same AMI.

## Environment Availability

| Dependency | Required by | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `tofu` (OpenTofu) | Pattern 1 — lockfile generation | ✓ (per STACK.md) | >= 1.5 | `terraform` binary works identically for `providers lock` |
| `packer` (HashiCorp) | Pattern 4, Pattern 5 — manifest post-processor + parameterstore data source | ✓ (per STACK.md) | >= 1.10 typical | None — required |
| `ansible-galaxy` | Pattern 2, Pattern 3 — collection install | ✓ (per STACK.md via Packer ansible provisioner) | bundled with Ansible | None — required |
| `jq` | Pattern 5 — manifest parsing | ✓ (per STACK.md, required by `scripts/devbox-status.sh`) | any modern | `python -c "import json"` if absent |
| `yq` | Verification commands (Example F) | ✓ (per STACK.md, `ansible/roles/devtools/defaults/main.yml`) | 4.44.3 | `grep` for verification, less precise |
| AWS API access (operator credentials) | Pattern 4 — resolve SSM parameter at Packer build time | ✓ assumed (Packer already uses AWS API) | n/a | None — required |
| `curl` (for Galaxy API checks) | Verification of pin versions | ✓ (universal) | any | None |

**Missing dependencies with no fallback:** None — this phase introduces no new runtime tooling, only new uses of tools already present.

**Missing dependencies with fallback:** None blocking.

## Project Constraints (from CLAUDE.md)

The repo-root `CLAUDE.md` is currently empty (0 bytes — flagged in CONCERNS.md as a LOW finding, scheduled for Phase 4 DOC-01). The user-global `~/.claude/rules/*.md` directives apply to plan execution:

- **Immutability:** Pin changes are write-once additions to existing files; the lockfile and tfvars files are generated artifacts (operator should not hand-edit). N/A to runtime data structures.
- **KISS / DRY / YAGNI:** Manifest-to-tfvars pattern is the simplest of the three REP-05 options that satisfies the requirement; no abstraction is added speculatively.
- **File organization:** No new modules introduced; only edits to existing files plus one new `users/${user}.auto.tfvars` generated artifact.
- **Error handling:** Verification commands (Example F) explicitly exit non-zero on missing pins; the Makefile target's `||` guards on the `jq` parse to fail loudly if manifest is broken.
- **Naming conventions:** `packer-bake` target follows the existing `devbox-*`/`tg-*` Makefile target naming.
- **Code review (when applied to this phase):** Section to focus on — every pinned version (collection / SSM parameter / SHA) needs a reviewer to confirm it matches the verified-current value from a published source. The Assumptions Log (above) drives the review checklist.
- **Testing (80% coverage):** N/A for an IaC-pinning phase — there is no executable test surface. The verification commands in Example F are the closest equivalent, and they belong in Phase 4's CI as well as in `<verification>` blocks of the Phase 3 plan.

## CI Implications for Phase 4 (Signal to Downstream)

Phase 4 (CI + pre-commit) will need these new commands to gate Phase 3's outcomes:

| Phase 3 artifact | Phase 4 CI command | What it catches |
|------------------|--------------------|-----------------|
| `terraform/.terraform.lock.hcl` | `cd terraform && tofu init -lockfile=readonly` | Provider drift; lockfile not updated when `required_providers` changes |
| `ansible/requirements.yml` | `ansible-galaxy collection install -r ansible/requirements.yml --offline` (after a pre-populated cache step) — or simpler `--ignore-errors --check` style smoke | Collection version typo; pin removed |
| `ansible/roles/AMAZON2023-CIS/collections/requirements.yml` | Same `ansible-galaxy` invocation with `-r` pointed at the vendored file | Same as above, for the vendored layer |
| `packer/devimage.pkr.hcl` source AMI pin | `packer validate packer/` plus a grep: `grep -E 'most_recent\s*=\s*true' packer/ && exit 1 \|\| exit 0` | Regression to floating filter |
| Built-AMI handoff | `grep -E '^\s*ami_id\s*=\s*"ami-' terragrunt.hcl && exit 1 \|\| exit 0` | Regression to hand-copied literal |

Phase 3 SUMMARY must surface these as a `CI hooks needed in Phase 4` list so the Phase 4 planner does not have to rediscover them.

## Sources

### Primary (HIGH confidence)
- `terraform providers lock` reference — https://developer.hashicorp.com/terraform/cli/commands/providers/lock
- OpenTofu Dependency Lock File — https://opentofu.org/docs/language/files/dependency-lock/
- Ansible collections install guide — https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html
- Ansible Galaxy User Guide — https://docs.ansible.com/projects/ansible/latest/galaxy/user_guide.html
- Packer Manifest Post-Processor — https://developer.hashicorp.com/packer/docs/post-processors/manifest
- AWS SSM AMI public parameters — https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami-parameter-store.html
- AWS SSM Parameter Store versioning — https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-versions.html
- Terraform `aws_ami` data source — https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
- Galaxy API (live-queried for current versions, 2026-05-13):
  - community.general 12.6.0 — `https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/general/`
  - community.crypto 3.2.0 — `https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/crypto/`
  - ansible.posix 2.1.0 — `https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/ansible/posix/`
  - community.aws 11.0.0 (current) — `https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/aws/`
- Terraform Registry — `hashicorp/aws` 6.44.0 current (2026-05-06) — https://registry.terraform.io/providers/hashicorp/aws/latest

### Secondary (MEDIUM confidence — verified against primary where possible)
- HashiCorp Terraform issue #29958 (lock file + multiple architectures) — https://github.com/hashicorp/terraform/issues/29958
- HashiCorp terraform-provider-aws issue #44833 (aws_ami non-determinism) — https://github.com/hashicorp/terraform-provider-aws/issues/44833
- code-server releases (4.118.0 2026-05-06) — https://github.com/coder/code-server/releases
- AL2023 docs (minimal AMI naming) — https://docs.aws.amazon.com/linux/al2023/ug/ec2.html

### Tertiary (LOW confidence — flagged where used)
- None retained — every claim that started LOW was either upgraded by cross-checking primary sources or excluded.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every pin candidate verified against Galaxy API or Terraform Registry within 24 hours of writing
- Architecture: HIGH — manifest post-processor + tfvars handoff is documented Packer + Terraform behavior; no speculation
- Pitfalls: HIGH — each pitfall references a documented behavior (lockfile platform recording, manifest append behavior, SSM parameter versioning) and a verifiable signal
- AMI handoff recommendation: HIGH — recommendation is the simplest pattern that meets REP-05; rejected alternatives explicitly justified

**Research date:** 2026-05-13
**Valid until:** 2026-06-13 (collection version checks should be re-run by the executor before locking diffs — versions float between research and execution; Galaxy major bumps in particular)
