---
phase: "10-xrdp-xorgxrdp-from-source-build-role"
plan: "01"
subsystem: "ansible/xrdp-role"
tags: [ansible, xrdp, xorgxrdp, build-from-source, sha256-pin, rdp]
dependency_graph:
  requires: []
  provides:
    - "ansible/roles/xrdp/defaults/main.yml — pinned versions + sha256 + airgap-override base URL"
    - "ansible/roles/xrdp/tasks/main.yml — build pipeline: dep install + RDP-03 assert + xrdp build + xorgxrdp build"
  affects:
    - "Phase 11 — will wire role into ansible/playbook.yml before hardening; will configure xrdp.ini/sesman.ini/PAM/systemd"
tech_stack:
  added:
    - "xrdp 0.10.6 (from source, sha256-pinned)"
    - "xorgxrdp 0.10.5 (from source, sha256-pinned)"
    - "AL2023 build toolchain: gcc make autoconf automake libtool pkgconfig"
    - "AL2023 Xorg SDK: xorg-x11-server-devel mesa-libGL-devel"
    - "AL2023 codec deps: libjpeg-turbo-devel nasm pixman-devel"
    - "AL2023 crypto/auth deps: openssl-devel pam-devel"
    - "AL2023 X11 client libs: libX11-devel libXfixes-devel libXrandr-devel"
  patterns:
    - "get_url + checksum: sha256:{{ var }} — mirrors devops role mise pin convention (RDP-01)"
    - "ansible.builtin.assert after dnf register — RDP-03 hard-gate pattern from desktop role"
    - "command: + args: chdir:/creates: — idempotent build step from devtools Thrift pattern"
    - "environment: PKG_CONFIG_PATH on configure task — cross-prefix pkg-config discovery"
key_files:
  created:
    - "ansible/roles/xrdp/defaults/main.yml"
    - "ansible/roles/xrdp/tasks/main.yml"
  modified: []
decisions:
  - "Used get_url+checksum: sha256: (not committed tarballs) — mirrors repo convention; sha256 is the integrity guarantee regardless of transport"
  - "xrdp_source_base_url is configurable default var — airgap override is a one-variable change; integrity preserved by checksum pin"
  - "Included pixman-devel even though RESEARCH marked it [ASSUMED] — conservative: it satisfies both xrdp pixman codec and xorgxrdp glamor path; low risk if absent (just remove --enable-pixman flag)"
  - "Wrote all 3 task blocks in initial file create then refined comments in follow-up commit — no structural deviation from plan order"
metrics:
  started_at: "2026-06-15T18:10:00Z"
  completed_at: "2026-06-15T18:27:54Z"
  duration_minutes: 18
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 0
---

# Phase 10 Plan 01: xrdp + xorgxrdp From-Source Build Role Summary

**One-liner:** xrdp 0.10.6 + xorgxrdp 0.10.5 built from sha256-pinned source tarballs via `get_url+checksum:`, with AL2023 Xorg SDK deps and a loud RDP-03 hard-gate assert — binary lands at `/usr/local/sbin/xrdp`, Xorg modules at `/usr/lib64/xorg/modules/drivers/xrdpdev_drv.so`.

## What Was Built

Created `ansible/roles/xrdp/` — a build-only Ansible role that:

1. **defaults/main.yml** — pins `xrdp 0.10.6` and `xorgxrdp 0.10.5` with their VERIFIED sha256 hashes and a configurable `xrdp_source_base_url` (default: `https://github.com/neutrinolabs`). Airgap override is a single variable change; sha256 pin is enforced regardless of transport.

2. **tasks/main.yml** — 14-step pipeline:
   - Installs 16 AL2023 core-repo build deps in one `ansible.builtin.dnf` task (no EPEL, no third-party repo)
   - **RDP-03 hard gate**: `ansible.builtin.assert` that names `xorg-x11-server-devel` explicitly and points operator at `dnf info` for diagnosis; `quiet: false` so it is always visible
   - Downloads and sha256-verifies `xrdp-0.10.6.tar.gz` via `get_url + checksum: sha256:{{ xrdp_checksum_sha256 }}`
   - Extracts, configures (`--prefix=/usr/local --sysconfdir=/etc --enable-pam --with-pam-rules=redhat --enable-jpeg --enable-tjpeg --enable-pixman --disable-tests`), builds, installs xrdp to `/usr/local/sbin/xrdp`
   - Downloads and sha256-verifies `xorgxrdp-0.10.5.tar.gz` via `get_url + checksum: sha256:{{ xorgxrdp_checksum_sha256 }}`
   - Extracts, configures with `environment: PKG_CONFIG_PATH: /usr/local/lib/pkgconfig` (critical: discovers installed xrdp.pc), builds, installs xorgxrdp modules to `/usr/lib64/xorg/modules/drivers/xrdpdev_drv.so`
   - SELinux relabel: `restorecon -Rv /usr/lib64/xorg/modules/` with `changed_when: false`
   - Cleanup: removes both extracted source trees and tarballs from `/tmp`

## Per-Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Role defaults + build-dep install + RDP-03 hard-gate assert | `b12864f` | ansible/roles/xrdp/defaults/main.yml, ansible/roles/xrdp/tasks/main.yml (initial create) |
| 2 | Fetch + sha256-verified build + install xrdp | `9991e6b` | ansible/roles/xrdp/tasks/main.yml (comment cleanup for scope-guard grep compliance) |
| 3 | Fetch + sha256-verified build + install xorgxrdp | (in `b12864f`) | xorgxrdp block was part of the initial file create; all Task 3 verifications pass on committed content |

**Note on commit structure:** All three task blocks were written in the initial file creation (commit `b12864f`). Commit `9991e6b` refined comments to satisfy the Task 2 scope-guard grep check (`! grep -nE 'systemd:|enabled: true|\.ini|pam\.d'`). Task 3's acceptance criteria are fully met by the content in `b12864f`+`9991e6b`.

## Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| RDP-01: sha256-pinned vendored source | SATISFIED | `xrdp_checksum_sha256` and `xorgxrdp_checksum_sha256` in defaults; both `get_url` tasks carry `checksum: "sha256:{{ ... }}"` |
| RDP-02: AL2023 toolchain + Xorg SDK install; compile + install both packages | SATISFIED | dnf task installs 16 deps from AL2023 core; xrdp configure/make/install sequence; xorgxrdp configure with PKG_CONFIG_PATH then make/install |
| RDP-03: Hard-gate assert if build dep missing | SATISFIED | `ansible.builtin.assert` follows dnf register; fail_msg names `xorg-x11-server-devel`; `quiet: false` |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Scope Guard] Removed EPEL and bootstrap references from comments**
- **Found during:** Task 1/2 verification
- **Issue:** The plan's scope-guard grep check (`! grep -ri 'epel'` and `! grep -nE 'bootstrap|...'`) would match comment lines that mentioned these terms as negative examples (e.g., "no EPEL or third-party repo" comment, "./bootstrap is NOT needed" comment)
- **Fix:** Rewrote those comments to preserve meaning without triggering the grep gate (e.g., "no third-party repo" instead of "no EPEL or third-party repo"; "no build-system regeneration step needed" instead of "./bootstrap is not needed")
- **Files modified:** `ansible/roles/xrdp/tasks/main.yml`
- **Commit:** `9991e6b`

## Known Stubs

None. This is a build-only role. No data flows to UI. No placeholder values — all version strings, checksums, and paths are final and load-bearing.

## Threat Flags

No new network endpoints or auth paths introduced in this plan. xrdp's `:3389` listener and PAM auth boundary are Phase 11. No threat flags beyond what the plan's threat model already captures.

| Flag | File | Description |
|------|------|-------------|
| T-10-04 (accepted) | ansible/roles/xrdp/tasks/main.yml | Build toolchain (`*-devel`, `gcc`, `make`) baked into AMI; accepted — single-operator image, SSM-only access, no public ingress in this phase |

## Self-Check

### Files exist
- `ansible/roles/xrdp/defaults/main.yml` — FOUND
- `ansible/roles/xrdp/tasks/main.yml` — FOUND

### Commits exist
- `b12864f` — FOUND (feat(10): add xrdp role defaults + build deps + RDP-03 hard-gate assert)
- `9991e6b` — FOUND (feat(10): xrdp fetch + sha256-verified build + install to /usr/local/sbin/xrdp)

### Verification checks
- defaults.yml sha256 pins: PASS
- tasks.yml package list (all 16 deps): PASS
- RDP-03 assert present with xorg-x11-server-devel in fail_msg: PASS
- xrdp get_url checksum: sha256:{{ xrdp_checksum_sha256 }}: PASS
- configure flags (--prefix=/usr/local --with-pam-rules=redhat --enable-pam): PASS
- creates: /usr/local/sbin/xrdp: PASS
- xorgxrdp get_url checksum: sha256:{{ xorgxrdp_checksum_sha256 }}: PASS
- PKG_CONFIG_PATH: /usr/local/lib/pkgconfig on xorgxrdp configure: PASS
- creates: /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so: PASS
- Ordering (xrdp install before xorgxrdp): PASS
- restorecon with changed_when: false: PASS
- No EPEL repo: PASS
- No bootstrap task: PASS
- No systemd/ini/pam.d task: PASS
- YAML validity (both files): PASS
- ansible-lint: no new errors (only pre-existing .ansible-lint config file issue)

## Self-Check: PASSED
