---
phase: 16-chrome-in-the-desktop-role
verified: 2026-07-24T14:05:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
deferred:
  - truth: "Chrome launches and renders from the GNOME desktop of a live hardened instance (runtime proof, CHROME-01)"
    addressed_in: "Phase 17"
    evidence: "Phase 17 goal: 'Chrome is proven working where the operator actually uses it — launched from the GNOME desktop of a live, hardened, SELinux-enforcing instance over DCV or xrdp'; success criterion 1 covers bake → apply → connect → launch"
---

# Phase 16: Chrome in the desktop role Verification Report

**Phase Goal:** Every desktop bake ships Google Chrome installed from Google's official signed dnf repo, with GPG verification on and no change to the playbook's invariant ordering.
**Verified:** 2026-07-24T14:05:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

Merged from ROADMAP Phase 16 Success Criteria (4) + 16-01-PLAN must_haves (restatements — roadmap wording kept).

| #   | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 1   | `layers.desktop: true` bake installs `google-chrome-stable` from Google's official dnf repo (baked `.repo` + GPG key), no new layer flag / sub-gate | ✓ VERIFIED | Three-task block at `ansible/roles/desktop/tasks/main.yml:160-200` (rpm_key → copy canonical `.repo` → dnf `google-chrome-stable`, `state: present`). Anchored `^\s*when:` count = 1 (only the pre-existing VS Code sub-gate at line 136); Chrome tasks carry no gate. Commit f778b56 footprint = exactly this one file; `layer_config.yml` untouched. |
| 2   | GPG verification stays ON: `gpgcheck=1` in the baked `.repo`, no `--nogpgcheck` / `disable_gpg_check: true` anywhere in the change | ✓ VERIFIED | `gpgcheck=1` at line 188 inside the copy `content:`; comment-filtered `nogpgcheck\|disable_gpg_check: true` = 0 hits in the file; dnf task states `disable_gpg_check: false` explicitly (anchored count = 2: VS Code + Chrome); rpm_key imports the Google key (line 176-178) before the install task. |
| 3   | `layers.desktop: false` bake unchanged — nothing lands outside the desktop layer | ✓ VERIFIED | All Chrome tasks live inside the desktop role; role gate `when: layers.desktop \| default(false)` intact at `ansible/playbook.yml:70`. Phase diff is append-only (42 insertions, 0 deletions, single hunk `@@ -156,3 +156,45 @@`); no other ansible file touched by any phase commit. |
| 4   | Playbook invariants hold: `hardening` last role, `sbom.yml` last import; pre-commit + CI grep-gates green | ✓ VERIFIED | `hardening` is the last entry in the roles list (`playbook.yml:85`); mechanically enforced by grep-gate #9 — `pre-commit run grep-gates --all-files` → **Passed** (run by verifier). Last `import_playbook` is `sbom.yml` (`playbook.yml:170`, direct inspection — note: sbom-last is NOT in the grep-gates hook, verified manually). CI-authoritative lint independently reproduced: pinned venv `ansible-lint==26.4.0`, production profile, `ansible-lint ansible/playbook.yml` → 0 failures, 0 warnings, exit 0. `ansible-playbook --syntax-check -e @ansible/layer_config.yml` → exit 0. |

**Score:** 4/4 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Runtime proof: Chrome launches from GNOME on a live hardened instance (CHROME-01) | Phase 17 | Phase 17 "Live UAT gate" goal + success criteria 1-2 (bake → apply → DCV/RDP connect → launch; SELinux/sandbox check). Phase 16's contract is bake-config-level only. |

CHROME-03 (SBOM version capture as a requirement) and CHROME-04 (dedicated bake-asserts) are **operator-deferred by re-scope 2026-07-24** (REQUIREMENTS.md Future Requirements; ROADMAP Pending). Their absence was confirmed correct — the append-only diff contains no SBOM-capture tasks, no bake-asserts, no version-pin var — and per plan ("do not smuggle them in") this is compliance, not a gap.

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `ansible/roles/desktop/tasks/main.yml` | Google Chrome install block (rpm_key → copy `.repo` → dnf) appended after the VS Code block, unconditional desktop content; contains `baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64` | ✓ VERIFIED | Exists; substantive (42-line block, 3 real tasks — no stubs, no debt markers); wired (loaded via `role: desktop` in playbook roles list, gated at role level); contains-pattern count = 1, no spaces around `=`. The `.repo` body is exactly the six canonical lines in order ([google-chrome] / name / baseurl / enabled=1 / gpgcheck=1 / gpgkey), no `repo_gpgcheck` line (count 0), no `fingerprint:` param (count 0). 16-REVIEW.md independently verified byte-identity against upstream `chrome/installer/linux/common/rpm.include`. |

Data-flow trace (Level 4): N/A — Ansible bake config, not a dynamic-data-rendering artifact. The equivalent check (task order: key import precedes install; repo file precedes install; both feed the same dnf transaction) passes by sequential task position (170 → 180 → 194).

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `ansible/playbook.yml` | `ansible/roles/desktop/tasks/main.yml` | role-level gate — the ONLY gate on the Chrome tasks | ✓ WIRED | `playbook.yml:69-70` — `role: desktop` / `when: layers.desktop \| default(false)`; pattern `when: layers\.desktop` found; no task-level wrapper exists (anchored `when:` count 1 = VS Code only). |
| rpm_key task (Google Linux signing key) | dnf install `google-chrome-stable` | key imported into rpm db BEFORE install | ✓ WIRED | Pattern `key: https://dl\.google\.com/linux/linux_signing_key\.pub` found (line 177); rpm_key task (170) precedes dnf task (194) in the same sequential task file; dnf has `disable_gpg_check: false`. |
| copy task (`/etc/yum.repos.d/google-chrome.repo`) | dnf install `google-chrome-stable` | dnf resolves the package from the `[google-chrome]` repo id, `gpgcheck=1` | ✓ WIRED | Pattern `gpgcheck=1` found (line 188); `dest: /etc/yum.repos.d/google-chrome.repo` count = 1; copy task (180) precedes dnf task (194); repo `enabled=1`. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Playbook parses with the Chrome block under layer config | `ansible-playbook ansible/playbook.yml --syntax-check -e @ansible/layer_config.yml` | exit 0 | ✓ PASS |
| CI-authoritative lint gate green | `ansible-lint ansible/playbook.yml` in fresh pinned venv (ansible-lint 26.4.0, ansible-core 2.21.2, production profile) | "Passed: 0 failure(s), 0 warning(s) in 49 files" exit 0 | ✓ PASS |
| Invariant grep-gates green | `pre-commit run grep-gates --all-files` | Passed | ✓ PASS |
| No secrets in phase file | `pre-commit run gitleaks --files ansible/roles/desktop/tasks/main.yml` | Passed | ✓ PASS |
| Live bake installs Chrome | — | requires AWS creds + live bake | ? SKIP → deferred to Phase 17 |

### Probe Execution

No probes exist (`find scripts -path '*/tests/probe-*.sh'` → empty) and none are declared in the PLAN/SUMMARY. N/A for this Ansible-config phase.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| CHROME-02 | 16-01-PLAN | Chrome installs from Google's official signed dnf repo — baked `.repo` config + GPG key, `gpgcheck=1`, no `--nogpgcheck` | ✓ SATISFIED | Truths 1-2 evidence; REQUIREMENTS.md marks it `[x]` Complete → Phase 16. |

Orphan check: REQUIREMENTS.md traceability maps only CHROME-02 to Phase 16 — no orphaned requirements. CHROME-01 → Phase 17 (Pending, by design); CHROME-03/04 intentionally unmapped (deferred re-scope).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `ansible/roles/desktop/tasks/main.yml` | — | none in phase-modified file (0 TBD/FIXME/XXX, 0 TODO/HACK/placeholder, 0 changeme, 0 stub patterns) | — | — |
| `ansible/roles/desktop/tasks/main.yml` | 57-103 | [PRE-EXISTING, not phase 16] unpinned/unchecksummed ffmpeg static download (16-REVIEW.md CR-01) | ℹ️ Info (for this phase) | Predates f778b56 (diff hunk starts at line 156); outside the phase change footprint; tracked in 16-REVIEW.md as a pre-existing critical for a future hygiene task. |
| `ansible/roles/desktop/tasks/main.yml` | 170-178 | Google key trust anchored solely in TLS at bake time (16-REVIEW.md WR-01) | ⚠️ Warning (advisory) | Matches the plan's locked decision (no `fingerprint:` param — ansible-core < 2.18 multi-key limitation, verified against module source in review; active fingerprint documented in-comment). Does not violate any success criterion. Review's suggested post-import fingerprint assert is a reasonable follow-up. |

Note: the repo-wide `pre-commit run --all-files` fails on 3 pre-existing baseline items (no-changeme guard in `ansible/roles/secrets/tasks/generate.yml` since 2026-05-13/06-19 — blame-verified by this verifier; check-yaml on `.gitlab-ci.yml` `!reference`; archived-doc whitespace). None are caused by phase 16; documented in `deferred-items.md`. The scoped/CI-authoritative forms are all green (run first-hand above).

### Human Verification Required

None for this phase. The phase contract is static bake-config delivery of CHROME-02; the only human-run item (live launch proof, CHROME-01) is Phase 17's explicit success criterion and is recorded under Deferred Items, not here. No `<human-check>` blocks exist in 16-01-PLAN.

### Gaps Summary

No gaps. All four ROADMAP success criteria are observably true in the codebase and were verified first-hand (grep counts, append-only diff shape, both claimed commits resolved via `git rev-parse`, grep-gates hook executed, and the CI-pinned ansible-lint 26.4.0 gate independently reproduced in a fresh venv rather than trusted from the SUMMARY). One SUMMARY inaccuracy found and corrected in this report: grep-gates does NOT mechanically enforce sbom-last-import (only hardening-last, gate #9) — the sbom-last invariant was instead verified by direct inspection of `playbook.yml:170` and holds.

---

_Verified: 2026-07-24T14:05:00Z_
_Verifier: Claude (gsd-verifier)_
