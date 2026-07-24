# Phase 16: Chrome in the desktop role - Pattern Map

**Mapped:** 2026-07-24
**Files analyzed:** 1 modified (0 created)
**Analogs found:** 1 / 1 (composite — three in-repo idioms cover the three new tasks)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `ansible/roles/desktop/tasks/main.yml` (append 3-task Chrome block) | ansible role task file (bake-time provisioning) | batch / file-I-O (GPG key import → config file write → package install) | Same file's VS Code block (`ansible/roles/desktop/tasks/main.yml:128-158`) + `ansible/roles/dcv/tasks/main.yml:19-24` + `ansible/roles/xrdp/tasks/main.yml:59-72` | exact (per-task); composite for the block as a whole |

**No new files.** Per RESEARCH.md (locked): no `files/` entry (the `.repo` content must be inline `content:` for byte-canonical fidelity with Chrome's `%post`), no playbook.yml change, no defaults var, no handlers, no `ansible/requirements.yml` change (all three modules are `ansible.builtin`).

## Pattern Assignments

### `ansible/roles/desktop/tasks/main.yml` — Chrome block (3 tasks, appended after the VS Code block)

The block decomposes into three tasks; each has a distinct best analog. Placement: **end of file, after line 158** (after the VS Code block — mirrors the file's `# --- Section ---` style, keeps the diff purely additive).

#### Task 1 — `rpm_key` vendor GPG key import

**Analog (primary):** `ansible/roles/dcv/tasks/main.yml` lines 19-24 — the cleanest vendor-key idiom, with the section-comment convention:

```yaml
# --- NICE GPG key — import BEFORE any RPM install (airgap integrity gate, DCV-01) ---

- name: Import NICE GPG key
  ansible.builtin.rpm_key:
    key: https:<MRCLEAN:ENTROPY:001>
    state: present
```

**Analog (same-file):** `ansible/roles/desktop/tasks/main.yml` lines 138-141 (inside the VS Code block):

```yaml
    - name: Import Microsoft GPG key (VS Code)
      ansible.builtin.rpm_key:
        key: https://packages.microsoft.com/keys/microsoft.asc
        state: present
```

**Copy exactly:** key-before-install ordering, `state: present`, **no `fingerprint:` param** (neither analog pins one — RESEARCH.md Pitfall 3: the Google key file is a multi-key bundle and ansible-core 2.15's single-fingerprint pin can mismatch; document the active fingerprint `EB4C 1BFD 4F04 2F6D DDCC EC91 7721 F63B D38B 4796` in a task comment instead, per the dcv role's comment-the-rationale style).

#### Task 2 — `copy` with inline `content:` for the `.repo` file

**Analog (same-file):** `ansible/roles/desktop/tasks/main.yml` lines 34-43 — inline-content config file, exact `key=value` bytes, quoted mode:

```yaml
- name: Disable GNOME screen lock via dconf system defaults
  ansible.builtin.copy:
    dest: /etc/dconf/db/local.d/01-screensaver
    content: |
      [org/gnome/desktop/screensaver]
      lock-enabled=false

      [org/gnome/desktop/session]
      idle-delay=uint32 0
    mode: "0644"
```

**Analog (secondary):** `ansible/roles/certs/tasks/main.yml` lines 27-38 (`/etc/profile.d/ca-trust.sh`) — same `copy` + `content: |` + `mode: "0644"` shape, gated variant.

**Analog (ownership fields):** `ansible/roles/xrdp/tasks/main.yml` lines 79-85 — root-owned system config file with explicit `owner`/`group`:

```yaml
- name: Install /etc/pam.d/xrdp-sesman delegating to password-auth (XRDP-02)
  ansible.builtin.copy:
    src: xrdp-sesman.pam
    dest: /etc/pam.d/xrdp-sesman
    owner: root
    group: root
    mode: "0644"
```

**Copy exactly:** `content: |` literal block (NOT `src:` — byte-fidelity requirement), `owner: root` / `group: root` / `mode: "0644"` (quoted — `risky-file-permissions` lint rule lists `copy`). The exact `.repo` bytes are in RESEARCH.md §Code Examples ("canonical repo file content") — no spaces around `=` (Pitfall 2 rules out `ansible.builtin.yum_repository`).

**Note — no exact in-repo analog writes a `.repo` file directly.** The only existing third-party repo (SPAL, `ansible/roles/base/tasks/main.yml:44-48`) is enabled via a vendor release RPM (`dnf install spal-release`) that drops the repo file itself. Google ships no release RPM, so `copy` is the substitute; this is a deliberate, researched deviation, not drift. Quote base's block as the contrast precedent if the plan needs to justify the approach:

```yaml
- name: Enable SPAL via the Amazon-signed spal-release package
  ansible.builtin.dnf:
    name: spal-release
    state: present
    disable_gpg_check: false
```

#### Task 3 — `dnf` install from the signed repo

**Analog (primary):** `ansible/roles/xrdp/tasks/main.yml` lines 59-72 — repo-sourced install with the GPG comment convention (trim the version-pin Jinja; Chrome is latest-at-bake, locked):

```yaml
# --- Install xrdp + xorgxrdp from SPAL (XRDP-01) ---
# SPAL is an EPEL9 rebuild; xrdp/xorgxrdp are EPEL9 packages, expected present. The SPAL GPG
# key was imported by spal-release (base role), so disable_gpg_check stays false. ...

- name: Install xrdp + xorgxrdp from the SPAL repo (XRDP-01)
  ansible.builtin.dnf:
    name:
      - "xrdp{{ ('-' ~ xrdp_version) if (xrdp_version | length > 0) else '' }}"
      - "xorgxrdp{{ ('-' ~ xrdp_xorgxrdp_version) if (xrdp_xorgxrdp_version | length > 0) else '' }}"
    state: present
    disable_gpg_check: false
```

**Analog (comment style for the GPG stance):** `ansible/roles/dcv/tasks/main.yml` lines 83-92:

```yaml
- name: Install DCV RPMs (nice-dcv-server, nice-xdcv, nice-dcv-web-viewer)
  # disable_gpg_check stays false — the NICE GPG key imported above verifies the signature.
  # NEVER add --nogpgcheck (CLAUDE.md §8 / airgap §2).
  ansible.builtin.dnf:
    name:
      - "{{ dcv_server_rpm.files[0].path }}"
      ...
    state: present
    disable_gpg_check: false
```

**Copy exactly:** `state: present` (never `latest` — `package-latest` lint rule; fresh AMI = latest-at-bake anyway), explicit `disable_gpg_check: false` (the repo-wide idiom in desktop/vscode line 153, xrdp line 72, dcv line 92, base line 48), the "NEVER add --nogpgcheck" comment style.

### Anti-analog — the VS Code sub-gate (do NOT copy this part)

`ansible/roles/desktop/tasks/main.yml` lines 135-137 wrap the VS Code tasks in a gated block:

```yaml
- name: Install Visual Studio Code desktop editor
  when: layers.vscode_desktop | default(true)
  block:
```

**Chrome must NOT get this.** Locked decision (RESEARCH.md §User Constraints): no sub-gate flag, no `when:`, no `block:` wrapper. Gating comes solely from the role-level gate in `ansible/playbook.yml` lines 69-70:

```yaml
    - role: desktop
      when: layers.desktop | default(false)
```

Also do NOT copy the VS Code block's `get_url`-pinned-RPM mechanics (lines 143-158) — Google hosts no historic RPMs (RESEARCH.md §Alternatives Considered rejects it), and no `/tmp` cleanup task is needed since nothing is downloaded to disk.

## Shared Patterns

### GPG posture (rpm_key pre-import + explicit disable_gpg_check: false)
**Sources:** `ansible/roles/dcv/tasks/main.yml:19-24,83-92`; `ansible/roles/desktop/tasks/main.yml:138-141,150-153`; `ansible/roles/xrdp/tasks/main.yml:66-72`; `ansible/roles/base/tasks/main.yml:44-48`
**Apply to:** Chrome tasks 1 and 3. The strings `--nogpgcheck` / `disable_gpg_check: true` must appear nowhere in the diff (phase success criterion 2; grep-verify in the plan's verify step per RESEARCH.md §Verification commands).

### Section-comment + requirement-ID convention
**Sources:** every role touched — `# --- Section name (REQ-ID) ---` headers with multi-line rationale prose above the tasks; requirement IDs in task names (`(XRDP-01)`, `(DCV-01)`).
**Apply to:** the Chrome block header (`# --- Google Chrome (CHROME-02) — from Google's official signed dnf repo ---`) and task names should carry `(CHROME-02)` or a rationale suffix. RESEARCH.md's recommended block already follows this. Keep authorship comments in the Ansible task, never inside the deployed `.repo` content (Pitfall 1 — `%post` overwrite deletes them).

### Lint conventions (ansible-lint v26.4.0 production profile, push-stage)
**Sources:** all current first-party roles.
**Apply to:** all three tasks — FQCN (`ansible.builtin.rpm_key|copy|dnf`), task names start uppercase (`name[casing]`), quoted `mode: "0644"` on `copy` (`risky-file-permissions`), `state: present` (`package-latest`). No `no_log` needed (no secrets in this block). Ignore `.planning/codebase/CONVENTIONS.md`'s stale "bare module names" note — current code + lint enforce FQCN.

### Kludge/workaround placement (memory rule — not triggered here)
Workarounds go in their own named playbook imported by the main one (cf. `ansible/firewalld-docker-fix.yml`). The Chrome block is standard provisioning, not a kludge — it belongs inline in the role. Noted so the planner does not misapply the rule to the byte-canonical `.repo` trick (which is a content choice inside a normal task, not a workaround play).

## No Analog Found

None. All three tasks have direct in-repo idioms. The single partial gap — no existing role authors a `.repo` file via `copy` (SPAL uses a release RPM) — is covered by the copy-with-`content:` idiom plus RESEARCH.md's verified byte-canonical content, and is documented under Task 2 above.

## Reference: files the planner must NOT touch

| File | Why it stays untouched |
|------|------------------------|
| `ansible/playbook.yml` | desktop role already wired before `hardening` (lines 69-70, 85); hardening-last invariant is grep-gated |
| `ansible/layer_config.yml` | `layers.desktop` gate pre-exists; no new flag (locked: no sub-gate) |
| `ansible/roles/desktop/defaults/main.yml` (if any) | no version var — latest-at-bake is locked; an empty pin var would contradict the decision |
| `ansible/sbom.yml` | Chrome is inventoried by the existing pass automatically (CHROME-03 deferred) |
| SPAL `chromium` entry (`desktop/tasks/main.yml:22`) | explicitly out of scope — coexists with Chrome |

## Metadata

**Analog search scope:** `ansible/roles/{desktop,xrdp,dcv,certs,base,ai_tools}/tasks/`, `ansible/playbook.yml`
**Files scanned:** 6 (5 read in full or targeted section, 1 line-count/grep only — ai_tools not needed once stronger dnf analogs were confirmed)
**Pattern extraction date:** 2026-07-24
