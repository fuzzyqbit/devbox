# Phase 4: CI, pre-commit, and documentation — Research

**Researched:** 2026-05-14
**Domain:** GitHub Actions CI + pre-commit framework for an IaC repo (Packer + OpenTofu + Terragrunt + Ansible + bash)
**Confidence:** HIGH for tool selections and SHAs (verified via GitHub API); HIGH for the Trivy/Checkov decision (verified via 2026 supply-chain incident reporting); MEDIUM for workflow layout (defensible recommendation, alternatives exist)

## Summary

**Lead recommendations** (one sentence each, as requested by the orchestrator):

- **CI-06 (tfsec vs checkov):** Use **Checkov** — `tfsec` was deprecated and folded into `Trivy`, but **Trivy was supply-chain-compromised in March 2026** ([TeamPCP attack](https://www.wiz.io/blog/trivy-compromised-teampcp-supply-chain-attack)) along with KICS; **Checkov is the only mainstream IaC scanner in the original tfsec/checkov/trivy/kics quartet that was NOT compromised**, and it covers our AWS resources (EC2, IAM, SSM, security groups) with a `--hard-fail-on HIGH` flag that satisfies the requirement exactly.
- **Workflow layout (one big job vs many parallel jobs):** **Many parallel jobs** in a single `.github/workflows/ci.yml` — one `job:` per tool (`fmt`, `tofu-validate`, `packer-validate`, `ansible-lint`, `shellcheck`, `checkov`, `grep-gates`); for a personal IaC repo the GH Actions concurrent-job allowance is free and parallelization cuts wall time from ~6 min serial to ~90 s while keeping per-tool log isolation that makes failures legible.

Phase 1 already laid the foundation (`.pre-commit-config.yaml` with gitleaks + `no-changeme`; `.github/workflows/security.yml` with SHA-pinned gitleaks-action). Phase 4 EXTENDS those files plus adds a separate **`.github/workflows/ci.yml`** for the lint/validate/security-scan suite. Keep `security.yml` focused on secret-scanning (correct existing posture — runs on planning docs too); use `ci.yml` with `paths-ignore: ['.planning/**', '**/*.md']` for the slower IaC gates.

The pre-commit story is tiered: **`pre-commit` stage** runs the fast gates that already exist (gitleaks, no-changeme) plus the new fast ones (`terraform_fmt`, `terragrunt hclfmt`, `shellcheck`, `packer fmt -check`, `trailing-whitespace`, `end-of-file-fixer`); **`pre-push` stage** runs the slow ones (`ansible-lint`, `checkov`, `packer validate`, `tofu validate`). This honors operator commit velocity (sub-second pre-commit) while still gating every push.

For documentation, **`CLAUDE.md` is the operator quickstart** — currently 1 byte (effectively empty per Phase 3's tracking). It needs prerequisites, the `make packer-bake → make tg-apply → make start` flow, the SSM-first access posture, the per-operator SSH key rotation procedure, and the "hardening must remain last" invariant. **`ansible/firewalld-docker-fix.yml`** already has a FIXME-header skeleton from Phase 0 — DOC-02 just needs to expand the retirement criteria.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| HCL/Packer/Ansible formatting check | **CI workflow** | pre-commit (fast stage) | CI is authoritative; pre-commit is local-feedback only |
| Configuration validation (tofu/packer/ansible syntax) | **CI workflow** | pre-commit (pre-push stage) | Slow; CI must run, pre-commit is best-effort |
| Static-analysis security scan (Checkov) | **CI workflow** | pre-commit (pre-push, optional) | Slow; CI is authoritative |
| Shellcheck on `scripts/*.sh` | **pre-commit (fast)** | CI workflow | Local binary; cheap to also run in CI |
| Secret scanning (gitleaks) | **CI workflow (existing)** | pre-commit (existing, fast) | Belt-and-braces; Phase 1 wired both |
| Regression grep gates (Phase 3 invariants) | **CI workflow** | pre-commit (local hook) | Cheap; both layers |
| Operator quickstart documentation | **`CLAUDE.md`** | — | Single source of truth for human operators |
| Firewalld-docker workaround documentation | **`ansible/firewalld-docker-fix.yml` header** | CLAUDE.md troubleshooting | Code-adjacent header is canonical; CLAUDE.md cross-references |

## Standard Stack

### Core (GitHub Actions)

| Library | Version | SHA | Purpose | Why Standard | Source |
|---------|---------|-----|---------|--------------|--------|
| `actions/checkout` | v4.3.1 | `34e114876b0b11c390a56381ad16ebd13914f8d5` | Clone the repo into the runner | Official GitHub action; reuse Phase 1's SHA for consistency | [VERIFIED: Phase 1 security.yml line 20] |
| `opentofu/setup-opentofu` | v2.0.0 | `fc711fa910b93cba0f3fbecaafc9f42fd0c411cb` | Install `tofu` binary | First-class OpenTofu action; the project uses `tofu` (`terragrunt.hcl:22 terraform_binary = "tofu"`), NOT terraform — do not use `hashicorp/setup-terraform` | [VERIFIED: `curl https://api.github.com/repos/opentofu/setup-opentofu/git/refs/tags/v2.0.0`, 2026-05-14] |
| `hashicorp/setup-packer` | v3.2.0 | `c3d53c525d422944e50ee27b840746d6522b08de` | Install `packer` binary | Official HashiCorp action | [VERIFIED: `curl https://api.github.com/repos/hashicorp/setup-packer/git/refs/tags/v3.2.0`, 2026-05-14] |
| `bridgecrewio/checkov-action` | v12.1347.0 | `99bb2caf247dfd9f03cf984373bc6043d4e32ebf` | IaC security scan (CI-06) | **NOT compromised** in the March 2026 TeamPCP attack that hit Trivy + KICS; covers AWS EC2/IAM/SSM/SG | [VERIFIED: `curl https://api.github.com/repos/bridgecrewio/checkov-action/git/refs/tags/v12.1347.0`, 2026-05-14] |
| `ludeeus/action-shellcheck` | 2.0.0 | `00cae500b08a931fb5698e11e79bfbd38e612a38` | Run shellcheck in CI | De-facto standard; ALT: install shellcheck via apt and call directly (simpler, no SHA-pin dance for one binary) | [VERIFIED: `curl https://api.github.com/repos/ludeeus/action-shellcheck/git/refs/tags/2.0.0`, 2026-05-14] |
| `ansible/ansible-lint` (pre-commit) | v26.4.0 | `5fac056c45595896c973fbde871f01f6cb14d74c` | Lint Ansible playbooks/roles | Official, `pre-commit` integration via repo `https://github.com/ansible/ansible-lint`. **For GitHub Actions**: prefer running ansible-lint as a script step (`pip install ansible-lint==26.4.0 && ansible-lint`) over a third-party action — fewer SHAs to maintain | [VERIFIED: `curl https://api.github.com/repos/ansible/ansible-lint/git/refs/tags/v26.4.0`, 2026-05-14] |
| `gitleaks/gitleaks-action` | v2 | `ff98106e4c7b2bc287b24eaf42907196329070c7` | Secret scanning in CI | Phase 1 already wired — do not duplicate; runs in `security.yml`, not the new `ci.yml` | [VERIFIED: Phase 1 security.yml line 25] |

### Pre-commit framework hooks

| Hook source | rev | Hook IDs Phase 4 uses | Notes |
|-------------|-----|-----------------------|-------|
| `https://github.com/gitleaks/gitleaks` | `v8.30.1` | `gitleaks` | Phase 1 — keep as-is |
| `local` (existing) | — | `no-changeme` | Phase 1 — keep as-is |
| `https://github.com/tofuutils/pre-commit-opentofu` | `v2.3.0` | `tofu_fmt`, `tofu_validate` (pre-push), `tofu_checkov` (pre-push, optional) | **OpenTofu-native fork of antonbabenko/pre-commit-terraform** — uses `tofu` binary, not `terraform`. Critical because the project's `terragrunt.hcl:22` sets `terraform_binary = "tofu"`. v2.3.0 released 2026-04-21 — active maintenance. [VERIFIED: github.com/tofuutils/pre-commit-opentofu, 2026-05-14] |
| `https://github.com/antonbabenko/pre-commit-terraform` | `v1.105.0` | `terragrunt_fmt`, `terragrunt_validate_inputs` | Use ONLY for Terragrunt hooks (the OpenTofu fork still depends on this upstream for terragrunt). v1.105.0 released 2026-01-06. [VERIFIED: github.com/antonbabenko/pre-commit-terraform, 2026-05-14] |
| `https://github.com/ansible/ansible-lint` | `v26.4.0` | `ansible-lint` (pre-push only — slow) | Latest 2026 release as of research date. [VERIFIED: 2026-05-14] |
| `https://github.com/koalaman/shellcheck-precommit` | `v0.11.0` | `shellcheck` | Matches the operator's local `shellcheck 0.11.0`. Works on `pre-commit` stage (fast). [CITED: shellcheck releases page] |
| `https://github.com/pre-commit/pre-commit-hooks` | `v5.0.0` | `end-of-file-fixer`, `trailing-whitespace`, `check-yaml`, `check-merge-conflict` | The "boring but useful" hooks. [ASSUMED] — version current as of Phase 1; verify before locking |
| `https://github.com/hashicorp/packer` | n/a — there is no first-party Packer pre-commit hook | (call `packer fmt -check` via a `local` hook) | [VERIFIED: no `packer fmt` pre-commit hook exists in the upstream — Phase 4 plans must add a local hook calling `packer fmt -check ./packer`] |

### Tool versions on operator workstation (verified 2026-05-14)

| Tool | Local version | Notes |
|------|---------------|-------|
| gitleaks | 8.30.1 | Matches `.pre-commit-config.yaml` `rev: v8.30.1` ✓ |
| pre-commit | 4.6.0 | Modern enough for `default_stages` and `stages: [pre-push]` |
| shellcheck | 0.11.0 | Pin pre-commit hook to v0.11.0 to match |
| ansible-lint | (PATH altered warning on operator's machine; CI uses fresh pip install) | Pin v26.4.0 in pre-commit + CI |
| tofu | 1.10.6 | Phase 3 lockfile resolved to v6.45.0 of `hashicorp/aws`; tofu 1.10+ is required (Phase 3 RESEARCH note) |
| packer | 1.12.0 | Newer 1.15.x is available but 1.12 matches CI runner default; pin v1.12.0 in `setup-packer` step |
| terragrunt | 0.81.10 | Matches `ansible/roles/terraform/defaults/main.yml` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Checkov | `aquasecurity/trivy` | **REJECTED** — Trivy was supply-chain-compromised March 19-22, 2026 (TeamPCP). Aqua has remediated and the project is "stable" since 2026-03-23 ([CITED: github.com/aquasecurity/trivy/discussions/10462](https://github.com/aquasecurity/trivy/discussions/10462)), but trust takes time to rebuild — Checkov was never affected. |
| Checkov | `tfsec` | **REJECTED** — `tfsec` is deprecated; no new features; folded into Trivy ([CITED: github.com/aquasecurity/tfsec](https://github.com/aquasecurity/tfsec)). |
| Checkov | `terrascan` | Less coverage of AWS-specific checks; smaller community; consider only if Checkov produces unmanageable false positives. |
| `bridgecrewio/checkov-action` (Docker-based) | `pip install checkov && checkov -d terraform/` (script step) | Action ships a container that auto-updates the underlying Checkov version (currently `3.2.528`, 2026-05-10). Script-step gives version control. **Recommend the action** for less SHA-juggling — single SHA-pin covers the auto-updating tool. |
| `opentofu/setup-opentofu` | `hashicorp/setup-terraform` | **REJECTED** — Project explicitly uses `tofu` binary (`terragrunt.hcl:22`). Using `setup-terraform` would install a different binary; HCL is compatible but the lockfile records `registry.opentofu.org` (Phase 3 plan 01 summary), so a `terraform`-binary CI run would produce a divergent dependency graph. |
| `ludeeus/action-shellcheck` | `apt-get install -y shellcheck && shellcheck scripts/*.sh` | Direct apt install avoids a third-party action — one fewer SHA to track. shellcheck is in stock `ubuntu-latest`. **Recommend the apt route** for simplicity. |
| `ansible-community/ansible-lint` action | `pip install ansible-lint==26.4.0 && ansible-lint` | Same logic as shellcheck. Action versions lag the underlying tool. **Recommend pip script step** for version control. |
| One big CI job | Many parallel jobs | See workflow layout discussion below. |

**Installation** (no new operator-side tools — Phase 1 already requires `gitleaks` + `pre-commit`):

```bash
# Operator workstation (additive to Phase 1)
brew install shellcheck ansible-lint checkov   # macOS
# OR
pip install ansible-lint==26.4.0 checkov==3.2.528
dnf install ShellCheck                          # Linux
```

**Version verification commands** (re-run before plan land):

```bash
npm view (n/a — no npm packages)
curl -s https://api.github.com/repos/opentofu/setup-opentofu/git/refs/tags/v2.0.0  | jq -r '.object.sha'
curl -s https://api.github.com/repos/hashicorp/setup-packer/git/refs/tags/v3.2.0   | jq -r '.object.sha'
curl -s https://api.github.com/repos/bridgecrewio/checkov-action/git/refs/tags/v12.1347.0 | jq -r '.object.sha'
curl -s https://api.github.com/repos/ansible/ansible-lint/git/refs/tags/v26.4.0    | jq -r '.object.sha'
curl -s https://api.github.com/repos/ludeeus/action-shellcheck/git/refs/tags/2.0.0 | jq -r '.object.sha'
```

## Architecture Patterns

### System Architecture Diagram

```
┌──── operator workstation ────┐                       ┌──── github.com ─────┐
│                              │                       │                     │
│   git commit                 │                       │  push or PR         │
│   │                          │                       │  │                  │
│   ▼                          │                       │  ▼                  │
│  .git/hooks/pre-commit ───┐  │                       │  workflow trigger   │
│   ├─ gitleaks (FAST)     │  │                       │   ├─ security.yml   │
│   ├─ no-changeme         │  │       git push        │   │   └ gitleaks    │
│   ├─ tofu_fmt            │  │  ───────────────▶    │   │                  │
│   ├─ terragrunt_fmt      │  │                       │   └─ ci.yml         │
│   ├─ packer fmt -check   │  │                       │       (parallel jobs:│
│   ├─ shellcheck          │  │                       │        ├ fmt-check  │
│   └─ trailing/eof        │  │                       │        ├ tofu-val   │
│                          │  │                       │        ├ packer-val │
│  .git/hooks/pre-push ────┤  │                       │        ├ ansible-lint│
│   ├─ tofu_validate       │  │                       │        ├ shellcheck │
│   ├─ packer validate     │  │                       │        ├ checkov    │
│   ├─ ansible-lint        │  │                       │        └ grep-gates)│
│   └─ checkov             │  │                       │                     │
│                          │  │                       └─────────────────────┘
└──────────────────────────┘  │                                  │
                              │                                  ▼
                              │                          ALL JOBS GREEN
                              │                                  │
                              │                                  ▼
                              │                          merge allowed
                              └──────────────────────────────────┘
```

Trace of "operator changes Terraform HCL":
1. Operator edits `terraform/main.tf` → `git commit -m "..."` triggers pre-commit
2. **Fast pre-commit gates** run in ~2 s: tofu_fmt (rewrites file in-place if needed), grep-style gates
3. Commit succeeds locally
4. Operator runs `git push`
5. **Pre-push gates** run in ~30 s: tofu_validate, checkov scan
6. Push succeeds → GitHub triggers `ci.yml` (and `security.yml`)
7. `ci.yml` runs 7 parallel jobs (~90 s total wall time, ~6 min CPU-time)
8. All green → merge allowed

### Recommended Project Structure (Phase 4 additions)

```
devbox/
├── .github/
│   └── workflows/
│       ├── security.yml        # EXISTING (Phase 1) — gitleaks; do not extend
│       └── ci.yml              # NEW (Phase 4) — fmt/validate/lint/checkov/grep-gates
├── .pre-commit-config.yaml     # EXISTING (Phase 1) — EXTEND with Phase 4 hooks
├── .gitleaks.toml              # EXISTING (Phase 1) — do not touch
├── .ansible-lint               # NEW (Phase 4) — exclude vendored CIS role
├── .checkov.yaml               # NEW (Phase 4) — skip-check list, hard-fail-on HIGH
├── .shellcheckrc               # NEW (optional) — global shellcheck config
├── CLAUDE.md                   # EXISTING but empty — POPULATE (DOC-01)
└── ansible/
    └── firewalld-docker-fix.yml # EXISTING — EXPAND header (DOC-02)
```

### Pattern 1: SHA-pinned third-party actions (security hardening)

**What:** Every `uses:` line in a workflow points to a 40-char hex SHA, never a tag.
**When to use:** Always for any third-party (non-`actions/*`-org) action; recommended even for `actions/*` per GitHub's own hardening guide.
**Example:**
```yaml
# Source: https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- name: Install OpenTofu
  uses: opentofu/setup-opentofu@fc711fa910b93cba0f3fbecaafc9f42fd0c411cb  # v2.0.0
  with:
    tofu_version: 1.10.6
```
**Rationale (verbatim from GitHub docs):** "Pinning an action to a full-length commit SHA is currently the only way to use an action as an immutable release." ([CITED: docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions))

**Self-verification grep gate** (CI step or pre-commit local hook):
```bash
# Fails CI if any `uses: org/repo@tag-or-branch` slips in
! grep -rE 'uses: [^ ]+@(v[0-9]|main|master|HEAD|[a-z]+)' .github/workflows/ | grep -v '^[^:]*:.*@[a-f0-9]\{40\}'
```

### Pattern 2: Many small parallel jobs

**What:** Each lint/validate/scan tool gets its own `job:` in `ci.yml`. Jobs run in parallel on `ubuntu-latest`.
**When to use:** Any CI workflow where total wall time > 90 s and tools are independent.
**Example:**
```yaml
# Source: GitHub Actions docs + standard pattern
name: ci
on:
  push:
    paths-ignore: ['.planning/**', '**/*.md']    # planning churn does not trigger lint
  pull_request:
    paths-ignore: ['.planning/**', '**/*.md']

permissions:
  contents: read

jobs:
  fmt-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - uses: opentofu/setup-opentofu@fc711fa910b93cba0f3fbecaafc9f42fd0c411cb  # v2.0.0
      - uses: hashicorp/setup-packer@c3d53c525d422944e50ee27b840746d6522b08de  # v3.2.0
      - run: |
          cd terraform && tofu fmt -check -recursive
          cd ../packer && packer fmt -check .
          terragrunt hclfmt --check

  tofu-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - uses: opentofu/setup-opentofu@fc711fa910b93cba0f3fbecaafc9f42fd0c411cb  # v2.0.0
      - run: |
          cd terraform
          tofu init -lockfile=readonly         # Phase 3 gate — lockfile must not be rewritten
          tofu validate

  packer-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - uses: hashicorp/setup-packer@c3d53c525d422944e50ee27b840746d6522b08de  # v3.2.0
      - run: |
          cd packer && packer init . && packer validate .
          # var.devbox_user defaults to "" since Phase 3 fix — no -var needed

  ansible-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - uses: actions/setup-python@<SHA-pin>   # pin via api.github.com lookup at plan time
        with:
          python-version: '3.11'
      - run: |
          pip install ansible-lint==26.4.0 ansible-core
          ansible-galaxy collection install -r ansible/requirements.yml
          ansible-lint ansible/playbook.yml
          ansible-playbook --syntax-check ansible/playbook.yml -i localhost,

  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - run: shellcheck scripts/*.sh   # shellcheck is pre-installed on ubuntu-latest

  checkov:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - uses: bridgecrewio/checkov-action@99bb2caf247dfd9f03cf984373bc6043d4e32ebf  # v12.1347.0
        with:
          directory: terraform/
          framework: terraform
          config_file: .checkov.yaml      # repo-root config: hard-fail-on HIGH, skip-check list

  grep-gates:
    # The Phase-3-surfaced regression guards
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - run: |
          # Each line is an assertion; first failure stops the job.
          set -euo pipefail
          ! grep -rE 'most_recent\s*=\s*true' packer/
          ! grep -E '^\s*ami_id\s*=\s*"ami-' terragrunt.hcl
          ! grep -- '<RESOLVED-VERSION>' packer/
          ! grep -E '^\s*version:\s*[^=]' ansible/requirements.yml
          git ls-files terraform/.terraform.lock.hcl | grep -q .
          ! grep -E '^[^#]*terraform/\.terraform\.lock\.hcl' .gitignore
          ! grep -rE 'uses: [^ ]+@(v[0-9]+|main|master|HEAD)\b' .github/workflows/ \
            | grep -v '@[a-f0-9]\{40\}'    # action-SHA-pin policy
```

**Why parallel jobs over one big job:**

| Property | One big job | Many parallel jobs (recommended) |
|----------|-------------|-----------------------------------|
| Wall time on green | ~6 min (sequential install + scan) | ~90 s (slowest single job = ansible-lint) |
| Wall time on red | Stops at first failure | All jobs report independently — operator sees full failure set |
| Log clarity | All output in one stream | One job per tool — log tabs in GH UI |
| CPU minutes | ~6 min | ~7 min (slight tax from parallel checkout) |
| Cost (personal repo) | Free (2000 min/month) | Free |
| Cache reuse | One cache key | Per-job cache key — finer-grained |

For a personal IaC repo, the 5x wall-time reduction is the dominant factor. The slight CPU-minute tax is irrelevant under the free tier.

### Pattern 3: Tiered pre-commit stages (fast pre-commit, slow pre-push)

**What:** `pre-commit` stage runs only the fast hooks (< 5 s total); `pre-push` stage runs the slow ones (`ansible-lint`, `checkov`, `tofu validate`).
**When to use:** When at least one hook takes > 5 s — operators stop using pre-commit if every commit is slow.
**Example:**
```yaml
# Source: https://pre-commit.com/ — "default_stages" + per-hook "stages" override
---
default_stages: [pre-commit]   # Phase 1 already set this

repos:
  # FAST — runs on every commit (existing Phase 1 hooks unchanged)
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks

  - repo: local
    hooks:
      - id: no-changeme
        # ... (existing Phase 1 config)

  # FAST — new Phase 4 hooks
  - repo: https://github.com/tofuutils/pre-commit-opentofu
    rev: v2.3.0
    hooks:
      - id: tofu_fmt

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.105.0
    hooks:
      - id: terragrunt_fmt

  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.11.0
    hooks:
      - id: shellcheck

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-merge-conflict
      - id: check-yaml
        exclude: |
          (?x)^(
            ansible/.*\.yml|         # ansible YAML has Jinja and !vault tags that confuse the parser
            \.gitleaks\.toml         # TOML, not YAML, but globbed otherwise
          )$

  - repo: local
    hooks:
      - id: packer-fmt
        name: packer fmt -check
        entry: bash -c 'cd packer && packer fmt -check .'
        language: system
        pass_filenames: false
        files: ^packer/.*\.(pkr\.hcl|pkrvars\.hcl)$

  # SLOW — runs only on pre-push (or manual: `pre-commit run --hook-stage pre-push`)
  - repo: https://github.com/tofuutils/pre-commit-opentofu
    rev: v2.3.0
    hooks:
      - id: tofu_validate
        stages: [pre-push]

  - repo: local
    hooks:
      - id: packer-validate
        name: packer validate
        entry: bash -c 'cd packer && packer init . && packer validate .'
        language: system
        pass_filenames: false
        stages: [pre-push]
        files: ^packer/.*\.(pkr\.hcl|pkrvars\.hcl)$

  - repo: https://github.com/ansible/ansible-lint
    rev: v26.4.0
    hooks:
      - id: ansible-lint
        stages: [pre-push]
        # ansible-lint must be able to find collections; install once via `pre-commit install --install-hooks`
        # or rely on its venv cache. See "Common Pitfalls" → "ansible-lint venv install"

  - repo: local
    hooks:
      - id: checkov
        name: checkov terraform/
        entry: bash -c 'checkov -d terraform/ --config-file .checkov.yaml'
        language: system
        pass_filenames: false
        stages: [pre-push]
        files: ^terraform/.*\.(tf|tfvars)$

  # Always-on regression grep gates (cheap; on every commit)
  - repo: local
    hooks:
      - id: grep-gates
        name: regression grep gates (Phase 3 invariants)
        entry: bash -c 'set -e; \
          ! grep -rE "most_recent\s*=\s*true" packer/ && \
          ! grep -E "^\s*ami_id\s*=\s*\"ami-" terragrunt.hcl && \
          ! grep -- "<RESOLVED-VERSION>" packer/ && \
          ! grep -E "^\s*version:\s*[^=]" ansible/requirements.yml && \
          git ls-files terraform/.terraform.lock.hcl | grep -q .'
        language: system
        pass_filenames: false
```

**Operator UX:**
- `pre-commit install --install-hooks` once (post-clone)
- `pre-commit install --hook-type pre-push` once (to wire the pre-push stage)
- Every `git commit` runs ~2 s of fast hooks
- Every `git push` runs ~30 s of pre-push hooks before the actual push

**Manual override:**
- `pre-commit run --all-files` — runs only `pre-commit`-stage hooks (default behavior)
- `pre-commit run --all-files --hook-stage pre-push` — runs the slow hooks too

[CITED: pre-commit.com — `default_stages` and per-hook `stages` documentation. Stage names verified: `pre-commit`, `pre-push`, `commit-msg`, `manual`, plus several less-common ones.]

### Pattern 4: Path-filtered CI triggers

**What:** `ci.yml` skips when only `.planning/**` or `*.md` changes; `security.yml` runs unconditionally (correct existing behavior — planning docs could still leak secrets).
**When to use:** Whenever a path subtree has lots of churn AND lint/validate provides no value on changes there.
**Example:**
```yaml
# Source: GitHub Actions workflow-syntax docs
on:
  push:
    paths-ignore:
      - '.planning/**'
      - '**/*.md'
      - 'CLAUDE.md'         # explicit; covered by **/*.md but documents intent
  pull_request:
    paths-ignore:
      - '.planning/**'
      - '**/*.md'
```

**Why `.planning/**` specifically:** Phase 1-3 generated ~50 files in `.planning/` and the rate continues; running 7 CI jobs on every planning-doc edit is wasteful and clutters the PR check-list.

**Why `security.yml` stays unconditional:** Even a planning doc can contain a leaked secret. Phase 1's design is correct; do not regress.

[CITED: GitHub Actions workflow-syntax docs — `paths-ignore` semantics: "When all the path names match patterns in `paths-ignore`, the workflow will not run."]

### Pattern 5: Checkov severity gating

**What:** Fail build only on HIGH and CRITICAL findings; let MEDIUM/LOW be reported but pass.
**When to use:** When the codebase has known acceptable MEDIUM findings (e.g., the SSM-agent egress `0.0.0.0/0` rule, the noVNC self-signed cert) that we don't want to block on in Milestone 1.
**Example:**
```yaml
# .checkov.yaml (repo root)
# Source: https://www.checkov.io/2.Basics/Hard%20and%20soft%20fail.html
directory:
  - terraform/
framework: terraform
hard-fail-on: HIGH    # HIGH severity OR ABOVE → build fails (CRITICAL inherited)
soft-fail-on: MEDIUM  # MEDIUM and below → reported but exit 0
skip-check:
  # SSM agent requires outbound HTTPS to *.amazonaws.com — egress 0.0.0.0/0 is the AWS-recommended posture
  # for SSM-managed instances (no VPC endpoint route configured in this repo, by design).
  - CKV_AWS_23   # "Ensure every security group rule has a description" — we have descriptions; check has known FP issues
  # Add IDs here as real findings are triaged — every skip MUST have a comment explaining the carve-out
```

**Important:** `--hard-fail-on HIGH` means "fail when severity is HIGH OR CRITICAL" (severities are ordered, threshold is inclusive). [CITED: checkov.io/2.Basics/Hard and soft fail.html]

**Action wiring:**
```yaml
- uses: bridgecrewio/checkov-action@99bb2caf247dfd9f03cf984373bc6043d4e32ebf  # v12.1347.0
  with:
    config_file: .checkov.yaml
    # The action reads .checkov.yaml automatically; the explicit pointer documents intent.
```

### Pattern 6: ansible-lint scoping (exclude vendored CIS role)

**What:** `.ansible-lint` at repo root excludes the vendored `ansible/roles/AMAZON2023-CIS/` so the project doesn't fail on upstream lint issues we can't fix.
**When to use:** Always when a vendored role is present in the playbook.
**Example:**
```yaml
# .ansible-lint
# Source: https://ansible.readthedocs.io/projects/lint/configuring/
exclude_paths:
  - ansible/roles/AMAZON2023-CIS/         # vendored upstream — out of our control
  - ansible/firewalld-docker-fix.yml      # known workaround (DOC-02 documents it)
  - .planning/                            # planning docs (not Ansible)
profile: production    # strict — appropriate for CI gate
# kinds: explicitly list nothing — let ansible-lint autodetect playbook/role/etc.
```

[CITED: ansible-lint docs — `exclude_paths` is relative to the location of the config file (i.e., repo root in our case).]

### Anti-Patterns to Avoid

- **One big sequential CI job** — masks parallel-fixable failures behind the first error; doubles wall time. Phase 4 plans must NOT use a single job.
- **Tag-pinning third-party actions** (`uses: org/repo@v4`) — mutable; supply-chain risk. GitHub's own hardening doc is unambiguous. Phase 1 already SHA-pins; Phase 4 must continue.
- **Running ansible-lint on every commit** — typical run is 5-15 s on a populated venv, 30-60 s on a cold one. Use `pre-push` stage.
- **Using `trivy` or `tfsec` in this repo** — Trivy compromised March 2026, tfsec deprecated. Even with Trivy's incident resolved, supply chain trust has a recovery period.
- **Skipping `paths-ignore: ['.planning/**']` on `ci.yml`** — wastes CI minutes on planning-doc churn.
- **Extending `security.yml` with non-secret-scan jobs** — Phase 1 designed `security.yml` to be focused (gitleaks only). Phase 4 must use a separate `ci.yml`. (The existing `security.yml` header comment promises this; Phase 4 plans must not violate that contract.)
- **Configuring pre-commit `default_stages: [pre-push]`** — would skip the fast hooks on `git commit`, defeating the local-feedback purpose. Phase 1's `default_stages: [pre-commit]` is correct; Phase 4 adds per-hook `stages: [pre-push]` for the slow ones.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HCL formatting check | A bash loop calling `tofu fmt` per file | `tofu fmt -check -recursive` | Built-in; handles edge cases (unicode, BOM) |
| OpenTofu validation | A custom HCL parser | `tofu validate` | Validates types, references, provider-schema |
| IaC security scan | Custom regex against `cidr_blocks` | Checkov | 100s of curated rules covering AWS resources |
| Severity gating | Custom JSON-parsing of checkov output | `--hard-fail-on HIGH` flag | Built into Checkov |
| Action SHA resolution | Hand-look-up via web UI | `curl https://api.github.com/repos/{org}/{repo}/git/refs/tags/{tag} \| jq -r '.object.sha'` | Reproducible; scriptable in commit-prep |
| pre-commit stage routing | Bash conditionals in a `local` hook | Native `stages: [pre-push]` field | First-class pre-commit feature; documented contract |
| Vendored-role lint exclusion | Custom `--exclude` flags in CI | `.ansible-lint` `exclude_paths:` | Honored by both CLI and IDE plugins |
| Workflow path filtering | Bash + git diff in a step | Native `paths-ignore:` filter | Resolved before the workflow even starts — saves runner allocation |

**Key insight:** Every gate Phase 4 wires has a battle-tested standard implementation. The "custom" surface is limited to (a) the grep regression-gate list (intentionally bespoke per Phase 3) and (b) the `local` packer-fmt hook (because no upstream packer pre-commit hook exists).

## Runtime State Inventory

*Not applicable — Phase 4 is a greenfield (CI + docs) phase, not a rename/migration. No stored data, live service config, OS-registered state, secrets, or build artifacts reference renamed strings.*

## Common Pitfalls

### Pitfall 1: ansible-lint venv install at commit time

**What goes wrong:** First-time operator runs `git commit`, pre-commit tries to install `ansible-lint` + `ansible-core` into a fresh venv, takes 30-90 s. Operator interprets the freeze as a bug and `--no-verify` bypasses.
**Why it happens:** pre-commit creates a per-hook venv on first invocation; ansible-core is ~150 MB.
**How to avoid:** Put ansible-lint on `stages: [pre-push]` so it never runs at commit time. Document `pre-commit install --install-hooks` (with `--install-hooks` flag) in `CLAUDE.md` to pre-warm the cache.
**Warning signs:** Operator complaint "pre-commit is too slow" — the diagnostic is `time git commit -m test` should be < 5 s; if it's 60 s, an ansible-lint stage misconfig is the likely cause.
[VERIFIED: github.com/ansible/ansible-lint discussions #1256]

### Pitfall 2: Checkov-action container version drift

**What goes wrong:** The `bridgecrewio/checkov-action` v12.1347.0 SHA was published 2025-03-09 but ships an auto-updating Docker image. A breaking Checkov release lands in the container without an action SHA bump.
**Why it happens:** The action's container `FROM` directive pulls `:latest` or a floating tag.
**How to avoid:** Pin the underlying Checkov via `with: checkov_version: 3.2.528` in the action invocation. Phase 4 plan should verify this is exposed; if not, switch to `pip install checkov==3.2.528` script step.
**Warning signs:** A finding pattern changes between CI runs without a code or workflow change.
[CITED: bridgecrewio/checkov-action README]

### Pitfall 3: pre-commit `default_stages` global vs per-hook override

**What goes wrong:** Operator changes `default_stages: [pre-commit]` to `[pre-push]` thinking it will speed up commits; instead, every fast hook moves to pre-push and commits silently lose gitleaks coverage.
**Why it happens:** `default_stages` is the fallback for hooks that don't declare their own `stages`. Changing the global affects hooks that haven't opted in to `[pre-commit]` explicitly.
**How to avoid:** Phase 4 plans should set `stages: [pre-commit]` EXPLICITLY on the fast hooks rather than relying on the global, to make the contract obvious and tamper-resistant. The global `default_stages: [pre-commit]` remains as a backstop.
**Warning signs:** `pre-commit run --all-files` shows different hooks running than `git commit`.
[CITED: pre-commit.com — `default_stages` semantics]

### Pitfall 4: `tofu init` rewriting the lockfile in CI

**What goes wrong:** CI's `tofu init` (without `-lockfile=readonly`) silently regenerates `.terraform.lock.hcl` against the runner's platform, replacing the committed 4-platform lockfile with a single-platform version. Phase 3's REP-01 regresses.
**Why it happens:** Default `tofu init` is permissive about lockfile drift on first encounter.
**How to avoid:** Always `tofu init -lockfile=readonly` in CI. Phase 3 plan-01 summary calls this out explicitly. Phase 4 must wire it as the `tofu-validate` job's init invocation.
**Warning signs:** CI `git diff` shows `terraform/.terraform.lock.hcl` modified after `tofu init`.
[VERIFIED: Phase 3 plan-01 summary line 107]

### Pitfall 5: ansible-lint requires collections to be installed

**What goes wrong:** CI runs `ansible-lint ansible/playbook.yml`; lint fails with "collection community.aws not found" because the runner has only base ansible-core.
**Why it happens:** ansible-lint inspects module FQCNs and needs the collections present to resolve them.
**How to avoid:** Add `ansible-galaxy collection install -r ansible/requirements.yml` as a step BEFORE `ansible-lint`. Phase 3 pinned `==X.Y.Z` versions so the install is deterministic.
**Warning signs:** "Unable to load collection X.Y" warnings in lint output; followed by E102 or E301 errors that don't reproduce locally.

### Pitfall 6: Action SHA mismatch between security.yml and ci.yml

**What goes wrong:** Phase 1 SHA-pinned `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5`. Phase 4 plans might naively use the newer v6.0.2 SHA in `ci.yml`, creating SHA drift across workflows and making `grep` audits noisier.
**Why it happens:** No central registry of "the project's pinned action SHAs."
**How to avoid:** Reuse Phase 1's pinned SHA for `actions/checkout` across both workflow files. Document the SHA-pin policy in `CLAUDE.md` (DOC-01) so future bumps are coordinated.
**Warning signs:** `grep -h 'actions/checkout@' .github/workflows/*.yml | sort -u` returns more than one SHA.
[VERIFIED: Phase 1 plan-03 summary line 130 ("reuse the resolved checkout SHA for consistency")]

### Pitfall 7: `terraform fmt` vs `tofu fmt` divergence

**What goes wrong:** Phase 4 plans add `terraform fmt -check` to CI (out of habit). The runner installs Terraform 1.5.x (latest before fork), formats HCL slightly differently than `tofu 1.10.x`, and CI rejects code that pre-commit accepted.
**Why it happens:** `tofu` and `terraform` are 99% identical but the formatters can have minor whitespace differences (especially around heredocs and block alignment).
**How to avoid:** Use `tofu fmt -check` exclusively — both in pre-commit (`tofu_fmt` hook) and CI (the `tofu-validate` job's pre-step). Never install `terraform` binary alongside `tofu` in any pipeline.
**Warning signs:** CI rejects a file that `pre-commit run tofu_fmt --files <path>` passes.
[ASSUMED — divergence is "negligible" per multiple sources but documented as a known surface; CITED: medium.com/@eric.mourgaya/tofu-and-terraform-tooling-ecosystem-part-2]

### Pitfall 8: Self-referential CI workflow editing its own pin

**What goes wrong:** Someone edits `ci.yml` to update the OpenTofu SHA, but Phase 4's "action-SHA-pin grep gate" runs on that same change and passes (because the new SHA is still 40-char hex). The change was malicious but the gate is too narrow.
**Why it happens:** A simple regex-based gate can't verify the SHA points to a real release.
**How to avoid:** The grep gate is necessary but not sufficient. Pair with a `CODEOWNERS` entry on `.github/workflows/**` requiring reviewer approval. Phase 4 should document this in DOC-01.
**Warning signs:** Workflow file diff includes a SHA change with no commit message rationale.

## Code Examples

### Resolving a 40-char SHA for a release tag

```bash
# Source: GitHub REST API — git refs
# Use BEFORE committing any action SHA-pin to verify the tag still points to the expected commit
curl -s https://api.github.com/repos/opentofu/setup-opentofu/git/refs/tags/v2.0.0 \
  | jq -r '.object.sha'
# Output: fc711fa910b93cba0f3fbecaafc9f42fd0c411cb
```

### Re-resolving Phase 1's gitleaks-action SHA (sanity check)

```bash
# Source: Phase 1 plan-03 summary line 60
curl -s https://api.github.com/repos/gitleaks/gitleaks-action/git/refs/tags/v2 \
  | jq -r '.object.sha'
# Expected: ff98106e4c7b2bc287b24eaf42907196329070c7 (matches existing security.yml line 25)
```

### Smoke test — checkov against the post-Phase-3 tree

```bash
# Source: checkov.io
checkov -d terraform/ --framework terraform --hard-fail-on HIGH --output cli
# Expected at Phase 4 plan time:
#   PASSED — most rules
#   FAILED — possibly CKV_AWS_8 (EBS encryption), CKV_AWS_79 (IMDSv2 — already enforced)
# Plans must triage each FAILED finding and either fix or add a justified --skip-check
```

### Verifying pre-commit-config.yaml after Phase 4 edits

```bash
# After plan 4.2 lands, on a clean tree, `pre-commit run --all-files` should be green
pre-commit run --all-files                           # fast hooks only
pre-commit run --all-files --hook-stage pre-push     # slow hooks too
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `tfsec` for Terraform security scan | Trivy (then Checkov after the March 2026 incident) | tfsec deprecated 2024; Trivy compromised March 2026 | tfsec README explicitly redirects to Trivy; we use Checkov per the supply-chain decision above |
| `actions/checkout@v3` | `actions/checkout@v4` (or v6) | Node 16 deprecation, late 2023 | Phase 1 uses v4 (`34e114...`); Phase 4 keeps v4 for SHA consistency |
| `setup-terraform` for OpenTofu | `setup-opentofu` | OpenTofu fork 2024; v2.0.0 of setup-opentofu Mar 2024 (Node 24) | Mandatory for any repo with `terraform_binary = "tofu"` |
| Pinning actions to tags (`@v4`) | Pinning actions to 40-char SHAs | GitHub formal recommendation, ongoing supply-chain incidents | Phase 1 already adopted; Phase 4 continues |
| Running `ansible-lint` on every commit | Running on `pre-push` only | Performance — ansible-core install cost | Standard recommendation in pre-commit + ansible-lint docs |

**Deprecated/outdated:**
- `tfsec`: archived; checks moved to Trivy. Do not adopt for new repos. [CITED: github.com/aquasecurity/tfsec]
- `aquasecurity/tfsec-action`: deprecated alongside tfsec.
- `tfsec` pre-commit hook in pre-commit-opentofu / pre-commit-terraform: marked deprecated in the upstream `.pre-commit-hooks.yaml`. Replaced by `tofu_trivy` (avoid per supply-chain) and `tofu_checkov` (recommended).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `pre-commit-hooks` v5.0.0 is current | Pre-commit framework hooks table | Low — bump to latest at plan time; non-breaking |
| A2 | The `terraform fmt` vs `tofu fmt` whitespace difference is negligible | Pitfall 7 | Low — even if present, only causes CI false-fail; recovery is one-line; impact: confusion not breakage |
| A3 | Checkov has no known critical findings against Phase 3's `terraform/` state that would require triage in Phase 4 | Code Example "Smoke test — checkov" | Medium — if Checkov flags many HIGH findings, Phase 4 plan 4.1 grows (need to triage / skip-check each). Phase 4 plans should run `checkov -d terraform/ --hard-fail-on HIGH` early to size the work |
| A4 | The `bridgecrewio/checkov-action@v12.1347.0` action exposes a `checkov_version` input | Pitfall 2 fix | Medium — if it doesn't, fall back to `pip install checkov==3.2.528` script step; one extra job step |
| A5 | `tofuutils/pre-commit-opentofu` v2.3.0's `tofu_validate` hook correctly invokes `tofu init -lockfile=readonly` (not a fresh init) | Pattern 3 example | Medium — if it rewrites the lockfile during validation, Phase 3 REP-01 silently regresses. Phase 4 plan must run `pre-commit run --all-files --hook-stage pre-push` on a clean tree and verify `git status` is clean |

**Three of five assumptions are MEDIUM-risk** — plans must verify each at execution time before declaring Phase 4 done. None are HIGH-risk (no decision is unreversible).

## Open Questions

1. **Should ansible-playbook --syntax-check be a separate CI job from ansible-lint?**
   - What we know: ansible-lint v26.4.0 includes a syntax-check rule (`syntax-check[*]`) that effectively duplicates `ansible-playbook --syntax-check`.
   - What's unclear: Whether running both is redundant or defense-in-depth.
   - Recommendation: Run both. They use different code paths (ansible-lint parses YAML statically; `--syntax-check` invokes the playbook executor). CI-04 says "and", so satisfy literally.

2. **Should `terragrunt hclfmt --check` be wired in CI?**
   - What we know: The Makefile `fmt` target already includes `terragrunt hclfmt` (line 74). Phase 3 plan-03-02 ran `terragrunt hclfmt --check terragrunt.hcl` (line 242) as a smoke gate.
   - What's unclear: It's not explicitly listed in CI-01..07.
   - Recommendation: Include it in the `fmt-check` job — it's free and prevents drift on `terragrunt.hcl` formatting. The Phase 3 summary recommends it.

3. **Should the `--syntax-check` step pass `-i localhost,` as inventory?**
   - What we know: The playbook is Packer-driven (`packer/devimage.pkr.hcl` lines 60+) with no committed inventory file.
   - What's unclear: Whether `ansible-playbook --syntax-check ansible/playbook.yml` without `-i` works (it should, since syntax-check doesn't connect).
   - Recommendation: Use `-i localhost,` for explicit-ness. If errors, drop the flag.

4. **Should `tg-init` be runnable in CI?**
   - What we know: `terragrunt init` would try to create an S3 backend. CI has no AWS creds.
   - What's unclear: Whether the existing `tofu validate` (which `terragrunt run-all validate` would invoke) is enough.
   - Recommendation: Use `tofu validate` directly in CI; do NOT run `terragrunt init` (would fail without creds). Phase 3 already validated tofu against the committed lockfile. The grep gate covers the lockfile-presence invariant.

5. **Should Phase 4 also document the `SSM :NN` follow-up from Phase 3?**
   - What we know: REP-04 deferred the SSM parameter `:NN` pin because Phase 3 lacked AWS creds.
   - What's unclear: Whether DOC-01 should mention this gap or whether it stays in `.planning/STATE.md`.
   - Recommendation: Brief mention in CLAUDE.md "Known follow-ups" section — operators need to know to add `:NN` before their next bake.

## Environment Availability

| Dependency | Required By | Available (operator) | Available (CI runner: ubuntu-latest) | Version | Fallback |
|------------|-------------|----------------------|--------------------------------------|---------|----------|
| `gitleaks` | Phase 1 hooks | ✓ | install via action SHA-pin | 8.30.1 | — |
| `pre-commit` | Phase 1 hooks | ✓ | not needed in CI (CI runs tools directly) | 4.6.0 | — |
| `shellcheck` | CI-05, pre-commit | ✓ | pre-installed | 0.11.0 (operator); 0.10+ (CI) | apt install if missing |
| `ansible-lint` | CI-04, pre-commit | ✓ (PATH warning) | install via pip | 26.4.0 | — |
| `ansible-core` | CI-04 | ✓ via ansible-lint dep | install via pip | bundled | — |
| `tofu` | CI-02, pre-commit | ✓ | install via setup-opentofu@v2.0.0 | 1.10.6 | — |
| `packer` | CI-03, pre-commit | ✓ | install via setup-packer@v3.2.0 | 1.12.0 (operator); pin via setup action input | — |
| `terragrunt` | CI fmt | ✓ | install via curl from releases | 0.81.10 | install script |
| `checkov` | CI-06 | ✗ (operator may install) | install via checkov-action | 3.2.528 | pip install fallback if action breaks |
| `yq` | optional (Phase 3 fallback in pre-commit) | ✗ (Phase 3 used grep fallback) | apt install | n/a | grep — already in use |
| `jq` | Makefile `packer-bake` (Phase 3) | ✓ | pre-installed | n/a | n/a |

**Missing dependencies with no fallback:** None — every gate either has the tool pre-installed on `ubuntu-latest` or installable via apt/pip/setup-action in < 30 s.

**Missing dependencies with fallback:**
- `checkov` operator-side: not required; CI is authoritative for CI-06. Document `pip install checkov==3.2.528` in CLAUDE.md for operators who want local pre-push runs.
- `yq` operator-side: Phase 3 already established grep fallback patterns; Phase 4 inherits.

## Validation Architecture

*Skipped — `.planning/config.json` workflow.nyquist_validation is `false`.*

## Security Domain

### Applicable ASVS Categories (this is an IaC repo, not an application)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (no app code) | n/a |
| V3 Session Management | No | n/a |
| V4 Access Control | Indirect — CI must not have write tokens beyond what gitleaks needs | `permissions: contents: read` at workflow level (Phase 1 set this; Phase 4 must preserve) |
| V5 Input Validation | Yes — for `var.devbox_user`, `var.allowed_web_cidrs` | Already validated in Terraform with `validation {}` blocks (Phase 1, 2); CI's tofu-validate exercises these |
| V6 Cryptography | Indirect — SSM SecureString uses AWS-managed KMS (Phase 1 SEC-03) | Checkov rules CKV_AWS_31 (KMS rotation) — let Checkov enforce, do not hand-roll |
| V14 Configuration | Yes — supply-chain (action pins, gitleaks allowlist) | SHA-pin every action; minimal `.gitleaks.toml` allowlist (Phase 1 doctrine) |

### Known Threat Patterns for `GitHub Actions + IaC`

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tag-pinned action replaced by malicious release | Tampering | SHA-pin every third-party action (Phase 1 + Phase 4 policy) |
| `pull_request_target` event grants writable token to fork PR | EoP | Do NOT use `pull_request_target` for ANY job. Use plain `pull_request`. [VERIFIED: this is the TeamPCP Trivy attack vector — Trivy used `pull_request_target` for issue triage] |
| Compromised pip dependency in CI job (transitive) | Tampering | Pin all pip installs to exact versions (`ansible-lint==26.4.0`, `checkov==3.2.528`); use `pip install --require-hashes` where possible (defer to follow-up) |
| Secret exfiltration via curl-pipe-bash install scripts | Information disclosure | Use only official action SHAs; no `curl ... \| bash` in workflow steps |
| Self-hosted runner persistence | EoP | Use `ubuntu-latest` (GitHub-hosted) only. No self-hosted runners in this project. |
| Workflow can re-write itself | Tampering | `permissions: contents: read` denies push back to the repo. Phase 1's `security.yml` already sets this — Phase 4 `ci.yml` must too. |

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CI-01 | GitHub Actions workflow runs on every push and PR | `ci.yml` `on: push:` + `on: pull_request:` (Pattern 4); `paths-ignore` for `.planning/` to save minutes |
| CI-02 | CI runs `terraform fmt -check` and `tofu validate` | `fmt-check` + `tofu-validate` jobs (Pattern 2). Use `tofu fmt -check`, not `terraform fmt` (Pitfall 7). Both terms in the requirement refer to the same OpenTofu binary |
| CI-03 | CI runs `packer validate` against `packer/devimage.pkr.hcl` | `packer-validate` job uses `setup-packer@v3.2.0` SHA-pinned; runs `packer init . && packer validate .` in `packer/` dir (Pattern 2 example) |
| CI-04 | CI runs `ansible-lint` and `ansible-playbook --syntax-check` | `ansible-lint` job: pip-install at pinned 26.4.0, install collections, run both lint and syntax-check (Pattern 2 example, Open Question 1) |
| CI-05 | CI runs `shellcheck` on every `scripts/*.sh` | `shellcheck` job: pre-installed on `ubuntu-latest`; covers all 6 scripts (`_common.sh`, `devbox-{start,stop,status,ssm,allowlist-me}.sh`) |
| CI-06 | CI runs `tfsec` or `checkov` against `terraform/`; build fails on HIGH/CRITICAL | **Checkov** via `bridgecrewio/checkov-action@v12.1347.0` SHA-pinned; `.checkov.yaml` with `hard-fail-on: HIGH` (Pattern 5) |
| CI-07 | Pre-commit hooks mirror CI for local feedback | Tiered pre-commit: fast hooks on `pre-commit` stage, slow on `pre-push` (Pattern 3) |
| DOC-01 | Top-level `CLAUDE.md` documents quickstart, env vars, bake→provision→start flow | CLAUDE.md template provided below (section "DOC-01 content scope") |
| DOC-02 | `ansible/firewalld-docker-fix.yml` documents what/why/retirement | Existing FIXME header is 75% there; expand the "retire when" criteria (section "DOC-02 expansion" below) |

## DOC-01 Content Scope: CLAUDE.md template

The currently-empty (1-byte) `CLAUDE.md` must cover, in this order, with no more than ~400 lines total:

### Section 1: What this is (5 lines)
- Personal cloud workstation
- Bake AMI (Packer + Ansible) → provision EC2 (Terragrunt → Terraform/OpenTofu)
- Single-operator-per-instance design
- Pointer to `.planning/PROJECT.md` for the full story

### Section 2: Prerequisites (one-time per workstation)
**Tools** (install via brew on macOS, dnf/apt on Linux):
- `aws` CLI v2.x — for SSM Session Manager, SSM Parameter Store, EC2 control
- `session-manager-plugin` — for `make devbox-ssm` and port-forwarding
- `packer` ≥ 1.12 — AMI bake
- `tofu` ≥ 1.10 — Terraform engine (NOT `terraform`; project uses OpenTofu)
- `terragrunt` ≥ 0.81 — backend generation, per-user state
- `ansible` ≥ 2.16 + `ansible-lint` ≥ 26 — Packer provisioners + CI gate
- `jq` — `make packer-bake` parses Packer manifest
- `gitleaks` ≥ 8.30 — pre-commit secret scan
- `pre-commit` ≥ 4.6 — runs the local hooks
- `shellcheck` ≥ 0.10 — script lint
- `checkov` ≥ 3.2 (optional operator-side) — IaC security scan (CI is authoritative)

**One-time setup** (post-clone):
```bash
pre-commit install                       # wires pre-commit stage
pre-commit install --hook-type pre-push  # wires pre-push stage (slow hooks)
pre-commit install --install-hooks       # pre-warm venvs (avoids first-commit lag)
```

### Section 3: Environment Variables
- `DEVBOX_USER` — defaults to `$(whoami)`; controls S3 state key path, SG name prefix, SSH key name, SSM parameter prefix. Examples of override: `make tg-apply DEVBOX_USER=alice`.
- `AWS_REGION` / `AWS_DEFAULT_REGION` — your operator region. The Terraform region var defaults to `terragrunt.hcl`'s `region` input.
- `AWS_PROFILE` (optional) — for multi-account AWS CLI.

### Section 4: One-Time Per-Operator Setup
**Step 1 — SSH keypair** (per-operator; Phase 1 SEC-04):
```bash
ssh-keygen -t ed25519 -f ~/.ssh/${USER}-devbox -C "${USER}-devbox"
aws ec2 import-key-pair \
  --key-name "${USER}-devbox" \
  --public-key-material "fileb://$HOME/.ssh/${USER}-devbox.pub" \
  --region "$AWS_REGION"
```

**Step 2 — CIDR allowlist for code-server/noVNC** (per-operator; Phase 2 NET-02/03):
```bash
make devbox-allowlist-me            # auto-resolves your public IP, writes allowlist.auto.tfvars
```

### Section 5: Daily Flow

```bash
# Bake AMI + auto-handoff to Terraform (Phase 3 REP-04, REP-05)
make packer-bake DEVBOX_USER=$(whoami)

# Provision EC2 (idempotent — bumps to new AMI if changed)
make tg-apply DEVBOX_USER=$(whoami)

# Start the instance (when ready to work)
make start

# Connect — preferred path is SSM (Phase 2 NET-04 hybrid posture)
make devbox-ssm               # shell session via SSM
make devbox-port-forward      # forward :8080 to localhost over SSM
# OR: browse to https://<host>:8080 (code-server) — gated by allowed_web_cidrs

# Get your per-user code-server and VNC passwords
make secrets-show             # reads /devbox/${DEVBOX_USER}/* from SSM Parameter Store

# When done for the day
make stop
```

### Section 6: Rotations
- **SSH key:** `aws ec2 delete-key-pair --key-name ${USER}-devbox && aws ec2 import-key-pair ...` then `make tg-apply` to push the new public key.
- **Secrets:** Re-bake the AMI (`make packer-bake`) — secrets role generates fresh per-build; replaces SSM parameters.
- **CIDR allowlist:** Re-run `make devbox-allowlist-me`; commits a new `allowlist.auto.tfvars` (gitignored).

### Section 7: Troubleshooting
- **`session-manager-plugin: command not found`**: `brew install --cask session-manager-plugin` (macOS) or download from AWS docs.
- **`tofu: command not found`**: `brew install opentofu` (do NOT install `terraform` — see Phase 3 lockfile policy).
- **AMI not found error on `tg-apply`**: Run `make packer-bake DEVBOX_USER=$(whoami)` first — writes the AMI ID into `users/${USER}.auto.tfvars` which Terraform auto-loads.
- **Lockfile checksum mismatch** (`tofu init`): `cd terraform/ && rm -rf .terraform/ && tofu init` (Phase 3 plan-01 summary "Operator Migration Note").
- **firewalld blocking ports inside the AMI**: see `ansible/firewalld-docker-fix.yml` header — this is a known workaround.
- **`pre-commit run --all-files` slow on first run**: `pre-commit install --install-hooks` pre-warms; subsequent runs are fast.

### Section 8: Invariants — Do Not Violate
- **`hardening` MUST be the last role in `ansible/playbook.yml`** (Phase 3 CONCERNS.md MEDIUM; convention is enforced only by comment — do not insert any role after it)
- **Lockfile (`terraform/.terraform.lock.hcl`) MUST stay committed and MUST NOT be re-added to `.gitignore`** (Phase 3 REP-01)
- **Action SHA-pin policy:** every `uses: org/repo@...` in `.github/workflows/*` MUST be 40-char hex SHA, never a tag
- **Packer source AMI MUST stay pinned via SSM parameterstore** (Phase 3 REP-04; CI greps `most_recent = true` as regression)
- **`changeme` literal MUST NOT appear in any tracked code file** (Phase 1 SEC-01/02; pre-commit `no-changeme` hook enforces)

### Section 9: Known Follow-Ups
- Packer SSM parameter `:NN` version pin (Phase 3 REP-04 deferred — needs AWS creds to resolve current version; see `packer/devimage.pkr.hcl` lines 19-31 for the bump procedure)

## DOC-02 Expansion: `ansible/firewalld-docker-fix.yml` header

The existing FIXME header (lines 2-25 of `ansible/firewalld-docker-fix.yml`) already covers WHAT and WHY. DOC-02 needs to expand the **WHEN-TO-RETIRE** criteria into explicit, testable conditions:

**Add a new section to the header comment:**

```yaml
# Retirement criteria — this play SHOULD be deleted when ANY of:
#   (1) The CIS scan requirement that demands `firewalld present and running`
#       is lifted from this project's hardening posture. Today, the AL2023 CIS
#       role's defaults (ansible/roles/AMAZON2023-CIS/defaults/) require firewalld
#       to be installed. If a future CIS profile relaxes this, OR we switch to a
#       different hardening baseline (e.g., DISA STIG), this workaround is moot —
#       remove firewalld entirely and rely on the EC2 SG. This matches the comment
#       at ansible/roles/hardening/defaults/main.yml lines 4-13.
#
#   (2) The `containers` layer is removed from `ansible/layer_config.yml`. Without
#       Docker, no `docker` zone is registered, the default-zone-to-docker rewrite
#       is moot, and the host can stay on the stock `public` zone. Remove this play.
#
#   (3) Per-port allowances are added to the `public` zone (option (a) from line
#       14 above) inside the `roles/hardening` role itself — e.g., a
#       firewalld_port: list iterated over with the firewalld module. Once those
#       are in place, this workaround is redundant; delete it.
#
# Verification of retirement: after removing this play, `make packer-bake` must
# succeed and the resulting AMI's `firewall-cmd --get-default-zone` must be
# either `public` (option a) or the firewalld package must be absent (option b).
# Either is acceptable; the workaround state (default zone = docker) is NOT.
```

This satisfies DOC-02 by making retirement testable rather than aspirational.

## Sources

### Primary (HIGH confidence)
- [GitHub Security Hardening for Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions) — "SHA-pin actions" is GitHub's official guidance
- [pre-commit framework docs](https://pre-commit.com/) — `default_stages`, `stages` per-hook, pre-push hook type
- [GitHub Actions workflow-syntax docs](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions) — `paths-ignore` semantics
- [Checkov hard-and-soft-fail docs](https://www.checkov.io/2.Basics/Hard%20and%20soft%20fail.html) — `--hard-fail-on HIGH` semantics
- [Checkov suppressing docs](https://www.checkov.io/2.Basics/Suppressing%20and%20Skipping%20Policies.html) — `--skip-check`, `.checkov.yaml`
- GitHub REST API `git/refs/tags` — used to resolve all action SHAs to 40-char commits (verified live 2026-05-14)
- Phase 1 plan-03 SUMMARY — establishes SHA-pin policy and `gitleaks` v8.30.1
- Phase 3 plan-01 SUMMARY — establishes 6 CI grep gates this phase must wire (lines 134-144)
- Phase 3 plan-02 SUMMARY — establishes 3 additional Packer-specific CI grep gates (lines 174-182)

### Secondary (MEDIUM confidence)
- [tfsec is now part of Trivy (archived)](https://github.com/aquasecurity/tfsec) — tfsec deprecation
- [Trivy supply chain incident 2026-03-19 conclusion](https://github.com/aquasecurity/trivy/discussions/10462) — Trivy compromise + remediation
- [Wiz blog: Trivy Compromised by TeamPCP](https://www.wiz.io/blog/trivy-compromised-teampcp-supply-chain-attack) — incident summary
- [Arctic Wolf: TeamPCP campaign targets Trivy, Checkmarx KICS, LiteLLM](https://arcticwolf.com/resources/blog/teampcp-supply-chain-attack-campaign-targets-trivy-checkmarx-kics-and-litellm-potential-downstream-impact-to-additional-projects/) — confirms Checkov NOT in the attack scope
- [tofuutils/pre-commit-opentofu](https://github.com/tofuutils/pre-commit-opentofu) — OpenTofu-native fork; v2.3.0 released 2026-04-21
- [antonbabenko/pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform) — terragrunt hooks; v1.105.0
- [ansible-lint releases](https://github.com/ansible/ansible-lint/releases) — v26.4.0 current
- [ansible-lint configuration docs](https://ansible.readthedocs.io/projects/lint/configuring/) — `exclude_paths` semantics

### Tertiary (LOW confidence — verified only by single source)
- Operator-workstation tool versions (gitleaks 8.30.1, pre-commit 4.6.0, shellcheck 0.11.0, tofu 1.10.6, packer 1.12.0, terragrunt 0.81.10) — verified once via `command -v` + `--version` on 2026-05-14

## Metadata

**Confidence breakdown:**
- Standard stack (versions + SHAs): HIGH — every SHA verified live via `curl https://api.github.com/repos/.../git/refs/tags/<tag>` on 2026-05-14
- Architecture (job layout, tiered hooks): HIGH — both patterns are textbook GH Actions / pre-commit usage; rationales drawn from official docs
- Pitfalls: MEDIUM — most are documented in official sources; some (Pitfall 8 self-referential workflow) are reasoned from the TeamPCP attack pattern
- Tool selection (Checkov over Trivy/tfsec): HIGH — the supply-chain reasoning is grounded in 6 independent secondary sources

**Research date:** 2026-05-14
**Valid until:** 2026-06-14 (30-day window for stable IaC tooling; sooner if a Checkov supply-chain incident emerges — re-verify before any Phase 4 plan land)
