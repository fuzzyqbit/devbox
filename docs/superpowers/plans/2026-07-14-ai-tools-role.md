# `ai-tools` Role Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake three agentic AI coding CLIs (Claude Code, OpenAI Codex CLI, opencode) into the devbox AMI as version-pinned npm globals, per the approved spec `docs/superpowers/specs/2026-07-14-agentic-ai-tools-design.md`.

**Architecture:** New self-contained Ansible role `ansible/roles/ai_tools/` (defaults + tasks) that dnf-installs nodejs20, npm-installs the three pinned packages to `/usr/local`, and bake-asserts each binary (stat + `--version`). Wired into `ansible/playbook.yml` after `devtools` / before `secrets`, gated on `layers.ai_tools`.

**Tech Stack:** Ansible (ansible-core ≥ 2.16, FQCN modules only), AL2023 dnf (`nodejs20`, `nodejs20-npm`), npm global installs, ansible-lint (production profile), GitHub Actions CI (9-check gate), `gh` CLI for PR flow.

## Global Constraints

- `hardening` MUST remain the LAST role in `ansible/playbook.yml` (CLAUDE.md §8 invariant; grep-gated). The new role entry goes after `devtools`, before `secrets` — nowhere near the bottom.
- Version pins (re-verify against registry.npmjs.org at implementation time, Task 1 Step 1): `@anthropic-ai/claude-code@2.1.209`, `@openai/codex@0.144.4`, `opencode-ai@1.17.20`.
- NO auth baked: no API keys, no provider config, no Bedrock IAM, no SSM plumbing (CLAUDE.md §8 secrets invariant). Runtime login only.
- The literal string `changeme` MUST NOT appear in any tracked file (grep-gated).
- ansible-lint production profile: 0 failures. CI pins ansible-lint 26.4.0; system ansible-lint is the fast local check, the venv recipe (Task 3 Step 1) is CI-exact.
- ansible-lint `name[template]` rule: Jinja expressions only at the END of a task `name:`. No-Jinja names are safest.
- `ansible.builtin.command` tasks need `creates:`/`removes:` or `changed_when:` (lint `no-changed-when`).
- Git: run `git commit` as its OWN Bash call (block-no-verify hook false-positives on chained commands). Conventional-commit format, no attribution footer.
- PR body via `--body-file <file>` (heredoc-in-`--body` breaks on shell quoting). Write the body to `$CLAUDE_JOB_DIR/tmp/` or a scratchpad file first.
- `gh pr checks` can show hung jobs as "pending 0" — verify via `gh api .../check-runs` `.steps[]` if a check looks stuck.
- Branch: all work on `feat/ai-tools-role` (already exists, currently @ `36ed114`).
- Do NOT install pre-commit hooks in this clone; do NOT chase the known `no-changeme` false-positive on `ansible/roles/secrets/tasks/generate.yml` — it is pre-existing and latent.

---

### Task 1: Role files — `defaults/main.yml` + `tasks/main.yml`

**Files:**
- Create: `ansible/roles/ai_tools/defaults/main.yml`
- Create: `ansible/roles/ai_tools/tasks/main.yml`
- Test: ansible-lint over the role directory (IaC — lint/syntax IS the test cycle; the in-file asserts are the bake-time tests)

**Interfaces:**
- Consumes: nothing from other tasks. AL2023 repo packages `nodejs20`, `nodejs20-npm` (same names the `devtools` role installs — `ansible/roles/devtools/defaults/main.yml:3-4`).
- Produces: role directory name `ai_tools` (referenced by Task 2's `role: ai_tools` playbook entry); defaults vars `ai_tools_claude_code_version`, `ai_tools_codex_version`, `ai_tools_opencode_version`, `ai_tools_npm_prefix`; installed binaries `/usr/local/bin/{claude,codex,opencode}` on the image.

- [ ] **Step 1: Re-verify the three npm pins (freshness check)**

The spec pins were resolved 2026-07-14. Confirm they are still current before committing them:

```bash
npm view @anthropic-ai/claude-code version
npm view @openai/codex version
npm view opencode-ai version
```

Expected: `2.1.209`, `0.144.4`, `1.17.20`. If the registry shows newer versions, use the NEWER version strings in Step 2 (latest-at-implementation is the pin policy; note the bump in the Task 1 commit message). If a package name 404s, STOP — do not guess an alternate name; report back.

- [ ] **Step 2: Write `ansible/roles/ai_tools/defaults/main.yml`**

```yaml
---
# Agentic AI coding CLIs — one pinned version per tool (repo pin invariant).
# [VERIFIED: registry.npmjs.org — 2026-07-14]
# Bump procedure: `npm view <pkg> version`, update the pin, rebake.
ai_tools_claude_code_version: "2.1.209" # @anthropic-ai/claude-code
ai_tools_codex_version: "0.144.4" # @openai/codex
ai_tools_opencode_version: "1.17.20" # opencode-ai

# npm global prefix: binaries land in <prefix>/bin, packages in <prefix>/lib/node_modules.
# /usr/local keeps the rpm-owned /usr tree clean (same target as the other hand-installed
# tools: kubectl, helm, mise, syft).
ai_tools_npm_prefix: /usr/local
```

Deliberate deviation from the spec's defaults sketch: `dev_user` / `dev_home` are OMITTED — no task in this role references them (YAGNI; other roles carry them only because their tasks write into `~/.bashrc`).

If Step 1 returned newer versions, substitute them and update the `[VERIFIED: …]` date to the actual check date.

- [ ] **Step 3: Write `ansible/roles/ai_tools/tasks/main.yml`**

```yaml
---
# Agentic AI coding CLIs (Claude Code, OpenAI Codex CLI, opencode) baked as pinned
# npm globals (design: docs/superpowers/specs/2026-07-14-agentic-ai-tools-design.md).
# NO auth is baked (CLAUDE.md §8 secrets invariant): operators authenticate at
# runtime (claude/codex/opencode login flows); credentials land under
# /home/ec2-user on the persistent EBS volume and survive AMI swaps.
# Self-contained: installs nodejs20 itself rather than depending on the devtools
# layer toggle (which happens to install the same packages — dnf is idempotent).

- name: Install the nodejs runtime for the AI CLIs
  ansible.builtin.dnf:
    name:
      - nodejs20
      - nodejs20-npm
    state: present

# NOTE [ASSUMED, confirmed-at-first-bake]: AL2023's nodejs20/nodejs20-npm packages
# register `node`/`npm` via alternatives. If the first bake fails here with
# "npm: command not found", switch cmd to `npm-20` (the versioned binary name).
- name: Install the pinned AI CLI npm packages
  ansible.builtin.command:
    cmd: >-
      npm install -g --prefix {{ ai_tools_npm_prefix }}
      {{ item.pkg }}@{{ item.pin }}
    creates: "{{ ai_tools_npm_prefix }}/lib/node_modules/{{ item.pkg }}"
  loop:
    - { pkg: "@anthropic-ai/claude-code", pin: "{{ ai_tools_claude_code_version }}" }
    - { pkg: "@openai/codex", pin: "{{ ai_tools_codex_version }}" }
    - { pkg: "opencode-ai", pin: "{{ ai_tools_opencode_version }}" }
  loop_control:
    label: "{{ item.pkg }}"

- name: Remove the root npm cache (image hygiene)
  ansible.builtin.file:
    path: /root/.npm
    state: absent

# ── Bake-asserts (dcv/xrdp bake-green-but-broken pattern) ──
# Stat proves npm linked each binary into <prefix>/bin; --version proves the
# binary actually executes on AL2023 (node ABI, bundled platform deps). A broken
# install fails the bake loudly here instead of shipping a dead CLI.

- name: Stat the installed AI CLI binaries (bake-assert)
  ansible.builtin.stat:
    path: "{{ ai_tools_npm_prefix }}/bin/{{ item }}"
  register: ai_tools_bake_bins
  loop:
    - claude
    - codex
    - opencode

- name: Assert every AI CLI binary exists (bake-assert)
  ansible.builtin.assert:
    that:
      - item.stat.exists
    fail_msg: >-
      {{ item.item }} is missing from {{ ai_tools_npm_prefix }}/bin after the npm
      install — npm did not link the binary. Check the npm --prefix bin layout
      ({{ ai_tools_npm_prefix }}/lib/node_modules vs bin symlinks) and the package's
      "bin" field.
    quiet: true
  loop: "{{ ai_tools_bake_bins.results }}"
  loop_control:
    label: "{{ item.item }}"

- name: Run each AI CLI --version (bake-assert)
  ansible.builtin.command:
    cmd: "{{ ai_tools_npm_prefix }}/bin/{{ item }} --version"
  changed_when: false
  loop:
    - claude
    - codex
    - opencode
```

- [ ] **Step 4: Lint the role**

```bash
ansible-lint ansible/roles/ai_tools/
```

Expected: `Passed: 0 failure(s), 0 warning(s)` (production profile — repo config applies). If `name[template]` fires, a task name has mid-string Jinja — reword so any Jinja sits at the end (or remove it). If `no-changed-when` fires, a `command:` task lost its `creates:`/`changed_when:` — restore it.

- [ ] **Step 5: Commit**

```bash
git add ansible/roles/ai_tools/
```

Then, as its OWN Bash call:

```bash
git commit -m "feat(ai-tools): role baking pinned agentic AI CLIs (claude, codex, opencode)"
```

Verify: `git log --oneline -1` shows the commit on `feat/ai-tools-role`.

---

### Task 2: Wiring — `playbook.yml` role entry + `layer_config.yml` toggle

**Files:**
- Modify: `ansible/playbook.yml:51-57` (insert between the `devtools` and `secrets` entries)
- Modify: `ansible/layer_config.yml:23` (insert after the `devtools: true` line)
- Test: `ansible-playbook --syntax-check` on the full import chain + `ansible-lint` on the playbook

**Interfaces:**
- Consumes: role directory `ai_tools` and its defaults (Task 1).
- Produces: `layers.ai_tools` toggle consumed by the playbook gate; the complete, lintable playbook Task 3 ships.

- [ ] **Step 1: Insert the role entry in `ansible/playbook.yml`**

Current context (lines 51–57):

```yaml
    - role: devtools
      when: layers.devtools | default(false)

    - role: secrets
      when: >-
        (layers.vscode | default(false)) or
        (layers.desktop | default(false))
```

Insert between them, so the block reads:

```yaml
    - role: devtools
      when: layers.devtools | default(false)

    - role: ai_tools
      when: layers.ai_tools | default(false)
      # Agentic AI coding CLIs (claude, codex, opencode) as pinned npm globals in
      # /usr/local. Self-contained (installs nodejs20 itself, no devtools dependency).
      # NO auth baked — operators log in at runtime; creds persist on the /home EBS
      # volume. MUST stay before hardening (last-role invariant).

    - role: secrets
      when: >-
        (layers.vscode | default(false)) or
        (layers.desktop | default(false))
```

Do NOT touch anything at or below the `hardening` entry.

- [ ] **Step 2: Add the layer toggle in `ansible/layer_config.yml`**

Current context (line 23):

```yaml
  devtools: true
```

Change to:

```yaml
  devtools: true
  # ai_tools bakes the agentic AI coding CLIs (claude, codex, opencode) as pinned
  # npm globals — no auth baked, operators log in at runtime.
  ai_tools: true
```

(Role dir and layers key are both `ai_tools` — the role-name lint rule forbids dashes; maintainer decision 2026-07-14.)

- [ ] **Step 3: Syntax-check the full import chain**

```bash
ansible-playbook --syntax-check ansible/playbook.yml
```

Expected output ends with:

```
playbook: ansible/playbook.yml
```

- [ ] **Step 4: Lint the full playbook**

```bash
ansible-lint ansible/playbook.yml
```

Expected: `Passed: 0 failure(s), 0 warning(s)`.

- [ ] **Step 5: Verify the hardening-last invariant survived**

```bash
grep -n "    - role:" ansible/playbook.yml | tail -3
```

Expected: `hardening` is the last `- role:` line (dcv, xrdp, hardening — ai-tools appears well above). If hardening is not last, the edit landed in the wrong place — fix before committing.

- [ ] **Step 6: Commit**

```bash
git add ansible/playbook.yml ansible/layer_config.yml
```

Then, as its OWN Bash call:

```bash
git commit -m "feat(ai-tools): wire role into playbook and layer_config (gated layers.ai_tools)"
```

---

### Task 3: CI-exact validation, PR, merge

**Files:**
- Create: `$CLAUDE_JOB_DIR/tmp/pr-body-ai-tools.md` (PR body scratch file, not tracked)
- Modify: `/Users/me/.claude/projects/-Users-me-Documents-code-devbox/memory/project_unmerged_milestone_backlog.md` (merge ledger, after merge)

**Interfaces:**
- Consumes: the two commits from Tasks 1–2 on `feat/ai-tools-role`.
- Produces: merged main; updated merge ledger.

- [ ] **Step 1: CI-exact lint (venv recipe, worked 2026-07-13)**

```bash
uv venv --python /opt/homebrew/bin/python3.13 /tmp/lintenv
uv pip install --python /tmp/lintenv/bin/python ansible-lint==26.4.0 ansible-core
/tmp/lintenv/bin/ansible-galaxy collection install -r ansible/requirements.yml -p /tmp/collections
ANSIBLE_COLLECTIONS_PATH=/tmp/collections /tmp/lintenv/bin/ansible-lint ansible/playbook.yml
```

Expected: `Passed: 0 failure(s), 0 warning(s)`. (Skip the checkov line from the recipe — no terraform/ changes in this feature.) If `/tmp/lintenv` already exists from a prior run, reuse it — just run the last line.

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feat/ai-tools-role
```

Expected: branch created on origin. (Branch contains spec commit `2a98f4b` + handoff WIP `36ed114` + Tasks 1–2 commits — all intentional.)

- [ ] **Step 3: Create the PR (body via file — never inline heredoc)**

Write `$CLAUDE_JOB_DIR/tmp/pr-body-ai-tools.md`:

```markdown
## Summary
- New `ansible/roles/ai_tools/` role: bakes three agentic AI coding CLIs as pinned npm globals in `/usr/local` — `@anthropic-ai/claude-code@2.1.209` (`claude`), `@openai/codex@0.144.4` (`codex`), `opencode-ai@1.17.20` (`opencode`)
- Self-contained: role dnf-installs nodejs20 + nodejs20-npm itself (idempotent overlap with devtools)
- NO auth baked (secrets invariant): runtime login only; credentials persist on the /home EBS volume
- Bake-asserts per binary (stat + `--version`) — bake-green-but-broken guard, dcv/xrdp pattern
- Wired after `devtools` / before `secrets`, gated `layers.ai_tools` (default on); hardening stays last
- Design spec: `docs/superpowers/specs/2026-07-14-agentic-ai-tools-design.md`

## Test plan
- [x] `ansible-lint` production profile: 0 failures (system + CI-exact 26.4.0 venv)
- [x] `ansible-playbook --syntax-check` on full import chain
- [ ] Real bake (deferred with the other first-bake items): three `--version` asserts run in-bake; syft SBOM catalogs the npm globals automatically
```

(Adjust version strings if Task 1 Step 1 bumped the pins.) Then:

```bash
gh pr create --title "feat(ai-tools): bake agentic AI CLIs (claude, codex, opencode)" \
  --body-file "$CLAUDE_JOB_DIR/tmp/pr-body-ai-tools.md" --base main
```

Expected: PR URL printed (PR #6 if nothing else landed).

- [ ] **Step 4: Watch the 9-check CI gate**

```bash
gh pr checks <PR#> --watch --interval 30
```

Expected all 9 green: fmt-check, gitleaks ×2, grep-gates, packer-validate, shellcheck, checkov, tofu-validate, ansible-syntax-check, ansible-lint. If a check sits "pending 0" for >5 min, don't trust it — inspect the run's steps:

```bash
gh api repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/check-runs --jq '.check_runs[] | {name, status, conclusion}'
```

Fix any red check, commit (own Bash call), push, re-watch.

- [ ] **Step 5: Merge (merge-commit style, matching PR #4/#5)**

```bash
gh pr merge <PR#> --merge --subject "Merge feat/ai-tools-role: bake agentic AI CLIs (claude, codex, opencode)"
```

Then watch main CI:

```bash
gh run list --branch main --limit 1
gh run watch <run-id> --interval 30
```

Expected: main CI green.

- [ ] **Step 6: Update the merge ledger memory**

Edit `/Users/me/.claude/projects/-Users-me-Documents-code-devbox/memory/project_unmerged_milestone_backlog.md`:
- Add under the merged entries: `**Merged to \`main\` 2026-07-14 (\`<merge-sha>\`, PR #<PR#>):** feat/ai-tools-role — ai-tools role bakes @anthropic-ai/claude-code <pin>, @openai/codex <pin>, opencode-ai <pin> as npm globals in /usr/local; bake-asserts per binary; no auth baked.`
- Add to the "First-bake deferred pins" bullet: `ai-tools --version asserts never bake-exercised (npm alternatives assumption, headless execution on AL2023)`.

Use the real merge SHA from `git log origin/main --oneline -1` after merge. No commit needed (memory files are outside the repo).

---

## Self-Review (performed at plan-writing time)

**Spec coverage:** defaults w/ 3 pins + prefix → Task 1 Step 2. dnf nodejs20 self-contained → Task 1 Step 3 (task 1 of the file). Three pinned npm installs with `creates:` guards on `/usr/local/lib/node_modules/<pkg>` (scoped `@org/name` paths work — npm creates the `@org/` directory) → Task 1 Step 3. Bake-asserts stat + `--version` → Task 1 Step 3. Playbook wiring after devtools/before secrets, gated → Task 2 Step 1. `layer_config.yml` `ai_tools: true` + comment → Task 2 Step 2. Nothing-baked auth → no task touches keys/IAM/SSM (constraint, not code). Testing section (lint, syntax-check, 9-check CI) → Tasks 1–3. Delivery (branch → PR → 9/9 → merge) → Task 3. Out-of-scope items: no task touches `./run`, MCP config, or dotfiles. ✔ No gaps.

**Deviations from spec (deliberate, minor):** `dev_user`/`dev_home` omitted from defaults (unused in this role); added `/root/.npm` cleanup task (image hygiene, matches the repo's clean-up-after-install convention); pins may be bumped at Task 1 Step 1 (spec's own bump procedure).

**Placeholder scan:** every code step carries full file/block content; commands carry expected output. `<PR#>`/`<merge-sha>`/`<run-id>` are runtime values resolved by earlier steps in the same task, not placeholders. ✔

**Type consistency:** var names identical across defaults, tasks, and prose (`ai_tools_claude_code_version`, `ai_tools_codex_version`, `ai_tools_opencode_version`, `ai_tools_npm_prefix`); register names `ai_tools_bake_bins` used once; role dir and layers key both `ai_tools`. ✔
