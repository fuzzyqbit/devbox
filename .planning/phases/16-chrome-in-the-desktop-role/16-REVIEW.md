---
phase: 16-chrome-in-the-desktop-role
reviewed: 2026-07-24T13:26:21Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - ansible/roles/desktop/tasks/main.yml
findings:
  critical: 1
  warning: 2
  info: 3
  total: 6
status: issues_found
---

# Phase 16: Code Review Report

**Reviewed:** 2026-07-24T13:26:21Z
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

Reviewed `ansible/roles/desktop/tasks/main.yml` with focus on the phase-16 Chrome block
(lines 160–200, commit `f778b56`). The Chrome block itself is well-constructed and its
load-bearing claims were independently verified during this review:

- **Byte-identity claim verified against upstream.** The baked `.repo` content was compared
  against `chrome/installer/linux/common/rpm.include` fetched from
  chromium.googlesource.com (`install_yum`, with `@@PACKAGE=google-chrome`,
  `$REPOCONFIG=https://dl.google.com/linux/chrome/rpm/stable`, `$DEFAULT_ARCH=x86_64`).
  The six lines match exactly, including trailing newline — the "%post overwrite is a
  content no-op" rationale holds.
- **rpm_key `< 2.18` claim verified against module source.** `getfingerprint()` in the
  installed ansible-core (2.15.x, same behavior through 2.17) returns only the *first*
  `fpr:` line of the key file, so a single `fingerprint:` pin against Google's multi-key
  bundle can indeed mismatch. The in-comment rationale is factually accurate.
- **Gating and ordering verified.** The desktop role is gated on `layers.desktop` in
  `playbook.yml` and runs before `hardening` (last-role invariant intact; grep-gate #9
  unaffected). GPG posture invariants hold: `gpgcheck=1`, `disable_gpg_check: false`,
  no `--nogpgcheck` anywhere in the block.
- **Lint/syntax verified.** `ansible-lint` (production profile) passes 0/0 on the file;
  `ansible-playbook --syntax-check -e @layer_config.yml` passes.
- **Spec conformance verified.** Plan 16-01 explicitly mandates: no sub-flag, no
  `repo_gpgcheck` line, `state: present` (not `latest`), retention of the SPAL `chromium`
  package. The implementation matches the plan on all four points.

Remaining findings: one Warning against the phase-16 change (key trust is anchored solely
in TLS at bake time with no post-import verification), plus pre-existing issues in the
same file that are load-bearing for the phase's own "GPG verification stays ON (§2/§8)"
rationale — most notably the unverified ffmpeg static-binary download, which is the one
place in this role where the posture the Chrome comments cite is actually violated.

## Critical Issues

### CR-01: [PRE-EXISTING] ffmpeg/ffprobe installed as root from an unverified, unpinned third-party download

**File:** `ansible/roles/desktop/tasks/main.yml:57-103`
**Introduced by:** pre-phase-16 (not part of commit `f778b56`) — reported because it is
load-bearing: the Chrome block's comments cite the CLAUDE.md §2/§8 verification posture
("GPG verification stays ON"), and this task block is the standing violation of that
posture in the same file.
**Issue:** `get_url` fetches `https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz`
with **no `checksum:`**, no GPG verification, and no version pin (the `ffmpeg-release-*`
URL is a floating "latest" alias), then copies the extracted binaries to
`/usr/local/bin/{ffmpeg,ffprobe}` mode 0755 as root. Every other install path in this
role is signature-verified (dnf gpgcheck, rpm_key-verified RPM, flatpak OSTree
signatures); this is the sole unverified arbitrary-binary path onto the hardened image.
A compromise of this single-maintainer personal site (or its CDN) puts an attacker
binary on every subsequent bake, silently. TLS is the only control.
**Fix:** Pin the versioned tarball and its checksum (the site publishes md5 alongside
each build; compute and pin sha256 once at adoption):
```yaml
- name: Download ffmpeg static build (pinned + checksummed)
  ansible.builtin.get_url:
    url: "https://johnvansickle.com/ffmpeg/releases/ffmpeg-{{ ffmpeg_static_version }}-amd64-static.tar.xz"
    dest: /tmp/ffmpeg-static.tar.xz
    checksum: "sha256:{{ ffmpeg_static_sha256 }}"
    mode: "0644"
```
with `ffmpeg_static_version` / `ffmpeg_static_sha256` in `roles/desktop/defaults/main.yml`
(same deliberate-bump pattern as `vscode_desktop_version`). Alternatively source ffmpeg
from a signed repo (e.g. the SPAL/EPEL9 ecosystem already enabled in base) and drop the
static build entirely.

## Warnings

### WR-01: Google signing-key trust is TLS-only at bake time — no post-import fingerprint verification

**File:** `ansible/roles/desktop/tasks/main.yml:170-178`
**Issue:** The `rpm_key` task imports `https://dl.google.com/linux/linux_signing_key.pub`
with no `fingerprint:` and no compensating post-import check. The comment's reason for
omitting `fingerprint:` is correct (verified: pre-2.18 `getfingerprint()` compares only
the bundle's first key), but that only rules out *that parameter* — it does not justify
having *zero* verification. As written, the sole trust anchor for every future
`gpgcheck=1` verification of Chrome packages is a single TLS connection at bake time: a
MITM or CDN-edge compromise that serves a malicious key bundle would be silently
imported, after which `gpgcheck=1` happily verifies attacker-signed RPMs. This weakens
the spirit of the §8 SHA-pin invariant (mutable refs are exactly what that invariant
exists to exclude). The MS-key task (line 138) shares the gap, but this phase repeats
the idiom rather than fixing it.
**Fix:** Keep the plain import (multi-key bundle lands intact), then assert the expected
active key actually arrived, pinned by full 40-hex fingerprint (documented in the task
comment already — `EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796`):
```yaml
- name: Assert the active Google signing key landed (fingerprint pin)
  ansible.builtin.shell: |
    set -o pipefail
    rpm -q gpg-pubkey-d38b4796 --qf '%{Pubkeys:armor}\n' \
      | gpg --show-keys --with-colons - \
      | grep -q '^fpr:::::::::EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796:'
  changed_when: false
```
(If ansible-core is ever floored at ≥ 2.18, replace both with the native list-form
`fingerprint:` parameter.) The same assert pattern is cheap to add for the Microsoft key.

### WR-02: [PRE-EXISTING] Unchecked `files[0]` index on find results — opaque bake failure mode

**File:** `ansible/roles/desktop/tasks/main.yml:93,100`
**Introduced by:** pre-phase-16; adjacent to CR-01's block.
**Issue:** `{{ ffmpeg_bin.files[0].path }}` and `{{ ffprobe_bin.files[0].path }}` index
into `find` results without checking `matched > 0`. If the upstream tarball layout
changes (or the download silently serves an HTML error page that `unarchive` rejects in
a later shape), the bake dies with a raw Jinja "list object has no element 0" instead of
a diagnosable message — this role's own convention elsewhere (base SPAL floor check,
W1/W1b guards) is loud asserts.
**Fix:**
```yaml
- name: Assert ffmpeg/ffprobe binaries were found in the archive
  ansible.builtin.assert:
    that:
      - ffmpeg_bin.matched > 0
      - ffprobe_bin.matched > 0
    fail_msg: "ffmpeg static tarball layout changed — no ffmpeg/ffprobe binary found under /tmp/ffmpeg-extract"
```

## Info

### IN-01: Two full browser stacks are now baked (SPAL chromium + google-chrome-stable)

**File:** `ansible/roles/desktop/tasks/main.yml:22,194-200`
**Issue:** The image now carries both EPEL9-rebuild `chromium` (SPAL: no AWS CVE
tracking, upstream-only patches per the §8 caveat) and `google-chrome-stable`. This is
**intentional per plan 16-01** ("no removal of the SPAL `chromium` package — line 22
stays") and is not a defect — noted so the doubled browser patch surface is a recorded,
reviewed decision rather than an oversight.
**Fix:** None required. If Chrome proves out in Phase 17 UAT, consider a follow-up to
drop SPAL chromium and shrink the unpatched-surface delta.

### IN-02: Chrome's permanently-unpinnable latest-at-bake posture is not recorded in CLAUDE.md

**File:** `ansible/roles/desktop/tasks/main.yml:160-168` (documentation gap, not a code defect)
**Issue:** Every other floating dependency has a ratchet or caveat on record: the Packer
SSM `:NN` pin and the SPAL xrdp pin are §9 follow-ups, and SPAL has a §8 caveat block.
Chrome is the only package that can *never* be pinned (Google hosts only current
stable), and that tradeoff currently lives only in a task comment. The commit
intentionally touches only `tasks/main.yml` per plan scope.
**Fix:** In a docs commit, add a short Chrome caveat next to the SPAL caveat in
CLAUDE.md §8 (latest-at-bake, rebake-to-remediate, repo left `enabled=1` so live
instances can drift via `dnf update`).

### IN-03: [PRE-EXISTING] `changed_when: false` on flathub remote-add misreports first-run state change

**File:** `ansible/roles/desktop/tasks/main.yml:119-121`
**Issue:** `flatpak remote-add --if-not-exists` *does* mutate system state on a fresh
image (the normal bake case), so `changed_when: false` is inaccurate — harmless on a
one-shot bake but wrong as a pattern.
**Fix:** Register the command and detect change, or use
`community.general.flatpak_remote` (collection already in requirements) which reports
change correctly.

---

_Reviewed: 2026-07-24T13:26:21Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
