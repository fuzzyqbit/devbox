---
phase: quick-260724-dh7-add-dnf-versionlock-and-lock-salt-minion
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ansible/roles/base/tasks/main.yml
  - ansible/roles/base/defaults/main.yml
autonomous: true
requirements:
  - VLOCK-01   # dnf versionlock capability installed EARLY in the base role — before the full-image update
  - VLOCK-02   # salt-minion locked to its currently-installed version; clean conditional no-op when absent
  - VLOCK-03   # static gates stay green: syntax check, CI-exact ansible-lint v26.4.0, grep-gates, scoped no-changeme

must_haves:
  truths:
    - "The versionlock plugin install AND the salt-minion lock run BEFORE the 'Update all packages' task in ansible/roles/base/tasks/main.yml — the full-image `state: latest` update can never bump salt-minion past the lock."
    - "On a source AMI that ships salt-minion, the bake locks salt-minion to the version present at bake START (pre-update), and the subsequent full-image update excludes it (versionlock plugin is honored by the dnf API the ansible.builtin.dnf module uses)."
    - "On the public AL2023 minimal AMI (no salt-minion), the bake completes cleanly: the lock task skips per-item and a debug task states WHY — no failure, no lock entry."
    - "Re-running the role against an already-locked salt-minion neither fails the play nor reports perpetual change (changed_when keyed on the dnf4 'Adding versionlock on:' output line)."
    - "The lock is baked into the AMI (/etc/dnf/plugins/versionlock.list), so runtime `dnf update` on launched instances also excludes salt-minion until an operator deliberately unlocks or rebakes."
    - "GPG verification stays ON for the plugin install (dnf defaults; no disable_gpg_check: true anywhere — CLAUDE.md §8 posture)."
  artifacts:
    - path: "ansible/roles/base/tasks/main.yml"
      provides: "versionlock block (comment header + plugin install + package_facts + conditional lock loop + absent-package debug) as the FIRST tasks of the role"
      contains: "python3-dnf-plugin-versionlock"
    - path: "ansible/roles/base/defaults/main.yml"
      provides: "dnf_versionlock_packages list (salt-minion) with the source-AMI story documented"
      contains: "dnf_versionlock_packages"
  key_links:
    - from: "ansible/roles/base/tasks/main.yml"
      to: "ansible/roles/base/defaults/main.yml"
      via: "lock loop iterates dnf_versionlock_packages"
      pattern: "dnf_versionlock_packages"
    - from: "Lock packages task"
      to: "package_facts gather"
      via: "per-item presence gate so a salt-minion-less AMI no-ops"
      pattern: "item in ansible_facts.packages"
    - from: "versionlock block"
      to: "Update all packages task"
      via: "file order — lock tasks appear at LOWER line numbers than the full-image update"
      pattern: "awk ordering check in Task 1 acceptance_criteria"
---

<objective>
Add dnf version-lock capability to the devbox AMI and lock `salt-minion` to whatever
version is installed when the bake starts — positioned as the FIRST tasks of the `base`
role, BEFORE the full-image `dnf update` (`name: "*"` / `state: latest`) that is currently
the role's first task.

Purpose: salt-minion is not installed by any role in this repo (verified — zero grep hits);
it ships on the org's source AMI or arrives at runtime. The operator wants its version
frozen at bake start. Ordering is the point of this task: a lock created AFTER the
full-image update would capture the already-updated version — wrong. The lock must exist
before the updater runs.

Output: a versionlock block at the top of `ansible/roles/base/tasks/main.yml`, a
`dnf_versionlock_packages` list in `ansible/roles/base/defaults/main.yml`, static
verification green (syntax, CI-exact ansible-lint v26.4.0, grep-gates). No live bake in
this task — bake-time behavior is proven on the next `./run build` (open live-UAT backlog).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@ansible/roles/base/tasks/main.yml
@ansible/roles/base/defaults/main.yml
@.pre-commit-config.yaml

<versionlock_facts>
Authoritative dnf4/AL2023 versionlock mechanics the executor must rely on (do NOT re-derive):

- PLUGIN PACKAGE: `python3-dnf-plugin-versionlock` — the dnf4 subpackage name in the
  AL2023 / EL9 / Fedora family (AL2023 ships dnf 4.x for its lifetime; the dnf5-era naming
  does not apply here). Installs the `versionlock` dnf subcommand and the lock file
  `/etc/dnf/plugins/versionlock.list`. It lives in the AL2023 core repo (Amazon-signed;
  GPG check stays ON — dnf module default, no `disable_gpg_check`). If a future AMI ever
  reports "no match", the provider-agnostic fallback spec is `dnf-command(versionlock)` —
  record that ONLY as a comment in the header block, do not code a fallback path (YAGNI).
- LOCK SEMANTICS: `dnf versionlock add salt-minion` pins the CURRENTLY INSTALLED
  version (writes an entry like `salt-minion-0:<ver>-<rel>.*`). Exactly the request.
- OUTPUT / IDEMPOTENCY: on a NEW lock, dnf4 prints `Adding versionlock on: <nevra>` to
  stdout and exits 0. On an ALREADY-LOCKED package it exits 0 WITHOUT printing that line —
  so `changed_when` keyed on the substring `'Adding versionlock on:'` is both the change
  signal and the idempotency guard. Belt-and-braces `failed_when` additionally tolerates
  any "already locked" wording, mirroring the curl-swap idiom already in this file.
- MISSING PACKAGE: `dnf versionlock add <absent-pkg>` FAILS (rc != 0, "no package found").
  This is why the per-item `when: item in ansible_facts.packages` gate is load-bearing —
  a bake from the public AL2023 minimal AMI has no salt-minion and must no-op cleanly.
- PLUGIN IS HONORED BY THE UPDATE TASK: `ansible.builtin.dnf` drives the dnf Python API
  with plugins loaded by default. The versionlock plugin filters the sack, so the existing
  `Update all packages` task (`name: "*"` / `state: latest`) will exclude locked packages.
  Do NOT add `disable_plugin`/`enable_plugin` to any task in this role.
- NO MODULE SUPPORT: there is no ansible dnf-module parameter for versionlock —
  `ansible.builtin.command` is correct. Precedent in this very file: the
  "Swap curl-minimal for full curl" task runs `dnf swap` via command with no noqa and is
  lint-green at v26.4.0 (command-instead-of-module does not fire on non-module dnf
  subcommands). Expect the same for `versionlock`; only if the pinned linter flags it, add
  `# noqa: command-instead-of-module` with a trailing justification comment.
</versionlock_facts>

<lint_baseline_facts>
From STATE.md (16-01 execution decisions) and .pre-commit-config.yaml — scope discipline
for Task 2:

- REPO-WIDE runs of the push-stage ansible-lint hook and of `pre-commit run --all-files`
  (no-changeme, trailing-whitespace) are PRE-EXISTING-RED on content blame-proven to
  predate this task. Do not chase those; do not widen scope to "fix" them.
- The CI-AUTHORITATIVE green scopes are: `grep-gates` (safe to run whole),
  gitleaks, and `ansible-lint ansible/playbook.yml` with the PINNED v26.4.0 binary
  (the upstream pre-commit ansible-lint hook is pass_filenames:false → repo-wide → red;
  invoke the binary directly instead, scoped to the playbook, which lints roles/base
  transitively).
- `check-yaml` excludes `ansible/*.yml` entirely — not applicable to this change.
- grep-gates gate 9 (hardening last role) and gate 8 (no retired `make <target>` phrases)
  are unaffected: this change touches only roles/base files and its comments must avoid
  phrases matching gate 8 (do not write e.g. "make" followed by a former target name).
</lint_baseline_facts>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Insert the versionlock block as the FIRST tasks of the base role and add the dnf_versionlock_packages default</name>
  <files>ansible/roles/base/tasks/main.yml, ansible/roles/base/defaults/main.yml</files>
  <read_first>
    - ansible/roles/base/tasks/main.yml — full file. Note: "Update all packages" (dnf
      name:"*" state:latest, `# noqa: package-latest`) is currently the FIRST task; the new
      block goes ABOVE it. Note the curl-swap idiom (register + changed_when substring +
      tolerant failed_when) at lines 8-14 — mirror it. Note the EXISTING package_facts
      gather at line ~27 for the SPAL floor gate — it must STAY (see action).
    - ansible/roles/base/defaults/main.yml — placement/comment style for the new list var.
    - The <versionlock_facts> block in this plan — plugin name, output strings, gates.
  </read_first>
  <action>
Edit `ansible/roles/base/tasks/main.yml`: insert a new block immediately after the leading
`---`, BEFORE the "Update all packages" task (per orchestrator-locked constraint: ordering
is the point — the lock must predate the full-image update). The block, in order:

1. A comment header (repo idiom: the `# --- ... ---` block style used for the SPAL section
   in this same file) explaining WHY: (a) ORDERING — the next task is the bake-time
   full-image update; a lock created after it would capture the post-update version, so
   this block MUST stay first in the role; (b) SOURCE-AMI STORY — no role in this repo
   installs salt-minion; it ships on the org's source AMI (or arrives at runtime), so the
   lock is conditional and a bake from the public AL2023 minimal AMI no-ops cleanly;
   (c) PLUGIN NAME — `python3-dnf-plugin-versionlock` is the dnf4 subpackage name on the
   AL2023/EL9 family; provider-agnostic fallback spec `dnf-command(versionlock)` noted as
   a comment only; (d) UNLOCK/REMEDIATION — `dnf versionlock delete salt-minion` then
   update, or rebake (the lock re-captures the source AMI's version at next bake). Wording
   MUST NOT contain "versionlock add" (keeps the Task-1 awk ordering check anchored to the
   task names, not prose) and MUST NOT contain "make " followed by a former Makefile target
   name (grep-gates gate 8).

2. Task `- name: Install dnf versionlock plugin` — `ansible.builtin.dnf` with
   `name: python3-dnf-plugin-versionlock`, `state: present`. Nothing else: GPG check is
   the dnf default (ON); do NOT add `disable_gpg_check` at all (CLAUDE.md §8).

3. Task `- name: Gather package facts for the versionlock gate` —
   `ansible.builtin.package_facts` with `manager: auto`. Add a short comment: this
   pre-update gather feeds the per-item presence gate below; the LATER package_facts
   gather for the SPAL floor (already in this file) must NOT be deduplicated away — it
   deliberately re-collects POST-update facts for the system-release floor assert.

4. Task `- name: Lock packages to their currently installed versions` —
   `ansible.builtin.command` with `cmd: dnf versionlock add {{ item }}`,
   `loop: "{{ dnf_versionlock_packages }}"`,
   `when: item in ansible_facts.packages`,
   `register: versionlock_add`,
   `changed_when: "'Adding versionlock on:' in versionlock_add.stdout"`,
   `failed_when: versionlock_add.rc != 0 and 'already locked' not in (versionlock_add.stdout + versionlock_add.stderr)`.
   (Per <versionlock_facts>: 'Adding versionlock on:' prints only on a NEW lock — this is
   the idempotency key; the `when` gate prevents the rc!=0 "no package found" failure on
   AMIs without salt-minion; the failed_when mirrors the curl-swap tolerance idiom.)
   Expect NO noqa needed (precedent: the `dnf swap` command task in this file is lint-green
   without one); only if the pinned v26.4.0 linter flags command-instead-of-module, append
   `# noqa: command-instead-of-module` plus a justification comment (no dnf-module support
   for versionlock).

5. Task `- name: Note packages absent from this source AMI (versionlock skipped)` —
   `ansible.builtin.debug` with a msg templating `{{ item }}` and stating the skip is
   expected on the public AL2023 minimal AMI (salt-minion comes from the org source AMI),
   `loop: "{{ dnf_versionlock_packages }}"`, `when: item not in ansible_facts.packages`.

Edit `ansible/roles/base/defaults/main.yml`: add, after the `spal_min_system_release`
block and before `base_packages`, a commented `dnf_versionlock_packages` list containing
the single entry `salt-minion`. Comment states: locked to whatever version is installed at
bake START (before the full-image update — ordering story in the tasks/main.yml header);
packages absent from the source AMI are skipped, not failed.

Style: FQCN modules, sentence-case task names, two-space indent, no fenced templating —
match the surrounding file exactly. Do NOT touch any existing task, the playbook, or any
other role. Do NOT commit — the orchestrator commits.
  </action>
  <verify>
    <automated>cd /Users/me/Documents/code/devbox && awk '/^- name: Install dnf versionlock plugin$/{v=NR} /^- name: Lock packages to their currently installed versions$/{l=NR} /^- name: Update all packages/{u=NR} END{exit !(v && l && u && v<u && l<u)}' ansible/roles/base/tasks/main.yml && grep -q 'python3-dnf-plugin-versionlock' ansible/roles/base/tasks/main.yml && grep -q 'Adding versionlock on:' ansible/roles/base/tasks/main.yml && grep -q 'item in ansible_facts.packages' ansible/roles/base/tasks/main.yml && grep -q 'item not in ansible_facts.packages' ansible/roles/base/tasks/main.yml && grep -A2 'dnf_versionlock_packages:' ansible/roles/base/defaults/main.yml | grep -q 'salt-minion' && ! grep -q 'disable_gpg_check: true' ansible/roles/base/tasks/main.yml</automated>
  </verify>
  <acceptance_criteria>
    - awk ordering check exits 0: line("Install dnf versionlock plugin") < line("Update all
      packages") AND line("Lock packages to their currently installed versions") <
      line("Update all packages") in ansible/roles/base/tasks/main.yml.
    - `grep -c 'python3-dnf-plugin-versionlock' ansible/roles/base/tasks/main.yml` >= 1.
    - `grep -q "Adding versionlock on:" ansible/roles/base/tasks/main.yml` exits 0
      (changed_when idempotency key present).
    - `grep -q 'item in ansible_facts.packages' ansible/roles/base/tasks/main.yml` AND
      `grep -q 'item not in ansible_facts.packages' ...` both exit 0 (presence gate +
      absent-package debug both wired).
    - `grep -A2 'dnf_versionlock_packages:' ansible/roles/base/defaults/main.yml | grep -q
      'salt-minion'` exits 0 (list var holds salt-minion).
    - `grep -c 'ansible.builtin.package_facts' ansible/roles/base/tasks/main.yml` == 2
      (new pre-update gather ADDED, SPAL gather PRESERVED).
    - `! grep -q 'disable_gpg_check: true' ansible/roles/base/tasks/main.yml` (GPG stays on).
    - `git diff --name-only` lists EXACTLY ansible/roles/base/tasks/main.yml and
      ansible/roles/base/defaults/main.yml.
  </acceptance_criteria>
  <done>The versionlock block (header comment, plugin install, package_facts, conditional lock loop, absent-package debug) is the first content of the base role's tasks, above "Update all packages"; defaults carry dnf_versionlock_packages: [salt-minion]; no other file changed; GPG check untouched.</done>
</task>

<task type="auto">
  <name>Task 2: Static verification sweep — syntax, CI-exact ansible-lint v26.4.0, grep-gates, scoped no-changeme</name>
  <files>none — read-only verification of Task 1's edits</files>
  <read_first>
    - The <lint_baseline_facts> block in this plan — which scopes are CI-authoritative
      green vs pre-existing-red. Scope discipline is mandatory: verify THIS change, do not
      chase (or "fix") blame-proven pre-existing failures elsewhere in the repo.
    - .pre-commit-config.yaml — hook ids `grep-gates` (fast tier, safe to run whole) and
      `ansible-lint` (push tier, pass_filenames:false → repo-wide → do NOT use the hook;
      use the pinned binary directly).
  </read_first>
  <action>
Run the static gate suite (no live bake — bake-time behavior lands on the operator's next
`./run build`, which is already queued in the open live-UAT backlog):

1. Syntax: `ansible-playbook --syntax-check ansible/playbook.yml` — must exit 0. A
   "provided hosts list is empty" / no-inventory warning is expected and fine.

2. CI-exact lint, scoped: locate a v26.4.0 ansible-lint binary — try `ansible-lint
   --version` on PATH first; if it is not 26.4.x, use the pre-commit cached venv binary
   (`find ~/.cache/pre-commit -path '*/bin/ansible-lint' 2>/dev/null`, pick the one whose
   `--version` reports 26.4.0; if no cache exists yet, `pre-commit install --install-hooks`
   builds it without running repo-wide lint). Then run `<binary> ansible/playbook.yml` —
   must exit 0 with zero findings (this lints roles/base transitively; production profile).
   If it errors on FQCN/collection resolution, run `ansible-galaxy collection install -r
   ansible/requirements.yml` (idempotent, per the hook's own comment) and rerun. Do NOT
   run ansible-lint repo-wide and do NOT use `pre-commit run ... ansible-lint`
   (pre-existing-red baseline; out of scope per <lint_baseline_facts>).

3. Grep gates (CI-authoritative, green baseline): `pre-commit run grep-gates --all-files`
   — must pass. Gate 9 (hardening last role) proves the playbook is untouched.

4. Scoped no-changeme (the hook itself is repo-wide and pre-existing-red; run the
   equivalent check scoped to the touched role): `git grep -nIE "changeme" --
   ansible/roles/base` — must produce NO output (exit non-zero from git grep is the pass).

5. Diff hygiene: `git diff --name-only` must list exactly the two Task-1 files; `git diff
   --stat` recorded in the SUMMARY.

Fix loop: if step 2 flags the new block (most plausible candidates: `no-changed-when` —
would mean the changed_when line is malformed; `command-instead-of-module` — apply the
noqa contingency from Task 1; `jinja[spacing]` — normalize `{{ item }}` spacing), edit
ONLY the new block in ansible/roles/base/{tasks,defaults}/main.yml and rerun steps 1-3
until green. Do NOT add noqa for anything except command-instead-of-module, and only if
actually flagged. Do NOT commit — the orchestrator commits.
  </action>
  <verify>
    <automated>cd /Users/me/Documents/code/devbox && ansible-playbook --syntax-check ansible/playbook.yml && pre-commit run grep-gates --all-files && ! git grep -nIE "changeme" -- ansible/roles/base && git diff --name-only | sort | diff - <(printf 'ansible/roles/base/defaults/main.yml\nansible/roles/base/tasks/main.yml\n')</automated>
  </verify>
  <acceptance_criteria>
    - `ansible-playbook --syntax-check ansible/playbook.yml` exits 0.
    - A v26.4.x `ansible-lint` binary run as `ansible-lint ansible/playbook.yml` exits 0
      (the binary's `--version` output is recorded in the SUMMARY as evidence of the
      CI-exact pin).
    - `pre-commit run grep-gates --all-files` passes (all 10 gates, incl. gate 9
      hardening-last and gate 8 no-retired-make-targets).
    - `git grep -nIE "changeme" -- ansible/roles/base` returns no matches.
    - `git diff --name-only` == exactly {ansible/roles/base/tasks/main.yml,
      ansible/roles/base/defaults/main.yml}.
    - Zero new noqa comments, OR exactly one `# noqa: command-instead-of-module` on the
      lock task with a justification comment, added only because the pinned linter flagged it.
  </acceptance_criteria>
  <done>All static gates green at CI-exact scopes; lint evidence (binary version + exit codes) captured for the SUMMARY; working tree contains only the two intended file edits, uncommitted.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| AL2023 core repo → dnf install | Third-party (Amazon-signed) plugin package enters the AMI at bake time. |
| versionlock policy → future updates | The lock deliberately alters which packages the update pipeline may touch. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-q260724dh7-01 | Tampering | `python3-dnf-plugin-versionlock` install | mitigate | Sourced from the AL2023 core repo (Amazon-signed); GPG check stays ON (dnf default, no `disable_gpg_check` anywhere — CLAUDE.md §8). Not an npm/pip/cargo install, so the package-legitimacy human-checkpoint gate does not apply. |
| T-q260724dh7-02 | Denial of Service | salt-minion patch starvation | accept | The lock excludes salt-minion from ALL updates including security fixes — this is the operator-requested behavior. Remediation documented in the block's comment header: `dnf versionlock delete salt-minion` + update, or rebake (the next bake re-captures the source AMI's then-current version). |
| T-q260724dh7-03 | Tampering | `/etc/dnf/plugins/versionlock.list` | accept | Root-owned file written by the root-context bake and by root-only dnf invocations at runtime; no additional hardening needed beyond the existing CIS baseline. |
| T-q260724dh7-04 | Elevation of Privilege | `ansible.builtin.command` lock task | mitigate | Command arguments come only from the role's own `dnf_versionlock_packages` default (operator-controlled repo content, not runtime input); loop items are bare package names, no shell interpolation (`command`, not `shell`). |
</threat_model>

<verification>
Static (this task): awk ordering proof that both new lock tasks precede "Update all
packages"; grep proofs for plugin name, changed_when key, presence/absence gates, defaults
list, GPG posture; `ansible-playbook --syntax-check` green; CI-exact
`ansible-lint ansible/playbook.yml` (pinned v26.4.0) green; `pre-commit run grep-gates
--all-files` green; scoped no-changeme clean; diff limited to the two role files.

Deferred to the next live bake (open live-UAT backlog — no new checkpoint here): on an org
source AMI, `dnf versionlock list` shows a salt-minion entry pinned at the pre-update
version and `rpm -q salt-minion` is unchanged after the full-image update; on the public
minimal AMI, the bake log shows the skip + the debug note and the bake succeeds.
</verification>

<success_criteria>
- `ansible/roles/base/tasks/main.yml` opens with the versionlock block (comment header,
  plugin install, package_facts, conditional lock loop, absent-package debug) ABOVE
  "Update all packages" — ordering mechanically proven by the awk check.
- `dnf_versionlock_packages: [salt-minion]` exists in the base role defaults with the
  source-AMI story documented.
- The lock is conditional: present package → locked at its bake-start version; absent
  package → per-item skip + debug note, bake proceeds (public minimal AMI safe).
- Idempotent: already-locked re-run reports ok (not changed, not failed) via the
  'Adding versionlock on:' changed_when key + tolerant failed_when.
- GPG verification untouched (no `disable_gpg_check: true`); no other file modified;
  hardening still last role (grep-gates gate 9); all static gates green at CI-exact scopes.
- Nothing committed by the executor (orchestrator commits).
</success_criteria>

<output>
Create `.planning/quick/260724-dh7-add-dnf-versionlock-and-lock-salt-minion/260724-dh7-SUMMARY.md`
when done (include the ansible-lint binary version + exit-code evidence and the
`git diff --stat`). Do NOT commit — the orchestrator commits.
</output>
