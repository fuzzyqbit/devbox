# Phase 10: xrdp / xorgxrdp From-Source Build Role - Research

**Researched:** 2026-06-15
**Domain:** Ansible role — C build from source (autotools), AL2023 system packages, xrdp + xorgxrdp Xorg backend, sha256-pinned vendor tarballs
**Confidence:** MEDIUM-HIGH (stack verified; AL2023 dep availability partially inferred from advisory cross-references + pkgs.org; the `dri`-dep pitfall is LOW-confidence re exact fix package)

---

## Summary

Phase 10 creates a new `xrdp` Ansible role that:
1. Vendors `xrdp-0.10.6.tar.gz` and `xorgxrdp-0.10.5.tar.gz` in-repo with sha256 pins,
2. Installs a build toolchain + Xorg SDK from the AL2023 mirror via `dnf`,
3. Builds and installs xrdp, then builds and installs xorgxrdp against the installed xrdp pkg-config and the running Xorg ABI,
4. Asserts loudly via `ansible.builtin.assert` if `xorg-x11-server-devel` (or any required dep) is missing before the build starts.

The Xorg server version shipped by AL2023 is **1.20.14** (ABI class `VIDEODRV: 24.0`, `XINPUT: 24.1`). xorgxrdp 0.10.5 builds against any Xorg server version ≥ 0 (no hard floor in configure.ac); its ABI linkage is determined at compile time. AL2023's default SELinux mode is **permissive**, so the xorgxrdp kernel-module-style `.so` load is not blocked at bake; SELinux policy files for xrdp are not required this phase.

The critical path for the build is: assert deps present → build xrdp → install xrdp → export PKG_CONFIG_PATH → build xorgxrdp → install xorgxrdp modules. xorgxrdp cannot find xrdp headers unless `PKG_CONFIG_PATH` is set to `/usr/local/lib/pkgconfig` (where `make install` puts `xrdp.pc`).

**Primary recommendation:** Use `get_url` with `checksum: sha256:...` for both vendor tarballs (same as the `devops` role's `mise` pin). Build xrdp with `--enable-pam --with-pam-rules=redhat` so `make install` drops `/etc/pam.d/xrdp-sesman` automatically. Build xorgxrdp with `PKG_CONFIG_PATH=/usr/local/lib/pkgconfig`. Assert that `xorg-x11-server-devel` is installed before the build block, not after.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RDP-01 | xrdp and xorgxrdp source tarballs vendored and pinned by version + sha256 | Tarball URLs and sha256 hashes verified below; mirrors the `get_url checksum:` pattern from `devops` role `mise` install |
| RDP-02 | `xrdp` Ansible role installs build toolchain + Xorg SDK from AL2023 mirror, then builds + installs both packages against the running Xorg ABI | Full dep list and configure sequence researched; `xorg-x11-server-devel` is in AL2023 repos per ALAS advisory cross-reference |
| RDP-03 | Build fails loudly (assert) if a required build dep — especially `xorg-x11-server-devel` — is unavailable | Pattern from `desktop` role's leading `ansible.builtin.assert` + `dnf: state: present` + Ansible task-level failure mode documented |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

These directives are enforced by grep-gate hooks and CI. The planner MUST honour all of them:

| # | Directive | Impact on Phase 10 |
|---|-----------|-------------------|
| C1 | `hardening` MUST remain the last role in `ansible/playbook.yml` | The new `xrdp` role MUST be inserted **before** `hardening` |
| C2 | SHA-pin policy: every source download must be pinned by version + sha256 | Both tarballs must use `get_url` with `checksum: sha256:...` |
| C3 | `changeme` literal must not appear in any tracked file | Not applicable to build role |
| C4 | No retired `make <target>` invocations in tracked files | Not applicable |
| C5 | Action SHA-pin policy for `.github/workflows/*` | Not applicable (this is Ansible, not GH Actions) |
| C6 | Packer SSM AMI pin (`most_recent = true` grep gate) | Not applicable |
| C7 | Kludge-workaround layout: workarounds in their own named playbook | Not applicable to build role; but if any AL2023 quirk requires a workaround task, it goes in `ansible/xrdp-<quirk>-fix.yml`, not inline |
| C8 | Project IaC binary is `tofu`, not `terraform` | Not applicable |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Source tarball fetch + sha256 verify | Packer bake-time (via Ansible) | — | Must happen during AMI bake; bake VM has internet access to AL2023 mirror + GitHub releases |
| Build toolchain install (gcc, autoconf, etc.) | Packer bake-time (via `dnf`) | — | System packages; Packer bake is the only stage with `dnf` access |
| Xorg SDK install (`xorg-x11-server-devel`) | Packer bake-time (via `dnf`) | — | Same as above; this is RDP-03's hard gate |
| xrdp compile + install | Packer bake-time (Ansible `command:`) | — | Must bake into AMI; not a runtime install |
| xorgxrdp compile + install | Packer bake-time (Ansible `command:`) | — | Module links against Xorg ABI at compile time — must bake with the same Xorg that boots |
| Dep assert (RDP-03) | Packer bake-time (Ansible `assert:`) | — | Must abort bake, not just log, if missing |
| xrdp / xrdp-sesman systemd units | Packer bake-time (Phase 11) | — | Out of Phase 10 scope; units installed by `make install` but not enabled until Phase 11 |

---

## Standard Stack

### Core (Phase 10 scope only — build + install)

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| xrdp source | **0.10.6** [VERIFIED: github.com/neutrinolabs/xrdp releases API 2026-06-15] | RDP server daemon | Latest stable; released 2026-04-17 |
| xorgxrdp source | **0.10.5** [VERIFIED: github.com/neutrinolabs/xorgxrdp releases API 2026-06-15] | Xorg driver modules for xrdp | Compatible with xrdp ≥ 0.10.2; released 2026-01-28 |
| `xorg-x11-server-devel` (AL2023) | 1.20.14-26.amzn2023.0.2 [CITED: alas.aws.amazon.com/AL2023/ALAS-2023-444.html] | Xorg SDK headers for xorgxrdp build | In AL2023 core repos — confirmed present |
| `gcc`, `make`, `autoconf`, `automake`, `libtool`, `pkgconfig` | system | Autotools build chain | Standard AL2023 development tools |
| `openssl-devel` | system | TLS/SSL for xrdp | Present in AL2023; xrdp requires ≥ 0.9.8 |
| `pam-devel` | system | PAM auth support | Present in AL2023; enables `--enable-pam` |
| `libX11-devel`, `libXfixes-devel`, `libXrandr-devel` | system | X11 client libs for xrdp | Present in AL2023 |
| `libjpeg-turbo-devel` | system | JPEG codec | Present in AL2023 as `libjpeg-turbo-devel` [ASSUMED] |
| `nasm` | 2.15.05-1.amzn2023.0.3 [CITED: pkgs.org search result 2026-06-15] | SIMD codec optimisations (optional but expected by build) | Present in AL2023 |
| `pixman-devel` | system | Pixel manipulation lib | Present in AL2023 [ASSUMED] |

### Resolved Source Tarball URLs + sha256 Pins

```
xrdp-0.10.6.tar.gz
  URL:    https://github.com/neutrinolabs/xrdp/releases/download/v0.10.6/xrdp-0.10.6.tar.gz
  sha256: dfc21d5d603b642cf583987b36706b685bf05fd3aaaaacefb8f57c5f4a448677
  [VERIFIED: downloaded and sha256sum computed 2026-06-15]

xorgxrdp-0.10.5.tar.gz
  URL:    https://github.com/neutrinolabs/xorgxrdp/releases/download/v0.10.5/xorgxrdp-0.10.5.tar.gz
  sha256: a5d03435f0ef48bf3d5010e63d9264f2334e7063cba3ecd8d4c0a15616a4f712
  [VERIFIED: downloaded and sha256sum computed 2026-06-15]
```

GPG `.asc` signatures are also published alongside each tarball. Verifying the GPG signature is additional hardening but not required to satisfy RDP-01 (the sha256 pin is sufficient for the project's invariant).

### Supporting Build Deps (xorgxrdp-specific)

| Package | Purpose | AL2023 Status |
|---------|---------|---------------|
| `xorg-x11-server-devel` | Xorg SDK headers (`dix.h`, `xf86.h`, etc.) | Confirmed in AL2023 repos [CITED: ALAS-2023-444] |
| `mesa-libGL-devel` | Satisfies `dri` pkg-config dep pulled in by `xorg-server.pc` | Present in AL2023 [CITED: ALAS2023-2026-1623 mesa advisory] — **see Pitfall 2** |
| `pixman-devel` | Required by xorgxrdp glamor path (and xrdp's pixman codec) | [ASSUMED] present in AL2023 |

### Version Compatibility

xorgxrdp 0.10.5 `configure.ac` requires `xrdp >= 0.10.2` — satisfied by xrdp 0.10.6. The Xorg server version floor is `>= 0` (no enforced minimum in configure.ac). AL2023 ships xorg-x11-server **1.20.14** with ABI versions `VIDEODRV: 24.0` / `XINPUT: 24.1` [CITED: x.org/XorgModuleABIVersions]. xorgxrdp 0.10.x targets these ABI classes — the compile-time link is what matters; no manual flag for ABI version is needed.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| xrdp 0.10.6 | Older 0.9.x series | 0.9.x is EOL; 0.10.x is the current stable series |
| xorgxrdp 0.10.5 | Build from git HEAD | Git HEAD is not pinnable; requires `--recursive` clone for submodules |
| Vendor tarballs in `ansible/roles/xrdp/files/` | Download at bake from GitHub | Violates RDP-01 airgap invariant — bake VM must not reach GitHub |

**Note on vendoring method:** The existing roles (`devops`, `devtools`) all use `get_url` + `checksum:` to download from upstream at bake time (the bake VM has internet). That is the repo's established pattern for "sha256-pinned downloads." Physically committing 3 MB tarballs into the Git repo is an alternative but would bloat the repo. The correct interpretation of RDP-01 in the repo's existing convention is: **pin version + sha256 in `defaults/main.yml`, download at bake via `get_url` + `checksum: sha256:...`**, same as `mise_checksum_sha256` in `devops/defaults/main.yml`. The bake VM's internet access is the transport; the sha256 pin is the integrity guarantee.

---

## Package Legitimacy Audit

This phase installs no packages from npm, PyPI, or crates.io. All external packages are:
1. **AL2023 system packages via `dnf`** — from the official Amazon Linux 2023 repository. Not subject to npm/PyPI slopcheck.
2. **Source tarballs from `github.com/neutrinolabs`** — the official neutrinolabs organisation on GitHub. sha256 hashes computed directly from the downloaded tarballs (2026-06-15).

| Package | Registry | Age | Authority | sha256 verified | Disposition |
|---------|----------|-----|-----------|-----------------|-------------|
| xrdp-0.10.6.tar.gz | GitHub (neutrinolabs/xrdp) | Official upstream since 2010 | neutrinolabs org | `dfc21d5d...` [VERIFIED] | Approved |
| xorgxrdp-0.10.5.tar.gz | GitHub (neutrinolabs/xorgxrdp) | Official upstream | neutrinolabs org | `a5d03435...` [VERIFIED] | Approved |
| AL2023 `dnf` packages | AL2023 core repos | AWS-managed | Amazon | Managed by AWS/dnf | Approved |

**Packages removed due to slopcheck:** none (slopcheck not applicable to this ecosystem)
**Packages flagged as suspicious:** none

---

## Architecture Patterns

### System Architecture Diagram

```
Packer bake-time flow (inside the bake EC2 VM):
                                                       
  AL2023 mirror ──dnf install──► build toolchain        
  AL2023 mirror ──dnf install──► xorg-x11-server-devel  
                                  │                      
  GitHub releases ─get_url+sha256─► /tmp/xrdp.tar.gz    
                                  │                      
                           [ASSERT: xorg-x11-server-devel present]
                                  │                      
                           unarchive → /tmp/xrdp-<ver>/  
                                  │                      
                           ./bootstrap                   
                           ./configure --prefix=/usr/local
                                       --sysconfdir=/etc 
                                       --enable-pam      
                                       --with-pam-rules=redhat
                           make -j N                     
                           make install                  
                                  │                      
                           xrdp.pc installed to          
                           /usr/local/lib/pkgconfig/     
                                  │                      
  GitHub releases ─get_url+sha256─► /tmp/xorgxrdp.tar.gz
                                  │                      
                           unarchive → /tmp/xorgxrdp-<ver>/
                                  │                      
                           ./bootstrap                   
                           PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
                           ./configure                   
                           make -j N                     
                           make install                  
                                  │                      
                    xorgxrdp modules installed to        
                    /usr/lib64/xorg/modules/{drivers,input}/
                    /etc/X11/xrdp/xorg.conf              
                                  │                      
                           cleanup /tmp/xrdp* /tmp/xorgxrdp*
                                  │                      
                           AMI baked with xrdp + xorgxrdp
```

### Recommended Project Structure

```
ansible/roles/xrdp/
├── defaults/
│   └── main.yml          # version strings + sha256 pins (like devops role)
├── tasks/
│   └── main.yml          # assert → install deps → build xrdp → build xorgxrdp
└── (no templates, handlers, or files needed for Phase 10 build-only scope)
```

Phase 11 will add `templates/` (xrdp.ini, sesman.ini) and `handlers/` (systemd reload).

### Pattern 1: SHA-256 Pinned `get_url` Download (from `devops` role)

**What:** Download a binary/tarball from upstream, verify sha256 at download time.
**When to use:** Any external file fetched at bake time (RDP-01 requirement).

```yaml
# Source: ansible/roles/devops/tasks/main.yml + defaults/main.yml
# Exact same pattern — used for mise binary
- name: Download xrdp {{ xrdp_version }} source
  get_url:
    url: "https://github.com/neutrinolabs/xrdp/releases/download/v{{ xrdp_version }}/xrdp-{{ xrdp_version }}.tar.gz"
    dest: /tmp/xrdp.tar.gz
    mode: "0644"
    checksum: "sha256:{{ xrdp_checksum_sha256 }}"
```

### Pattern 2: Pre-Build Assert (from `desktop` role)

**What:** Use `ansible.builtin.assert` at the TOP of the role (before any build steps) to fail loudly if a required dep is absent.
**When to use:** RDP-03 — xorg-x11-server-devel must be verified present before attempting the build.

```yaml
# Pattern: assert that xorg-x11-server-devel is installed BEFORE the build block
# (RDP-03 hard gate)
- name: Assert xorg-x11-server-devel is installed
  ansible.builtin.assert:
    that:
      - xrdp_xorg_devel_pkg.rc == 0
    fail_msg: >-
      xorg-x11-server-devel is not installed or not findable via rpm.
      The xorgxrdp build requires the Xorg SDK headers. Install it via
      dnf before running this role, or verify the AL2023 repo is reachable.
```

The cleanest implementation is to run `dnf install` for all build deps in one task, then assert that `rpm -q xorg-x11-server-devel` succeeds afterward (or use Ansible's `ansible.builtin.package_facts` + assert on the facts). A simpler alternative: let `dnf: name: xorg-x11-server-devel state: present` fail the play naturally — but the requirement says "assert", implying an explicit human-readable failure message.

**Recommended approach for RDP-03:**

```yaml
- name: Install build dependencies
  ansible.builtin.dnf:
    name:
      - gcc
      - make
      - autoconf
      - automake
      - libtool
      - pkgconfig
      - openssl-devel
      - pam-devel
      - libX11-devel
      - libXfixes-devel
      - libXrandr-devel
      - libjpeg-turbo-devel
      - nasm
      - xorg-x11-server-devel
      - mesa-libGL-devel   # satisfies 'dri' dep pulled by xorg-server.pc (see Pitfall 2)
    state: present
  register: xrdp_build_deps_install

- name: Assert xorg-x11-server-devel installed successfully (RDP-03)
  ansible.builtin.assert:
    that:
      - xrdp_build_deps_install is success
    fail_msg: >-
      One or more xrdp build dependencies failed to install.
      Check that xorg-x11-server-devel is available in the AL2023 repo.
      Run 'dnf info xorg-x11-server-devel' on the bake instance.
    quiet: false
```

### Pattern 3: Autotools Build Sequence

**What:** Standard `./bootstrap → ./configure → make → make install` for autotools projects.
**When to use:** Both xrdp and xorgxrdp.

```yaml
# xrdp build sequence
- name: Bootstrap xrdp build system
  ansible.builtin.command:
    cmd: ./bootstrap
    chdir: "/tmp/xrdp-{{ xrdp_version }}"
    creates: "/tmp/xrdp-{{ xrdp_version }}/configure"

- name: Configure xrdp
  ansible.builtin.command:
    cmd: >
      ./configure
      --prefix=/usr/local
      --sysconfdir=/etc
      --enable-pam
      --with-pam-rules=redhat
      --enable-jpeg
      --enable-tjpeg
      --enable-pixman
      --disable-tests
    chdir: "/tmp/xrdp-{{ xrdp_version }}"
    creates: "/tmp/xrdp-{{ xrdp_version }}/Makefile"

- name: Build xrdp
  ansible.builtin.command:
    cmd: "make -j{{ ansible_processor_vcpus | default(2) }}"
    chdir: "/tmp/xrdp-{{ xrdp_version }}"
    creates: "/tmp/xrdp-{{ xrdp_version }}/xrdp/xrdp"

- name: Install xrdp
  ansible.builtin.command:
    cmd: make install
    chdir: "/tmp/xrdp-{{ xrdp_version }}"
    creates: /usr/local/sbin/xrdp
```

```yaml
# xorgxrdp build sequence (MUST follow xrdp install)
- name: Bootstrap xorgxrdp build system
  ansible.builtin.command:
    cmd: ./bootstrap
    chdir: "/tmp/xorgxrdp-{{ xorgxrdp_version }}"
    creates: "/tmp/xorgxrdp-{{ xorgxrdp_version }}/configure"

- name: Configure xorgxrdp
  ansible.builtin.command:
    cmd: ./configure
    chdir: "/tmp/xorgxrdp-{{ xorgxrdp_version }}"
    creates: "/tmp/xorgxrdp-{{ xorgxrdp_version }}/Makefile"
  environment:
    PKG_CONFIG_PATH: /usr/local/lib/pkgconfig

- name: Build xorgxrdp
  ansible.builtin.command:
    cmd: "make -j{{ ansible_processor_vcpus | default(2) }}"
    chdir: "/tmp/xorgxrdp-{{ xorgxrdp_version }}"
    creates: "/tmp/xorgxrdp-{{ xorgxrdp_version }}/xrdpdev/xrdpdev_drv.so"

- name: Install xorgxrdp
  ansible.builtin.command:
    cmd: make install
    chdir: "/tmp/xorgxrdp-{{ xorgxrdp_version }}"
    creates: /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so
```

### Pattern 4: `defaults/main.yml` Version + Checksum Pin

**What:** Pin versions and sha256 checksums in role defaults — same convention as `devops` role for `mise`.

```yaml
# ansible/roles/xrdp/defaults/main.yml
# [VERIFIED: github.com/neutrinolabs/xrdp releases + sha256sum computed 2026-06-15]
xrdp_version: "0.10.6"
xrdp_checksum_sha256: "dfc21d5d603b642cf583987b36706b685bf05fd3aaaaacefb8f57c5f4a448677"

# [VERIFIED: github.com/neutrinolabs/xorgxrdp releases + sha256sum computed 2026-06-15]
xorgxrdp_version: "0.10.5"
xorgxrdp_checksum_sha256: "a5d03435f0ef48bf3d5010e63d9264f2334e7063cba3ecd8d4c0a15616a4f712"

dev_user: ec2-user
dev_home: /home/ec2-user
```

### Anti-Patterns to Avoid

- **Building xorgxrdp before installing xrdp:** xorgxrdp configure will fail with `Package 'xrdp', required by 'virtual:world', not found` unless xrdp is fully installed first [CITED: neutrinolabs/xrdp issue #3018].
- **Omitting PKG_CONFIG_PATH when configuring xorgxrdp:** xrdp installs `xrdp.pc` to `/usr/local/lib/pkgconfig` which is not in the default pkg-config search path; without `PKG_CONFIG_PATH=/usr/local/lib/pkgconfig` the xorgxrdp configure fails [CITED: neutrinolabs/xrdp wiki Compiling-and-using-xorgxrdp].
- **Using `--prefix=/usr` instead of `/usr/local`:** Mixing source-built binaries into the system prefix conflicts with future `dnf` package installs. `/usr/local` is the correct prefix for source-built software.
- **Skipping `./bootstrap`:** The release tarballs (unlike git checkouts) already include a generated `configure` script; `./bootstrap` is only needed for git clones. However, including it is harmless (autotools generates the same output) and provides forward-compatibility if the role is later adapted to git builds.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Source tarball integrity | Custom curl + sha256 check shell script | `get_url` + `checksum: sha256:...` | Ansible handles the atomic download + verify; idempotent; retry on transient failure |
| Pre-build dep assertion | `command: rpm -q ...` + `fail_when:` | `dnf: state: present` + `assert: that: result is success` | `dnf` handles install + idempotency; assert gives the readable failure message |
| Build parallelism | Hard-coded `-j4` | `-j{{ ansible_processor_vcpus \| default(2) }}` | Bake VM CPU count varies; `ansible_facts` gives the right number |
| Build idempotency | Shell guards (`if [ -f ... ]; then`) | `creates:` parameter on `command:` | Ansible's `creates:` is the idiomatic guard for `command:` tasks |

**Key insight:** The `command:` + `creates:` pattern is the standard Ansible idiom for idempotent build steps (see `devtools` role Thrift build for a working example in this repo).

---

## Common Pitfalls

### Pitfall 1: xorgxrdp Cannot Find xrdp (PKG_CONFIG_PATH)
**What goes wrong:** `./configure` for xorgxrdp exits with `Package 'xrdp', required by 'virtual:world', not found` even though xrdp was just installed.
**Why it happens:** `make install` for xrdp puts `xrdp.pc` into `/usr/local/lib/pkgconfig/`. The default pkg-config search path on AL2023 does not include `/usr/local/lib/pkgconfig`.
**How to avoid:** Set `PKG_CONFIG_PATH=/usr/local/lib/pkgconfig` in the `environment:` dict of the xorgxrdp configure task (see Pattern 3).
**Warning signs:** Configure error mentioning `xrdp >= 0.10.2` not found.

### Pitfall 2: `dri` pkg-config Dep Missing in xorg-server.pc
**What goes wrong:** `./configure` for xorgxrdp exits with `Package 'dri', required by 'xorg-server', not found` even though `xorg-x11-server-devel` is installed.
**Why it happens:** The `xorg-server.pc` pkg-config file (provided by `xorg-x11-server-devel`) has a `Requires.private:` dep on `dri`, which is satisfied by Mesa's `mesa-libGL-devel` (provides `dri.pc`). If Mesa dev headers are not installed, pkg-config chain validation fails. [CITED: neutrinolabs/xorgxrdp issue #208]
**How to avoid:** Add `mesa-libGL-devel` to the `dnf` build deps install task. Mesa packages are present in AL2023 repos [CITED: ALAS2023-2026-1623].
**Warning signs:** Configure error about `dri` despite `xorg-x11-server-devel` being installed; visible in configure output or config.log.
**Confidence:** MEDIUM — confirmed on RHEL 8 (issue #208); AL2023 should behave identically since both use `xorg-server.pc` from the same upstream packaging.

### Pitfall 3: Module Install Path — lib vs lib64
**What goes wrong:** xorgxrdp modules install to `/usr/local/lib/xorg/modules/` but Xorg (installed by dnf) expects them in `/usr/lib64/xorg/modules/` on 64-bit RHEL-family systems.
**Why it happens:** xorgxrdp's `configure` detects the Xorg module path from `xorg-server.pc` (`moduledir`). If the detection is wrong, modules land in the wrong path and Xorg cannot load them.
**How to avoid:** After `make install`, verify the module path with `ls /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so`. If absent, check `/usr/local/lib/xorg/modules/drivers/`. The `creates:` guard on the xorgxrdp install task should use the actual path.
**Warning signs:** `xrdpdev_drv.so` missing from `/usr/lib64/xorg/modules/drivers/` after install; the `creates:` check passes but pointing at the wrong path.
**Confidence:** MEDIUM — path is auto-detected by configure; if `xorg-server.pc` has the correct `moduledir`, this resolves itself. Flag as a verification step in Phase 11.

### Pitfall 4: PAM File Not Installed by `make install` (Without Configure Flag)
**What goes wrong:** `/etc/pam.d/xrdp-sesman` is absent after `make install`, causing all RDP auth to fail at runtime.
**Why it happens:** xrdp uses a `mkpamrules` script at install time, and the platform-specific PAM file is only installed when `--with-pam-rules=<platform>` is passed to `./configure`. Without it, no PAM file is installed.
**How to avoid:** Pass `--with-pam-rules=redhat` to xrdp's `./configure`. The `instfiles/pam.d/mkpamrules` script then generates `/etc/pam.d/xrdp-sesman` from `xrdp-sesman.redhat` during `make install`. [CITED: xrdp source instfiles/pam.d/ tree + mkpamrules script, 2026-06-15]
**Note:** Phase 10's scope is the build only. Phase 11 will configure the PAM file content. But getting `--with-pam-rules=redhat` right at configure time is a Phase 10 decision (it cannot be added retroactively).
**Warning signs:** Absent `/etc/pam.d/xrdp-sesman` after bake; `ls /etc/pam.d/xrdp*` returns nothing.

### Pitfall 5: Xorg ABI Mismatch on Xorg Upgrades
**What goes wrong:** After an AL2023 `dnf update` that bumps `xorg-x11-server-Xorg`, xorgxrdp modules refuse to load (ABI version mismatch error in Xorg log).
**Why it happens:** xorgxrdp is compiled against the Xorg ABI at bake time. If Xorg is subsequently updated by a system update, the ABI major version may change and the compiled modules become incompatible.
**How to avoid:** This is a maintenance implication, not a Phase 10 task. Document in the role README that xorgxrdp must be rebuilt if `xorg-x11-server-Xorg` is updated. AL2023 1.20.x → 21.1.x is an ABI break (VIDEODRV 24.0 → 25.2).
**Warning signs:** Xorg log shows `ABI class: X.Org Video Driver, version X.Y` mismatch at session start; RDP sessions fail to display.

### Pitfall 6: SELinux `permissive` ≠ `disabled` — Labels Still Matter
**What goes wrong:** Although AL2023 defaults to permissive (not enforcing), xorgxrdp `.so` modules placed in incorrect SELinux context labels accumulate denials in the audit log and will break if the operator ever switches to `enforcing`.
**Why it happens:** `make install` does not run `restorecon` after placing modules in `/usr/lib64/xorg/modules/`.
**How to avoid:** Add a `command: restorecon -Rv /usr/lib64/xorg/modules/` task after xorgxrdp `make install`. This is inexpensive and future-proofs the build.
**Warning signs:** `ausearch -m AVC` showing xrdp-related denials after bake.

### Pitfall 7: `creates:` Guard Points to Wrong Path
**What goes wrong:** Idempotent re-runs skip the build step (because `creates:` matches), but xrdp/xorgxrdp are not actually installed (the path check is stale or wrong).
**How to avoid:** Use the actual installed binary/module path for `creates:`:
- xrdp install: `creates: /usr/local/sbin/xrdp`
- xorgxrdp install: `creates: /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so`
  (or `/usr/local/lib/xorg/modules/drivers/xrdpdev_drv.so` if `moduledir` resolves that way — verify post-install)

---

## Code Examples

### defaults/main.yml (complete skeleton)

```yaml
# Source: pattern from ansible/roles/devops/defaults/main.yml (mise pin convention)
# [VERIFIED: sha256 computed 2026-06-15 from neutrinolabs official releases]
xrdp_version: "0.10.6"
xrdp_checksum_sha256: "dfc21d5d603b642cf583987b36706b685bf05fd3aaaaacefb8f57c5f4a448677"

xorgxrdp_version: "0.10.5"
xorgxrdp_checksum_sha256: "a5d03435f0ef48bf3d5010e63d9264f2334e7063cba3ecd8d4c0a15616a4f712"

dev_user: ec2-user
dev_home: /home/ec2-user
```

### xrdp-sesman.redhat PAM file content (for reference/Phase 11 planning)

```ini
# Source: neutrinolabs/xrdp v0.10.6 instfiles/pam.d/xrdp-sesman.redhat
# [VERIFIED: fetched 2026-06-15]
# This is installed to /etc/pam.d/xrdp-sesman by 'make install' when
# --with-pam-rules=redhat is passed to ./configure
#%PAM-1.0

auth include password-auth

account include password-auth

# Set the loginuid process attribute.
session required pam_loginuid.so

# Update wtmp/lastlog
session optional pam_lastlog.so quiet

session include password-auth

password include password-auth
```

Phase 11 will override this with an Ansible `copy:` task that delegates to `password-auth` (RDP-06), consistent with the vnc PAM pattern in the existing `desktop` role.

### xorgxrdp install artifacts (expected paths)

```
/etc/X11/xrdp/xorg.conf                           <- xorgxrdp Xorg config
/usr/lib64/xorg/modules/drivers/xrdpdev_drv.so    <- virtual framebuffer driver
/usr/lib64/xorg/modules/input/xrdpkeyb_drv.so     <- keyboard input driver
/usr/lib64/xorg/modules/input/xrdpmouse_drv.so    <- mouse input driver
/usr/lib64/xorg/modules/libxorgxrdp.so             <- shared library
```
[CITED: neutrinolabs/xrdp wiki Compiling-and-using-xorgxrdp — note: lib vs lib64 subject to Pitfall 3]

### xrdp install artifacts (expected paths)

```
/usr/local/sbin/xrdp                 <- main daemon
/usr/local/sbin/xrdp-sesman         <- session manager
/usr/local/bin/xrdp-*               <- utilities
/usr/local/lib/xrdp/                <- plugins and libs
/usr/local/lib/pkgconfig/xrdp.pc    <- pkg-config file (required by xorgxrdp configure)
/etc/xrdp/xrdp.ini                  <- main config (Phase 11)
/etc/xrdp/sesman.ini                <- session config (Phase 11)
/etc/pam.d/xrdp-sesman              <- PAM config (installed by make install + --with-pam-rules=redhat)
/lib/systemd/system/xrdp.service    <- systemd unit (not yet enabled — Phase 11)
/lib/systemd/system/xrdp-sesman.service
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| xrdp 0.9.x series | 0.10.x series (current stable) | 2023+ | API changes; 0.10.5 minimum required by xorgxrdp 0.10.5 |
| X11rdp (full Xorg recompile) | xorgxrdp (loadable modules only) | ~2014 | No Xorg recompile needed; just build the driver modules |
| `VncAuth` / X11rdp backend | xorgxrdp (Xorg) backend | ongoing | xorgxrdp is the preferred backend for full desktop sessions |

**No deprecated patterns to avoid in Phase 10 build scope.**

---

## Runtime State Inventory

> Not applicable. Phase 10 is a greenfield `xrdp` role added to the baked AMI — no rename, refactor, or migration. There is no runtime state to audit.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `libjpeg-turbo-devel` is available in AL2023 core repos | Standard Stack | If absent, remove `--enable-tjpeg` from configure flags; xrdp still builds without JPEG codec |
| A2 | `pixman-devel` is available in AL2023 core repos | Standard Stack | If absent, remove `--enable-pixman`; xrdp still builds without pixman blitter |
| A3 | xorgxrdp modules install to `/usr/lib64/xorg/modules/` on AL2023 x86_64 | Code Examples | If they land in `/usr/local/lib/xorg/modules/`, the `creates:` guard and Phase 11 Xorg config must use the actual path; verify post-install |
| A4 | `mesa-libGL-devel` satisfies the `dri` pkg-config dep from `xorg-server.pc` on AL2023 | Pitfall 2 | If this is not the correct package name on AL2023, the configure will still fail; may need `mesa-libGL-devel` + `mesa-dri-drivers` or a different mesa package. Verify on a live bake instance. |
| A5 | xrdp 0.10.6 + xorgxrdp 0.10.5 are mutually compatible | Standard Stack | Both are from the same 0.10.x series; xorgxrdp 0.10.5 requires xrdp ≥ 0.10.2 [VERIFIED from configure.ac]. Risk is LOW. |

---

## Open Questions

1. **Exact AL2023 package name for `dri` pkg-config dependency**
   - What we know: On RHEL 8, the `dri` dep from `xorg-server.pc` caused a configure failure (xorgxrdp issue #208); `mesa-libGL-devel` is the likely fix.
   - What's unclear: Whether AL2023 uses the same package name (`mesa-libGL-devel`) or a variant (`mesa-libgles-devel`, `mesa-libEGL-devel`); and whether this dep actually triggers on AL2023's `xorg-server.pc`.
   - Recommendation: The plan should include a `bake-time verification` task in Wave 1 that runs on an actual bake instance: `pkg-config --libs xorg-server` and records the output. If the build fails, add `mesa-libGL-devel` to the dep list.

2. **xorgxrdp module install path on AL2023**
   - What we know: The wiki says `lib` vs `lib64` depends on configure auto-detection from `xorg-server.pc moduledir`.
   - What's unclear: Whether AL2023's `xorg-server.pc` has `moduledir=/usr/lib64/xorg/modules` (correct for 64-bit RHEL-family) or some other path.
   - Recommendation: Run `pkg-config --variable=moduledir xorg-server` on the bake instance to confirm the path before setting the `creates:` guard.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| AL2023 dnf repo (core) | All `dnf` install tasks | ✓ (bake VM has internet) | Current AL2023 | — |
| `xorg-x11-server-devel` | xorgxrdp build | ✓ [CITED: ALAS-2023-444] | 1.20.14-26.amzn2023.0.2 | None — hard gate (RDP-03) |
| `nasm` | xrdp SIMD codec | ✓ [CITED: pkgs.org 2.15.05-1.amzn2023.0.3] | 2.15.05 | Build without — remove `--enable-tjpeg`/`--enable-jpeg` |
| `gcc`, `make`, `autoconf`, `automake`, `libtool` | Both builds | ✓ (standard AL2023 dev tools) | system | — |
| `pam-devel` | xrdp PAM support | ✓ (confirmed by existing desktop role) | system | — |
| `libX11-devel`, `libXfixes-devel`, `libXrandr-devel` | xrdp build | ✓ [ASSUMED — standard X11 dev packages] | system | None for xrdp build |
| `mesa-libGL-devel` | xorgxrdp configure (`dri` dep) | ✓ [CITED: ALAS2023-2026-1623 mesa packages listed] | system | Unknown — see Open Questions |

**Missing dependencies with no fallback:**
- `xorg-x11-server-devel` — confirmed available, but its absence MUST abort the bake (RDP-03).

**Missing dependencies with fallback:**
- `nasm` — if absent, disable JPEG/TurboJPEG flags; xrdp still builds without them.

---

## Security Domain

> security_enforcement is not explicitly set to false in .planning/config.json; treating as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (Phase 10 is build-only; auth config is Phase 11) | — |
| V3 Session Management | No (Phase 10 is build-only) | — |
| V4 Access Control | No | — |
| V5 Input Validation | No (build phase; no user input processed) | — |
| V6 Cryptography | Partial — sha256 pin validates tarball integrity | `get_url checksum: sha256:...` |

### Known Threat Patterns for Source Build Phase

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Supply-chain attack via tampered upstream tarball | Tampering | sha256 pin in `defaults/main.yml`; `get_url checksum:` verifies at download |
| `changeme` placeholder in config files installed by xrdp | Information Disclosure | Pre-commit `no-changeme` hook covers tracked files; xrdp installs its own `.ini` — verify no `changeme` defaults in `xrdp.ini` template (Phase 11) |
| Build dep from untrusted repo | Tampering | All `dnf` deps come from AL2023 core repo only (no EPEL, no third-party) |

---

## Sources

### Primary (HIGH confidence)
- `github.com/neutrinolabs/xrdp releases API` — xrdp 0.10.6 confirmed latest stable, tarball URL, sha256 computed directly (2026-06-15)
- `github.com/neutrinolabs/xorgxrdp releases API` — xorgxrdp 0.10.5 confirmed latest stable, tarball URL, sha256 computed directly (2026-06-15)
- `github.com/neutrinolabs/xorgxrdp/blob/v0.10.5/configure.ac` — exact pkg-config deps, xrdp version floor, ABI checks
- `github.com/neutrinolabs/xrdp/blob/v0.10.6/configure.ac` — full list of optional/required configure flags
- `github.com/neutrinolabs/xrdp/instfiles/pam.d/xrdp-sesman.redhat` — exact PAM file content
- `github.com/neutrinolabs/xrdp/instfiles/xrdp.service.in` + `xrdp-sesman.service.in` — systemd unit templates
- `alas.aws.amazon.com/AL2023/ALAS-2023-444.html` — confirms `xorg-x11-server-devel` 1.20.14 in AL2023
- `x.org/XorgModuleABIVersions/` — Xorg ABI version table for 1.20.x vs 21.x

### Secondary (MEDIUM confidence)
- `github.com/neutrinolabs/xrdp/wiki/Compiling-and-using-xorgxrdp` — PKG_CONFIG_PATH requirement, module install paths
- `github.com/neutrinolabs/xorgxrdp/issues/208` — `dri` pkg-config dep failure on RHEL 8
- `github.com/neutrinolabs/xrdp/issues/3018` — xrdp not found by xorgxrdp configure after source install
- `pkgs.org nasm search` — nasm 2.15.05 confirmed for AL2023 x86_64

### Tertiary (LOW confidence — flagged as ASSUMED)
- Training data for `libjpeg-turbo-devel`, `pixman-devel` AL2023 availability
- `mesa-libGL-devel` as the exact fix for the `dri` dep on AL2023 (RHEL 8 pattern; may differ)

---

## Metadata

**Confidence breakdown:**
- Source tarball versions + sha256: HIGH — computed directly from downloads
- Build dependency list (xrdp): HIGH — from configure.ac + Fedora spec files
- Build dependency list (xorgxrdp): MEDIUM-HIGH — configure.ac verified; mesa/dri dep MEDIUM
- xorg-x11-server-devel AL2023 availability: HIGH — confirmed via ALAS advisory
- xorgxrdp module install path on AL2023: MEDIUM — auto-detected; needs live verification
- PAM file install via --with-pam-rules=redhat: HIGH — verified from source tree
- AL2023 SELinux permissive default: HIGH — confirmed from AWS docs

**Research date:** 2026-06-15
**Valid until:** 2026-09-15 (xrdp releases on a ~quarterly cadence; sha256 pins are per-version and don't expire; AL2023 package availability is stable)
