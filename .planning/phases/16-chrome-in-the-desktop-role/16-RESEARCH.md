# Phase 16: Chrome in the desktop role - Research

**Researched:** 2026-07-24
**Domain:** Google Chrome dnf repo install on Amazon Linux 2023 (Ansible bake-time, CIS-hardened image)
**Confidence:** HIGH

## Summary

Chrome installs cleanly on an AL2023 desktop bake from Google's official signed dnf repo. Every
hard dependency of the current `google-chrome-stable` (150.0.7871.186-1 as of research date) was
verified directly against the live repo metadata and resolves from AL2023 core: `ca-certificates`,
`liberation-fonts`, `wget`, `xdg-utils`, `libvulkan.so.1` (→ `vulkan-loader`), and
`/usr/sbin/update-alternatives` (→ `alternatives`) all exist in the AL2023 core repo
[VERIFIED: direct query of AL2023 core primary.sqlite via cdn.amazonlinux.com]. Everything else
(gtk3, nss, alsa-lib, mesa-libgbm, cups-libs, libxkbcommon…) is already on desktop bakes via
`@Desktop` + GNOME + SPAL chromium. Dependency risk is effectively zero.

The one genuinely tricky finding is Chrome's **self-managing repo config**, verified from the
Chromium installer source: the RPM `%post` scriptlet **unconditionally overwrites**
`/etc/yum.repos.d/google-chrome.repo` via `cat >` when `repo_add_once="true"` (which `%post`
itself sets on first install), and the daily cron (`/etc/cron.daily/google-chrome`) greps for the
exact string `^baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64` (no spaces around
`=`) [VERIFIED: chromium.googlesource.com chrome/installer/linux/common/rpm.include +
chrome.spec.template]. This rules out `ansible.builtin.yum_repository` (it writes `key = value`
with spaces) and rules out any custom lines in the `.repo` file (they get overwritten at `%post`).
The winning move: bake the `.repo` file **byte-identical** to what Chrome's own installer writes
(`ansible.builtin.copy` with exact content, `gpgcheck=1`), so the `%post` overwrite is a content
no-op and the cron finds nothing to fix — the file is stable forever.

GPG posture is fully coherent: Google signs both packages and repo metadata (`repomd.xml.asc`
returns HTTP 200 [VERIFIED: direct probe]), as do AL2023 core and SPAL [VERIFIED: direct probes].
The vendored CIS role's rule 1.2.4 (enabled — not overridden in `hardening/defaults`) sets
`repo_gpgcheck=1` globally in `/etc/dnf/dnf.conf` at hardening time, so the Google repo meets the
post-hardening posture without any extra line in the `.repo` file. No playbook.yml change is
needed at all — the desktop role is already wired before `hardening` — so invariant risk is nil.

**Primary recommendation:** Append a three-task `# --- Google Chrome ---` block to
`ansible/roles/desktop/tasks/main.yml`: `ansible.builtin.rpm_key` (Google key URL) →
`ansible.builtin.copy` (byte-canonical `google-chrome.repo`, `gpgcheck=1`, mode 0644) →
`ansible.builtin.dnf` (`google-chrome-stable`, `state: present`, `disable_gpg_check: false`).

## User Constraints (from milestone questioning — no CONTEXT.md file exists)

### Locked Decisions
- **Plain part of the desktop role** — no sub-gate flag (no `vscode_desktop`-style toggle). Chrome applies unconditionally whenever `layers.desktop` is on.
- **Latest-at-bake version policy** — Google's repo serves only the current stable; no version pin. Remediation for a bad version is a rebake (SPAL/xrdp precedent, CLAUDE.md §8).
- **No bake-asserts and no SBOM-capture requirements this phase** — CHROME-03/04 deferred by operator (deliberate deviation from the dcv/xrdp/ai_tools bake-assert doctrine; revisit if a bake ever ships a dead Chrome).

### Claude's Discretion
- Exact task mechanics (module choice, task placement inside the desktop role, repo-file authoring approach).
- `repo_gpgcheck` posture, provided bakes don't break and `gpgcheck=1` holds.

### Deferred Ideas (OUT OF SCOPE)
- CHROME-03: SBOM/manifest version capture as a stated requirement (behavior persists via existing `sbom.yml` pass — do not add tasks for it).
- CHROME-04: dedicated bake-asserts (headless `--version`; W1-style post-hardening guard).
- Chrome managed policies (`/etc/opt/chrome/policies/`); default-browser `xdg-settings` wiring.
- Chromium removal / other browsers — REQUIREMENTS.md lists Chromium as out of scope; the SPAL `chromium` package in the desktop role **stays untouched**.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CHROME-02 | Chrome installs from Google's official signed dnf repo — baked `.repo` config + GPG key, `gpgcheck=1`, no `--nogpgcheck` (GPG posture consistent with CLAUDE.md §2/§8 and the SPAL precedent) | Canonical repo config verified from Chromium installer source (§Code Examples); key URL + fingerprints from google.com/linuxrepositories; all deps verified resolvable from AL2023 core (§Summary); `%post`/cron rewrite semantics verified (§Common Pitfalls 1-2); CIS 1.2.2/1.2.4 interplay verified benign (§Common Pitfalls 6) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **`hardening` MUST remain the last role in `ansible/playbook.yml`** (grep-gated, invariant #9). This phase needs **no playbook.yml change** — the desktop role is already wired before hardening — so the invariant holds trivially.
- **`sbom.yml` MUST stay the last import** in playbook.yml. Also untouched by this phase.
- **GPG verification stays ON**: no `--nogpgcheck`, no `disable_gpg_check: true` anywhere. Match the xrdp/dcv idiom of explicit `disable_gpg_check: false`.
- **`changeme` literal MUST NOT appear** in tracked code (pre-commit `no-changeme`). Not applicable but keep out of comments.
- **No retired `make <target>` invocations** in tracked files (grep-gate #8). Any docs/comments must say `./run build`, never `make build`.
- **Action SHA-pin / Packer SSM-pin invariants** — untouched by this phase.
- Pre-commit tiers: fast hooks (gitleaks, grep-gates, check-yaml…) on commit; `ansible-lint` (v26.4.0, production profile) on push. New tasks must be lint-clean under the production profile.
- Stale-doc note: `.planning/codebase/CONVENTIONS.md` (2026-05-13) says "bare module names" — the **current** first-party roles use FQCN (`ansible.builtin.dnf` etc.) and ansible-lint production profile enforces it. Follow current code, not the stale doc.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Google repo config + GPG key baked | Bake-time (Ansible `desktop` role) | — | CHROME-02 deliverable; must exist before the dnf install task |
| Chrome package install | Bake-time (Ansible `desktop` role) | — | Latest-at-bake; `dnf` resolves from the baked repo |
| GPG enforcement (`gpgcheck=1`, global `repo_gpgcheck=1`) | Bake-time (`.repo` file) + `hardening` role (CIS 1.2.2/1.2.4) | — | Repo file carries `gpgcheck=1`; CIS 1.2.4 adds global `repo_gpgcheck=1` at hardening (pre-existing behavior) |
| GNOME launcher entry | Chrome RPM itself | — | `/usr/share/applications/google-chrome.desktop` ships in the RPM [VERIFIED: repo filelists.xml] — no Ansible task needed |
| Repo/key self-maintenance on live instance | Chrome RPM (`%post` + `/etc/cron.daily/google-chrome`) | — | Verified from Chromium source; the baked file must be byte-compatible (see Pitfall 1) |
| Chrome version updates over image life | Operator (rebake) | Chrome cron (runtime `dnf` possible) | Locked decision: remediation = rebake, matching SPAL precedent |
| Launch/render/sandbox proof | Phase 17 live UAT (human/AWS) | — | Explicitly out of this phase (CHROME-01) |

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `google-chrome-stable` (RPM) | 150.0.7871.186-1 at research date; latest-at-bake | The browser | Google's official signed package; only channel Google hosts for stable [VERIFIED: repo primary.xml] |
| Google repo | `https://dl.google.com/linux/chrome/rpm/stable/x86_64` | dnf source | Exact baseurl Chrome's own installer writes [VERIFIED: Chromium source rpm.include] |
| Google GPG key | `https://dl.google.com/linux/linux_signing_key.pub` | Package + metadata signing | Official key URL; active fingerprint `EB4C 1BFD 4F04 2F6D DDCC EC91 7721 F63B D38B 4796` [CITED: google.com/linuxrepositories] |
| `ansible.builtin.rpm_key` | ansible-core builtin (verified on 2.15) | Import key into rpm db before install | Existing repo idiom (Microsoft key in this same role; NICE key in dcv) [VERIFIED: local ansible-doc + repo grep] |
| `ansible.builtin.copy` | ansible-core builtin | Write byte-canonical `.repo` file | Repo convention for config files; only way to match Chrome's `%post` content byte-for-byte (see Pitfall 2) |
| `ansible.builtin.dnf` | ansible-core builtin | Install `google-chrome-stable` | Used by every role; `state: present` on fresh image = latest-at-bake and lint-clean |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| AL2023 core repo deps | `liberation-fonts` 2.1.5, `vulkan-loader` 1.3.x, `xdg-utils`, `wget`, `alternatives` | Chrome's hard requires | Auto-resolved by dnf — **do not** pre-install explicitly [VERIFIED: AL2023 primary.sqlite query] |
| Chrome's own cron | ships in RPM (`/etc/cron.daily/google-chrome`) | Keeps key + repo healthy at runtime | Nothing to do — verified benign against the canonical baked file |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ansible.builtin.copy` exact `.repo` | `ansible.builtin.yum_repository` | Module writes `key = value` (spaces); Chrome's `%post` overwrites the file anyway and its cron greps `^baseurl=` without spaces — divergent bytes create silent config drift. Rejected. |
| Baked repo + dnf install | Pinned `get_url` RPM (vscode_desktop pattern) | Google does not host historic RPMs — a pinned URL 404s within weeks (~4-6-week release cadence). Repo install is the only stable mechanism; also delivers CHROME-02's literal ".repo config" requirement. Rejected. |
| Leave `repo_add_once` alone | Pre-seed `/etc/default/google-chrome` with `repo_add_once="false"` | Only needed if the baked file diverges from canonical content. With byte-identical content the `%post` overwrite is a no-op — pre-seeding is an extra moving part with no benefit. Rejected (see Pitfall 1). |
| `gpgcheck=1` only in `.repo` | Add `repo_gpgcheck=1` line to `.repo` | Chrome's `%post` would strip the extra line on install (overwrite); CIS 1.2.4 already enforces `repo_gpgcheck=1` globally post-hardening, and Google's metadata IS signed — same enforcement, zero bake-failure surface. Rejected as a repo-file line; achieved globally via existing hardening. |

**Installation (what the role will run at bake):**
```bash
# equivalent of the three Ansible tasks
rpm --import https://dl.google.com/linux/linux_signing_key.pub
# write /etc/yum.repos.d/google-chrome.repo (canonical content, §Code Examples)
dnf install -y google-chrome-stable   # GPG verified; no --nogpgcheck
```

**Version verification:** performed in-session against the live repo (no npm/pip analog for rpm):
```bash
# current stable in Google's repo, from repodata/primary.xml (2026-07-24):
# google-chrome-stable 150.0.7871.186-1  (beta 151.x, canary 152.x)
```

## Package Legitimacy Audit

This phase installs **OS packages from a vendor rpm repo**, not language-registry packages —
`slopcheck` (npm/PyPI/crates tool) does not apply. The rpm-ecosystem equivalent was performed:

| Package | Registry | Age | Source | Signing | Disposition |
|---------|----------|-----|--------|---------|-------------|
| `google-chrome-stable` | dl.google.com official repo | repo live since ~2010 | Google (Chromium installer source verified) | RPM signed + repomd.xml.asc served; key fingerprints published on google.com/linuxrepositories | Approved [VERIFIED: direct repo metadata + .asc probes, official key page] |
| Transitive deps (liberation-fonts, vulkan-loader, xdg-utils, wget, alternatives, …) | AL2023 core (cdn.amazonlinux.com) | AL2023 GA 2023 | Amazon | Amazon-signed repo, metadata signed (.asc → HTTP 200) | Approved [VERIFIED: AL2023 primary.sqlite] |

**Packages removed due to slopcheck [SLOP] verdict:** none (tool not applicable — no language-registry installs)
**Packages flagged as suspicious [SUS]:** none
**New Ansible collections required:** none — all three modules are `ansible.builtin` [VERIFIED: local `ansible-doc` on core 2.15.13]; `ansible/requirements.yml` unchanged.

## Architecture Patterns

### System Architecture Diagram

```
BAKE TIME (packer build → ansible/playbook.yml, desktop role, BEFORE hardening)
────────────────────────────────────────────────────────────────────────────────
  dl.google.com/linux/linux_signing_key.pub
        │  (HTTPS)
        ▼
  [rpm_key] ──imports──▶ rpm db (both Google keys: active D38B4796 + obsolete 7FAC5991)
        │
        ▼
  [copy] ──writes──▶ /etc/yum.repos.d/google-chrome.repo   (canonical bytes, gpgcheck=1)
        │
        ▼
  [dnf install google-chrome-stable]
        ├── resolves deps ──▶ AL2023 core repo (liberation-fonts, vulkan-loader, xdg-utils, wget, alternatives)
        ├── downloads RPM ──▶ dl.google.com …/rpm/stable/x86_64  (sig verified against imported key)
        └── RPM %post:
              ├─ creates /etc/default/google-chrome (repo_add_once="true")
              ├─ install_yum: cat > google-chrome.repo   ◀── content NO-OP (file already canonical)
              └─ update-alternatives: /usr/bin/google-chrome
        │
        ▼
  /opt/google/chrome/* + /usr/bin/google-chrome-stable + /usr/share/applications/google-chrome.desktop
        │
        ▼
  … later roles … → [hardening] → CIS 1.2.2 (gpgcheck=0→1 sweep: no-op) + CIS 1.2.4 (dnf.conf repo_gpgcheck=1)
        │
        ▼
  [sbom.yml last import] ──▶ Chrome inventoried in /etc/devimage-sbom.cdx.json (ordinary behavior, not a requirement)

RUNTIME (live instance)
────────────────────────
  /etc/cron.daily/google-chrome ─▶ install_rpm_key (keeps key fresh) ─▶ verify_install (file exists → flips repo_add_once="false")
  GNOME app grid ─▶ google-chrome.desktop ─▶ /usr/bin/google-chrome  (Phase 17 UAT proves this)
```

### Recommended Change Footprint
```
ansible/roles/desktop/tasks/main.yml    # + one "# --- Google Chrome ---" block (3 tasks), appended after the VS Code block
```
Nothing else: no playbook.yml change, no layer_config.yml change, no defaults var (no version pin
— locked), no handlers, no new files.

### Pattern 1: Vendor-repo install with pre-imported key (this repo's idiom)
**What:** `rpm_key` → repo config → `dnf` with `disable_gpg_check: false` explicit.
**When to use:** Any signed third-party repo (SPAL uses a release RPM; Google has none, so the repo file is baked directly).
**Example:** see §Code Examples (the desktop role's VS Code block and the xrdp role's SPAL install are the in-repo precedents).

### Pattern 2: Unconditional-in-role content (no sub-gate)
**What:** Tasks live in `desktop/tasks/main.yml` with **no** `when:` of their own — gating comes solely from `role: desktop / when: layers.desktop` in playbook.yml.
**When to use:** Locked decision for Chrome (contrast: the VS Code block's `when: layers.vscode_desktop` sub-gate — explicitly NOT wanted here).
**Why it satisfies success criterion 3:** `layers.desktop: false` skips the whole role, so no repo/key/package lands — for free.

### Anti-Patterns to Avoid
- **`state: latest` on the dnf task** — triggers ansible-lint `package-latest` (production profile). `state: present` on a fresh AMI is already latest-at-bake.
- **Custom lines (comments, `repo_gpgcheck=`) inside the `.repo` file** — Chrome's `%post` overwrite silently deletes them (Pitfall 1). Keep authorship comments in the Ansible task, not in the deployed file.
- **A different repo filename** (e.g., `google.repo`) — `%post` writes its own `/etc/yum.repos.d/google-chrome.repo`, yielding two files defining `[google-chrome]` → duplicate-repo dnf errors.
- **`fingerprint:` on the rpm_key task** — operator's ansible-core 2.15 accepts a single fingerprint only, but the key file is a multi-key bundle (active + obsolete); a single-fingerprint pin can mismatch. Multi-fingerprint support landed upstream later (ansible/ansible PR #83493). Follow the in-repo precedent (MS/NICE keys: no fingerprint) [MEDIUM confidence on exact failure mode; the omission is the verified-safe path].

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Getting Chrome onto the image | `get_url` of the standalone RPM + localinstall | The baked Google repo + `dnf` | Standalone RPM URL is unversioned-latest anyway; repo delivers the literal CHROME-02 requirement and lets `dnf` resolve deps with GPG on |
| `/usr/bin/google-chrome` symlink | Manual `file: state: link` | RPM `%post` `update-alternatives` | Verified in chrome.spec.template; hand-rolling fights the RPM on every update |
| GNOME launcher entry | Custom `.desktop` file | RPM-shipped `/usr/share/applications/google-chrome.desktop` | Verified present in repo filelists.xml |
| Repo self-heal / key rotation on live instances | Custom cron/systemd timer | Chrome's own `/etc/cron.daily/google-chrome` | Its `install_rpm_key` handles the rpm "silent subkey import failure" gotcha (erase + reimport) that a naive script would hit |
| Version pinning | `google-chrome-stable-150.x` pin | Nothing (latest-at-bake, locked) | Google hosts only current stable — a pin 404s the next release and breaks every bake |

**Key insight:** Chrome's RPM actively manages its own repo config and key. Any bake-time config
that diverges from what Chrome itself writes becomes drift the moment `%post` runs. The only
stable strategy is to bake **exactly** what Chrome would write.

## Common Pitfalls

### Pitfall 1: Chrome's `%post` unconditionally overwrites the repo file
**What goes wrong:** Any customization of `/etc/yum.repos.d/google-chrome.repo` (comments, `repo_gpgcheck=1`, different formatting) silently disappears during `dnf install google-chrome-stable`.
**Why it happens:** `%post` creates `/etc/default/google-chrome` with `repo_add_once="true"` if absent, then runs `install_yum`, which does `cat > $YUM_REPO_FILE` — a full overwrite, no existence check [VERIFIED: chrome.spec.template lines 128-148 + rpm.include install_yum].
**How to avoid:** Bake the file byte-identical to the canonical content (§Code Examples). The overwrite becomes a no-op.
**Warning signs:** Post-bake `.repo` file differs from what the Ansible task wrote; a re-run of the role reports `changed` on the copy task.

### Pitfall 2: `ansible.builtin.yum_repository` writes `key = value` (spaces)
**What goes wrong:** File diverges from Chrome's grep expectations; the daily cron's `update_repo_file` matches `^baseurl=https://…` with **no spaces** — a spaced file is treated as "not configured," and dnf/CIS sweeps that match `^gpgcheck=0`/`^repo_gpgcheck` also miss spaced variants.
**Why it happens:** The module renders ini via configparser's default `key = value` format.
**How to avoid:** Use `ansible.builtin.copy` with exact `key=value` content. (dnf itself parses both, but byte-fidelity is what makes Pitfall 1 a no-op.)
**Warning signs:** `grep '^baseurl=' /etc/yum.repos.d/google-chrome.repo` returns nothing on the image.

### Pitfall 3: Multi-key bundle vs `rpm_key` fingerprint pinning
**What goes wrong:** Pinning `fingerprint:` (single value on ansible-core 2.15) against `linux_signing_key.pub` — which bundles the active key (`EB4C…4796`) AND the obsolete key (`4CCA…5991`) — can fail verification or skip later keys.
**Why it happens:** Older `rpm_key` only checks the first key in a file; list-of-fingerprints support arrived upstream later (ansible/ansible PR #83493, issues #50615/#83394).
**How to avoid:** Omit `fingerprint:` (matches the existing Microsoft/NICE key idiom); a single `rpm --import` of the bundle imports all keys on a fresh image. Document the active fingerprint in the task comment for human verification.
**Warning signs:** "fingerprint does not match" errors, or Chrome install failing GPG check with only one gpg-pubkey-* present.

### Pitfall 4: rpm silently fails importing new subkeys to an existing key
**What goes wrong:** On a long-lived system, a re-import of an updated key file does not add new subkeys — future packages signed by a new subkey fail GPG check (the recurring Fedora "SIGNATURE: NOT OK" reports).
**Why it happens:** rpm behavior, documented by Google itself [CITED: google.com/linuxrepositories].
**How to avoid:** Nothing to do at bake (fresh image imports the full current bundle). At runtime, Chrome's own cron handles rotation (erase + reimport, verified in rpm.include `install_rpm_key`). If a live instance ever hits it: rebake — consistent with the locked remediation policy.
**Warning signs:** Runtime `dnf update google-chrome-stable` GPG failures months after a bake.

### Pitfall 5: ansible-lint production-profile rules on the new tasks
**What goes wrong:** Push-stage `ansible-lint` (v26.4.0) failures.
**Why it happens / How to avoid:**
- `risky-file-permissions`: `copy` is on the rule's module list — set `mode: "0644"` explicitly [VERIFIED: rule source inspection]. (`rpm_key` and `dnf` are not on the list.)
- `package-latest`: use `state: present`, never `state: latest`.
- `fqcn`: use `ansible.builtin.rpm_key` / `ansible.builtin.copy` / `ansible.builtin.dnf` (current first-party convention despite the stale CONVENTIONS.md).
- `name[casing]`: task names start uppercase.
- No `no_log` needed — no secrets in this block.
**Warning signs:** `pre-commit run --hook-stage pre-push` failures.

### Pitfall 6: CIS hardening interplay (verified — all benign, but know why)
**What goes wrong (if unmanaged):** Assuming hardening might strip or break Chrome.
**Verified facts:**
- CIS 1.2.2 (enabled) rewrites `^gpgcheck=0` → `1` across `/etc/yum.repos.d/*.repo` — our file says `gpgcheck=1`; no-op.
- CIS 1.2.4 (enabled by default `amzn2023cis_rule_1_2_4: true`, NOT overridden in `hardening/defaults/main.yml`) sets `repo_gpgcheck=1` in `/etc/dnf/dnf.conf` — global, post-hardening, pre-existing behavior. Google, AL2023 core, and SPAL all serve signed `repomd.xml.asc` [VERIFIED: HTTP 200 probes on all three], so runtime dnf stays coherent.
- CIS 2.2.1 removes only `xorg-x11-server-common` (the X **server**) — Chrome is an X **client** (libX11 etc. via GNOME); unaffected on both DCV-only and xrdp builds [VERIFIED: cis_2.2.x.yml].
- CIS 6.1.12 SUID review is audit/warn-only — `/opt/google/chrome/chrome-sandbox` (SUID) survives [VERIFIED: cis_6.1.x.yml].
- No CIS rule or base sysctl restricts user namespaces (Chrome's modern sandbox path) [VERIFIED: grep of CIS defaults + base sysctl_tuning].
- Chrome install must (and does) happen **before** hardening simply by being in the desktop role — no ordering work needed.
**Warning signs:** none expected; sandbox/AVC runtime proof is Phase 17's explicit criterion.

### Pitfall 7: Success criterion 4 is already satisfied — don't touch what's green
**What goes wrong:** Well-meaning edits to playbook.yml or layer_config.yml to "wire" Chrome.
**How to avoid:** The desktop role is already gated and ordered. The entire change is additive inside `desktop/tasks/main.yml`. Run `pre-commit run --all-files` to confirm grep-gates stay green (none of the 10 gates pattern-match this change).

## Code Examples

### The canonical repo file content (byte-for-byte what Chrome's installer writes)
```
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
```
Source: Chromium installer source, `install_yum()` heredoc with `@@PACKAGE=google-chrome`,
`REPOCONFIG=https://dl.google.com/linux/chrome/rpm/stable`, `DEFAULT_ARCH=x86_64`
[VERIFIED: chromium.googlesource.com/chromium/src/+/main/chrome/installer/linux/common/rpm.include]

### Recommended task block (append to ansible/roles/desktop/tasks/main.yml)
```yaml
# --- Google Chrome (CHROME-02) — from Google's official signed dnf repo ---
# Unconditional desktop content: gated ONLY by layers.desktop via playbook.yml (operator
# decision — no vscode_desktop-style sub-flag). Latest-at-bake: Google's repo hosts only
# the current stable (historic RPMs are not hosted); remediation for a bad version is a
# rebake (SPAL precedent, CLAUDE.md §8). The .repo content below is byte-identical to what
# the Chrome RPM's %post writes (chromium.googlesource.com chrome/installer/linux/common/
# rpm.include install_yum), so the RPM's unconditional overwrite of this file at install is
# a content no-op and the daily google-chrome cron finds nothing to "fix".

- name: Import the Google Linux signing key (Chrome)
  # Multi-key bundle (active EB4C 1BFD 4F04 2F6D DDCC EC91 7721 F63B D38B 4796 + obsolete
  # 4CCA…5991 — google.com/linuxrepositories). No fingerprint: pin — ansible-core < 2.18
  # rpm_key verifies a single fingerprint against the bundle's first key and can mismatch;
  # a plain import lands all keys on a fresh image (same idiom as the MS key above).
  ansible.builtin.rpm_key:
    key: https://dl.google.com/linux/linux_signing_key.pub
    state: present

- name: Bake the Google Chrome dnf repo config (gpgcheck on)
  ansible.builtin.copy:
    dest: /etc/yum.repos.d/google-chrome.repo
    content: |
      [google-chrome]
      name=google-chrome
      baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
      enabled=1
      gpgcheck=1
      gpgkey=https://dl.google.com/linux/linux_signing_key.pub
    owner: root
    group: root
    mode: "0644"

- name: Install Google Chrome (latest-at-bake from the signed repo)
  ansible.builtin.dnf:
    name: google-chrome-stable
    state: present
    disable_gpg_check: false
```
Notes for the planner:
- Placement: end of `desktop/tasks/main.yml`, after the VS Code block (any position inside the role works; end-of-file mirrors the file's section style and keeps the diff additive).
- No `when:` on these tasks (locked: no sub-gate). Success criterion 3 (desktop:false unchanged) follows from the role-level gate in playbook.yml.
- No new defaults/vars (no version var — latest-at-bake is locked; adding an empty pin var would contradict the decision).
- The strings `--nogpgcheck` / `disable_gpg_check: true` must appear nowhere in the diff (success criterion 2); `disable_gpg_check: false` explicit matches the xrdp/dcv/vscode idiom.

### Verification commands (for the plan's verify steps — static, since CHROME-04 asserts are deferred)
```bash
# lint + gates (local, no AWS needed)
pre-commit run --all-files
pre-commit run --hook-stage pre-push ansible-lint
# syntax check of the playbook with the desktop layer on
ansible-playbook ansible/playbook.yml --syntax-check -e @ansible/layer_config.yml
# grep the diff for forbidden strings
git diff main -- ansible/ | grep -E "nogpgcheck|disable_gpg_check: true" && echo FAIL || echo OK
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-download Chrome RPM + `rpm -i` | Vendor dnf repo + GPG (repo self-managed by RPM `%post`/cron) | ~2010 onward, stable since | Repo install is the only supported/stable path; standalone RPM URL serves rolling latest |
| Google key 1024D/`7FAC5991` (2007) | 4096R/`D38B4796` (2016) + rotating subkeys | 2016 | Both ship in one bundle; import the bundle, don't pin a single fingerprint on core 2.15 |
| Unsigned third-party repo metadata (historic norm) | Google signs `repomd.xml` (`.asc` served) | verified live 2026-07-24 | Compatible with CIS 1.2.4's global `repo_gpgcheck=1` post-hardening |
| Desktop's browser = SPAL `chromium` only | chromium (SPAL) + google-chrome-stable (Google repo) coexist | this phase | Different package names/paths (`/usr/bin/chromium-browser` vs `/opt/google/chrome`); no conflict; chromium removal explicitly out of scope |

**Deprecated/outdated:** nothing relevant; the Chrome rpm repo layout and key URL have been stable for years (cross-checked against current Chromium `main` source).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The ansible `dnf` module needs the key pre-imported via `rpm_key` (it does not auto-accept key import prompts) | Standard Stack / task order | Low — pre-importing is harmless even if the module could auto-import; task order already handles it |
| A2 | ansible-core 2.15 `rpm_key` single-`fingerprint` pinning can mismatch on the multi-key bundle (exact failure mode not reproduced in-session) | Pitfall 3 | Low — recommendation (omit fingerprint) is safe under either behavior |
| A3 | Chrome's modern sandbox uses unprivileged user namespaces on AL2023's 6.1+ kernel (SUID fallback also present and CIS-survivable) | Pitfall 6 | Low for this phase — runtime sandbox proof is Phase 17's criterion; both sandbox paths verified present/unblocked statically |
| A4 | `packer build` invokes the operator's local ansible-playbook (core 2.15.13) — module behavior verified against that version locally | Environment Availability | Low — all three modules verified present with needed params on 2.15.13 |

## Open Questions

1. **Should the SPAL `chromium` package eventually be dropped now that Chrome ships?**
   - What we know: REQUIREMENTS.md marks Chromium as out of scope ("different support story"); the desktop role installs it today; both coexist without conflict.
   - What's unclear: whether the operator wants two Chromium-family browsers long-term (image size ~+330MB for Chrome).
   - Recommendation: leave `chromium` untouched this phase (locked scope); surface as a UAT-time question for the operator. Do NOT plan its removal.
2. **First-bake confirmation of `%post` no-op behavior.**
   - What we know: `%post` overwrite logic verified from Chromium `main` source; the baked content matches its heredoc byte-for-byte.
   - What's unclear: whether the shipping RPM's scriptlet lags the `main` source in some cosmetic way.
   - Recommendation: at the Phase 17 live session (or first bake), run `diff <(rpm -q --scripts google-chrome-stable | sed -n '/YUM_REPO_FILE/,$p') …` — or simply `cat /etc/yum.repos.d/google-chrome.repo` — to confirm the file is still canonical. No bake-assert (CHROME-04 deferred).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ansible-playbook (local) | Packer ansible provisioner at bake | ✓ | core 2.15.13 (below CLAUDE.md's documented ≥2.16 floor — pre-existing; all modules used here verified on 2.15) | brew upgrade if a bake hits a module gap |
| ansible-lint (local) | pre-push lint | ✓ | 6.22.2 local; CI/pre-commit pins v26.4.0 (authoritative) | `pre-commit run --hook-stage pre-push` uses the pinned venv |
| pre-commit | fast + push gates | ✓ | 4.6.0 | — |
| packer | bake (not needed for this phase's code deliverable) | ✓ | 1.12.0 | — |
| gitleaks / shellcheck | commit gates | ✓ | 8.30.1 / present | — |
| AWS creds + live bake | actually baking the AMI | ✗ (operator-run) | — | Phase deliverable is code + lint; bake/UAT is the operator's live session (composes with the open live-UAT backlog) |
| dl.google.com reachability from bake host | repo + key fetch at bake | ✓ (verified from workstation today) | — | none — bake fails loudly if Google is unreachable (acceptable; airgap policy allows vendor downloads) |

**Missing dependencies with no fallback:** none for the code deliverable. The live bake requires AWS creds (operator-run, as with every phase).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — (no auth surface added) |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | no | — (no user input path; config is static) |
| V6 Cryptography | yes (supply chain) | GPG package signatures (`gpgcheck=1`) + signed repo metadata (global `repo_gpgcheck=1` via CIS 1.2.4) + HTTPS transport — never hand-roll verification |
| V14 Configuration | yes | Baked, root-owned 0644 repo config; key fingerprints documented from Google's official page |

### Known Threat Patterns for this change

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tampered RPM in transit / mirror compromise | Tampering | `gpgcheck=1` + pre-imported Google key (fingerprint `EB4C…D38B 4796` published at google.com/linuxrepositories); signed repomd for metadata |
| Key-substitution via lookalike URL | Spoofing | Key + baseurl are the exact canonical Google URLs verified against Chromium source; HTTPS; document fingerprint in task comment |
| GPG bypass creep in future edits | Tampering | Success criterion 2 (`no --nogpgcheck / disable_gpg_check: true`); consider grep-verifying the diff in the plan's verify step |
| Browser attack surface on hardened image | Elevation of Privilege | Operator-accepted (same class as existing SPAL chromium); Chrome sandbox (userns/SUID) survives CIS (verified); runtime AVC/sandbox proof deferred to Phase 17 by design |
| Auto-update drift vs reproducibility | Repudiation/Drift | Latest-at-bake policy (locked); SBOM pass inventories the exact baked version as ordinary behavior; runtime cron may update Chrome via dnf — accepted, remediation = rebake |

## Sources

### Primary (HIGH confidence — verified in-session)
- Chromium installer source (chromium.googlesource.com/chromium/src, `main`): `chrome/installer/linux/common/rpm.include` (install_yum heredoc, install_rpm_key, update_bad_repo/update_repo_file), `chrome/installer/linux/common/rpmrepo.cron`, `chrome/installer/linux/rpm/chrome.spec.template` (%post) — repo content + overwrite/cron semantics
- https://www.google.com/linuxrepositories/ — official key URL, active/obsolete fingerprints, rpm subkey-import caveat
- Live Google repo probes: `…/rpm/stable/x86_64/repodata/{repomd.xml,repomd.xml.asc,primary.xml.gz,filelists.xml.gz}` — current versions, full Requires, shipped files, metadata signing
- Live AL2023 core repo metadata (cdn.amazonlinux.com mirror.list → primary.sqlite) — dependency availability incl. liberation-fonts, vulkan-loader, alternatives; `repomd.xml.asc` HTTP 200; SPAL `repomd.xml.asc` HTTP 200
- Local `ansible-doc` (core 2.15.13): `ansible.builtin.rpm_key`, `ansible.builtin.yum_repository` (params incl. `repo_gpgcheck`) ; ansible-lint 6.22.2 `risky_file_permissions.py` module list
- Codebase: `ansible/playbook.yml`, `roles/desktop|base|xrdp|hardening`, vendored `AMAZON2023-CIS` (rules 1.2.2/1.2.4/2.2.1/6.1.12 + defaults), `.pre-commit-config.yaml` grep-gates, `.ansible-lint`, `.github/workflows/ci.yml`

### Secondary (MEDIUM confidence)
- ansible/ansible PR #83493 (rpm_key multi-fingerprint support) + issues #50615, #83394 (multi-key bundle behavior) — https://github.com/ansible/ansible/pull/83493
- docs.ansible.com module reference pages for rpm_key / yum_repository

### Tertiary (LOW confidence — context only)
- Fedora Discussion threads on google-chrome GPG/"SIGNATURE: NOT OK" episodes (motivates Pitfall 4; not load-bearing for the recommendation)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every package, URL, version, and dependency verified against live repo metadata and Chromium source in-session
- Architecture: HIGH — change footprint is one file; invariants verified against actual grep-gate implementations
- Pitfalls: HIGH for %post/cron/lint/CIS interplay (source-verified); MEDIUM for rpm_key fingerprint edge behavior (upstream issues, not reproduced)

**Research date:** 2026-07-24
**Valid until:** ~2026-08-24 (Chrome version number will drift on its ~4-6-week cadence — irrelevant under latest-at-bake; repo layout/key stable for years)
