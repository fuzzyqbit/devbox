---
phase: quick-260724-kck-gitlab-runner-role
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ansible/roles/gitlab_runner/defaults/main.yml
  - ansible/roles/gitlab_runner/tasks/main.yml
  - ansible/playbook.yml
  - ansible/layer_config.yml
autonomous: true
requirements:
  - GLR-01   # gitlab-runner installed from GitLab's official signed rpm repo — gpgcheck=1 AND repo_gpgcheck=1, version pinned via role var
  - GLR-02   # layer-gated layers.gitlab_runner DEFAULT FALSE; wired before secrets/hardening; default bake byte-unchanged
  - GLR-03   # installed-NOT-registered: no runner token baked (§8), service disabled at boot, runtime registration documented + mechanically asserted
  - GLR-04   # static gates green: syntax check, CI-exact ansible-lint v26.4.0, grep-gates, scoped no-changeme

must_haves:
  truths:
    - "A bake with layers.gitlab_runner=true installs gitlab-runner from packages.gitlab.com's official rpm repo with gpgcheck=1 AND repo_gpgcheck=1 baked into the .repo file — no --nogpgcheck and no disable_gpg_check: true anywhere in the role (CLAUDE.md §8 posture)."
    - "The DEFAULT bake is unchanged: layer_config.yml carries gitlab_runner: false and the playbook gate is `layers.gitlab_runner | default(false)` — an operator who does nothing bakes the exact same image as before this change."
    - "The installed version is pinned via gitlab_runner_version in the role defaults ([VERIFIED via gitlab.com releases API at plan time: 19.2.0]); bumping is a one-var edit + rebake, mirroring the ai_tools pin doctrine."
    - "NO registration secret is baked: the bake FAILS LOUDLY (assert) if /etc/gitlab-runner/config.toml contains a `token` or a `[[runners]]` section at bake end — the §8 no-secrets invariant is mechanical, not aspirational."
    - "gitlab-runner.service exists in the AMI but is disabled + stopped: `systemctl is-enabled gitlab-runner` answers `disabled` at bake-assert time. The operator registers at runtime (`sudo gitlab-runner register`) and only then enables the service — the procedure is documented in the role header comment."
    - "hardening remains the LAST role in ansible/playbook.yml (grep-gates gate 9); gitlab_runner wires in immediately before `secrets`."
    - "All static gates are green at CI-exact scopes: syntax check, pinned ansible-lint v26.4.0 on the playbook (lints the new role transitively), grep-gates --all-files, scoped no-changeme."
  artifacts:
    - path: "ansible/roles/gitlab_runner/tasks/main.yml"
      provides: "role header (runtime-registration + AMI-swap caveat docs) + baked .repo (gpgcheck=1/repo_gpgcheck=1) + rpm_key imports + scoped makecache + pinned dnf install + service-disable + bake-asserts (binary stat, --version run, is-enabled=disabled, config.toml no-secrets)"
      contains: "repo_gpgcheck=1"
    - path: "ansible/roles/gitlab_runner/defaults/main.yml"
      provides: "gitlab_runner_version pin with [VERIFIED: …] comment + bump/refine-at-first-bake procedure"
      contains: "gitlab_runner_version"
    - path: "ansible/playbook.yml"
      provides: "gitlab_runner role entry gated on layers.gitlab_runner, positioned before secrets, hardening still last"
      contains: "role: gitlab_runner"
    - path: "ansible/layer_config.yml"
      provides: "gitlab_runner: false flag (default OFF — org-specific tool) with comment"
      contains: "gitlab_runner: false"
  key_links:
    - from: "ansible/playbook.yml"
      to: "ansible/roles/gitlab_runner/"
      via: "role entry with layer gate"
      pattern: "layers\\.gitlab_runner \\| default\\(false\\)"
    - from: "ansible/roles/gitlab_runner/tasks/main.yml"
      to: "ansible/roles/gitlab_runner/defaults/main.yml"
      via: "pinned dnf name spec templating gitlab_runner_version"
      pattern: "gitlab_runner_version"
    - from: "baked /etc/yum.repos.d/gitlab-runner.repo"
      to: "dnf install task"
      via: "repo id runner_gitlab-runner (packagecloud canonical section name)"
      pattern: "runner_gitlab-runner"
    - from: "service-disable task"
      to: "is-enabled bake-assert"
      via: "systemctl is-enabled stdout must be `disabled`"
      pattern: "is-enabled"
---

<objective>
Add a new layer-gated ansible role `gitlab_runner` that bakes the GitLab CI runner binary
into the devbox AMI from GitLab's OFFICIAL signed rpm repository
(packages.gitlab.com/runner/gitlab-runner), installed-but-NOT-registered: version pinned
via role var, GPG verification fully ON (gpgcheck=1 AND repo_gpgcheck=1, no bypass flags),
service disabled at boot, and zero secrets baked — the runner registration token is a
secret (CLAUDE.md §8), so the operator registers at runtime with
`sudo gitlab-runner register`. Layer flag `layers.gitlab_runner` defaults FALSE
(org-specific tool): the default bake is byte-identical to today's.

Purpose: org CI jobs can target the devbox as a runner host without the image build ever
touching a registration token, and without changing the image for operators who don't
need it.

Output: `ansible/roles/gitlab_runner/{defaults,tasks}/main.yml` (new), a gated role entry
in `ansible/playbook.yml` (before `secrets`, hardening still last), a `gitlab_runner:
false` flag in `ansible/layer_config.yml`, and static verification green (syntax,
CI-exact ansible-lint v26.4.0, grep-gates). No live bake in this task — bake-time
behavior lands on the operator's next `./run build` (open live-UAT backlog).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@ansible/playbook.yml
@ansible/layer_config.yml
@ansible/roles/ai_tools/tasks/main.yml
@ansible/roles/ai_tools/defaults/main.yml
@ansible/roles/xrdp/tasks/main.yml
@ansible/roles/xrdp/defaults/main.yml
@ansible/roles/desktop/tasks/main.yml
@.pre-commit-config.yaml

<gitlab_runner_facts>
Authoritative mechanics resolved at PLAN time (2026-07-24) — the executor must rely on
these, not re-derive them:

- CURRENT STABLE VERSION: gitlab-runner **19.2.0** [VERIFIED: gitlab.com releases API,
  2026-07-24 — v19.2.0 released 2026-07-16; prior: v19.1.1 2026-06-25, v19.0.2
  2026-07-01]. Pin `gitlab_runner_version: "19.2.0"` (name-version dnf spec). The rpm
  RELEASE suffix (e.g. `-1`) was NOT verified — do not guess it; the defaults comment
  documents refining the pin to the full version-release string at first bake via
  `dnf list --showduplicates --repo=runner_gitlab-runner gitlab-runner` (the xrdp
  deferred-pin idiom, CLAUDE.md §9). packages.gitlab.com DOES host historic versions,
  so a pin does not break future bakes (unlike the Chrome repo).
- CANONICAL .repo CONTENT — RESOLVE AT EXEC, DO NOT TRANSCRIBE FROM THIS PLAN: fetch
  `curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/config_file.repo?os=amazon&dist=2023&source=script"`
  at execution time and embed the `[runner_gitlab-runner]` section VERBATIM (drop the
  `[runner_gitlab-runner-source]` SRPMS section — not needed, smaller surface).
  IMPORTANT: the planning session's fetched copy had 2 values substituted by a
  secrets-scrubbing hook (almost certainly the two hex `.pub.gpg` gpgkey filenames), so
  any gpgkey filename appearing in THIS plan is untrusted — the exec-time fetch is the
  only source of truth for the gpgkey URLs. Structural shape to EXPECT and VERIFY in the
  fetched section: `baseurl=https://packages.gitlab.com/runner/gitlab-runner/amazon/2023/$basearch`,
  `repo_gpgcheck=1`, `gpgcheck=1`, `enabled=1`, `sslverify=1`,
  `sslcacert=/etc/pki/tls/certs/ca-bundle.crt`, and a multi-line `gpgkey=` list of
  https://packages.gitlab.com/... URLs (packagecloud metadata key + runner package
  signing keys). If ANY of gpgcheck=1 / repo_gpgcheck=1 is absent from the fetch, STOP —
  do not weaken; re-fetch or fail the task. FALLBACK (only if the endpoint is
  unreachable): use the structural shape above with the single per-repo key bundle URL
  `gpgkey=https://packages.gitlab.com/runner/gitlab-runner/gpgkey`, marked
  `[ASSUMED, confirmed-at-first-bake]` in a comment (ai_tools comment idiom).
- `$basearch` in the .repo content is a dnf variable, not Jinja — an
  `ansible.builtin.copy` inline `content:` block passes it through untouched.
- RPM %post BEHAVIOR [ASSUMED, confirmed-at-first-bake]: the gitlab-runner rpm creates a
  `gitlab-runner` system user, runs `gitlab-runner install --user gitlab-runner ...`
  (which writes the systemd unit — kardianos/service library, typically
  /etc/systemd/system/gitlab-runner.service), and STARTS/ENABLES the service. This is
  why the role must explicitly disable+stop AFTER install. An unregistered
  /etc/gitlab-runner/config.toml (if created) contains only globals (concurrent,
  check_interval) — no `token`, no `[[runners]]` — so the no-secrets assert passes on a
  clean bake and fails only if someone later bakes a registration.
- SERVICE-DISABLED SEMANTICS: `systemctl is-enabled gitlab-runner` prints `disabled` on
  stdout and exits NON-ZERO (rc 1) when disabled — register with `failed_when: false`
  and assert on the stdout string, NOT the rc (same trap the xrdp role documents). A
  missing unit prints an error with empty stdout, so the `disabled` stdout assert
  doubles as the unit-present proof.
- BINARY PATH: /usr/bin/gitlab-runner [ASSUMED, confirmed-at-first-bake — confirm with
  `rpm -ql gitlab-runner | grep bin/` on the instance; xrdp [RESOLVE-AT-EXEC] idiom].
- repo_gpgcheck KEY IMPORT [ASSUMED, confirmed-at-first-bake]: `rpm_key` imports cover
  package-signature verification (gpgcheck), but repo METADATA verification
  (repo_gpgcheck=1) needs dnf/librepo to accept the packagecloud metadata-signing key
  into its own keyring. CLI `dnf -y makecache` auto-accepts keys listed in `gpgkey=`;
  the ansible dnf-API path may not. Hence the scoped
  `dnf -y makecache --disablerepo=* --enablerepo=runner_gitlab-runner` command task
  BEFORE the install. If the first bake proves the module handles it, the task can be
  dropped — note that in its comment.
- EXECUTOR DEPS (do NOT hard-depend): the shell executor works with what's already baked
  (bash + git from the `git` layer); the docker executor becomes available when
  `layers.containers` is on. Record the interplay ONLY as a role-header comment — no
  dependency assert, no layer coupling (orchestrator offered executor's choice; the
  comment-only answer is the KISS one).
- REGISTRATION DOES NOT SURVIVE AMI SWAPS: /etc/gitlab-runner/config.toml lives on the
  root volume, NOT the persistent /home EBS volume — unlike ai_tools credentials. After
  every rebake+tf-apply the operator re-registers. This MUST be stated in the role
  header comment (operator-facing caveat).
- KION POSITION NOTE: the orchestrator's locked wiring is "after `kion` / before
  `secrets`", but the `kion` role lives on the unmerged `feat/kion-creds` branch and is
  ABSENT from this branch's playbook. "Immediately before `- role: secrets`" satisfies
  both orderings; when kion merges it lands in the same region (trivial conflict).
</gitlab_runner_facts>

<lint_baseline_facts>
From STATE.md (16-01 execution decisions) and .pre-commit-config.yaml — scope discipline
for Task 3:

- REPO-WIDE runs of the push-stage ansible-lint hook and of `pre-commit run --all-files`
  (no-changeme, trailing-whitespace) are PRE-EXISTING-RED on content blame-proven to
  predate this task. Do not chase those; do not widen scope to "fix" them.
- CI-AUTHORITATIVE green scopes: `grep-gates` (safe to run whole), gitleaks, and
  `ansible-lint ansible/playbook.yml` with the PINNED v26.4.0 binary (the upstream
  pre-commit ansible-lint hook is pass_filenames:false → repo-wide → red; invoke the
  binary directly, scoped to the playbook — it lints roles/gitlab_runner transitively
  because the role is listed in the playbook regardless of its `when:` gate).
- `check-yaml` excludes `ansible/*.yml` — not applicable.
- grep-gates gate 8 (no retired make-target phrases): comments in the new files must not
  contain the word "make" followed by a former Makefile target name (build, tf-*, start,
  stop, status, …). Gate 9 (hardening last role) is exercised by the Task 2 wiring.
- Only-if-flagged noqa contingencies at the pinned v26.4.0: `command-instead-of-module`
  on the `systemctl is-enabled` check (xrdp precedent — same noqa + justification
  comment, xrdp/tasks/main.yml line 335) and possibly on the `dnf -y makecache` command
  (base-role `dnf swap` precedent suggests non-module dnf subcommands are green — add
  the noqa only if actually flagged). No other noqa permitted.
</lint_baseline_facts>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create the gitlab_runner role (defaults + tasks) — signed-repo pinned install, service disabled, no-secrets bake-asserts</name>
  <files>ansible/roles/gitlab_runner/defaults/main.yml, ansible/roles/gitlab_runner/tasks/main.yml</files>
  <read_first>
    - The <gitlab_runner_facts> block in this plan — version pin, exec-time .repo
      resolution procedure (MANDATORY — plan-transcribed gpgkey filenames are untrusted),
      %post behavior, is-enabled rc semantics, [ASSUMED] markers.
    - ansible/roles/ai_tools/tasks/main.yml + defaults/main.yml — the pattern to follow:
      header no-secrets doc, pinned versions with [VERIFIED: …] comment, [ASSUMED,
      confirmed-at-first-bake] comment idiom, "Bake-asserts (dcv/xrdp
      bake-green-but-broken pattern)" section banner, quiet asserts with actionable
      fail_msg.
    - ansible/roles/desktop/tasks/main.yml lines 160-200 — the Chrome block: the exact
      rpm_key-import + inline-content .repo bake + `disable_gpg_check: false` install
      idiom (including the "no fingerprint pin — multi-key bundle" rpm_key comment
      rationale to mirror).
    - ansible/roles/xrdp/tasks/main.yml lines 59-73 and 334-351 — the deferred-pin dnf
      name templating idiom and the is-enabled noqa/failed_when idiom.
    - ansible/roles/xrdp/defaults/main.yml — the deferred-pin comment style for the
      version var.
  </read_first>
  <action>
First, resolve the canonical repo config (workstation-side, before writing any file):
run `curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/config_file.repo?os=amazon&dist=2023&source=script"`
and capture the `[runner_gitlab-runner]` section per <gitlab_runner_facts> (verify
gpgcheck=1 AND repo_gpgcheck=1 present; drop the SRPMS section; fallback + [ASSUMED]
marking only if the endpoint is unreachable).

Create `ansible/roles/gitlab_runner/defaults/main.yml`:
- `gitlab_runner_version: "19.2.0"` with a comment block in the ai_tools style:
  `# [VERIFIED: gitlab.com releases API — 2026-07-24 (v19.2.0 released 2026-07-16)]`,
  bump procedure (edit var, rebake), and the deferred REFINEMENT note (xrdp §9 idiom):
  at first bake, run `dnf list --showduplicates --repo=runner_gitlab-runner gitlab-runner`
  on the instance and extend the pin to the exact version-release string. Use the xrdp
  conditional templating downstream so an emptied var falls back to repo-latest.

Create `ansible/roles/gitlab_runner/tasks/main.yml`, in order:

1. HEADER COMMENT (role contract — mirrors ai_tools header): GitLab CI runner from
   GitLab's official packagecloud rpm repo, installed-NOT-registered. NO secrets baked
   (CLAUDE.md §8): the runner registration token is a secret — the operator registers at
   runtime with `sudo gitlab-runner register --url <gitlab-url> --token <runner-token>`
   (config lands in /etc/gitlab-runner/config.toml at runtime), then
   `sudo systemctl enable --now gitlab-runner`. CAVEAT: /etc/gitlab-runner is on the
   root volume, not the persistent /home EBS volume — registration does NOT survive an
   AMI swap; re-register after every rebake + apply. EXECUTOR DEPS: shell executor works
   out of the box (bash + git are baked by the git layer); the docker executor becomes
   available when layers.containers is on — noted here, deliberately NOT a hard
   dependency. GPG posture: gpgcheck=1 AND repo_gpgcheck=1 baked; no bypass flags (§8).

2. Task `- name: Bake the GitLab runner dnf repo config (gpgcheck + repo_gpgcheck on)` —
   `ansible.builtin.copy` with `dest: /etc/yum.repos.d/gitlab-runner.repo`, inline
   `content:` holding the exec-time-fetched `[runner_gitlab-runner]` section VERBATIM
   (preserve the multi-line gpgkey continuation indentation exactly; `$basearch` passes
   through — it is a dnf var, not Jinja), `owner: root`, `group: root`, `mode: "0644"`.
   Comment above it: content fetched verbatim from the packagecloud config_file.repo
   endpoint (URL + fetch date), binary repo section only (SRPMS dropped), Chrome-block
   precedent for baking a vendor .repo with GPG on.

3. Task `- name: Import the GitLab runner package signing keys` —
   `ansible.builtin.rpm_key` with `state: present`, looped over EACH https URL that
   appears on the fetched section's `gpgkey=` lines (a literal list of those URLs).
   Comment mirrors the Chrome rpm_key rationale: plain import, no fingerprint pin
   (multi-key bundles + ansible-core < 2.18 single-fingerprint limitation).

4. Task `- name: Refresh the GitLab runner repo metadata (accept the repo signing key)` —
   `ansible.builtin.command` with
   `cmd: dnf -y makecache --disablerepo=* --enablerepo=runner_gitlab-runner`,
   `changed_when: false`. Comment: [ASSUMED, confirmed-at-first-bake] per
   <gitlab_runner_facts> — repo_gpgcheck=1 needs dnf/librepo to accept the packagecloud
   metadata-signing key; CLI `-y` auto-accepts, the module API path may not; drop this
   task if the first bake proves it redundant.

5. Task `- name: Install gitlab-runner (pinned) from the signed repo` —
   `ansible.builtin.dnf` with
   `name: "gitlab-runner{{ ('-' ~ gitlab_runner_version) if (gitlab_runner_version | length > 0) else '' }}"`
   (xrdp deferred-pin templating idiom), `state: present`,
   `disable_gpg_check: false` with the Chrome-style comment (GPG verification stays ON —
   CLAUDE.md §2/§8).

6. Task `- name: Disable and stop the gitlab-runner service (installed-not-registered)` —
   `ansible.builtin.systemd` with `name: gitlab-runner`, `enabled: false`,
   `state: stopped`, `daemon_reload: true`. Comment: the rpm %post enables+starts the
   service ([ASSUMED, confirmed-at-first-bake]); an unregistered runner must not run at
   boot — the operator enables it after registering (see header).

7. BAKE-ASSERTS section (banner comment: `# ── Bake-asserts (dcv/xrdp
   bake-green-but-broken pattern) ──`):
   a. `- name: Stat the gitlab-runner binary (bake-assert)` — stat
      `/usr/bin/gitlab-runner`, register, then an assert task with `quiet: true` and a
      fail_msg that includes the [ASSUMED] path caveat + the `rpm -ql gitlab-runner |
      grep bin/` confirmation command.
   b. `- name: Run gitlab-runner --version (bake-assert)` — command
      `/usr/bin/gitlab-runner --version`, `changed_when: false` (proves the binary
      executes on AL2023, not just exists — ai_tools doctrine).
   c. `- name: Check gitlab-runner service enablement (bake-assert)` — command
      `cmd: systemctl is-enabled gitlab-runner`, register, `changed_when: false`,
      `failed_when: false` (is-enabled exits rc 1 for `disabled` — assert on stdout, not
      rc), with the xrdp `# noqa: command-instead-of-module` + justification comment
      idiom ONLY if the pinned linter flags it (Task 3 contingency).
      Then `- name: Assert the gitlab-runner service is present but disabled
      (bake-assert)` — assert `'disabled' in <register>.stdout` with fail_msg explaining
      both failure modes: empty stdout/error → unit missing (install or %post
      regression); `enabled` → the disable task regressed and an unregistered runner
      would start at boot.
   d. No-secrets assert: `- name: Stat /etc/gitlab-runner/config.toml (bake-assert)` —
      stat + register; `- name: Slurp config.toml for the no-secrets assert
      (bake-assert)` — `ansible.builtin.slurp` with `when: <stat>.stat.exists`,
      register; `- name: Assert no runner registration is baked (bake-assert)` — assert,
      `when: <stat>.stat.exists`, that the b64decoded content contains NEITHER `token`
      NOR `[[runners]]`, `quiet: true`, fail_msg citing CLAUDE.md §8: a registration
      token is a secret and MUST NOT enter the AMI; registration is a runtime step.

Style: FQCN modules everywhere, sentence-case task names, two-space indent, `>-` folded
fail_msgs — match ai_tools/xrdp exactly. Comments must not contain "changeme" and must
not contain "make" followed by a retired Makefile target name (grep-gates gates; see
<lint_baseline_facts>). Do NOT create meta/, handlers/, files/ or templates/ dirs —
tasks + defaults only (ai_tools shape). Do NOT touch any other file in this task. Do NOT
commit — the orchestrator commits.
  </action>
  <verify>
    <automated>cd /Users/me/Documents/code/devbox && test -f ansible/roles/gitlab_runner/tasks/main.yml && test -f ansible/roles/gitlab_runner/defaults/main.yml && grep -q 'repo_gpgcheck=1' ansible/roles/gitlab_runner/tasks/main.yml && grep -q 'gitlab_runner_version: "19.2.0"' ansible/roles/gitlab_runner/defaults/main.yml && grep -q 'disable_gpg_check: false' ansible/roles/gitlab_runner/tasks/main.yml && ! grep -q 'disable_gpg_check: true' ansible/roles/gitlab_runner/tasks/main.yml && ! grep -qi 'nogpgcheck' ansible/roles/gitlab_runner/tasks/main.yml && grep -q 'enabled: false' ansible/roles/gitlab_runner/tasks/main.yml && grep -q 'gitlab-runner register' ansible/roles/gitlab_runner/tasks/main.yml && grep -qF '[[runners]]' ansible/roles/gitlab_runner/tasks/main.yml</automated>
  </verify>
  <acceptance_criteria>
    - Both new files exist; `git status --porcelain` shows ONLY the new
      ansible/roles/gitlab_runner/ path as untracked (no other file touched yet).
    - The baked .repo content in tasks/main.yml carries `gpgcheck=1` AND
      `repo_gpgcheck=1` AND `sslverify=1`, with baseurl
      `https://packages.gitlab.com/runner/gitlab-runner/amazon/2023/$basearch`, and was
      taken from the EXEC-TIME curl of the packagecloud config_file.repo endpoint (the
      curl command + its date recorded in the SUMMARY as evidence). No
      `[runner_gitlab-runner-source]` section baked.
    - Every gpgkey URL in the baked .repo also appears in the rpm_key import loop list
      (`grep -o 'https://packages.gitlab.com[^[:space:]]*' ansible/roles/gitlab_runner/tasks/main.yml`
      shows each key URL at least twice — once in the .repo content, once in the loop) —
      OR, in the endpoint-unreachable fallback, the single
      `https://packages.gitlab.com/runner/gitlab-runner/gpgkey` URL is used in both
      places and an `[ASSUMED, confirmed-at-first-bake]` comment marks it.
    - `grep -q 'gitlab_runner_version' ansible/roles/gitlab_runner/tasks/main.yml` exits
      0 (the dnf name spec templates the pin) and the defaults comment carries
      `[VERIFIED:` + the first-bake release-suffix refinement procedure.
    - `! grep -q 'disable_gpg_check: true'` and `! grep -qi 'nogpgcheck'` over the role
      dir both hold (§8 GPG posture).
    - Service posture wired: `enabled: false`, `state: stopped`, `daemon_reload: true`
      present on the systemd task; is-enabled bake-assert asserts on stdout `disabled`
      with `failed_when: false` on the command.
    - No-secrets assert present: slurp gated on stat, assert rejects both `token` and
      `[[runners]]`, fail_msg cites §8.
    - Runtime registration + AMI-swap caveat + executor-deps interplay all present in
      the role header comment (`grep -q 'gitlab-runner register'` and
      `grep -qi 'AMI swap'` and `grep -qi 'containers'` on tasks/main.yml all exit 0).
    - No meta/, handlers/, files/, templates/ dirs created; no "changeme" literal
      anywhere in the new files.
  </acceptance_criteria>
  <done>ansible/roles/gitlab_runner/ exists with defaults (pinned 19.2.0 + [VERIFIED] comment) and tasks (exec-time-fetched signed .repo, key imports, scoped makecache, pinned GPG-on install, service disabled+stopped, four bake-assert groups incl. the §8 no-secrets assert); nothing else in the tree touched; nothing committed.</done>
</task>

<task type="auto">
  <name>Task 2: Wire the role — playbook.yml entry (before secrets, hardening still last) + layer_config.yml flag default false</name>
  <files>ansible/playbook.yml, ansible/layer_config.yml</files>
  <read_first>
    - ansible/playbook.yml lines 54-65 — the ai_tools entry (comment style to mirror)
      and the `- role: secrets` entry the new role must precede. Line 85: the hardening
      entry with its MUST-remain-last comment — do not touch it.
    - ansible/layer_config.yml — key naming (underscores), comment style on the
      ai_tools/xrdp flags, and the file's "To add a new layer" header instruction.
    - The KION POSITION NOTE in <gitlab_runner_facts> — why "immediately before secrets"
      is the locked position on this branch.
  </read_first>
  <action>
Edit `ansible/playbook.yml`: insert a new role entry immediately AFTER the ai_tools
entry's comment block (after current line 59) and immediately BEFORE `- role: secrets`:

- `- role: gitlab_runner` with `when: layers.gitlab_runner | default(false)` and a
  comment block in the ai_tools style stating: GitLab CI runner from GitLab's official
  packagecloud rpm repo (gpgcheck + repo_gpgcheck ON), version-pinned;
  installed-NOT-registered — no runner token baked (§8 no-secrets), service ships
  disabled, operator registers at runtime (see the role header); default OFF
  (org-specific). MUST stay before hardening (last-role invariant).

Do not reorder or edit any other entry; `- role: hardening` MUST remain the last role
(grep-gates gate 9 verifies mechanically).

Edit `ansible/layer_config.yml`: add after the `ai_tools: true` line:
- a comment: gitlab_runner bakes the GitLab CI runner, installed-not-registered (service
  disabled; operator registers at runtime — no token baked). Default OFF — org-specific
  tool.
- `gitlab_runner: false`

Preserve two-space indent under `layers:`; underscore key naming (ai_tools precedent).
Do NOT commit — the orchestrator commits. If staging is ever needed, `git add` runs as
its OWN Bash call, never chained with a commit (executor memory rule).
  </action>
  <verify>
    <automated>cd /Users/me/Documents/code/devbox && awk '/^[[:space:]]*- role: gitlab_runner$/{g=NR} /^[[:space:]]*- role: secrets$/{s=NR} /^[[:space:]]*- role: hardening/{h=NR} END{exit !(g && s && h && g<s && s<h)}' ansible/playbook.yml && grep -q 'layers.gitlab_runner | default(false)' ansible/playbook.yml && grep -qE '^[[:space:]]{2}gitlab_runner: false$' ansible/layer_config.yml && [ "$(grep -E '^[[:space:]]*-[[:space:]]*role:' ansible/playbook.yml | tail -1 | grep -c 'role:[[:space:]]*hardening')" -eq 1 ]</automated>
  </verify>
  <acceptance_criteria>
    - awk ordering proof exits 0: line("- role: gitlab_runner") < line("- role:
      secrets") < line("- role: hardening") in ansible/playbook.yml.
    - The gate expression is exactly `layers.gitlab_runner | default(false)` (default
      FALSE — a layer_config.yml without the key still bakes nothing).
    - The last `- role:` line in the playbook still names hardening (grep-gates gate 9
      expression replicated locally, exits 0).
    - `ansible/layer_config.yml` contains `gitlab_runner: false` (two-space indent under
      layers:) with the explanatory comment above it.
    - The playbook entry's comment mentions the runtime registration posture and "MUST
      stay before hardening".
    - `git status --porcelain` now shows exactly: modified ansible/playbook.yml,
      modified ansible/layer_config.yml, untracked ansible/roles/gitlab_runner/ —
      nothing else.
  </acceptance_criteria>
  <done>gitlab_runner is wired into the playbook immediately before secrets with the default-false gate and posture comment; layer_config.yml carries gitlab_runner: false; hardening is still the last role; no other entries changed; nothing committed.</done>
</task>

<task type="auto">
  <name>Task 3: Static verification sweep — syntax, CI-exact ansible-lint v26.4.0, grep-gates, scoped no-changeme, diff hygiene</name>
  <files>none — read-only verification of Tasks 1-2 (fix loop may edit only the new role files / the two wiring hunks)</files>
  <read_first>
    - The <lint_baseline_facts> block in this plan — which scopes are CI-authoritative
      green vs pre-existing-red. Scope discipline is mandatory: verify THIS change, do
      not chase (or "fix") blame-proven pre-existing failures elsewhere in the repo.
    - .pre-commit-config.yaml — hook ids `grep-gates` (fast tier, safe to run whole) and
      `ansible-lint` (push tier, pass_filenames:false → repo-wide → do NOT use the hook;
      use the pinned binary directly).
  </read_first>
  <action>
Run the static gate suite (no live bake — bake-time behavior lands on the operator's
next `./run build`, already queued in the open live-UAT backlog):

1. Syntax: `ansible-playbook --syntax-check ansible/playbook.yml` — must exit 0. A
   "provided hosts list is empty" / no-inventory warning is expected and fine.

2. CI-exact lint, scoped: locate a v26.4.0 ansible-lint binary — try `ansible-lint
   --version` on PATH first; if not 26.4.x, use the pre-commit cached venv binary
   (`find ~/.cache/pre-commit -path '*/bin/ansible-lint' 2>/dev/null`, pick the one
   whose `--version` reports 26.4.0; if no cache exists, `pre-commit install
   --install-hooks` builds it without running repo-wide lint). Run
   `<binary> ansible/playbook.yml` — must exit 0 with zero findings (lints
   roles/gitlab_runner transitively; production profile). If it errors on
   FQCN/collection resolution, run `ansible-galaxy collection install -r
   ansible/requirements.yml` (idempotent) and rerun. Do NOT run ansible-lint repo-wide
   and do NOT use `pre-commit run ... ansible-lint` (pre-existing-red baseline).

3. Grep gates (CI-authoritative, green baseline): `pre-commit run grep-gates
   --all-files` — must pass. Gate 9 proves hardening is still last; gate 8 proves the
   new comments carry no retired make-target phrases.

4. Scoped no-changeme (the hook itself is repo-wide and pre-existing-red; run the
   equivalent scoped to the touched paths): `git grep -nIE "changeme" --
   ansible/roles/gitlab_runner ansible/playbook.yml ansible/layer_config.yml` — must
   produce NO output (non-zero exit from git grep is the pass).

5. Diff hygiene: `git status --porcelain` must list exactly modified
   ansible/playbook.yml + ansible/layer_config.yml and untracked
   ansible/roles/gitlab_runner/; `git diff --stat` recorded in the SUMMARY.

Fix loop: if step 2 flags the new role (plausible candidates: `no-changed-when` — a
command task missing changed_when; `command-instead-of-module` on the `systemctl
is-enabled` check — apply the xrdp noqa + justification; same rule on `dnf -y makecache`
— noqa only if actually flagged; `risky-file-permissions` — ensure owner/group/mode on
the copy task; `jinja[spacing]` — normalize the dnf name-spec templating), edit ONLY
ansible/roles/gitlab_runner/**, or the two Task-2 hunks, and rerun steps 1-3 until
green. No other noqa permitted. Do NOT commit — the orchestrator commits.
  </action>
  <verify>
    <automated>cd /Users/me/Documents/code/devbox && ansible-playbook --syntax-check ansible/playbook.yml && pre-commit run grep-gates --all-files && ! git grep -nIE "changeme" -- ansible/roles/gitlab_runner ansible/playbook.yml ansible/layer_config.yml && git status --porcelain | grep -vE '^(\?\? ansible/roles/gitlab_runner/| M ansible/(playbook|layer_config)\.yml$|\?\? \.planning/)' | { ! grep -q .; }</automated>
  </verify>
  <acceptance_criteria>
    - `ansible-playbook --syntax-check ansible/playbook.yml` exits 0.
    - A v26.4.x `ansible-lint` binary run as `ansible-lint ansible/playbook.yml` exits 0
      (binary `--version` output recorded in the SUMMARY as CI-pin evidence).
    - `pre-commit run grep-gates --all-files` passes (all 10 gates, incl. gate 8
      no-retired-make-targets and gate 9 hardening-last).
    - `git grep -nIE "changeme" -- ansible/roles/gitlab_runner ansible/playbook.yml
      ansible/layer_config.yml` returns no matches.
    - Working tree contains exactly the four intended paths (two modified files + the
      new role dir), uncommitted.
    - Zero new noqa comments, OR only `# noqa: command-instead-of-module` on
      systemctl/dnf command tasks with justification comments, added only because the
      pinned linter actually flagged them.
  </acceptance_criteria>
  <done>All static gates green at CI-exact scopes; lint evidence (binary version + exit codes) captured for the SUMMARY; working tree contains only the intended changes, uncommitted.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| packages.gitlab.com → dnf install | Third-party (GitLab-signed, packagecloud-hosted) rpm + repo metadata enter the AMI at bake time. |
| Runner registration (runtime) | The registration token — a credential granting the org's GitLab instance code-execution on the devbox — is handled ONLY at runtime, never at bake. |
| GitLab instance → runner jobs (runtime) | Once registered, the org GitLab can execute CI jobs on the devbox — out of bake-time scope, gated by the operator's deliberate register+enable. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-q260724kck-01 | Tampering | gitlab-runner rpm + repo metadata | mitigate | gpgcheck=1 AND repo_gpgcheck=1 baked in the .repo; rpm_key imports of GitLab's signing keys; sslverify=1; `disable_gpg_check: false` on the install; version pinned (19.2.0). Not an npm/pip/cargo install — the package-legitimacy human-checkpoint gate does not apply; the vendor-signed rpm channel is the §8-consistent equivalent. |
| T-q260724kck-02 | Information Disclosure | runner registration token | mitigate | NO registration at bake (design constraint): no token var, no config.toml templating; bake-assert FAILS the build if config.toml carries `token` or `[[runners]]`. Registration is a documented runtime step. |
| T-q260724kck-03 | Elevation of Privilege | gitlab-runner.service (root-run service daemon; registered runners execute arbitrary org CI jobs) | mitigate | Service baked disabled + stopped; layer default FALSE; runner only becomes an execution surface after the operator deliberately registers and enables it at runtime. Runtime job-execution posture is the operator's org-policy concern, noted in the role header. |
| T-q260724kck-04 | Denial of Service | upstream version bump breaking bakes | mitigate | Version pinned via gitlab_runner_version; packages.gitlab.com hosts historic versions so the pin stays resolvable; bump = one-var edit + rebake. |
| T-q260724kck-05 | Tampering | /etc/yum.repos.d/gitlab-runner.repo, /etc/gitlab-runner/ | accept | Root-owned 0644 files written by the root-context bake; covered by the existing CIS baseline; no additional hardening invented. |
</threat_model>

<verification>
Static (this task): Task-1 grep proofs (gpgcheck=1 + repo_gpgcheck=1 baked, pin var
present + [VERIFIED] comment, no disable_gpg_check:true / nogpgcheck, service disabled,
no-secrets assert, registration + AMI-swap docs in header); Task-2 awk ordering proof
(gitlab_runner < secrets < hardening) + gate expression + layer flag false;
`ansible-playbook --syntax-check` green; CI-exact `ansible-lint ansible/playbook.yml`
(pinned v26.4.0) green; `pre-commit run grep-gates --all-files` green; scoped no-changeme
clean; working tree limited to the four intended paths.

Deferred to the next live bake with `layers.gitlab_runner: true` (open live-UAT backlog —
no new checkpoint here): dnf resolves gitlab-runner-19.2.0 from runner_gitlab-runner with
GPG green (confirm the makecache [ASSUMED] and the /usr/bin path [ASSUMED]); fill the
release-suffix refinement of the pin (`dnf list --showduplicates
--repo=runner_gitlab-runner gitlab-runner`); `gitlab-runner --version` prints 19.2.0;
`systemctl is-enabled gitlab-runner` → disabled; then the runtime flow: `sudo
gitlab-runner register` + `sudo systemctl enable --now gitlab-runner` against the org
GitLab. Note: the DEFAULT bake (flag false) needs no UAT — it is provably unchanged.
</verification>

<success_criteria>
- `ansible/roles/gitlab_runner/` exists (tasks + defaults only) implementing:
  exec-time-fetched signed .repo (gpgcheck=1 + repo_gpgcheck=1), rpm_key imports, scoped
  makecache, dnf install pinned to 19.2.0 via gitlab_runner_version with GPG on, service
  disabled + stopped, and bake-asserts for binary stat, --version execution,
  is-enabled=disabled, and the §8 no-secrets config.toml check.
- Runtime registration procedure + AMI-swap re-register caveat + shell/docker executor
  interplay documented in the role header comment (comment-only, no hard dependency on
  the containers layer).
- Playbook wiring: gitlab_runner gated `layers.gitlab_runner | default(false)`,
  positioned immediately before secrets, with the MUST-stay-before-hardening comment;
  hardening mechanically proven still last (grep-gates gate 9).
- `ansible/layer_config.yml` carries `gitlab_runner: false` — the default bake is
  unchanged.
- All static gates green at CI-exact scopes (syntax, pinned ansible-lint v26.4.0,
  grep-gates, scoped no-changeme); zero unapproved noqa.
- Nothing committed by the executor (orchestrator commits; any staging uses `git add` as
  its own Bash call, never chained).
</success_criteria>

<output>
Create `.planning/quick/260724-kck-gitlab-runner-role/260724-kck-SUMMARY.md` when done
(include: the exec-time curl of the packagecloud .repo endpoint + fetch date + which
gpgkey URLs were baked, the ansible-lint binary version + exit-code evidence, and the
`git diff --stat`). Do NOT commit — the orchestrator commits.
</output>
