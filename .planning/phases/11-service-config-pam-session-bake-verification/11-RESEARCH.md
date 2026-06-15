# Phase 11: Service Config, PAM, Session + Bake Verification — Research

**Researched:** 2026-06-15
**Domain:** Ansible role extension — xrdp/sesman.ini configuration, TLS cert, PAM, GNOME/Xorg session setup, systemd units, bake assertion
**Confidence:** HIGH (all major config keys verified from xrdp v0.10.6 source tree; session setup verified from existing repo xstartup.j2 pattern)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RDP-04 | xrdp listens on `:3389` with TLS enabled (`security_layer`/`certificate`/`key_file`), reusing the existing self-signed cert pattern | `security_layer`, `certificate`, `key_file`, `ssl_protocols` keys verified from `xrdp/xrdp.ini.in` v0.10.6 [CITED]; openssl cert-generation pattern exists in `desktop` role |
| RDP-05 | `sesman.ini` configured for xorgxrdp (Xorg) backend — no Xvnc | `[Xorg]` section with `param=/usr/libexec/Xorg` verified from `sesman/sesman.ini.in` v0.10.6 [CITED]; Fedora 26+/RHEL8+ path confirmed from xrdp issue #1646 [CITED] |
| RDP-06 | `/etc/pam.d/xrdp-sesman` delegates to `password-auth` | `--with-pam-rules=redhat` at configure time installs `xrdp-sesman.redhat` content; verified from `instfiles/pam.d/xrdp-sesman.redhat` v0.10.6 [CITED]; Phase 11 overrides with Ansible `copy:` to guarantee content |
| RDP-07 | Operator logs in over RDP as `ec2-user` with the `./run secrets-show` password and reaches the installed desktop | Requires: PAM delegates to `password-auth` (RDP-06) + `startwm.sh` launches GNOME Xorg session + xordxrdp Xorg backend (RDP-05) |
| RDP-08 | xrdp + xrdp-sesman are enabled systemd services; `xrdp` role inserted before `hardening` | systemd unit content verified from `instfiles/xrdp.service.in` + `instfiles/xrdp-sesman.service.in` v0.10.6 [CITED]; exec paths `/usr/local/sbin/xrdp` and `/usr/local/sbin/xrdp-sesman` from Phase 10 source install |
| RDP-13 | Bake-time assertion confirms xrdp + xorgxrdp binaries/modules present and services enabled | `ansible.builtin.assert` + `ansible.builtin.stat` for binary/module presence + `command: systemctl is-enabled xrdp xrdp-sesman` for service state |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

| # | Directive | Impact on Phase 11 |
|---|-----------|-------------------|
| C1 | `hardening` MUST remain the last role in `ansible/playbook.yml` | The `xrdp` role MUST be inserted BEFORE `hardening` (and BEFORE `desktop`, or immediately after it — see Architecture section) |
| C2 | SHA-pin policy for source downloads | No new external downloads in Phase 11 (cert is generated locally via openssl, not fetched) |
| C3 | `changeme` literal must not appear in any tracked file | xrdp.ini template must not contain `changeme`; cert/key paths must be real values, not placeholders |
| C4 | No retired `make <target>` invocations in tracked files | Not applicable to this phase |
| C5 | Action SHA-pin for `.github/workflows/*` | Not applicable (Ansible, not GH Actions) |
| C6 | Packer SSM AMI pin | Not applicable |
| C7 | Workaround kludge layout | If any AL2023 quirk requires a workaround (e.g., polkit/colord), it goes in a standalone `ansible/xrdp-<quirk>-fix.yml` imported by `playbook.yml`, NOT inline in the role |
| C8 | Project binary is `tofu` | Not applicable |

The `secrets` role gating condition in `playbook.yml` currently reads:
```yaml
when: >-
  (layers.vscode | default(false)) or
  (layers.desktop | default(false))
```
Phase 11 does NOT need to widen this condition — the `ec2-user` PAM password is already set by `secrets` when `layers.desktop` is true (which xrdp coexists with). No new secret is added (RDP-07 uses the existing `vnc-password` SSM param). If xrdp becomes the sole desktop access path in Phase 12, the secrets gating condition may need updating — but that is Phase 12 scope, not Phase 11.

---

## Summary

Phase 11 extends the `ansible/roles/xrdp/` role (Phase 10 built and installed the binaries) with configuration files, TLS cert, session startup, systemd service enable, playbook wiring, and a bake-time assertion.

The six deliverables map cleanly to the six requirements:

1. **xrdp.ini** (RDP-04) — template to `/etc/xrdp/xrdp.ini`; sets `port=3389`, `security_layer=tls`, `certificate=/etc/xrdp/cert.pem`, `key_file=/etc/xrdp/key.pem`, `ssl_protocols=TLSv1.2, TLSv1.3`; generates the self-signed cert via `openssl req` (mirrors the desktop role's noVNC pattern).
2. **sesman.ini** (RDP-05) — template to `/etc/xrdp/sesman.ini`; sets `[Xorg]` section with `param=/usr/libexec/Xorg` (RHEL/AL2023 path for non-setuid Xorg).
3. **PAM file** (RDP-06) — `ansible.builtin.copy:` to `/etc/pam.d/xrdp-sesman` with the `password-auth` delegation content; overrides whatever `--with-pam-rules=redhat` installed at make time, guaranteeing the exact content.
4. **startwm.sh** (RDP-07) — template to `/etc/xrdp/startwm.sh`; mirrors the existing `xstartup.j2` pattern (`XDG_SESSION_TYPE=x11`, `LIBGL_ALWAYS_SOFTWARE=1`, `GDK_BACKEND=x11`, `XDG_RUNTIME_DIR`, `dbus-launch --exit-with-session gnome-session`).
5. **systemd enable** (RDP-08) — `ansible.builtin.systemd:` to enable `xrdp` + `xrdp-sesman`; must also place/template the unit files (see below) since auto-detection may not have run during Phase 10's `make install`.
6. **Bake assertion** (RDP-13) — `ansible.builtin.stat` + `ansible.builtin.assert` + `command: systemctl is-enabled` to gate the bake.

**Primary recommendation:** Extend `ansible/roles/xrdp/tasks/main.yml` (Phase 11 block appended after Phase 10's cleanup) with templates for `xrdp.ini`, `sesman.ini`, `startwm.sh`, systemd units; a `copy:` for the PAM file; openssl cert generation; systemd enable; and the RDP-13 bake-time assertion. Wire the role into `ansible/playbook.yml` before `hardening`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| TLS cert generation | Packer bake-time (Ansible `command: openssl`) | — | Self-signed cert baked into AMI; mirrors the noVNC pattern in the desktop role |
| xrdp.ini configuration | Packer bake-time (Ansible `template:`) | — | Config file in AMI; must be present before first boot |
| sesman.ini configuration | Packer bake-time (Ansible `template:`) | — | Same; must know Xorg path at bake time |
| PAM file | Packer bake-time (Ansible `copy:`) | — | `/etc/pam.d/xrdp-sesman` must exist and delegate to `password-auth` at bake |
| startwm.sh session launcher | Packer bake-time (Ansible `template:`) | — | Session startup script; must be present and correct at bake |
| systemd unit files | Packer bake-time (Ansible `copy:` to `/usr/lib/systemd/system/`) | — | Units may not be installed by `make install` (see Pitfall 1); explicit copy is safer |
| systemd service enable | Packer bake-time (Ansible `systemd: enabled:true`) | — | Services start on first boot; `enabled:` at bake, not `started:` |
| Bake-time assertion (RDP-13) | Packer bake-time (Ansible `assert:` + `stat:` + `command:`) | — | Must fail the bake, not just log, if binaries/modules/services are absent |
| playbook.yml wiring | Packer bake-time (Ansible orchestration) | — | Role must be listed before `hardening`; RDP-08 invariant |

---

## Standard Stack

### Core (Phase 11 scope — configuration + service)

| Tool / Pattern | Source | Purpose | Why Standard |
|---------------|--------|---------|--------------|
| `ansible.builtin.template:` | Ansible stdlib | Render `xrdp.ini`, `sesman.ini`, `startwm.sh` from Jinja2 templates | Idiomatic Ansible for config files with variables |
| `ansible.builtin.copy:` | Ansible stdlib | Place PAM file `/etc/pam.d/xrdp-sesman` with exact content | Same pattern as the desktop role's `/etc/pam.d/vnc` |
| `openssl req -x509 ...` | AL2023 system openssl | Generate self-signed TLS cert | Mirrors `desktop` role noVNC cert pattern exactly |
| `ansible.builtin.systemd:` | Ansible stdlib | Enable `xrdp` + `xrdp-sesman` at boot | Standard Ansible module for systemd management |
| `ansible.builtin.stat:` + `ansible.builtin.assert:` | Ansible stdlib | RDP-13 bake assertion (binary/module/service presence) | Same assertion pattern as desktop role's leading assert |
| `ansible.builtin.command: systemctl is-enabled xrdp` | systemd | RDP-13 service enablement check | `systemctl is-enabled` returns 0 if enabled; idiomatic assertion |

### Installed File Paths (from Phase 10 `make install`)

All paths confirmed from xrdp v0.10.6 source analysis [CITED: github.com/neutrinolabs/xrdp v0.10.6 source tree]:

```
# Binaries (Phase 10 installed — Phase 11 only asserts presence)
/usr/local/sbin/xrdp
/usr/local/sbin/xrdp-sesman

# Config files (installed by make install; Phase 11 OVERWRITES with templates)
/etc/xrdp/xrdp.ini          <- Phase 11 templates this
/etc/xrdp/sesman.ini         <- Phase 11 templates this
/etc/xrdp/startwm.sh        <- Phase 11 templates this

# PAM file (installed by make install --with-pam-rules=redhat; Phase 11 re-copies for exactness)
/etc/pam.d/xrdp-sesman      <- Phase 11 copy: this with password-auth delegation

# xorgxrdp modules (Phase 10 installed)
/usr/lib64/xorg/modules/drivers/xrdpdev_drv.so
/usr/lib64/xorg/modules/input/xrdpkeyb_drv.so
/usr/lib64/xorg/modules/input/xrdpmouse_drv.so

# xorgxrdp xorg.conf (Phase 10 installed; DO NOT modify — xrdp/sesman.ini references it)
/etc/X11/xrdp/xorg.conf

# TLS cert/key (Phase 11 generates these)
/etc/xrdp/cert.pem          <- new: openssl self-signed cert
/etc/xrdp/key.pem           <- new: private key

# Systemd units (Phase 11 must place these explicitly — see Pitfall 1)
/usr/lib/systemd/system/xrdp.service
/usr/lib/systemd/system/xrdp-sesman.service
```

---

## Architecture Patterns

### System Architecture Diagram

```
Packer bake-time flow (Phase 11 — extends Phase 10):

  Phase 10 output:
    /usr/local/sbin/xrdp
    /usr/local/sbin/xrdp-sesman
    /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so
    /etc/xrdp/ (populated by make install: ini files, startwm.sh)
    /etc/pam.d/xrdp-sesman (installed by --with-pam-rules=redhat)
    /etc/X11/xrdp/xorg.conf
                          │
                          ▼
  Phase 11 Ansible tasks:

  [TLS Cert]
  openssl req -x509 -newkey rsa:2048 -nodes
    -keyout /etc/xrdp/key.pem
    -out    /etc/xrdp/cert.pem
    -days 3650 -subj '/CN=devbox'
                          │
  [Config Files]          │
  template: xrdp.ini.j2 ──►  /etc/xrdp/xrdp.ini
    port=3389, security_layer=tls
    certificate=/etc/xrdp/cert.pem
    key_file=/etc/xrdp/key.pem
    ssl_protocols=TLSv1.2, TLSv1.3

  template: sesman.ini.j2 ─►  /etc/xrdp/sesman.ini
    [Xorg] param=/usr/libexec/Xorg
           param=-config xrdp/xorg.conf
           param=-noreset ...

  template: startwm.sh.j2 ─►  /etc/xrdp/startwm.sh
    export XDG_SESSION_TYPE=x11
    export LIBGL_ALWAYS_SOFTWARE=1, GALLIUM_DRIVER=llvmpipe
    export GDK_BACKEND=x11
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    exec dbus-launch --exit-with-session gnome-session
                          │
  [PAM]                   │
  copy: dest=/etc/pam.d/xrdp-sesman
    auth include password-auth
    account include password-auth
    session include password-auth
    password include password-auth
                          │
  [Systemd Units]         │
  copy: xrdp.service ────►  /usr/lib/systemd/system/xrdp.service
  copy: xrdp-sesman.service► /usr/lib/systemd/system/xrdp-sesman.service
    (ExecStart=/usr/local/sbin/xrdp --nodaemon etc.)

  systemd: xrdp enabled: true
  systemd: xrdp-sesman enabled: true
                          │
  [Bake Assertion RDP-13] │
  stat: /usr/local/sbin/xrdp            -> assert exists
  stat: /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so -> assert exists
  command: systemctl is-enabled xrdp    -> assert rc == 0
  command: systemctl is-enabled xrdp-sesman -> assert rc == 0
                          │
  [playbook.yml wiring]   │
  roles: ... desktop → xrdp → hardening
                          │
                    AMI baked: xrdp ready on :3389 with TLS
```

### Recommended Project Structure (extended from Phase 10)

```
ansible/roles/xrdp/
├── defaults/
│   └── main.yml          # existing Phase 10 defaults; no new vars needed for Phase 11
│                         # (cert paths are static /etc/xrdp/cert.pem + key.pem)
├── tasks/
│   └── main.yml          # Phase 10 build pipeline + Phase 11 config/service/assert appended
├── templates/            # NEW in Phase 11
│   ├── xrdp.ini.j2       # TLS + port + session-type config
│   ├── sesman.ini.j2     # Xorg backend config (param=/usr/libexec/Xorg)
│   └── startwm.sh.j2     # GNOME Xorg session launcher (mirrors xstartup.j2)
└── files/                # NEW in Phase 11
    ├── xrdp.service       # systemd unit (hardcoded /usr/local paths)
    └── xrdp-sesman.service # systemd unit (hardcoded /usr/local paths)
```

Note: systemd units go in `files/` (not `templates/`) because all variable substitution (`@sbindir@`, `@sysconfdir@`) is resolved at write time to fixed paths — no Jinja2 variables needed.

### Pattern 1: TLS Cert Generation (mirrors desktop role noVNC pattern)

**What:** Generate a self-signed cert at bake time with `openssl req -x509`, idempotent via `creates:`.
**When to use:** RDP-04 — xrdp needs its own TLS cert at `/etc/xrdp/cert.pem` + `/etc/xrdp/key.pem`.

```yaml
# Source: ansible/roles/desktop/tasks/main.yml (noVNC TLS cert pattern, adapted)
# /etc/xrdp/ already exists (created by make install in Phase 10)
- name: Generate self-signed TLS cert for xrdp
  ansible.builtin.command:
    cmd: >
      openssl req -x509 -nodes -newkey rsa:2048
      -keyout /etc/xrdp/key.pem
      -out /etc/xrdp/cert.pem
      -days 3650 -subj '/CN=devbox'
  args:
    creates: /etc/xrdp/cert.pem

- name: Set xrdp TLS cert/key permissions
  ansible.builtin.file:
    path: "{{ item.path }}"
    owner: root
    group: root
    mode: "{{ item.mode }}"
  loop:
    - { path: /etc/xrdp/cert.pem, mode: "0644" }
    - { path: /etc/xrdp/key.pem,  mode: "0600" }
```

### Pattern 2: xrdp.ini template [Globals] section (RDP-04)

**What:** Override the make-installed `xrdp.ini` with a minimal TLS-enabled config.
**Key insight:** Only the `[Globals]` section changes relative to the upstream defaults; the session-type sections (`[Xorg]`, `[Xvnc]`, etc.) are inherited from the upstream template. Template only what must change; preserve upstream defaults for everything else.

```jinja2
{# Source: xrdp/xrdp.ini.in v0.10.6 [CITED: github.com/neutrinolabs/xrdp] #}
{# Minimal Phase 11 override — sets TLS and cert paths; rest stays upstream default #}
[Globals]
ini_version=1
fork=true
port=3389
tcp_nodelay=true
tcp_keepalive=true
security_layer=tls
crypt_level=high
certificate=/etc/xrdp/cert.pem
key_file=/etc/xrdp/key.pem
ssl_protocols=TLSv1.2, TLSv1.3
autorun=Xorg
allow_channels=true
allow_multimon=true
bitmap_cache=true
bitmap_compression=true
bulk_compression=true
max_bpp=32
new_cursors=true
use_fastpath=both

[Channels]
rdpdr=true
rdpsnd=true
drdynvc=true
cliprdr=true
rail=true
xrdpvr=true

[Xorg]
name=Xorg
lib=libxup.so
username=ask
password=ask
port=-1
code=20
h264_frame_interval=16
rfx_frame_interval=32
normal_frame_interval=40
```

**Notes:**
- `security_layer=tls` (not `negotiate`) — RDP-04 requires TLS explicitly.
- `autorun=Xorg` — auto-selects the Xorg session type; operator does not need to pick from a dropdown. [ASSUMED — verify that this key causes autorun to the [Xorg] section without prompting for session selection]
- `lib=libxup.so` — the shared library for the Xorg session type; installed to `/usr/local/lib/xrdp/libxup.so` by Phase 10's `make install`. The `.in` file uses `@lib_extension@` which resolves to `so`.

### Pattern 3: sesman.ini [Xorg] section (RDP-05)

**What:** Override the make-installed `sesman.ini` to point the Xorg param at AL2023's non-setuid Xorg binary.
**Critical key:** `param=/usr/libexec/Xorg` (not plain `Xorg`). [CITED: neutrinolabs/xrdp issue #1646; sesman.ini.in v0.10.6 comments confirm Fedora 26+/RHEL8+]

```ini
{# Source: sesman/sesman.ini.in v0.10.6 [CITED] #}
[Globals]
EnableUserWindowManager=true
UserWindowManager=startwm.sh
DefaultWindowManager=startwm.sh
ReconnectScript=reconnectwm.sh

[Security]
AllowRootLogin=false
MaxLoginRetry=4
TerminalServerUsers=tsusers
TerminalServerAdmins=tsadmins
AlwaysGroupCheck=false
RestrictOutboundClipboard=none
RestrictInboundClipboard=none

[Sessions]
X11DisplayOffset=10
MaxSessions=1
KillDisconnected=false
DisconnectedTimeLimit=0
IdleTimeLimit=0
Policy=Default

[Logging]
LogFile=xrdp-sesman.log
LogLevel=INFO
EnableSyslog=true

[Xorg]
param=/usr/libexec/Xorg
param=-config
param=xrdp/xorg.conf
param=-noreset
param=-nolisten
param=tcp
param=-logfile
param=.xorgxrdp.%s.log
```

**Notes:**
- `MaxSessions=1` — single-operator model.
- `AllowRootLogin=false` — hardening; `ec2-user` is the only login account.
- The `-config xrdp/xorg.conf` param is relative; Xorg looks in `/etc/X11/xrdp/xorg.conf` (installed by xorgxrdp `make install` in Phase 10). [CITED: xorgxrdp v0.10.5 xrdpdev/Makefile.am — `xrdpdevsysconfdir=$(sysconfdir)/X11/xrdp`]

### Pattern 4: startwm.sh template (RDP-07)

**What:** Template `/etc/xrdp/startwm.sh` to launch GNOME under Xorg (not Wayland) on EC2.
**When to use:** This is the key session-launcher script. It MUST export `XDG_SESSION_TYPE=x11` before launching `gnome-session`, or GNOME will attempt to start a Wayland compositor, which is incompatible with xorgxrdp.

```bash
#!/bin/bash
# Source: ansible/roles/desktop/templates/xstartup.j2 (adapted for xrdp startwm.sh)
# [VERIFIED: xstartup.j2 is the proven working GNOME Xorg session launcher for this repo]

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Force Xorg session — GNOME 40+ defaults to Wayland; xorgxrdp requires Xorg
export XDG_SESSION_TYPE=x11
export XDG_RUNTIME_DIR=/run/user/$(id -u)

# Software rendering — EC2 instances have no GPU; llvmpipe avoids blank screen
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export GDK_BACKEND=x11

# Ensure runtime dir exists (not created by systemd-logind for service sessions)
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

exec dbus-launch --exit-with-session gnome-session
```

**Key difference from upstream startwm.sh:** The upstream startwm.sh dispatches via `/etc/X11/xinit/Xsession`, which reads `DESKTOP_SESSION` from the environment and has complex fallback logic. The direct `exec dbus-launch --exit-with-session gnome-session` approach is simpler, already proven to work in this repo (xstartup.j2), and sidesteps all the environment-variable-inheritance problems.

### Pattern 5: systemd units for source-installed xrdp (RDP-08)

**What:** Place unit files with hardcoded `/usr/local/sbin/` exec paths (because Phase 10 installs to `--prefix=/usr/local`).

```ini
# /usr/lib/systemd/system/xrdp.service
# Source: instfiles/xrdp.service.in v0.10.6 [CITED] with @sbindir@ -> /usr/local/sbin
[Unit]
Description=xrdp daemon
Documentation=man:xrdp(8) man:xrdp.ini(5)
Requires=xrdp-sesman.service
After=network-online.target xrdp-sesman.service

[Service]
Type=exec
EnvironmentFile=-/etc/sysconfig/xrdp
EnvironmentFile=-/etc/default/xrdp
ExecStart=/usr/local/sbin/xrdp $XRDP_OPTIONS --nodaemon
SystemCallArchitectures=native
SystemCallFilter=@system-service

[Install]
WantedBy=multi-user.target
```

```ini
# /usr/lib/systemd/system/xrdp-sesman.service
# Source: instfiles/xrdp-sesman.service.in v0.10.6 [CITED] with @sbindir@ -> /usr/local/sbin
[Unit]
Description=xrdp session manager
Documentation=man:xrdp-sesman(8) man:sesman.ini(5)
After=network.target
StopWhenUnneeded=true
BindsTo=xrdp.service

[Service]
Type=exec
EnvironmentFile=-/etc/sysconfig/xrdp
EnvironmentFile=-/etc/default/xrdp
ExecStart=/usr/local/sbin/xrdp-sesman $SESMAN_OPTIONS --nodaemon
ExecReload=kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

### Pattern 6: Bake assertion (RDP-13)

**What:** Assert at bake time that binaries, modules, config files, and service enablement are all in place.

```yaml
# Source: pattern from desktop role leading assert + ansible.builtin.stat idiom
- name: Stat xrdp binary (RDP-13)
  ansible.builtin.stat:
    path: /usr/local/sbin/xrdp
  register: xrdp_rdp13_binary

- name: Stat xrdpdev Xorg driver module (RDP-13)
  ansible.builtin.stat:
    path: /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so
  register: xrdp_rdp13_module

- name: Assert xrdp binary and xorgxrdp module are present (RDP-13)
  ansible.builtin.assert:
    that:
      - xrdp_rdp13_binary.stat.exists
      - xrdp_rdp13_module.stat.exists
    fail_msg: >-
      RDP-13 bake assertion FAILED. One or more required files are missing:
        /usr/local/sbin/xrdp exists: {{ xrdp_rdp13_binary.stat.exists | default(false) }}
        /usr/lib64/xorg/modules/drivers/xrdpdev_drv.so exists: {{ xrdp_rdp13_module.stat.exists | default(false) }}
      Phase 10 build tasks may not have run, or make install may have failed silently.
    quiet: false

- name: Check xrdp service enablement (RDP-13)
  ansible.builtin.command:
    cmd: systemctl is-enabled xrdp xrdp-sesman
  register: xrdp_rdp13_enabled
  changed_when: false
  failed_when: false  # we assert below; don't fail here

- name: Assert xrdp and xrdp-sesman are enabled (RDP-13)
  ansible.builtin.assert:
    that:
      - xrdp_rdp13_enabled.rc == 0
    fail_msg: >-
      RDP-13 bake assertion FAILED. xrdp or xrdp-sesman is not enabled.
      Output: {{ xrdp_rdp13_enabled.stdout | default('') }}
      Run: systemctl is-enabled xrdp xrdp-sesman
    quiet: false
```

### Pattern 7: playbook.yml role insertion (RDP-08)

**What:** Insert the `xrdp` role in `ansible/playbook.yml` between `desktop` and `hardening`.

```yaml
# ansible/playbook.yml — add after desktop, before hardening
- role: desktop
  when: layers.desktop | default(false)

- role: xrdp                          # NEW — Phase 11
  when: layers.desktop | default(false)   # runs when desktop is enabled

- role: hardening  # MUST remain last — invariant (JUP-08 / CLAUDE.md §8)
  when: layers.hardening | default(false)
```

**Note on xrdp `when:` condition:** xrdp depends on the GNOME desktop (`@Desktop` group) being installed. Tying it to `layers.desktop` is the correct condition — same as the `secrets` role gating. If a future bake layer wants xrdp without a GNOME desktop, this condition would need a separate `layers.xrdp` gate, but that is not in scope.

**Note on secrets role gating:** the `secrets` role runs when `layers.vscode OR layers.desktop`. Since xrdp is gated on `layers.desktop`, the `secrets` role will always run before `xrdp`, guaranteeing `ec2-user` has a PAM password set before xrdp needs to auth it. No change to the secrets gating condition is needed for Phase 11.

### Anti-Patterns to Avoid

- **Using `security_layer=negotiate` instead of `tls`:** The default is `negotiate` which allows fallback to classic RDP (unencrypted). RDP-04 requires TLS explicitly — set `security_layer=tls`.
- **Leaving `certificate=` and `key_file=` empty:** xrdp can generate its own self-signed cert, but its auto-generated cert has no predictable permissions or location. Generating our own cert via `openssl req` mirrors the existing repo pattern and gives us explicit permission control.
- **Using `param=Xorg` (not the full path) in sesman.ini:** Works on systems where `/usr/bin/Xorg` is in PATH, but fails on AL2023 where the non-setuid Xorg is at `/usr/libexec/Xorg`. Always use the full path. [CITED: neutrinolabs/xrdp issue #1646]
- **Using the upstream startwm.sh without modification:** The upstream script dispatches via `/etc/X11/xinit/Xsession` which relies on `DESKTOP_SESSION` being set in the environment; under xrdp sessions the environment is minimal. The direct `exec dbus-launch --exit-with-session gnome-session` + explicit `XDG_SESSION_TYPE=x11` is simpler and proven in this repo.
- **Setting `autorun=` to a section name that uses a `@lib_extension@` placeholder:** After `make install`, `xrdp.ini` has the extension resolved to `so`. But if Phase 11 templates the entire xrdp.ini, we must use the literal `libxup.so` (not `libxup.@lib_extension@`).
- **Enabling `xrdp` without `daemon_reload: true`:** After placing new unit files, systemd must reload its unit database before `enabled: true` can take effect. Use `daemon_reload: true` on the first `systemd:` task (or a preceding `systemd: daemon_reload: true` task).
- **Inserting `xrdp` role AFTER `hardening` in playbook.yml:** Violates CLAUDE.md §8 invariant and the grep-gate hook. The role MUST go before `hardening`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Self-signed TLS cert | Shell script with openssl + custom permissions | `ansible.builtin.command: openssl req` + `args: creates:` + `file: mode:` | Idempotent; mirrors the repo's noVNC pattern; `creates:` prevents regenerating on every bake |
| PAM file content | Lineinfile edits to the `--with-pam-rules=redhat` installed file | `ansible.builtin.copy: content:` | Guaranteed exact content; idempotent; same pattern as desktop role `/etc/pam.d/vnc` |
| systemd unit content | Writing sed commands to substitute `@sbindir@` after make install | Static files in `ansible/roles/xrdp/files/` with hardcoded `/usr/local/sbin/` | The substitution is deterministic (prefix=/usr/local); static files are simpler and self-documenting |
| Service enable | `command: systemctl enable xrdp xrdp-sesman` | `ansible.builtin.systemd: name: xrdp enabled: true daemon_reload: true` | Ansible module is idempotent and handles daemon_reload properly |
| GNOME session launch | Writing custom xinitrc / Xsession dispatch logic | Direct `exec dbus-launch --exit-with-session gnome-session` with explicit env vars | The xstartup.j2 in this repo already proves this works on EC2 AL2023 GNOME |

**Key insight:** The heavy lifting for this phase is NOT code — it is configuration. Every pattern has a known-working analog already in the repo (cert from noVNC, PAM from vnc, systemd from vncserver/novnc, GNOME session from xstartup.j2). Phase 11 mirrors those patterns with xrdp-specific paths.

---

## Critical Findings: What `make install` Actually Installed

### Did `make install` install systemd units?

**Finding:** UNCERTAIN — depends on whether `pkg-config systemd` succeeded during Phase 10's `./configure`. [ASSUMED: likely NOT installed]

**Reasoning:** xrdp's `configure.ac` auto-detects the systemd unit directory via:
```sh
with_systemdsystemunitdir=$($PKG_CONFIG --variable=systemdsystemunitdir systemd)
```
This requires the `systemd` pkg-config package (provided by `systemd-devel` on RHEL/AL2023). Phase 10's build deps do NOT include `systemd-devel`. If `pkg-config systemd` fails (returns empty), `HAVE_SYSTEMD=false` and `make install` installs `init.d` and `sysconfig/default` fallback files INSTEAD of systemd units. [CITED: instfiles/Makefile.am v0.10.6 conditional logic]

**Consequence:** Phase 11 MUST place systemd unit files explicitly (via `ansible.builtin.copy:` from `files/`) regardless of what `make install` did. This is safe: if `make install` did install units to `/usr/lib/systemd/system/`, the `copy:` task overwrites them with our corrected version (which uses `/usr/local/sbin/` paths). If it did not install them, `copy:` creates them.

**Alternative approach:** Add `systemd-devel` to the Phase 10 build deps AND pass `--with-systemdsystemunitdir=/usr/lib/systemd/system` to configure. This is the cleaner solution but requires modifying Phase 10. The file-copy approach in Phase 11 achieves the same result without touching the completed Phase 10 plan.

### Did `make install` install `/etc/pam.d/xrdp-sesman`?

**Finding:** YES — Phase 10's configure includes `--enable-pam --with-pam-rules=redhat`, which causes the `instfiles/pam.d/mkpamrules` script to generate and install `/etc/pam.d/xrdp-sesman` from `xrdp-sesman.redhat` during `make install`. [CITED: instfiles/pam.d/Makefile.am v0.10.6; mkpamrules script]

**Consequence:** The file already exists after Phase 10. Phase 11 overwrites it with `ansible.builtin.copy:` to guarantee the exact content (including `pam_loginuid.so` and `pam_lastlog.so` lines). This is idempotent.

The installed content from `--with-pam-rules=redhat` is: [CITED: instfiles/pam.d/xrdp-sesman.redhat v0.10.6]
```
#%PAM-1.0
auth        include     password-auth
account     include     password-auth
session     required    pam_loginuid.so
session    optional     pam_lastlog.so quiet
session     include     password-auth
password    include     password-auth
```
Phase 11 can use this content verbatim — it already delegates to `password-auth` (satisfying RDP-06).

### Did `make install` install `/etc/xrdp/xrdp.ini` and `/etc/xrdp/sesman.ini`?

**Finding:** YES — both are generated from `.in` files and installed to `/etc/xrdp/` by `make install`. Phase 11 overwrites them with `template:` tasks. [CITED: xrdp/Makefile.am and sesman/Makefile.am v0.10.6]

### Did `make install` install `/etc/xrdp/startwm.sh`?

**Finding:** YES — `sesman/Makefile.am` includes `dist_sesmansysconf_SCRIPTS = startwm.sh ...`, which installs it to `$(sesmansysconfdir)` = `/etc/xrdp/`. Phase 11 overwrites it with `template:`. [CITED: sesman/Makefile.am v0.10.6]

---

## Common Pitfalls

### Pitfall 1: systemd Units NOT Installed by `make install` (CRITICAL)
**What goes wrong:** `systemctl enable xrdp` fails because the unit file doesn't exist, or xrdp's init.d script is installed instead of the systemd units.
**Why it happens:** `configure.ac` only installs systemd units when `HAVE_SYSTEMD=true`, which requires a successful `pkg-config --variable=systemdsystemunitdir systemd` call. If `systemd-devel` is not in the build deps, `pkg-config systemd` fails silently, `HAVE_SYSTEMD=false`, and the init.d fallback is installed instead. Phase 10's dep list does not include `systemd-devel`.
**How to avoid:** Phase 11 places the unit files explicitly with `ansible.builtin.copy: src: files/xrdp.service dest: /usr/lib/systemd/system/xrdp.service`. This is idempotent and correct regardless of what `make install` did.
**Warning signs:** `systemctl enable xrdp` reports "Unit file xrdp.service not found"; `ls /usr/lib/systemd/system/xrdp*` returns nothing.
**Confidence:** MEDIUM — inferred from configure.ac logic + Phase 10 dep list; verified by live bake if `make install`'s configure output is inspected.

### Pitfall 2: GNOME Launches Wayland Instead of Xorg (CRITICAL)
**What goes wrong:** The RDP session connects but shows a black screen or immediately disconnects. In logs, `gnome-session` starts but xorgxrdp's Xorg server fails.
**Why it happens:** GNOME 40+ defaults to Wayland sessions. On AL2023, `gnome-session` without `XDG_SESSION_TYPE=x11` will attempt to launch a Wayland compositor (Mutter in Wayland mode), which is incompatible with xorgxrdp's Xorg backend.
**How to avoid:** Set `export XDG_SESSION_TYPE=x11` in `startwm.sh` BEFORE the `exec gnome-session` line. Also set `GDK_BACKEND=x11`. The existing `xstartup.j2` in this repo already demonstrates the correct pattern. [VERIFIED: ansible/roles/desktop/templates/xstartup.j2]
**Warning signs:** Black screen on connect; xrdp log shows `xorgxrdp: starting Xorg failed` or session exits immediately after connection; Wayland warnings in session log.

### Pitfall 3: `param=Xorg` Instead of Full Path in sesman.ini
**What goes wrong:** xrdp-sesman attempts to launch `Xorg` (bare executable) which resolves to `/usr/bin/Xorg` (the setuid-root wrapper) or fails if the wrapper isn't found in PATH.
**Why it happens:** The default sesman.ini shipped by make install has `param=Xorg` (bare name). On Fedora 26+/RHEL8+/AL2023, the correct non-setuid Xorg is at `/usr/libexec/Xorg`. Using the setuid wrapper causes kernel or SELinux complications.
**How to avoid:** Template sesman.ini with `param=/usr/libexec/Xorg` in the `[Xorg]` section. [CITED: neutrinolabs/xrdp issue #1646; sesman.ini.in v0.10.6 comments confirm this path for Fedora 26+/Alma/Rocky 8+]
**Warning signs:** xrdp session log shows `Xorg: failed to start Xorg server` or permission denied errors; display never appears.

### Pitfall 4: ExecStart Path Uses `/usr/sbin/xrdp` Instead of `/usr/local/sbin/xrdp`
**What goes wrong:** systemd unit file points to the wrong path; `systemctl start xrdp` fails with "No such file or directory".
**Why it happens:** Distribution packages install xrdp to `/usr/sbin/`. Phase 10 installs from source with `--prefix=/usr/local`, so the binary is at `/usr/local/sbin/xrdp`. The unit `.in` files use `@sbindir@` which must be substituted with `/usr/local/sbin`.
**How to avoid:** The static unit files in `ansible/roles/xrdp/files/` use hardcoded `/usr/local/sbin/xrdp` and `/usr/local/sbin/xrdp-sesman`. Do NOT copy unit files from a distribution package or from make install output without verifying the exec path.
**Warning signs:** `systemctl start xrdp` fails; `systemctl status xrdp` shows `execStart=/usr/sbin/xrdp` (wrong prefix).

### Pitfall 5: `libxup.so` Not Found at Session Start
**What goes wrong:** xrdp connects, attempts to start the Xorg session, but immediately fails with "failed to load libxup".
**Why it happens:** Phase 10's make install puts xrdp plugins to `/usr/local/lib/xrdp/libxup.so`. If xrdp.ini uses `lib=libxup.@lib_extension@` (the `.in` template value, not the resolved value), the library won't be found. Also: `/usr/local/lib/` may not be in the dynamic linker search path on AL2023.
**How to avoid:** (1) The Phase 11 xrdp.ini template uses the literal `lib=libxup.so`. (2) If the dynamic linker cannot find libraries in `/usr/local/lib/`, add a `ldconfig` entry: create `/etc/ld.so.conf.d/xrdp.conf` containing `/usr/local/lib` and run `ldconfig`. This is a common source-install gotcha. [ASSUMED — verify at bake time]
**Warning signs:** xrdp connection log shows `failed to load /usr/local/lib/xrdp/libxup.so` or `cannot open shared object file`.

### Pitfall 6: colord/polkit Authentication Popup Breaks GNOME Session
**What goes wrong:** GNOME session starts but immediately shows an authentication dialog for colord color management, which hangs the session (xrdp can't interact with graphical auth dialogs).
**Why it happens:** GNOME's color management daemon (colord) requests polkit authorization at session startup. In headless/xrdp sessions, the polkit agent may not be running, and the dialog hangs.
**How to avoid:** Add a polkit rule granting users color-manager access without a password prompt. [CITED: Debian bug #907878]

```ini
# /etc/polkit-1/localauthority/50-local.d/45-allow.colord.pkla
[Allow colord for all users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
```

**Note:** The dconf settings in the existing `desktop` role (disable screensaver lock) suggest the project is already aware of dconf/GNOME system configuration. The polkit fix is the same kind of GNOME-in-headless-mode configuration. Whether the existing desktop role + noVNC sessions already encounter this issue (and whether it's already handled) should be checked before adding the fix — it may already be resolved, or it may be a Phase 11-specific issue.
**Warning signs:** GNOME session log shows `(colord:NN): GNOME_COLOR_MANAGER-WARNING`; session hangs at startup with a grey or partial screen.

### Pitfall 7: `autorun=` key causes session bypass issues
**What goes wrong:** Setting `autorun=Xorg` in xrdp.ini bypasses the login window entirely — if the operator hasn't yet configured a password, or if the PAM file is wrong, authentication silently fails.
**Why it happens:** `autorun=` in `[Globals]` tells xrdp to auto-route to that session type without showing the session-selection screen. This is a convenience feature but hides auth errors.
**How to avoid:** During initial debugging, leave `autorun=` unset and have the operator choose "Xorg" from the login screen. Add `autorun=Xorg` only after confirming auth works. In a baked AMI, `autorun=Xorg` is acceptable as the final state — there's only one session type anyway.
**Note:** This pitfall is LOW severity — the bake assertion (RDP-13) checks service enablement, not auth flow. The live auth test is RDP-14 (post-bake human UAT). [ASSUMED]

### Pitfall 8: `daemon_reload: true` Timing
**What goes wrong:** `ansible.builtin.systemd: name: xrdp enabled: true` fails with "Unit file changed on disk" error if systemd is not reloaded after the unit files are placed.
**Why it happens:** Ansible's `systemd` module needs a `daemon_reload: true` call (or a prior `systemd: daemon_reload: true` task) after placing new unit files, before trying to enable services.
**How to avoid:** Place the `daemon_reload: true` on the `systemd:` task that enables the service, or run a separate `systemd: daemon_reload: true` task after copying the unit files and before the `enabled: true` task.

---

## Code Examples

### Complete `/etc/pam.d/xrdp-sesman` content

```
# Source: instfiles/pam.d/xrdp-sesman.redhat v0.10.6 [CITED: github.com/neutrinolabs/xrdp]
# Installed by --with-pam-rules=redhat; Phase 11 re-copies for guaranteed content (RDP-06)
#%PAM-1.0
auth        include     password-auth
account     include     password-auth
session     required    pam_loginuid.so
session    optional     pam_lastlog.so quiet
session     include     password-auth
password    include     password-auth
```

This is the `xrdp-sesman.redhat` source file verbatim. It satisfies RDP-06: delegates to `password-auth`, which is the CIS-hardened PAM stack (faillock + pwquality).

### xrdp.service static unit file

```ini
# Source: instfiles/xrdp.service.in v0.10.6 [CITED: github.com/neutrinolabs/xrdp]
# @sbindir@ -> /usr/local/sbin (Phase 10 --prefix=/usr/local)
# @sysconfdir@ -> /etc (Phase 10 --sysconfdir=/etc)
[Unit]
Description=xrdp daemon
Documentation=man:xrdp(8) man:xrdp.ini(5)
Requires=xrdp-sesman.service
After=network-online.target xrdp-sesman.service

[Service]
Type=exec
EnvironmentFile=-/etc/sysconfig/xrdp
EnvironmentFile=-/etc/default/xrdp
ExecStart=/usr/local/sbin/xrdp $XRDP_OPTIONS --nodaemon
SystemCallArchitectures=native
SystemCallFilter=@system-service

[Install]
WantedBy=multi-user.target
```

### xrdp-sesman.service static unit file

```ini
# Source: instfiles/xrdp-sesman.service.in v0.10.6 [CITED: github.com/neutrinolabs/xrdp]
# @sbindir@ -> /usr/local/sbin (Phase 10 --prefix=/usr/local)
# @sysconfdir@ -> /etc (Phase 10 --sysconfdir=/etc)
[Unit]
Description=xrdp session manager
Documentation=man:xrdp-sesman(8) man:sesman.ini(5)
After=network.target
StopWhenUnneeded=true
BindsTo=xrdp.service

[Service]
Type=exec
EnvironmentFile=-/etc/sysconfig/xrdp
EnvironmentFile=-/etc/default/xrdp
ExecStart=/usr/local/sbin/xrdp-sesman $SESMAN_OPTIONS --nodaemon
ExecReload=kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| xrdp from EPEL package (`dnf install xrdp`) | Build from source with sha256-pinned tarballs | This repo's airgap invariant; Phase 10 handles the build |
| `security_layer=negotiate` (allows unencrypted RDP) | `security_layer=tls` | TLS-only; more secure; RDP-04 requirement |
| `param=Xorg` in sesman.ini (works on Debian/Ubuntu) | `param=/usr/libexec/Xorg` (RHEL/AL2023) | Full path required for non-setuid Xorg on RHEL8+/AL2023 |
| X11rdp (full Xorg recompile) | xorgxrdp (loadable Xorg modules) | xorgxrdp is current standard; X11rdp is legacy |
| VNC-based remote desktop | xrdp with xorgxrdp Xorg backend | This milestone's replacement; native RDP client, PAM auth |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `make install` did NOT install systemd units (because systemd-devel was not in Phase 10 build deps) | Critical Findings / Pitfall 1 | If units WERE installed, Phase 11's `copy:` is a harmless overwrite; the consequence of being wrong is low |
| A2 | `autorun=Xorg` in xrdp.ini causes xrdp to auto-select the Xorg session type without showing a session-selection dropdown | Pattern 2 / Pitfall 7 | If `autorun=Xorg` works differently than expected, the operator sees a session chooser; fix is to verify at UAT (RDP-14) |
| A3 | `libxup.so` is in `/usr/local/lib/xrdp/` and the dynamic linker finds it without explicit `ld.so.conf` entry | Pitfall 5 | If linker cannot find it, add `/etc/ld.so.conf.d/xrdp.conf` with `/usr/local/lib` and run `ldconfig` — a simple fix if needed |
| A4 | The colord/polkit issue (Pitfall 6) exists on this image | Pitfall 6 | If it doesn't manifest (e.g., the existing desktop role already handles it, or AL2023's colord policy allows unauthenticated access), the polkit fix is harmless but unnecessary |
| A5 | `/usr/libexec/Xorg` is the correct non-setuid Xorg path on AL2023 (same as Fedora 26+/RHEL8+) | Pattern 3 / Pitfall 3 | AL2023 follows the same packaging conventions as RHEL8 for Xorg; if the path differs, the session fails to start; verify by `which Xorg` or `ls /usr/libexec/Xorg` on a live bake instance |
| A6 | `XDG_SESSION_TYPE=x11` in startwm.sh is sufficient to prevent GNOME from using Wayland | Pattern 4 / Pitfall 2 | This is the proven approach from this repo's xstartup.j2; LOW risk |
| A7 | The `xrdp` role `when:` condition should use `layers.desktop` (not a new `layers.xrdp`) | Pattern 7 (playbook.yml wiring) | If layers.xrdp is preferred (for a future bake without desktop), the condition should be updated; for this phase, xrdp is always co-deployed with the GNOME desktop |

---

## Open Questions

1. **Did Phase 10's `make install` actually install systemd units?**
   - What we know: `configure.ac` auto-detects systemd via `pkg-config systemd`; `systemd-devel` is not in Phase 10's dep list; if detection failed, units are NOT installed.
   - What's unclear: Whether `pkg-config systemd` on AL2023 works without `systemd-devel` (some distros include the pc file in the base `systemd` package).
   - Recommendation: Phase 11 places units explicitly via `files/`; this is safe regardless. Optionally, inspect `configure` output at bake time (look for "systemd support: yes/no" in the configure summary printed by Phase 10's configure task).

2. **Does the colord/polkit issue manifest on this image?**
   - What we know: It is a documented GNOME-over-xrdp issue on RHEL-family [CITED: Debian bug #907878 + community reports on RHEL8]. The desktop role does not currently include a colord polkit rule.
   - What's unclear: Whether the existing dconf screensaver disable + GNOME version on AL2023 GNOME triggers this.
   - Recommendation: Include the polkit rule in Phase 11 proactively. If it's not needed, it's harmless (just allows color calibration without a password prompt). Adding it reactively after a failed RDP-14 UAT means another bake cycle.

3. **Is `ldconfig` needed for `/usr/local/lib/xrdp/libxup.so`?**
   - What we know: `/usr/local/lib/` is typically NOT in the default ld.so search path on RHEL/AL2023.
   - What's unclear: Whether xrdp loads `libxup.so` via dlopen() (bypasses ld.so) or relies on the linker. If via dlopen() with a full path from xrdp.ini's `lib=`, no ldconfig is needed.
   - Recommendation: Add an `ldconfig` step (`ansible.builtin.command: cmd: ldconfig args: creates: /etc/ld.so.conf.d/xrdp.conf`) and create `/etc/ld.so.conf.d/xrdp.conf` with `/usr/local/lib`. This is cheap and preempts the issue.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `/usr/local/sbin/xrdp` | RDP-04/08/13 | ✓ (Phase 10 installed) | 0.10.6 | None — Phase 10 must have completed |
| `/usr/lib64/xorg/modules/drivers/xrdpdev_drv.so` | RDP-05/13 | ✓ (Phase 10 installed) | 0.10.5 | None — Phase 10 must have completed |
| `openssl` (for cert gen) | RDP-04 | ✓ (AL2023 base) | system openssl | — |
| `/usr/libexec/Xorg` (non-setuid) | RDP-05 | ✓ [ASSUMED: AL2023 = RHEL8 convention] | 1.20.14 | Verify path at bake; `which Xorg` |
| `gnome-session` | RDP-07 | ✓ (installed by `@Desktop` group in desktop role) | system | — |
| `dbus-launch` | RDP-07 | ✓ (part of `dbus-x11` installed with GNOME) | system | — |
| `systemd` | RDP-08 | ✓ (AL2023 uses systemd) | system | — |
| `/usr/lib/systemd/system/` (writable at bake) | RDP-08 | ✓ (Packer bake runs as root) | — | — |

**Missing dependencies with no fallback:**
- Phase 10 binaries must exist — if Phase 10 did not complete, Phase 11 bake assertion will fail loudly (RDP-13).

---

## Security Domain

> security_enforcement not set to false in .planning/config.json — treating as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes — RDP-06/07 | PAM `password-auth` (faillock + pwquality); no xrdp-specific password bypass |
| V3 Session Management | Partial | `MaxLoginRetry=4` in sesman.ini; `KillDisconnected=false` (session preserved on disconnect) |
| V4 Access Control | Partial | `AllowRootLogin=false` in sesman.ini; single-user model (`ec2-user` only) |
| V5 Input Validation | No | Config files are operator-controlled at bake; no runtime user input into configs |
| V6 Cryptography | Yes — RDP-04 | TLS only (`security_layer=tls`); `ssl_protocols=TLSv1.2, TLSv1.3`; RSA-2048 self-signed cert |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unencrypted RDP session | Information Disclosure | `security_layer=tls` (not `negotiate`); TLSv1.2+ only |
| TLS certificate not validated by client | Spoofing | Self-signed cert; client must accept on first connect (pin-on-first-use); RDP-14 UAT verifies |
| Root login over RDP | Elevation of Privilege | `AllowRootLogin=false` in sesman.ini |
| PAM stack bypass (weak auth) | Authentication bypass | `/etc/pam.d/xrdp-sesman` delegates to `password-auth` which includes faillock (brute-force protection) and pwquality |
| xrdp listening on all interfaces | Spoofing/DoS | `:3389` firewall gating is Phase 12 (Terraform SG); at bake time the port is configured; Phase 12 restricts to `allowed_web_cidrs` |
| `changeme` in xrdp.ini template | Information Disclosure | Pre-commit `no-changeme` hook covers tracked files; templates must use actual values or Jinja2 vars, never `changeme` |

### Security Notes

- **Cert permissions:** `cert.pem` at `0644 root:root` (readable by all, needed by xrdp daemon); `key.pem` at `0600 root:root` (only root reads it; xrdp daemon runs as root by default in this config). [ASSUMED: xrdp runs as root without a separate `runtime_user`; the `runtime_user=xrdp` option is commented out in the default xrdp.ini and is not configured in Phase 11]
- **No `:22` impact:** This phase is purely AMI-layer configuration. The SSM-first posture is unchanged; `:3389` network exposure is Phase 12 scope.

---

## Sources

### Primary (HIGH confidence)
- `github.com/neutrinolabs/xrdp` v0.10.6 source tree — `xrdp/xrdp.ini.in`, `sesman/sesman.ini.in`, `sesman/startwm.sh`, `instfiles/xrdp.service.in`, `instfiles/xrdp-sesman.service.in`, `instfiles/pam.d/xrdp-sesman.redhat`, `instfiles/pam.d/Makefile.am`, `instfiles/Makefile.am`, `xrdp/Makefile.am`, `sesman/Makefile.am`, `configure.ac` — all fetched via GitHub API 2026-06-15
- `github.com/neutrinolabs/xorgxrdp` v0.10.5 source tree — `xrdpdev/xorg.conf`, `xrdpdev/Makefile.am`, `configure.ac` — all fetched via GitHub API 2026-06-15
- `ansible/roles/desktop/templates/xstartup.j2` (this repo) — proven GNOME Xorg session launcher pattern for EC2/AL2023; `XDG_SESSION_TYPE=x11 + LIBGL_ALWAYS_SOFTWARE + dbus-launch gnome-session` confirmed working

### Secondary (MEDIUM confidence)
- `github.com/neutrinolabs/xrdp/issues/1646` — CentOS 8 Xorg path; confirms `param=/usr/libexec/Xorg` for RHEL8/Fedora 26+
- `bugs.debian.org/907878` — colord polkit issue with GNOME over xrdp; polkit.pkla workaround documented
- AWS documentation — `docs.aws.amazon.com/linux/al2023/ug/installing-gnome-al2023.html` — confirms `dnf groupinstall "Desktop"` installs GNOME on AL2023

### Tertiary (LOW confidence — flagged as ASSUMED)
- A1: systemd units not installed by Phase 10 `make install`
- A2: `autorun=Xorg` behavior in xrdp.ini
- A3: `libxup.so` linker resolution without explicit ldconfig entry
- A4: colord/polkit issue manifests on AL2023 + this image
- A5: `/usr/libexec/Xorg` path on AL2023

---

## Metadata

**Confidence breakdown:**
- xrdp.ini / sesman.ini config keys: HIGH — verified from v0.10.6 source tree
- systemd unit content: HIGH — verified from v0.10.6 source tree with deterministic path substitution
- PAM file content: HIGH — verified from xrdp-sesman.redhat source
- startwm.sh GNOME session pattern: HIGH — mirrors existing repo xstartup.j2 (proven on EC2 AL2023 GNOME)
- Xorg path for sesman.ini: HIGH — documented in sesman.ini.in comments + confirmed by xrdp issue #1646
- systemd auto-detection (whether units were installed by Phase 10): MEDIUM — inferred from configure.ac logic
- colord/polkit issue on AL2023: LOW — documented on RHEL-family but not confirmed on this specific image
- ldconfig necessity: LOW — depends on how xrdp loads libxup.so at runtime

**Research date:** 2026-06-15
**Valid until:** 2026-09-15 (xrdp 0.10.x stable series; AL2023 package paths stable)
