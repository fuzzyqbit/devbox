---
phase: 04-ci-precommit-documentation
plan: 03
subsystem: documentation
tags: [documentation, claude-md, operator-quickstart, firewalld-workaround, retirement-criteria]
requirements_completed: [DOC-01, DOC-02]
wave: 1
depends_on: []
key_files:
  created:
    - CLAUDE.md
  modified:
    - ansible/firewalld-docker-fix.yml
commits:
  - 8d4be9a: docs(phase-04-03): populate CLAUDE.md operator quickstart (DOC-01)
  - 8cab699: docs(phase-04-03): expand firewalld-docker-fix.yml retirement criteria (DOC-02)
metrics:
  duration_minutes: ~10
  tasks_completed: 3
  files_changed: 2
  insertions: 231
  deletions: 0
completed_date: 2026-05-14
verdict: COMPLETE
---

# Phase 4 Plan 03: Documentation (DOC-01, DOC-02) Summary

Populated the previously-empty top-level `CLAUDE.md` with a 9-section operator
quickstart (DOC-01) and expanded the FIXME header of `ansible/firewalld-docker-fix.yml`
with three OR-joined, testable retirement criteria (DOC-02). The repo is now
self-documenting for a fresh-clone operator and the firewalld-docker workaround
is no longer aspirational.

## Tasks Completed

| Task | Name | Files | Commit |
|------|------|-------|--------|
| 1 | Populate CLAUDE.md operator quickstart | `CLAUDE.md` (new, 205 lines) | `8d4be9a` |
| 2 | Expand firewalld retirement criteria | `ansible/firewalld-docker-fix.yml` (+26 lines, 61 → 86) | `8cab699` |
| 3 | Cross-link sanity smokes | n/a (verification only; no diff) | (none) |

## CLAUDE.md Sections (with line ranges)

All 9 RESEARCH-mandated sections present in order. The file opens with a single H1
`# devbox` at line 3 and closes with a `.planning/` pointer at line 200.

| § | Section | Line range |
|---|---------|------------|
| Header | _Operator quickstart … For project history …_ | L1 |
| H1 | `# devbox` | L3 |
| 1 | What this is | L5–L11 |
| 2 | Prerequisites (+ all 3 `pre-commit install` invocations) | L13–L55 |
| 3 | Environment variables (table form) | L57–L63 |
| 4 | One-time per-operator setup (SSH keypair + CIDR allowlist) | L65–L92 |
| 5 | Daily flow (packer-bake → tg-apply → start → ssm → secrets-show → stop) | L94–L125 |
| 6 | Rotations (SSH key, secrets via re-bake, CIDR allowlist) | L127–L144 |
| 7 | Troubleshooting (incl. cross-link to firewalld YAML at L165) | L146–L170 |
| 8 | Invariants — do not violate (5 verbatim bullets from RESEARCH L830–835) | L172–L191 |
| 9 | Known follow-ups (Packer SSM `:NN` deferred) | L193–L198 |
| Footer | `.planning/` pointer trio | L200–L205 |

Final line count: **205** (target window 180–400; min_lines from must_haves.artifacts is 180).

## ansible/firewalld-docker-fix.yml Header Expansion

| Region | Line range | Status |
|--------|------------|--------|
| Pre-existing front-matter (`---`, FIXME WHAT/WHY) | L1–L25 | Unchanged byte-for-byte |
| **NEW retirement-criteria block** | **L26–L51** | Inserted |
| Pre-existing playbook tasks (`- name: firewalld default zone = docker (workaround)` … `meta: end_play` … final `set-default-zone=docker`) | L53–L86 | Unchanged byte-for-byte |

Final line count: **86** (baseline 61 + 25 inserted; cap 200). Diff verified
insert-only via `git diff-tree --no-commit-id --name-only -r 8cab699` — single file,
single hunk, zero deletions.

The block covers all three retirement options:

1. **CIS posture lifted** — relax firewalld dependency in
   `ansible/roles/AMAZON2023-CIS/defaults/` or switch to a different hardening
   baseline (e.g., DISA STIG). Cross-refs `ansible/roles/hardening/defaults/main.yml`
   lines 4-13.
2. **`containers` layer removed** from `ansible/layer_config.yml` — without Docker,
   no `docker` zone is registered and the workaround becomes a no-op.
3. **Per-port allowances** added to the `public` zone inside `roles/hardening` —
   option (a) from line 14 of the existing header.

Plus the binary **verification command** (`firewall-cmd --get-default-zone` should
return `public` (a) OR firewalld must be absent (b); the workaround state, default
zone = `docker`, is no longer acceptable post-retirement) and a closing
cross-reference back to `CLAUDE.md` Troubleshooting.

## Cross-references

| Direction | Anchor in CLAUDE.md | Anchor in firewalld YAML |
|-----------|---------------------|--------------------------|
| CLAUDE.md → firewalld YAML | Troubleshooting bullet "firewalld blocking ports inside the AMI" (CLAUDE.md L165) | (target) |
| firewalld YAML → CLAUDE.md | (target) | Closing comment "Cross-reference: CLAUDE.md Troubleshooting → …" (firewalld YAML L50–L51) |

Both directions verified by `grep` in Smoke 1.

## Smoke Test Results

| # | Smoke | Result | Notes |
|---|-------|--------|-------|
| 1 | Bidirectional cross-link | **PASS** | Both `grep` checks return OK. |
| 2 | Makefile target reality | **PASS** | 20/20 documented `make <target>` mentions present in actual Makefile (`packer-bake`, `tg-apply`, `start`, `stop`, `status`, `devbox-ssm`, `devbox-port-forward`, `devbox-allowlist-me`, `secrets-show`, `init`, `validate`, `build`, `fmt`, `clean`, `tg-init`, `tg-reinit`, `tg-plan`, `tg-auto-apply`, `tg-destroy`, `tg-auto-destroy`). Zero drift. |
| 3 | checkov reference check | **PASS** | CLAUDE.md does not present `.checkov.yaml` as an operator file (it appears only as "optional operator-side… CI is authoritative" in Prerequisites; no .checkov.yaml path literal). |
| 4 | gitleaks against new docs | **PASS** | Both files scan clean (0 leaks). `gitleaks` v8.30.x with default ruleset + project allowlist (`.gitleaks.toml` permits canonical AWS-docs example creds in `.md`). |
| 5 | ansible syntax-check | **PASS — ran** | `ansible-playbook --syntax-check ansible/firewalld-docker-fix.yml -i localhost,` exit 0. `python3 -c "yaml.safe_load_all(...)"` also passes (defense-in-depth). Executor had `ansible-playbook` on PATH (`/Users/me/Library/Python/3.9/bin/ansible-playbook`) so the primary check ran rather than the YAML-only fallback. |
| 6 | markdownlint | **SKIPPED (cosmetic)** | `markdownlint` not on executor PATH. Plan declares this non-fatal; verdict relies on the structural checks in Task 1's automated verify (28/28 PASS) which cover code-block balance, single H1, ordered H2 hierarchy. |

## Task 1 Automated Verify (Task 1 `<verify>` block)

28/28 checks PASS — including:
- File exists, line count 205 ∈ [180, 400]
- All 9 documented Makefile targets grep-able (`make packer-bake`, `make tg-apply`,
  `make start`, `make stop`, `make devbox-ssm`, `make devbox-port-forward`,
  `make devbox-allowlist-me`, `make secrets-show`, `pre-commit install …`)
- All 3 pre-commit invocations present (`install`, `install --hook-type pre-push`,
  `install --install-hooks`)
- SSH keypair flow present (`ssh-keygen`, `aws ec2 import-key-pair`)
- `ansible/firewalld-docker-fix.yml` cross-reference present
- `terraform/.terraform.lock.hcl` invariant referenced
- "hardening", "invariant", "SSM", "follow-up" all present
- No emoji (🎉/🚀/✨ regex returns no matches)

## Task 2 Automated Verify (Task 2 `<verify>` block)

10/10 PASS — including:
- `^# Retirement criteria` present
- All 3 retirement-trigger phrases present ("CIS scan requirement",
  "`containers` layer is removed", "Per-port allowances")
- Verification command present (`firewall-cmd --get-default-zone`)
- Cross-reference present (`CLAUDE.md`)
- Play opener `- name: firewalld default zone = docker (workaround)` unchanged
- `meta: end_play` still present (early-exit task intact)
- Line count 86 ≤ 200
- `python3 -c "yaml.safe_load_all(...)"` passes

## Boundary Compliance

Per-commit boundary check (using `git diff-tree --no-commit-id --name-only`):

| Commit | Files changed | In-scope? |
|--------|---------------|-----------|
| `8d4be9a` | `CLAUDE.md` | YES (DOC-01 file) |
| `8cab699` | `ansible/firewalld-docker-fix.yml` | YES (DOC-02 file) |

Out-of-scope plan-territory left untouched by my commits:
- `.github/workflows/*` (plan 04-01 territory) — not in either commit's diff
- `.pre-commit-config.yaml` (plan 04-02 territory) — not in either commit's diff
- `.checkov.yaml`, `.ansible-lint` (plan 04-01 territory) — not in either commit's diff
- `Makefile` — not in either commit's diff (referenced verbatim, not modified)
- All other `ansible/` files — only `firewalld-docker-fix.yml` in `8cab699`'s diff

**Note on Task 3 verify wording:** Task 3's `<automated>` block uses
`git diff HEAD~2 -- .pre-commit-config.yaml` as the boundary gate. That diff is
non-empty because `HEAD~2` resolves to `9b2299d` (Phase 4 plan slice 1 — DOC of
04-01-PLAN.md), and the commit chain prior to my work already included a
`.pre-commit-config.yaml` change unrelated to this plan. Switching the gate to
per-commit (`git diff-tree --no-commit-id --name-only -r HEAD~1 HEAD`) confirms
my two commits each touch exactly one file in scope. Recorded as a
**verify-wording deviation** below; the intent of the gate (this plan must not
modify plan-01/02 files) is satisfied.

## Deviations from RESEARCH Template

All deviations were explicitly authorized in the plan's `<action>` blocks (Rule 4
"deviation rationale" requirement satisfied by plan text):

1. **Section 2 — Prerequisites:** Two OS-specific fenced bash blocks (macOS brew /
   Fedora-RHEL dnf+pip) instead of the prose comma-separated tool list from
   RESEARCH L753–765. Rationale (plan action item 2): copy-pasteable for fresh-
   clone operators; avoids the operator having to translate "and also
   ansible-lint ≥ 26" into a package-manager invocation.
2. **Section 4 — Per-operator setup:** SSH keypair (Step 1) and CIDR allowlist
   (Step 2) merged under a single section with numbered steps. RESEARCH described
   them separately; the plan asked for the merger for clearer onboarding.
3. **Markdown styling:** No emoji, H1 `# devbox`, H2 per numbered section,
   fenced code blocks with `bash` / `yaml` language hints, definition-list /
   table form in §3 instead of bullets. Per plan action item 8.
4. **Header note prefix line** above the H1: `_Operator quickstart for the
   devbox IaC repo. Last updated: 2026-05-14 (Phase 4 DOC-01). For project
   history and architecture, see `.planning/PROJECT.md`._` — directly mandated
   by plan action item 9.
5. **Footer trio reference** at end of file linking `.planning/PROJECT.md`,
   `.planning/codebase/`, and `.planning/phases/*/` — small addition to the
   RESEARCH template (no rationale field was required by the plan, but the link
   is necessary to satisfy the must_haves "self-documenting … pointer to
   .planning" claim without forcing every operator to memorize the directory
   layout).

## Threat Model Mitigations Applied

From the plan's `<threat_model>` (all `mitigate` dispositions):

| Threat | Mitigation realized |
|--------|---------------------|
| T-04-18 (information disclosure — example creds in CLAUDE.md) | No real keys / ARNs / account IDs in CLAUDE.md. Placeholders only (`${USER}`, `$AWS_REGION`, `<host>`). Smoke 4 (gitleaks) returns 0 leaks on both files. The `.gitleaks.toml` allowlist for `.md` files (Phase 1) covers any canonical AWS-docs example creds we _might_ have wanted to reference; we didn't reference any. |
| T-04-19 (doc drift from Makefile) | Smoke 2 enforces — 20/20 documented `make <target>` mentions verified present in the actual Makefile. Recorded above. |
| T-04-20 (doc drift from .pre-commit-config.yaml) | All 3 `pre-commit install …` invocations documented in §2 of CLAUDE.md; duplication with `.pre-commit-config.yaml` header (which is plan 04-02 territory) is intentional defense-in-depth per the plan's threat model. |
| T-04-21 (operator denies knowing the invariants) | §8 of CLAUDE.md lists all 5 invariants verbatim from RESEARCH L830–835. The grep gates (plan 04-01 + plan 04-02) are the authoritative enforcement; this doc is the human-readable contract. |
| T-04-22 (retirement-criteria misinterpretation) | All 3 criteria explicitly OR-joined ("ANY of:") in the firewalld YAML header. Each criterion has a testable trigger (CIS posture / layer_config.yml content / role contents) and the binary verification command is `firewall-cmd --get-default-zone`. |
| T-04-23 (SSM parameter paths in docs) | **Accepted** per plan's threat register — `/devbox/${DEVBOX_USER}/*` is documented in §3 (env vars) and §6 (rotations) of CLAUDE.md. Knowing the path is not sensitive; IAM scoping enforces access control. |

## Threat Flags

None. No file created or modified in this plan introduces new network endpoints,
auth paths, file-system access patterns, or schema changes at trust boundaries.

## Known Stubs

None. CLAUDE.md is fully populated; the firewalld YAML retirement-criteria block
has no placeholder fields.

## Self-Check: PASSED

- File created: `CLAUDE.md` — verified `[ -f CLAUDE.md ]` → FOUND
- File modified: `ansible/firewalld-docker-fix.yml` — verified `[ -f ansible/firewalld-docker-fix.yml ]` → FOUND
- Commit `8d4be9a` — verified `git log --oneline | grep -q 8d4be9a` → FOUND
- Commit `8cab699` — verified `git log --oneline | grep -q 8cab699` → FOUND
- Bidirectional cross-reference (CLAUDE.md ↔ firewalld YAML) — verified by Smoke 1, both directions OK
- 20/20 documented Makefile targets present in actual Makefile — verified by Smoke 2 (zero MISSING)
- YAML syntax valid — verified by `ansible-playbook --syntax-check` exit 0 and `python3 yaml.safe_load_all` exit 0
- gitleaks clean — verified on both files
- Verdict: **COMPLETE**
