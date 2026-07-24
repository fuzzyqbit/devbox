---
phase: 10-xrdp-xorgxrdp-from-source-build-role
verified: 2026-06-15T19:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 10: xrdp / xorgxrdp From-Source Build Role Verification Report

**Phase Goal:** A new `xrdp` Ansible role builds and installs xrdp and the xorgxrdp Xorg backend from vendored, pinned source at bake — entirely offline — failing loudly if the Xorg SDK is missing rather than producing a half-installed image.

**Verified:** 2026-06-15T19:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The `xrdp` Ansible role exists with xrdp 0.10.6 + xorgxrdp 0.10.5 versions and their sha256 pins in defaults/main.yml | VERIFIED | `ansible/roles/xrdp/defaults/main.yml` lines 7–13: `xrdp_version: "0.10.6"`, sha256 `dfc21d5d...`, `xorgxrdp_version: "0.10.5"`, sha256 `a5d034...`; configurable `xrdp_source_base_url` at line 23 |
| 2 | The role installs the autotools build toolchain + Xorg SDK from the AL2023 dnf mirror | VERIFIED | `tasks/main.yml` Task 1 (line 10): `ansible.builtin.dnf` installs all 16 deps from AL2023 core including `xorg-x11-server-devel` and `mesa-libGL-devel`; no EPEL or third-party repo task |
| 3 | The bake aborts with an explicit human-readable assert if xorg-x11-server-devel (or any build dep) is unavailable | VERIFIED | `tasks/main.yml` Task 2 (line 33): `ansible.builtin.assert` with `that: [xrdp_build_deps_install is success]`, `quiet: false`, `fail_msg` explicitly names `xorg-x11-server-devel` and points operator at `dnf info xorg-x11-server-devel` |
| 4 | xrdp source is fetched with sha256 verification from a configurable base URL, then compiled and installed (xrdp binary present at /usr/local/sbin/xrdp) | VERIFIED | Tasks 3–7: `get_url` with `checksum: "sha256:{{ xrdp_checksum_sha256 }}"` (line 53); configure with `--prefix=/usr/local --sysconfdir=/etc --enable-pam --with-pam-rules=redhat`; install `creates: /usr/local/sbin/xrdp` (line 96) |
| 5 | xorgxrdp builds against the installed xrdp pkg-config (PKG_CONFIG_PATH=/usr/local/lib/pkgconfig) and installs its Xorg driver module | VERIFIED | Tasks 8–12: xorgxrdp `get_url` with `checksum: "sha256:{{ xorgxrdp_checksum_sha256 }}"` (line 107); configure task (line 122) has `environment: PKG_CONFIG_PATH: /usr/local/lib/pkgconfig`; install `creates: /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so` (line 147); xorgxrdp block is Tasks 8–12, after xrdp install in Task 7 |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `ansible/roles/xrdp/defaults/main.yml` | Pinned versions + sha256 + configurable source base URL | VERIFIED | 27 lines; valid YAML; 7 keys including all 5 required vars |
| `ansible/roles/xrdp/tasks/main.yml` | dep install + RDP-03 assert + xrdp build + xorgxrdp build | VERIFIED | 169 lines; valid YAML; 14 tasks in correct spine order |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `tasks/main.yml` | `defaults/main.yml` | `xrdp_checksum_sha256` var in `get_url checksum:` | WIRED | `checksum: "sha256:{{ xrdp_checksum_sha256 }}"` at line 53; `xorgxrdp_checksum_sha256` at line 107 |
| `tasks/main.yml` | `defaults/main.yml` | `xrdp_source_base_url` in `get_url url:` | WIRED | URL built as `{{ xrdp_source_base_url }}/xrdp/releases/download/...` at line 50 |
| `xorgxrdp configure task` | `/usr/local/lib/pkgconfig/xrdp.pc` (installed by xrdp make install) | `environment: PKG_CONFIG_PATH` | WIRED | Task 10 `environment: PKG_CONFIG_PATH: /usr/local/lib/pkgconfig` at line 127–128; Task 7 (xrdp make install) places `xrdp.pc` there |
| `RDP-03 assert task` | dnf install result | `xrdp_build_deps_install is success` | WIRED | Task 1 registers `xrdp_build_deps_install`; Task 2 asserts it `is success` |

---

### Data-Flow Trace (Level 4)

Not applicable. This is a build-only Ansible role with no UI or data rendering. No dynamic state/props to trace.

---

### Behavioral Spot-Checks

Static-only verification is appropriate for this phase. The actual compilation runs during a Packer bake against a live EC2 instance with AWS credentials — this cannot be invoked without running the full bake pipeline. The role structure is fully verifiable statically.

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| YAML validity — defaults | `python3 -c "import yaml; yaml.safe_load(open('ansible/roles/xrdp/defaults/main.yml'))"` | success, 7 keys | PASS |
| YAML validity — tasks | `python3 -c "import yaml; yaml.safe_load(open('ansible/roles/xrdp/tasks/main.yml'))"` | success, 14 tasks | PASS |
| sha256 pins exact match | Python assert on both hashes vs plan-specified values | exact match | PASS |
| RDP-03 quiet:false | Python introspection on parsed task | `quiet` is `False` (bool) | PASS |
| No EPEL references | `grep -rni 'epel' ansible/roles/xrdp/` | no matches (exit 1) | PASS |
| Scope guard clean | `grep -nE 'systemd:\|enabled: true\|\.ini\|pam\.d'` tasks | no matches (exit 1) | PASS |
| Commit b12864f exists | `git rev-parse b12864f` | `b12864fd1e8c065ff953418da40e2e119044865a` | PASS |
| Commit 9991e6b exists | `git rev-parse 9991e6b` | `9991e6ba17f7e288e6771eb77137a27d887595e2` | PASS |
| Actual bake compile | requires Packer + AWS credentials | not run | DEFERRED-TO-BAKE |

---

### Probe Execution

No probes defined for this phase. The phase PLAN declares the runtime build assertion is Phase 11's RDP-13 bake assertion.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| RDP-01 | 10-01-PLAN.md | xrdp + xorgxrdp source vendored and pinned by version + sha256 | SATISFIED | Both `get_url` tasks carry `checksum: "sha256:{{ var }}"` referencing defaults-pinned hashes; `xrdp_source_base_url` is configurable for airgap override; sha256 enforced regardless of transport |
| RDP-02 | 10-01-PLAN.md | Build toolchain + Xorg SDK from AL2023; compile+install both packages | SATISFIED | 16-package dnf install from AL2023 core (no EPEL); xrdp configure `--prefix=/usr/local --enable-pam --with-pam-rules=redhat`; xorgxrdp configure with `PKG_CONFIG_PATH=/usr/local/lib/pkgconfig`; correct build order (xrdp install before xorgxrdp configure) |
| RDP-03 | 10-01-PLAN.md | Hard-gate assert if build dep unavailable | SATISFIED | Task 2: `ansible.builtin.assert` with `that: [xrdp_build_deps_install is success]`, `quiet: false`, `fail_msg` names `xorg-x11-server-devel` explicitly |

---

### Invariant Checks

| Invariant | Check | Status |
|-----------|-------|--------|
| hardening-stays-last (CLAUDE.md §8) | `ansible/playbook.yml` role list: last role is `hardening`; `xrdp` role is NOT wired in (Phase 11 scope) | PASS |
| No `changeme` literal | Not applicable — no config content written in this phase | N/A |
| No EPEL / third-party repo | `grep -rni 'epel' ansible/roles/xrdp/` returns no matches | PASS |
| SHA-pin policy (CLAUDE.md §8) | `checksum: "sha256:..."` on both `get_url` tasks; versions + hashes in defaults | PASS |

---

### Anti-Patterns Found

No blockers. No warnings. Checked files: `ansible/roles/xrdp/defaults/main.yml`, `ansible/roles/xrdp/tasks/main.yml`.

- No TBD/FIXME/XXX debt markers with missing issue references
- No placeholder or stub values (all version strings, hashes, paths are load-bearing)
- No `return null` / empty handler patterns (not applicable — Ansible YAML)
- The two inline `# FIXME` comments in `ansible/playbook.yml` are pre-existing (firewalld and novnc workarounds); Phase 10 did not modify `playbook.yml` and did not add these markers

---

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Actual xrdp + xorgxrdp compile success at bake time | Phase 11 | Phase 11 success criteria #4: "A bake-time assertion (RDP-13) confirms the xrdp + xorgxrdp binaries/modules are present and the services are enabled — the bake fails if not" |
| 2 | xorgxrdp module path confirmation (Pitfall 3: `/usr/lib64/xorg/...` vs `/usr/local/lib/xorg/...`) | Phase 11 | Phase 11 bake assertion (RDP-13) verifies binary/module paths on a live bake; inline comment in `tasks/main.yml` line 140–142 flags this as bake-time verification item |

---

### Human Verification Required

None for this phase. All static verification checks are automated and pass. The runtime bake verification is deferred to Phase 11 (RDP-13) by design — it requires AWS credentials and is not a gap in Phase 10.

---

## Gaps Summary

No gaps. All 5 must-have truths are VERIFIED against the actual committed files. The two deferred items are explicitly called out in the ROADMAP.md Phase 11 success criteria and in the phase's own PLAN.md threat model (T-10-04, RDP-13 note). Phase 10's scope is build-role static structure only; runtime compilation is Phase 11's bake assertion gate.

---

_Verified: 2026-06-15T19:00:00Z_
_Verifier: Claude (gsd-verifier)_
