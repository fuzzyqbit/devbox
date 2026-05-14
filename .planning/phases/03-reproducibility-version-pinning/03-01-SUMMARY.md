---
phase: 03-reproducibility-version-pinning
plan: 01
subsystem: iac-pinning
tags: [reproducibility, version-pinning, terraform, opentofu, ansible-galaxy, lockfile]
requirements_closed: [REP-01, REP-02, REP-03]
dependency_graph:
  requires:
    - terraform/main.tf required_providers block (Phase 1 baseline)
    - ansible/requirements.yml (Phase 1 added community.aws)
    - terragrunt.hcl:22 terraform_binary = "tofu" (Phase 1 baseline)
  provides:
    - terraform/.terraform.lock.hcl — committed lockfile (REP-01)
    - ansible/requirements.yml — exact-pinned collections (REP-02)
    - ansible/roles/AMAZON2023-CIS/collections/requirements.yml — tagged git refs (REP-03 coverage by absence-of-roles)
    - terraform/main.tf required_providers pinned to `~> 6.0` (locks AWS provider major)
  affects:
    - terragrunt apply — next `terragrunt init` re-resolves against `~> 6.0`; lockfile hashes enforced
    - Phase 4 CI gates — `tofu init -lockfile=readonly` and `ansible-galaxy collection install -r ... --offline`
    - Phase 03-02 (parallel-safe wave 1) — files disjoint, no cross-impact
tech_stack:
  added: []  # No new tools; only new uses of existing tooling
  patterns:
    - OpenTofu multi-platform `tofu providers lock` (RESEARCH Pattern 1)
    - PEP 440 `==X.Y.Z` exact-equality for Galaxy collections (RESEARCH Pattern 2)
    - Tagged git refs for `type: git` collection sources (RESEARCH Pattern 3, distinct from PEP 440)
key_files:
  created:
    - terraform/.terraform.lock.hcl
  modified:
    - .gitignore
    - terraform/main.tf
    - ansible/requirements.yml
    - ansible/roles/AMAZON2023-CIS/collections/requirements.yml
decisions:
  - Held community.aws at ==9.0.0 (did not bump to 11.0.0); avoids raising the ansible-core floor to 2.17
  - Tightened hashicorp/aws from ">= 5.0" to "~> 6.0" (locks to the 6.x major; tofu init resolved to v6.45.0)
  - Locked 4 platforms: darwin_arm64, darwin_amd64, linux_amd64, linux_arm64 (Windows out of scope)
  - Vendored CIS collections pinned to bare git tag refs (no `==` operator — tags are git refs, not PEP 440 specifiers)
metrics:
  duration_minutes: ~12
  completed_date: 2026-05-14
  task_count: 2
  file_count: 5
  commit_count: 2
---

# Phase 3 Plan 1: Pin Terraform Provider + Ansible Galaxy Collections + Commit OpenTofu Lockfile Summary

OpenTofu lockfile committed across 4 platforms with `hashicorp/aws v6.45.0` pinned to `~> 6.0`; every Galaxy collection in both `ansible/requirements.yml` (PEP 440 `==X.Y.Z`) and the vendored CIS role's `collections/requirements.yml` (git tag refs) is now exact-pinned. Closes REP-01, REP-02, REP-03.

## Files Modified

| File | Change | Purpose |
|------|--------|---------|
| `.gitignore` | Removed line 7 (`terraform/.terraform.lock.hcl`) and line 26-27 (comment + `.terraform.lock.hcl` root entry) | Lockfile must be tracked for REP-01 |
| `terraform/main.tf` | `version = ">= 5.0"` → `version = "~> 6.0"` (lines 4-9 required_providers block) | Locks AWS provider to the current 6.x major (research:651-654) |
| `ansible/requirements.yml` | Every collection now has `version: "==X.Y.Z"`; entire file rewritten with policy comment | REP-02 — exact-equality pinning |
| `ansible/roles/AMAZON2023-CIS/collections/requirements.yml` | Every git-source collection now has `version: X.Y.Z` (tag ref); file rewritten with policy comment | REP-03 coverage — pinning the vendored collection refs |
| `terraform/.terraform.lock.hcl` | **NEW** (28 lines) | OpenTofu provider checksum lockfile, 4 platforms |

Files preserved unchanged (must_have invariants):
- `.gitignore` lines that keep `*.pkr.hcl.lock`, `.terragrunt-cache/`, `*.auto.tfvars`, `allowlist.auto.tfvars` (verified post-commit)

## Pinned Collection Versions

| Collection | Source | Pinned version | Verified against | Notes |
|------------|--------|----------------|------------------|-------|
| community.general | Galaxy (top-level `requirements.yml`) | `==12.6.0` | Live Galaxy API 2026-05-14 | Highest published; matches research target |
| community.crypto | Galaxy (top-level) | `==3.2.0` | Live Galaxy API 2026-05-14 | Highest published |
| ansible.posix | Galaxy (top-level) | `==2.1.0` | Live Galaxy API 2026-05-14 | Highest published |
| community.aws | Galaxy (top-level) | `==9.0.0` | Live API shows 11.0.0 current; held at 9.0.0 | Open Question #1 (RESEARCH:646-650) — 11.0.0 raises ansible-core floor to 2.17 |
| community.general | git: github.com/ansible-collections/community.general | `version: 12.6.0` (tag) | Lockstep with top-level | No `==` operator — type=git uses git refs |
| community.crypto | git: github.com/ansible-collections/community.crypto | `version: 3.2.0` (tag) | Lockstep with top-level | Same |
| ansible.posix | git: github.com/ansible-collections/ansible.posix | `version: 2.1.0` (tag) | Lockstep with top-level | Same |

Galaxy live-API recheck performed on 2026-05-14 before locking diffs (per RESEARCH:733-739). No drift from the 2026-05-13 research targets.

## OpenTofu Lockfile

Generated from `terraform/` with:

```bash
rm -f .terraform.lock.hcl
rm -rf .terraform/                     # forces re-resolution against `~> 6.0`
tofu init                              # seeds lockfile for current platform
tofu providers lock \
  -platform=linux_amd64 \
  -platform=linux_arm64 \
  -platform=darwin_amd64 \
  -platform=darwin_arm64
```

Lockfile contents (28 lines):

| Field | Value |
|-------|-------|
| Provider source | `registry.opentofu.org/hashicorp/aws` |
| Resolved version | `6.45.0` |
| Constraint recorded | `~> 6.0` |
| `h1:` hashes (per-platform SHA256) | 4 (one per platform — darwin_arm64, darwin_amd64, linux_amd64, linux_arm64) |
| `zh:` hashes (zip-archive integrity) | 16 |

Note: the lockfile uses **`registry.opentofu.org/hashicorp/aws`**, not `registry.terraform.io/hashicorp/aws`. This is OpenTofu's default registry and matches `terragrunt.hcl:22 terraform_binary = "tofu"`. The plan's `must_haves.artifacts` `contains` predicate used `registry.terraform.io/...`; the deviation is documented below but does NOT break any consumer — `terragrunt`/`tofu` resolve `hashicorp/aws` to whichever registry the binary defaults to, and OpenTofu's default is `registry.opentofu.org`.

Verification:
- `cd terraform && tofu init -lockfile=readonly` → exits 0, no rewrite. This is the Phase 4 CI gate command (RESEARCH:695).
- `grep -c '"h1:' terraform/.terraform.lock.hcl` → `4` (one h1 per platform).
- `git ls-files terraform/.terraform.lock.hcl` → returns path (file is tracked).
- `git check-ignore terraform/.terraform.lock.hcl` → non-zero (not ignored).

## REP-03 Disposition: Satisfied by Absence

REP-03 reads "Galaxy roles pinned to exact versions (no floating refs)." This repository contains:

1. **No `roles:` key in either `requirements.yml`** — confirmed by `grep -E '^roles:' ansible/requirements.yml ansible/roles/AMAZON2023-CIS/collections/requirements.yml` (no matches).
2. **The only role-shaped artifact in this repo is the vendored CIS role itself** — `ansible/roles/AMAZON2023-CIS/` is committed verbatim, not Galaxy-installed at bake time. There is no floating reference to it; its source is the repo's own HEAD.
3. **The CIS role pulls collection dependencies via a nested `collections/requirements.yml`** — those collections (community.general, community.crypto, ansible.posix) are now pinned in this plan to tagged git releases. While these are collections (not roles), they cover the spirit of REP-03's "no floating refs" mandate for the CIS role's transitive Galaxy footprint.

**Therefore REP-03 is closed with no implementation change beyond REP-02's coverage** — there were never any Galaxy roles to pin. The plan's `<success_criteria>` block at lines 425-432 anticipates this disposition.

## Threat Mitigations Applied

Per the plan's `<threat_model>`:

| Threat ID | Mitigation Implemented |
|-----------|------------------------|
| T-03-01 (aws provider tampering) | Lockfile records 4 `h1:` SHA256 + 16 `zh:` zip-archive hashes; `tofu init -lockfile=readonly` rejects mismatched downloads |
| T-03-02 (Galaxy tarball replacement) | `==X.Y.Z` pins in `ansible/requirements.yml`; Galaxy enforces version immutability |
| T-03-03 (CIS git-tag poisoning) | Pinned to tagged refs; **residual risk noted** — bumping to commit-SHA pinning is a follow-up if a higher trust bar is needed |
| T-03-04 (Who bumped this version?) | Every pin change is a reviewable git diff; commit history is the audit trail |
| T-03-07 (Privileged collection code) | Pin reviewed THIS specific tarball/tag — defense in depth from bake-host ephemerality |

T-03-05 (lockfile metadata disclosure) and T-03-06 (upstream takedown) are accepted-risk per the threat register; no implementation change required.

## Phase 4 CI Gates to Wire In

When Phase 4 builds the GitHub Actions workflow + pre-commit checks, the following grep + tooling gates close the regression loop:

1. **Readonly lockfile init:** `cd terraform && tofu init -lockfile=readonly` (fail on non-zero) — catches provider drift, unstaged lockfile rewrites, checksum mismatches.
2. **No bare-version pins:** `! grep -E '^\s*version:\s*[^=]' ansible/requirements.yml` — fails CI if any collection version is not `==X.Y.Z`. (For `type: git` sources in the CIS file, where bare `version:` is correct, scope this grep to the top-level `ansible/requirements.yml` only — the CIS file uses bare-version refs deliberately.)
3. **Lockfile is tracked:** `git ls-files terraform/.terraform.lock.hcl | grep -q .` — fails CI if the lockfile is ever deleted or moved.
4. **Provider pin not regressed:** `grep -E 'version = "~> 6\.0"' terraform/main.tf` — fails CI if someone widens back to `>= 5.0`.
5. **Lockfile-exclusion never re-added:** `! grep -E '^[^#]*terraform/\.terraform\.lock\.hcl' .gitignore && ! grep -E '^\.terraform\.lock\.hcl$' .gitignore` — fails CI if a future commit re-adds either exclusion.
6. **Offline collection install smoke (optional):** `ansible-galaxy collection install -r ansible/requirements.yml --offline` against a pre-populated runner cache (RESEARCH:696) — catches collection-name typos and missing pins.

These gates are precise enough to drop into a single CI job and slow enough to skip on cache-only changes.

## Deviations from Plan

### Auto-fixed / Informational

**1. [Note - Documentation drift] Lockfile uses OpenTofu registry, not Terraform registry**

- **Found during:** Task 2 lockfile generation
- **Issue:** The plan's `must_haves.artifacts` block at line 33 says the lockfile `contains: "provider \"registry.terraform.io/hashicorp/aws\""`. The actual lockfile uses `registry.opentofu.org/hashicorp/aws` because the project explicitly uses `tofu` (per `terragrunt.hcl:22 terraform_binary = "tofu"`), and OpenTofu's default registry is `registry.opentofu.org`.
- **Fix:** None required — this is correct OpenTofu behavior and matches the intent of the must-have (record AWS provider provenance + hashes). The plan's contains-predicate value was inherited from Terraform-CLI documentation phrasing; both registries serve the same artifact set for `hashicorp/aws`.
- **Files modified:** None — informational only.
- **Action for Phase 4 CI gate:** Use `grep -q 'hashicorp/aws' terraform/.terraform.lock.hcl` (registry-agnostic) rather than pinning to either domain.

**2. [Note - Tooling] `yq` not available locally; used `grep` for YAML structural checks**

- **Found during:** Task 1 verification
- **Issue:** Plan's verification block uses `yq` queries. `yq` is in the bake-host STACK but not on this operator workstation.
- **Fix:** Replaced YAML-aware queries with `grep -E` patterns that count `- name:` and `version: "==X.Y.Z"` lines and compare. Equivalent assurance because the YAML is hand-maintained with stable indentation and a single nesting level.
- **Files modified:** None.
- **Action for Phase 4 CI gate:** Use `yq` in CI (already in the runner's apt repo); local pre-commit can fall back to the grep pattern in this SUMMARY's "Phase 4 CI Gates" section.

No bugs, no architectural changes, no auth gates encountered.

## Operator Migration Note

The next `terragrunt init` will re-resolve provider downloads against the new `~> 6.0` pin. Lockfile hashes must match. **If an operator hits a checksum error** (e.g., they have a stale `.terraform/` from before the pin tightening), the recovery is:

```bash
cd terraform/
rm -rf .terraform/
tofu init                       # downloads v6.45.0 fresh; hashes match the committed lockfile
```

**Do NOT run `tofu init -upgrade`** unless intentionally bumping to a newer 6.x — that command rewrites the lockfile and the operator must commit the diff.

For `terragrunt`, the same recovery applies inside `.terragrunt-cache/`:

```bash
rm -rf .terragrunt-cache/
terragrunt init
```

## Commits

| Commit | Type | Files | Closes |
|--------|------|-------|--------|
| `4bca849` | chore(phase-03-01) | `.gitignore`, `terraform/main.tf`, `ansible/requirements.yml`, `ansible/roles/AMAZON2023-CIS/collections/requirements.yml` | REP-02, REP-03 |
| `7bea740` | feat(phase-03-01) | `terraform/.terraform.lock.hcl` (NEW) | REP-01 |

## Verdict

**COMPLETE** — all 2 tasks executed, both committed atomically, every `<verification>` and `<success_criteria>` predicate passes:

- REP-01 ✓ lockfile tracked, records 4 platforms, readonly init exits 0
- REP-02 ✓ every collection in `ansible/requirements.yml` uses `==X.Y.Z`
- REP-03 ✓ closed by absence — no `roles:` key in either requirements.yml; CIS role's transitive collections pinned to tagged git refs as part of REP-02 coverage
- AWS provider tightened to `~> 6.0` (resolved to v6.45.0)
- `.gitignore` preserves `*.auto.tfvars`, `*.pkr.hcl.lock`, `.terragrunt-cache/`
- Zero changes to `packer/`, `Makefile`, `terragrunt.hcl` (Plan 03-02 territory)

## Self-Check: PASSED

- `git ls-files terraform/.terraform.lock.hcl` → returns `terraform/.terraform.lock.hcl` ✓
- `git log --oneline | grep 4bca849` → present ✓
- `git log --oneline | grep 7bea740` → present ✓
- `terraform/main.tf` contains `version = "~> 6.0"` ✓
- `ansible/requirements.yml` 4 collections, all with `==X.Y.Z` ✓
- `ansible/roles/AMAZON2023-CIS/collections/requirements.yml` 3 collections, all with bare-version tag ref ✓
- `.gitignore` contains zero `^[^#]*terraform/\.terraform\.lock\.hcl` matches ✓
- `tofu init -lockfile=readonly` exits 0 ✓
