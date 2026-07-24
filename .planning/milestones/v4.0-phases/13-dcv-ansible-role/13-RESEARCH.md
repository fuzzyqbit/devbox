# Phase 13: `dcv` Ansible Role - Research

**Researched:** 2026-06-19
**Domain:** Amazon DCV remote-desktop server (`dcvserver`) on CIS-hardened (SELinux enforcing + FIPS) AL2023 x86_64, baked via Packer + Ansible; PORT of a proven prior role recovered from git + v4.0 deltas
**Confidence:** HIGH (prior role recovered from git at file:line; every dcv.conf key + cert path + session mechanism verified against the official AWS DCV config-param reference this session; the FIPS-cert / SELinux-fcontext / bake-assert recipes are read verbatim from the shipped v3.2 `xrdp` role)

## Summary

Phase 13 is a **port-plus-deltas**, not a greenfield build. A complete, syntax-verified `dcv` role existed in git (`51c5f1f` — the corrected version; `67faeb3`/`8538ef3`/`1d2f32e` carry a PII-scrubber-mangled GPG URL) and was reverted at `d3bd9a0` **solely** for a runtime licensing failure (S3 `dcv-license.<region>` unreachable in airgap) — that licensing fix is **Phase 14 Terraform scope, explicitly out of this phase**. The prior role already: asserts the secrets-role PAM password, imports the NICE GPG key, `get_url`s the pinned `2025.0-20103` tarball (optional sha256), installs the three non-GPU RPMs (`nice-dcv-server`, `nice-xdcv`, `nice-dcv-web-viewer`), templates `dcv.conf`, templates + enables a oneshot `dcv-virtual-session.service`, enables `dcvserver`, and cleans `/tmp`. Port that, then layer on the v4.0 hardening deltas the prior attempt never reached: QUIC-on, a FIPS-safe cert at the DCV-mandated path, SELinux fcontext+relabel, and an xrdp-RDP-13-grade bake assert.

The single most important technical resolution this research delivers: **DCV does not support automatic virtual sessions.** The AWS config-param reference and the session-management guide are explicit — `[session-management] create-session=true` + `[session-management/automatic-console-session] owner=…` creates a **CONSOLE** session only ("Amazon DCV doesn't support automatic virtual sessions"). Since v4.0 mandates a **virtual** session (DCV-03), the dcv.conf auto-session path is **unusable**; the **oneshot systemd unit running `dcv create-session --type virtual`** is the *only* mechanism. The prior role already chose this — keep it. A second decisive correction: there is **no `[security] certificate`/`certificate-key` dcv.conf key.** DCV reads a hardcoded `/etc/dcv/dcv.pem` + `/etc/dcv/dcv.key` (those exact names, owned by the `dcv` user, mode 600). You do **not** point dcv.conf at a cert — you drop the FIPS-clean cert at that fixed path with those fixed names and DCV hot-reloads it (2022.0+).

**Primary recommendation:** Port `git show 51c5f1f:ansible/roles/dcv/` verbatim as the base, then apply six surgical deltas: (1) dcv.conf gains `[connectivity] enable-quic-frontend=true` + `web-port=8443` (QUIC stays ON — v4.0 direct-connect, opposite of the SSM-era PITFALLS.md), (2) generate a FIPS-clean RSA-2048/sha256/SAN cert to `/etc/dcv/dcv.{pem,key}` chowned to `dcv`:`dcv` 0600 (xrdp cert recipe), (3) `semanage fcontext` + `restorecon` over DCV's RPM paths, (4) keep the oneshot virtual-session unit (the only auto-virtual mechanism), (5) reuse the xrdp `45-allow-colord.rules` + a `/etc/pam.d/dcv` delegate, (6) an RDP-13-style bake assert over binary/conf/cert/units. Wire `- role: dcv` before `hardening`, gated `when: layers.dcv and layers.desktop`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| DCV server install (RPMs from CloudFront) | Bake / Ansible `dcv` role | — | Airgap `get_url` + GPG + sha256 at bake; mirrors ffmpeg/mise convention |
| `dcv.conf` (auth/TLS/QUIC/port) | Bake / Ansible `dcv` role | — | Declarative config templated at bake |
| Virtual session auto-create | Bake (systemd unit) / runtime (boot) | — | DCV creates no session; oneshot unit runs `dcv create-session --type virtual` at boot |
| GNOME desktop the session renders | `desktop` role (existing) | `dcv` role consumes it | `@Desktop`+gnome-session already installed; `dcv` gated on `layers.desktop` |
| PAM credential | `secrets` role (existing) | `dcv` role consumes via `authentication=system` | ec2-user password generated/published/applied by secrets pipeline; no new secret |
| FIPS-safe TLS cert | Bake / Ansible `dcv` role | — | Self-signed RSA-2048/sha256/SAN at `/etc/dcv/dcv.{pem,key}` |
| SELinux labels for dcvserver | Bake / Ansible `dcv` role | hardening flips enforcing (last) | fcontext+relabel at bake while still permissive; AVC proof is live (Phase 15) |
| Licensing (S3 `dcv-license.<region>`) | **Terraform — Phase 14** | — | **OUT OF SCOPE for Phase 13.** Runtime infra (VPC endpoint + IAM); bake succeeds under 15-day grace |
| SG `:8443` TCP+UDP ingress | **Terraform — Phase 14** | — | **OUT OF SCOPE for Phase 13.** Network perimeter |

## User Constraints

> No `CONTEXT.md` exists for Phase 13 (discuss-phase has not run). Constraints below are derived from the authoritative upstream docs: `.planning/REQUIREMENTS.md` (v4.0), `.planning/ROADMAP.md` (Phase 13 success criteria), and `./CLAUDE.md` (invariants). The planner MUST honor these.

### Locked Decisions (from REQUIREMENTS.md + ROADMAP.md, authoritative)

- **Virtual session, not console** — `nice-xdcv` / `Xdcv`, software render, owner `ec2-user` (DCV-03).
- **QUIC ON** — `enable-quic-frontend=true`; this is the v4.0 direct-connect posture (REQUIREMENTS.md line 7, DCV-02). UDP `:8443` is opened in Phase 14, not here.
- **`authentication=system`** (PAM) reusing the existing ec2-user password — no new secret; the SSM param `/devbox/<user>/vnc-password` path is unchanged (relabelled only).
- **TLS on** with a self-signed cert; **FIPS-safe** (RSA-2048 / sha256 / SAN) per DCV-05.
- **`web-port=8443`** (DCV-02).
- **Non-GPU package set only** — `nice-dcv-server`, `nice-xdcv`, `nice-dcv-web-viewer`; NO `nice-dcv-gl`/`nice-dcv-gltest`/GPU packages (DCV-01).
- **Airgap-compliant install** — pinned `get_url` from CloudFront + NICE-GPG-KEY imported + sha256, no S3-for-install, no private mirror, no `--nogpgcheck` (DCV-01, CLAUDE.md §2/§8).
- **`hardening` stays the last role**; `dcv` wires strictly before it (DCV-04, CLAUDE.md §8 invariant).
- **Bake-time assertion** proves DCV binaries + session config present; bake fails if not (DCV-04).
- **SELinux relabel + AVC-clean-capable** (DCV-05); the live AVC proof is Phase 15 (out of scope here).

### Claude's Discretion

- The exact oneshot unit `ExecStart`/`ExecStop` form and session-ID naming (prior role used `ec2-user-session`).
- Whether to add a `/etc/pam.d/dcv` file explicitly vs. relying on the RPM-shipped default (recommend: provide it explicitly, delegate to `password-auth` — see Pattern 5).
- Whether to vendor the ~3 KB NICE-GPG-KEY into `files/` vs. importing from CloudFront (recommend: import from CloudFront, matching the prior role; vendoring is a future true-airgap nicety).
- The `dcv_tarball_sha256` value — empty on first bake (deferred-pin per CLAUDE.md §9), filled after first bake.
- Whether the virtual session uses the DCV default init script or a custom `--init` GNOME launcher (recommend: rely on the default desktop + a `~/.xsession`/dconf nudge if needed — see Pattern 4 / Open Question 2).

### Deferred Ideas (OUT OF SCOPE for Phase 13)

- **S3 license VPC endpoint + IAM `s3:GetObject`** — Phase 14 / Terraform. (The make-or-break runtime fix; bake works under the 15-day grace without it.)
- **SG `:8443` TCP+UDP ingress, drop `:3389`** — Phase 14 / Terraform.
- **xrdp/xorgxrdp role removal, `test-xrdp.yml` deletion, CIS 2.2.1 revert, post-hardening Xorg guard deletion** — Phase 14.
- **Operator surface** (`run`, `scripts/`, `secrets-show` labels, CLAUDE.md) — Phase 14.
- **secrets-bootstrap restart-loop edit** (`xrdp.service` → `dcvserver.service dcv-virtual-session.service`) — Phase 14 removal sweep (see Pitfall 8 / Open Question 3 — flagged but not owned by Phase 13).
- **Live UAT** (license resolves, GNOME renders, AVC-clean enforcing, FIPS handshake, QUIC works) — Phase 15.
- GPU acceleration, native client, custom CA cert, multi-monitor, collaboration — v4.x.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DCV-01 | Install non-GPU DCV package set (`nice-dcv-server`, `nice-dcv-web-viewer`, `nice-xdcv`) via pinned `get_url` from CloudFront + NICE-GPG-KEY + sha256; no GPU pkgs; airgap-compliant | Standard Stack table + Install section + prior-role keep table; CloudFront URL + GPG URL + builds (20103/688) verified against amazondcv.com + AWS adminguide |
| DCV-02 | `dcv.conf`: `authentication=system`, TLS on, **QUIC enabled** (`enable-quic-frontend=true`), `web-port=8443`, owner `ec2-user` | "Exact dcv.conf for v4.0" section — every key verified against AWS config-param reference (defaults + types) |
| DCV-03 | Virtual session (`Xdcv`) at boot rendering GNOME owned by `ec2-user`; DCV does not auto-create | Pattern 3 (oneshot unit = ONLY auto-virtual mechanism — AWS: "doesn't support automatic virtual sessions") + Pattern 4 (GNOME wiring) |
| DCV-04 | `dcvserver` enabled; `dcv` wired before `hardening`; bake-time assert proves binaries + session config | Pattern 6 (bake assert, mirrors xrdp RDP-13) + Playbook Wiring section + hardening-last invariant check |
| DCV-05 | Survives hardened baseline: SELinux relabel (+ AVC-clean) + FIPS-safe self-signed cert (RSA-2048/sha256/SAN), reusing v3.2 recipe | FIPS-Cert Decision section + SELinux Relabel section — both copy the shipped xrdp tasks verbatim |

## Project Constraints (from CLAUDE.md)

- **`hardening` MUST remain the last role in `ansible/playbook.yml`.** `dcv` inserts before it (same slot xrdp occupies). Enforced by the `grep-gates` hook + CI. (§8)
- **`changeme` literal MUST NOT appear in any tracked code file.** The prior role's PAM-password assert contains `desktop_vnc_password != "changeme"` — this is a **known pre-existing `no-changeme` hook false-positive** that the surviving secrets-role asserts also carry. The planner must decide: keep it (matching the secrets-role precedent — the hook already tolerates those) or rephrase to avoid the literal. (§8) — see Assumptions A4.
- **Airgap install:** download-based (`get_url`), sha256-pinned, NICE-GPG-KEY imported, `disable_gpg_check: false`, no S3-for-install, no private mirror, no `--nogpgcheck`. (§2)
- **Deferred-pin posture:** the `dcv_tarball_sha256` is intentionally empty on first bake; fill after first bake with `sha256sum`. Matches the Packer SSM `:NN` follow-up convention. (§9)
- **No retired `make <target>` invocations** in tracked files (operator surface is `./run`) — not relevant to the role itself but to any docs touched (Phase 14).
- **Immutability / KISS / small files** (global coding-style rules): the role is many small files (defaults, tasks, handlers, 2 templates, 1-2 `files/`), each focused.

## Standard Stack

### Core (DCV RPMs — from the pinned CloudFront tarball, NOT a registry)

| Package | Version (build) | Purpose | Why Standard |
|---------|-----------------|---------|--------------|
| `nice-dcv-server` | 2025.0.20103-1.amzn2023.x86_64 | The `dcvserver.service` daemon + `dcv` CLI; web/QUIC transport on `:8443`; auto-creates the `dcv` system user | Mandatory — the only strictly-required package [CITED: docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html] |
| `nice-xdcv` | 2025.0.688-1.amzn2023.x86_64 | The `Xdcv` virtual X server — headless, no GPU, no gdm/console X needed | Required for **virtual** sessions (the v4.0 model). **Build 688 ≠ server 20103** — independent per-component builds [CITED: amazondcv.com download index] |
| `nice-dcv-web-viewer` | 2025.0.20103-1.amzn2023.x86_64 | Browser web client served by `dcvserver` | Required for browser connect (DCV-02 `web-port=8443`) [CITED: adminguide] |

### Supporting (AL2023 dnf core repo — airgap-safe, NO new get_url)

| Package | Purpose | When to Use |
|---------|---------|-------------|
| `policycoreutils-python-utils` | provides `semanage` for the fcontext mapping (DCV-05) | **Required** — the xrdp role already pulls this; the dcv role needs it for `semanage fcontext` (it is NOT pulled in automatically). Add to a `dcv_runtime_deps` dnf install |
| GNOME (`@Desktop` + `gnome-shell` + `gnome-session` + `mesa-dri-drivers` + `dejavu-*` fonts) | The desktop the virtual session renders + software OpenGL | **Already installed by the `desktop` role** — do NOT re-add. Gate `dcv` on `layers.desktop` so it runs first |
| `glx-utils` (provides `glxinfo`) | Optional: verify Mesa software GL inside the session | Optional bake/UAT nicety; cheap. Recommend skip unless a UAT assertion wants it (YAGNI) |

### Packages explicitly OMITTED (non-GPU single-operator box)

| Package | Why omitted |
|---------|-------------|
| `nice-dcv-gl` / `nice-dcv-gltest` | GPU-sharing only; needs an NVIDIA/AMD driver this instance lacks; aarch64-unavailable. Mesa software GL (from `mesa-dri-drivers`) covers non-GPU [CITED: adminguide prereq — "non-GPU … software rendering mode using the Mesa drivers"] |
| `nice-dcv-simple-external-authenticator` | External/token auth only; we use `authentication=system` (PAM) |
| `xorg-x11-drv-dummy` (XDummy) | Console-session-only. **"This is not required if you intend to use virtual sessions."** [CITED: adminguide prereq] |
| `xorg-x11-server-Xorg` (system X) | **"If you intend to use virtual sessions without GPU sharing, you don't need an X server."** [CITED: adminguide prereq]. The virtual session uses `Xdcv` from `nice-xdcv`. This is WHY Phase 14 can revert CIS 2.2.1 |
| USB drivers (`dcvusbdriverinstaller`+`dkms`) | USB remotization — not needed for a browser dev workstation |

**Installation:**
```bash
# 1. Import the NICE GPG key BEFORE any RPM install (ansible.builtin.rpm_key)
rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY

# 2. Download the pinned AL2023 x86_64 server tarball (~41 MB) over HTTPS at bake
#    get_url url=.../2025.0/Servers/nice-dcv-2025.0-20103-amzn2023-x86_64.tgz checksum=sha256:<pin>

# 3. Extract (tarball = folder of RPMs, --strip-components=1), then dnf-install the THREE RPMs
dnf install -y \
  nice-dcv-server-2025.0.20103-1.amzn2023.x86_64.rpm \
  nice-xdcv-2025.0.688-1.amzn2023.x86_64.rpm \
  nice-dcv-web-viewer-2025.0.20103-1.amzn2023.x86_64.rpm
#    disable_gpg_check: false  (key imported in step 1 → signature verified)

# 4. Supporting dnf (AL2023 core): semanage for SELinux fcontext
dnf install -y policycoreutils-python-utils
```

**Version verification (this session):**
- `nice-dcv-server` 2025.0-20103 — current latest [VERIFIED: AWS what's-new — DCV 2025.0 released 2025-10-22; amazondcv.com index lists `nice-dcv-2025.0-20103-amzn2023-x86_64.tgz`]. Same build the prior role pinned.
- `nice-xdcv` 2025.0-688 — [CITED: amazondcv.com index]. The prior role glob-matched `nice-xdcv-*.rpm` rather than hardcoding 688 in the path — KEEP that glob approach (independent build numbers).
- CloudFront install host + NICE-GPG-KEY URL [VERIFIED: prior role `51c5f1f` + AWS adminguide].

## Package Legitimacy Audit

> DCV is distributed **only** as a GPG-signed tarball from AWS CloudFront (`d1uj6qtbmh3dt5.cloudfront.net`) — it is NOT on npm/PyPI/crates/dnf. Standard registry slopcheck does not apply; the integrity gate is **NICE-GPG-KEY signature verification + a pinned sha256 on the tarball** (the project's airgap idiom). `slopcheck` install was attempted and correctly denied by the sandbox (undeclared PyPI package); it would not apply to a vendor RPM tarball regardless.

| Package | Source | Integrity Gate | Pin | Disposition |
|---------|--------|----------------|-----|-------------|
| `nice-dcv-server` 2025.0.20103 | AWS CloudFront tarball | NICE-GPG-KEY RPM signature (`disable_gpg_check: false`) + tarball sha256 | exact version+build in defaults | Approved — official AWS artifact |
| `nice-xdcv` 2025.0.688 | same tarball | same GPG signature | glob `nice-xdcv-*.rpm` from the pinned tarball | Approved |
| `nice-dcv-web-viewer` 2025.0.20103 | same tarball | same GPG signature | exact version+build | Approved |
| `policycoreutils-python-utils` | AL2023 core dnf repo | distro repo GPG | dnf `state: present` | Approved — AL2023 core, same as xrdp role |

**Packages removed due to slopcheck [SLOP]:** none (not registry packages).
**Packages flagged [SUS]:** none.
**Integrity note:** the planner MUST keep `disable_gpg_check: false` and MUST NOT add `--nogpgcheck` (CLAUDE.md §8 / Pitfall 9). The `dcv_tarball_sha256` is `[ASSUMED]` empty on first bake (deferred-pin, A3) — fill after first bake; until filled, the GPG signature is the integrity gate.

## Recovered Prior-Role Inventory (KEEP / CHANGE)

> Base to port: **`git show 51c5f1f:ansible/roles/dcv/`** (the corrected version — its `rpm_key` URL is the canonical `https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY`, fixed in `78e169b` after the PII-scrubber mangled it to `https:<MRCLEAN:ENTROPY:001>` in `67faeb3`/`8538ef3`/`1d2f32e`). **Do NOT port from `67faeb3` — its GPG URL is a redaction placeholder that breaks the install.**

| Prior-role element | What it did | KEEP / CHANGE | v4.0 action |
|--------------------|-------------|---------------|-------------|
| PAM-password assert (`desktop_vnc_password` defined / non-empty / `!= "changeme"`, `no_log`) | Gates on the secrets-role password being set | **KEEP** | Port verbatim. Reword the fail_msg "desktop role" wording if desired; the `!= "changeme"` is the known hook false-positive (A4) |
| `rpm_key` NICE GPG import | Imports the signing key before RPM install | **KEEP** | Use the `51c5f1f` literal URL `https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY` — guard against PII-scrubber re-mangling (Pitfall 9) |
| `get_url` tarball (checksum-gated + no-checksum fallback, two tasks) | Downloads `nice-dcv-{ver}-{build}-amzn2023-x86_64.tgz` | **KEEP** | Keep the dual-task `when dcv_tarball_sha256` pattern; pin build via defaults; fill sha256 after first bake |
| extract dir + `unarchive --strip-components=1` | Unpacks the tarball folder | **KEEP** | Verbatim |
| `find` the 3 RPMs (`nice-dcv-server-*`, `nice-xdcv-*`, `nice-dcv-web-viewer-*`) | Glob the extracted RPMs | **KEEP** | Verbatim — the glob handles the 688≠20103 build skew correctly |
| `dnf` install the 3 RPMs (`disable_gpg_check: false`) | Local-RPM install, signature-verified | **KEEP** | Verbatim |
| `template dcv.conf` (`[security] authentication="system"` + `[connectivity] web-port`) | Minimal config | **CHANGE** | **Expand** the template — add `enable-quic-frontend=true`, keep web-port, add nothing for cert (no key exists). See "Exact dcv.conf" |
| `template dcv-virtual-session.service` (oneshot `dcv create-session --type virtual --owner ec2-user`) | The only auto-virtual mechanism | **KEEP** | Verbatim (this is the correct + only mechanism — Pattern 3) |
| `enable dcvserver` + `enable dcv-virtual-session` (daemon_reload) | Boot enablement | **KEEP** | Verbatim |
| cleanup `/tmp/nice-dcv.tgz` + `/tmp/dcv-extract` | Tidy | **KEEP** | Verbatim |
| handlers `reload systemd` | daemon-reload handler | **KEEP** | Verbatim (use `ansible.builtin.systemd` FQCN like the xrdp handler) |
| defaults (`dcv_version`/`dcv_build`/`dcv_web_port`/`dcv_tarball_sha256`/`dev_user`/`dev_home`) | Pins | **CHANGE** | Split `dcv_build` → `dcv_build_server: "20103"` + `dcv_build_xdcv: "688"` per STACK.md (the prior single `dcv_build` is wrong for xdcv). Add `dcv_runtime_deps: [policycoreutils-python-utils]` |
| — (ABSENT in prior role) | FIPS-safe cert | **ADD** | Generate `/etc/dcv/dcv.{pem,key}` (DCV-05) — see FIPS-Cert Decision |
| — (ABSENT) | SELinux fcontext + relabel | **ADD** | `semanage fcontext` + `restorecon` over DCV paths (DCV-05) |
| — (ABSENT) | colord polkit `.rules` | **ADD** | Reuse xrdp `files/45-allow-colord.rules` (GNOME color-manager hang) |
| — (ABSENT) | `/etc/pam.d/dcv` delegate | **ADD (recommended)** | Delegate to `password-auth` so CIS faillock/pwquality apply (Pattern 5) |
| — (ABSENT) | bake assert (RDP-13 grade) | **ADD** | Stat binary/conf/cert/units + assert (DCV-04) — Pattern 6 |
| — (ABSENT) | `dcv_runtime_deps` dnf (semanage) | **ADD** | `policycoreutils-python-utils` from AL2023 core |

## Exact `dcv.conf` for v4.0 (DCV-02) — every key verified against the AWS config-param reference

```ini
# /etc/dcv/dcv.conf  (templated by the dcv role; mode 0644)
# All keys + defaults verified against
# https://docs.aws.amazon.com/dcv/latest/adminguide/config-param-ref.html (this session).

[security]
# authentication default IS already 'system' (PAM via /etc/pam.d/dcv) — set explicitly anyway
# so a bake-assert/grep-gate can prove it is never 'none' (Pitfall 11 / security gate).
authentication="system"
# NOTE: there is NO certificate / certificate-key key here. DCV reads /etc/dcv/dcv.pem +
# /etc/dcv/dcv.key by HARDCODED path+name. The FIPS cert is delivered as files, not config.
# pam-service-name defaults to 'dcv' → /etc/pam.d/dcv (we ship that file, Pattern 5).

[connectivity]
web-port={{ dcv_web_port }}                 # default 8443 (TCP, web/WebSocket client)
enable-quic-frontend=true                    # QUIC ON — v4.0 direct-connect (DCV-02). Default
#                                              on Linux is already true (since 2020.2); set
#                                              explicit so it cannot silently flip.
# quic-port defaults to 8443 (UDP). web-port (TCP) and quic-port (UDP) share 8443 by default.
# UDP :8443 ingress is opened in Phase 14 (Terraform SG), NOT in this role.

[session-management]
# DO NOT set create-session here for a VIRTUAL session — create-session creates a CONSOLE
# session only ("Create a console session at server startup"; "Amazon DCV doesn't support
# automatic virtual sessions"). The virtual session is created by the oneshot unit instead.
```

**Key facts driving the above (all [VERIFIED: AWS config-param-ref this session]):**
- `connectivity/enable-quic-frontend` — type `true|false`, **default Linux: true**, reload `server`. → v4.0 keeps it `true`. (This is the OPPOSITE of `.planning/research/PITFALLS.md` Pitfall 4 / SUMMARY, which prescribe `false` — those reflect the now-superseded SSM-tunnel posture. REQUIREMENTS.md line 7 makes direct-connect + QUIC-on authoritative. See Pitfall note below.)
- `connectivity/web-port` — type int, **default 8443** (TCP). `connectivity/quic-port` — type int, **default 8443** (UDP). They are separate ports that both default to 8443.
- `security/authentication` — type string, **default `system`**; `none` = passwordless. Keep `system`; grep-gate against `none`.
- `security/pam-service-name` — default `dcv` → `/etc/pam.d/dcv`. Used only with `authentication=system`.
- `session-management/create-session` — **"Create a console session at server startup"** — console only; default false.
- `session-management/automatic-console-session/owner` — owner of the **console** session — console only.
- **NO `certificate`/`certificate-key` key exists in `[security]`** — confirmed by reading the full security parameter table; cert is path-based (`/etc/dcv/dcv.pem`+`dcv.key`).

### The auto-VIRTUAL-session mechanism — RESOLVED

**There is exactly one correct mechanism: the oneshot systemd unit.** AWS docs state plainly: *"Amazon DCV doesn't support automatic virtual sessions"* [CITED: adminguide managing-sessions-start]. The `[session-management] create-session=true` + `[session-management/automatic-console-session] owner=…` config path creates a **console** session (attaches to seat0/Xorg — which we don't have, since virtual sessions need no system X). Therefore:
- **Use the prior role's oneshot unit verbatim** (`dcv-virtual-session.service`, `Type=oneshot`, `RemainAfterExit=true`, `After=/Requires=dcvserver.service`, `ExecStart=/usr/bin/dcv create-session --owner ec2-user --type virtual ec2-user-session`, `ExecStop=/usr/bin/dcv close-session ec2-user-session`).
- This is also the **better bake-assert target** (`systemctl is-enabled dcv-virtual-session`) and the more observable mechanism.
- Do NOT set `create-session=true` in dcv.conf — it would spawn a useless console session alongside.

## FIPS-Safe Cert Decision (DCV-05) — GENERATE OUR OWN, do not rely on DCV's auto-cert

**Decision: generate a FIPS-clean self-signed cert in the role; do NOT rely on DCV's auto-generated cert.**

Rationale:
- DCV auto-generates `/etc/dcv/dcv.pem` + `dcv.key` at first start [CITED: adminguide manage-cert]. Its algorithm/key-size/SAN are **not guaranteed FIPS-acceptable** — under the kernel FIPS provider (`hardening` runs `fips-mode-setup --enable`) a CN-only or SHA-1 cert fails the TLS handshake on `:8443` and the web client cannot load (Pitfall 7; this exact class of failure was the xrdp HIGH finding in 11-VERIFICATION.md).
- The v3.2 xrdp role already proved the FIPS-clean recipe on this host. Reuse it verbatim.

**The critical path constraint (corrects the objective's framing):** DCV does **not** take a cert path from dcv.conf. It reads **hardcoded** `/etc/dcv/dcv.pem` (cert) and `/etc/dcv/dcv.key` (key) [CITED: adminguide manage-cert — *"you must name your certificate `dcv.pem` and you must name the key `dcv.key`"*, in `/etc/dcv/`, **owned by the `dcv` user, chmod 600**]. So the role generates the cert directly to those names + path and chowns to `dcv`:`dcv` 0600. DCV hot-reloads a replaced cert (2022.0+), but at bake the cert is in place before first start anyway.

**Cert task (port the xrdp cert-gen recipe, change paths/owner):**
```yaml
- name: Generate FIPS-safe self-signed TLS cert for DCV (DCV-05)
  ansible.builtin.command:
    cmd: >
      openssl req -x509 -nodes -newkey rsa:2048 -sha256
      -keyout /etc/dcv/dcv.key
      -out /etc/dcv/dcv.pem
      -days 3650 -subj '/CN=devbox'
      -addext "subjectAltName=DNS:devbox"
  args:
    creates: /etc/dcv/dcv.pem
  # RSA-2048 is FIPS-acceptable; -sha256 forces a FIPS-approved digest; the SAN is required —
  # a FIPS-strict TLS handshake rejects CN-only certs (xrdp 11-VERIFICATION HIGH finding).

- name: Set DCV TLS cert/key ownership + perms (DCV-05) — dcv user, 0600 (AWS-mandated)
  ansible.builtin.file:
    path: "{{ item.path }}"
    owner: dcv          # the nice-dcv-server RPM auto-creates the 'dcv' system user
    group: dcv
    mode: "{{ item.mode }}"
  loop:
    - { path: /etc/dcv/dcv.pem, mode: "0600" }   # AWS requires 600 (NOT 0644 like xrdp's cert)
    - { path: /etc/dcv/dcv.key, mode: "0600" }
```
> Ordering: this task must run AFTER the RPM install (the `dcv` user + `/etc/dcv/` exist only post-install) and AFTER any DCV first-start that might auto-generate a competing cert — generate with `creates:` so a re-bake is idempotent. Bake-assert the SAN (Pattern 6).

## SELinux Relabel Approach (DCV-05) — relabel ≠ policy; AVC proof is live (Phase 15)

DCV ships **no** SELinux policy module and the AWS adminguide is silent on SELinux. `hardening` (last role) flips SELinux to **enforcing** and reboots into it — AVCs only appear at the first confined session-create, which is live-only. Lower risk than xrdp (DCV is a vendor RPM landing in distro paths `/usr/bin/dcv*`, `/usr/lib*`, `/etc/dcv`, with sane default labels — vs xrdp's source-built `/usr/local/sbin`), but the runtime exec-into-user-session + `/var/run/dcv` socket transitions are the real risk surface.

**Approach (port the xrdp two-step: fcontext THEN restorecon):**
1. Install `policycoreutils-python-utils` (provides `semanage`) from AL2023 core (`dcv_runtime_deps`).
2. **restorecon over DCV's installed paths** after RPM install + cert + config (cheap insurance, same as xrdp's `restorecon -RvF`):
   ```yaml
   - name: SELinux relabel DCV install paths + config (DCV-05)
     ansible.builtin.command:
       cmd: restorecon -RvF /usr/bin/dcv* /usr/lib64/dcv* /etc/dcv /var/lib/dcv /var/run/dcv
     changed_when: false
     failed_when: false   # tolerate paths absent on a given build (e.g. /var/run/dcv pre-first-start)
   ```
3. **fcontext only if a path lacks a mapping** — unlike xrdp's `/usr/local/sbin` (which had NO mapping and needed `xrdp_exec_t`), DCV's `/usr/bin`/`/usr/lib64` already get `bin_t`/`lib_t` and the RPM-shipped `dcvserver.service` runs under a reasonable domain. Recommend: ship the `restorecon` (above) at bake; **do NOT** invent a custom fcontext type speculatively. If the Phase 15 live UAT shows AVC denials, generate a scoped module: `ausearch -m AVC -ts boot | audit2allow -M dcv_local && semodule -i dcv_local.pp`, vendor `dcv_local.pp` into `files/`. **Never `setenforce 0`.**
4. **AVC-clean proof is the live UAT (Phase 15)** — `ausearch -m AVC,USER_AVC -ts boot` after first connect shows zero DCV/Xorg denials. Bake is permissive (AL2023 default until hardening reboot), so the confined boot cannot be exercised at bake. Document this residual; it is NOT a Phase-13 gate.

## GNOME-in-Virtual-Session Wiring (DCV-03)

The `desktop` role already installs everything the session renders: `@Desktop` + `gnome-shell` + **`gnome-session`** (installed by name — the proven xrdp lesson) + `mesa-dri-drivers` (software GL) + `dejavu-*` fonts. The `dcv` role consumes this; gate `when: layers.dcv and layers.desktop` so `desktop` runs first.

**How the virtual session picks GNOME** [CITED: adminguide — virtual session uses `Xdcv`, no system X / no XDummy needed for non-GPU virtual]:
- The DCV virtual-session default init script starts the system **default** desktop environment; on AL2023 that is GNOME (`@Desktop`). For software-render non-GPU, Mesa/llvmpipe is automatic (the benign `dcv-gl disabled` log is expected, Pitfall 5).
- DCV respects `~/.xsession` / `~/.Xclients` for explicit desktop selection, and `dcv create-session --init <script>` can point at a custom GNOME launcher. **Recommend: rely on the AL2023 default (GNOME) first** — the prior role did, and it rendered live. Only add an explicit `--init` GNOME launcher or a `~/.xsession` for `ec2-user` if the Phase 15 UAT shows a wrong/empty desktop (Open Question 2).
- **No `WaylandEnable=false` needed** — that is a gdm/console-session concern. A virtual session uses `Xdcv` (X11), never Wayland/gdm/seat0 (this is the whole point of choosing virtual over console). Do NOT add gdm autologin.
- **colord polkit:** GNOME-over-remote hits the color-manager polkit prompt and hangs. Reuse the xrdp `files/45-allow-colord.rules` (the `.rules` JS form — `.pkla` is ignored on AL2023 polkit 121+). Copy to `/etc/polkit-1/rules.d/45-allow-colord.rules`.

## Bake-Assert List (DCV-04) — mirror the xrdp RDP-13 discipline

Stat each + a single `assert that: [...].stat.exists`, with a loud `fail_msg`. Runs INSIDE the role (before hardening). Assert the things whose absence yields a green-but-DCV-dead AMI:

| Assert | Path / check | Why |
|--------|-------------|-----|
| dcvserver binary | `/usr/bin/dcvserver` (stat) | the daemon exists post-install |
| dcv CLI | `/usr/bin/dcv` (stat) | the oneshot unit's `ExecStart` needs it |
| Xdcv binary | `/usr/bin/Xdcv` (stat) | confirms `nice-xdcv` actually installed (virtual session needs it) |
| dcv.conf | `/etc/dcv/dcv.conf` (stat) | config templated |
| dcv.conf keys | `grep authentication=.system. ` + `web-port=8443` + `enable-quic-frontend=true` (slurp/assert) | DCV-02 keys present + correct (and `authentication` NOT `none` — security gate) |
| TLS cert | `/etc/dcv/dcv.pem` + `/etc/dcv/dcv.key` (stat) | FIPS cert delivered |
| cert SAN | `openssl x509 -in /etc/dcv/dcv.pem -noout -text` contains `Subject Alternative Name` + `DNS:devbox` | FIPS-strict handshake needs SAN (DCV-05; xrdp RDP-13 cert-SAN proof) |
| cert owner/mode | `/etc/dcv/dcv.pem` owned `dcv`, mode 0600 | AWS-mandated; wrong perms → DCV ignores it |
| virtual-session unit | `/etc/systemd/system/dcv-virtual-session.service` (stat) | the only auto-virtual mechanism present |
| services enabled | `systemctl is-enabled dcvserver dcv-virtual-session` rc==0 | DCV-04 boot enablement |
| colord rules | `/etc/polkit-1/rules.d/45-allow-colord.rules` (stat) | GNOME hang prevention |
| pam file (if shipped) | `/etc/pam.d/dcv` (stat) | auth path (Pattern 5) |

> Binary paths (`/usr/bin/dcvserver`, `/usr/bin/dcv`, `/usr/bin/Xdcv`) are [ASSUMED] from the vendor RPM convention (A2) — the planner should confirm the exact paths at first bake (`rpm -ql nice-dcv-server | grep bin`) and adjust the stats; the assert design is what matters. The prior role's oneshot unit already references `/usr/bin/dcv` so that path is corroborated.

## Airgap Install Specifics (DCV-01)

- **Source:** `get_url` from `https://d1uj6qtbmh3dt5.cloudfront.net/2025.0/Servers/nice-dcv-2025.0-20103-amzn2023-x86_64.tgz` — bake-time HTTPS egress, identical in kind to the existing ffmpeg (`johnvansickle.com`), mise, helm, JetBrains downloads. CloudFront is just one more `get_url` host. [VERIFIED: prior role `51c5f1f` downloaded it successfully; revert was licensing, not install.]
- **GPG:** `rpm_key` from `https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY` (same host) BEFORE the RPM install; keep `disable_gpg_check: false` so the local-RPM install verifies the signature. **Watch the PII-scrubber:** it mangled this URL once (`67faeb3` → `https:<MRCLEAN:ENTROPY:001>`, fixed in `78e169b`). Port from `51c5f1f` and double-check the literal URL survives into the committed file (Pitfall 9 / A1).
- **Pin:** exact version + build in `defaults` — `dcv_version: "2025.0"`, `dcv_build_server: "20103"`, `dcv_build_xdcv: "688"`. NEVER the floating `…latest` URL (breaks REP-01 reproducibility; same discipline as the Packer SSM `:NN` pin).
- **sha256:** `dcv_tarball_sha256: ""` on first bake (deferred-pin, CLAUDE.md §9 / A3). After first bake: `sha256sum nice-dcv-2025.0-20103-amzn2023-x86_64.tgz`, set the value, commit. The dual-task `when dcv_tarball_sha256 | length > 0` pattern from the prior role enforces the checksum once filled.
- **No S3-for-install, no private mirror, no `--nogpgcheck`** (CLAUDE.md §8 / Pitfall 9).

## Architecture Patterns

### System Architecture Diagram (bake-time scope of Phase 13)

```
ansible/playbook.yml roles[]:
  base → … → secrets → vscode → desktop → [ dcv ] → hardening (LAST — invariant)
                          │         │         │
   secrets: ec2-user PAM  │         │         │ dcv role (THIS PHASE):
   pw → SSM → chpasswd ───┘         │         │   1. assert desktop_vnc_password set
                                    │         │   2. rpm_key NICE-GPG-KEY (CloudFront)
   desktop: @Desktop + gnome-session│         │   3. get_url tarball (pinned + sha256) → extract
   + mesa-dri-drivers + fonts ──────┘         │   4. dnf install 3 RPMs (gpg-verified)
   (the GNOME the virtual session renders)    │   5. template /etc/dcv/dcv.conf
                                              │      (auth=system, web-port=8443, QUIC=on)
                                              │   6. openssl → /etc/dcv/dcv.{pem,key}
                                              │      (RSA-2048/sha256/SAN, dcv:dcv 0600)
                                              │   7. copy 45-allow-colord.rules + /etc/pam.d/dcv
                                              │   8. template dcv-virtual-session.service (oneshot)
                                              │   9. enable dcvserver + dcv-virtual-session
                                              │  10. semanage fcontext (if needed) + restorecon
                                              │  11. BAKE ASSERT (binary/conf/cert/units) ← fails loud
                                              ▼
                            hardening: SELinux enforcing + FIPS + reboot
                                              ▼
                       (RUNTIME — Phase 14/15, NOT this phase:)
                       dcvserver listens :8443 TCP (web) + :8443 UDP (QUIC)
                       → boot: oneshot runs `dcv create-session --type virtual --owner ec2-user`
                       → Xdcv (software render) renders GNOME → operator connects (direct, allowlisted CIDR)
                       → dcvserver periodically GETs dcv-license.<region> (needs Phase-14 endpoint+IAM)
```

### Recommended Project Structure
```
ansible/roles/dcv/
├── defaults/main.yml          # dcv_version, dcv_build_server(20103)/dcv_build_xdcv(688),
│                              #   dcv_web_port(8443), dcv_tarball_sha256(""), dcv_runtime_deps,
│                              #   dev_user/dev_home
├── tasks/main.yml             # assert PAM pw → rpm_key → get_url+extract → dnf 3 RPMs →
│                              #   dcv_runtime_deps dnf → template dcv.conf → openssl cert+chown →
│                              #   colord .rules → /etc/pam.d/dcv → template oneshot unit →
│                              #   enable dcvserver+session → fcontext+restorecon → BAKE ASSERT → cleanup
├── handlers/main.yml          # reload systemd (ansible.builtin.systemd daemon_reload)
├── files/
│   ├── 45-allow-colord.rules  # copy from ansible/roles/xrdp/files/45-allow-colord.rules
│   └── dcv.pam                # /etc/pam.d/dcv delegating to password-auth (Pattern 5)
└── templates/
    ├── dcv.conf.j2            # [security]/[connectivity] (Exact dcv.conf section)
    └── dcv-virtual-session.service.j2   # oneshot create-session --type virtual (KEEP from prior)
```

### Pattern 1: Airgap download with deferred sha256 (KEEP from prior role)
**What:** `get_url` the pinned tarball from CloudFront with an optional `checksum:` gated on `dcv_tarball_sha256`, after `rpm_key` imports the NICE GPG key. **When:** the project airgap idiom (ffmpeg/mise precedent). **Example:** the prior role's dual `get_url` tasks (checksum / no-checksum) — port verbatim.

### Pattern 2: PAM credential reuse (KEEP — no new secret)
**What:** `authentication=system` → PAM → the ec2-user password the `secrets` role already generates/publishes/applies. **When:** the repo's locked credential model. **Example:** port the prior role's `desktop_vnc_password` assert verbatim (`no_log: true`).

### Pattern 3: Headless virtual session via oneshot systemd unit (KEEP — the ONLY auto-virtual mechanism)
**What:** `Type=oneshot, RemainAfterExit=true, After=/Requires=dcvserver.service, ExecStart=/usr/bin/dcv create-session --owner ec2-user --type virtual ec2-user-session`. **When:** always for v4.0 — DCV has no auto-virtual config (AWS: "doesn't support automatic virtual sessions"). **Anti-pattern:** also setting `create-session=true` in dcv.conf → spawns a redundant console session.

### Pattern 4: GNOME via the default desktop (KEEP simple; `--init` only if UAT demands)
**What:** virtual session starts the AL2023 default desktop (GNOME) via DCV's default init; software-rendered (Mesa/llvmpipe) on non-GPU. **When:** default first. **Escalation:** explicit `~/.xsession`/`--init` GNOME launcher only if Phase 15 shows a wrong desktop.

### Pattern 5: `/etc/pam.d/dcv` delegating to `password-auth` (ADD — recommended)
**What:** ship `/etc/pam.d/dcv` (the default `pam-service-name`) delegating auth/account/session/password to `password-auth`, so the CIS-hardened faillock/pwquality stack applies and ec2-user can authenticate. **When:** `authentication=system`. **Example:** model on the xrdp `files/xrdp-sesman.pam` (`include password-auth` lines; include `pam_loginuid.so`/`pam_lastlog.so` as xrdp does). The RPM ships a default `/etc/pam.d/dcv`; overwriting it with an explicit, asserted file is the safer, deterministic choice (matches the xrdp precedent).

### Pattern 6: RDP-13-grade bake assert (ADD)
**What:** stat + assert every load-bearing artifact (binary, conf+keys, cert+SAN, units, enablement). **When:** DCV-04. **Example:** the xrdp `tasks/main.yml` RDP-13 block (lines ~486-638) is the template — same stat→assert→loud-fail_msg structure, retargeted to DCV paths.

### Anti-Patterns to Avoid
- **`create-session=true` for a virtual session** — creates a console session, not virtual. Use the oneshot unit.
- **Pointing dcv.conf at a cert path** — no such key; DCV reads `/etc/dcv/dcv.{pem,key}` by name. Wrong perms/owner → DCV ignores the cert and may fall back to a non-FIPS auto-cert.
- **`enable-quic-frontend=false`** — WRONG for v4.0 (that was the SSM-era posture). Direct-connect keeps QUIC on (DCV-02).
- **Installing system Xorg / XDummy / nice-dcv-gl** — virtual sessions need none; adding system Xorg re-creates the CIS-2.2.1 dependency Phase 14 wants to retire.
- **`--nogpgcheck` / floating `latest` URL** — supply-chain hole / non-reproducible (CLAUDE.md §8).
- **`setenforce 0`** — defeats hardening; use restorecon + scoped audit2allow if AVCs appear.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| FIPS-clean self-signed cert | Custom cert logic / DCV auto-cert | The xrdp `openssl req -x509 -newkey rsa:2048 -sha256 -addext SAN` recipe → `/etc/dcv/dcv.{pem,key}` | Proven FIPS-clean on this exact host; SAN required or FIPS rejects |
| SELinux labeling | Hand-written .te policy upfront | `restorecon` over RPM paths now; `audit2allow` scoped module only if Phase 15 shows AVCs | Don't invent policy speculatively; relabel is cheap, custom module is last-resort |
| colord polkit allow | New polkit logic | Copy xrdp `files/45-allow-colord.rules` | Already proven; `.pkla` is ignored on AL2023 polkit 121+ |
| Virtual session auto-create | dcv.conf hacking | The prior role's oneshot unit | DCV has no auto-virtual config — the unit is the only way |
| PAM stack | Custom auth module | `/etc/pam.d/dcv` → `include password-auth` | Inherits CIS faillock/pwquality; xrdp precedent |
| GPG-verified install | Manual key handling | `ansible.builtin.rpm_key` + `disable_gpg_check: false` | The role's existing idiom |

**Key insight:** ~80% of this role already exists and was proven to bake. The new 20% (cert, SELinux, asserts, colord, PAM) is *also* already written — in the shipped `xrdp` role. This phase is overwhelmingly porting two proven bodies of code, not authoring new logic.

## Common Pitfalls

### Pitfall A: dcv.conf has NO cert key — cert is path-based
**What goes wrong:** Planner writes `certificate=/etc/dcv/dcv.pem` into dcv.conf (as the objective implies); DCV ignores it (no such key), the FIPS cert may not be picked up, DCV falls back to its auto-cert which FIPS rejects → web client won't load. **Avoid:** deliver the cert as `/etc/dcv/dcv.pem`+`dcv.key` (exact names), owner `dcv`:`dcv`, mode 0600. **Warning sign:** `openssl s_client -connect localhost:8443` shows a different cert than the one generated.

### Pitfall B: `create-session=true` ≠ virtual session
**What goes wrong:** Using the dcv.conf auto-session for a virtual desktop. It creates a CONSOLE session (needs seat0/Xorg we don't have) → blank/no usable session. **Avoid:** oneshot unit only. **Warning sign:** `dcv list-sessions` shows a `console` session, or none usable.

### Pitfall C: QUIC posture inversion vs. milestone research
**What goes wrong:** Following `.planning/research/PITFALLS.md`/`SUMMARY.md` (which say `enable-quic-frontend=false`) instead of REQUIREMENTS.md (QUIC ON). Those research files predate the direct-connect pivot and assume SSM tunneling (TCP-only). **Authoritative:** REQUIREMENTS.md line 7 + DCV-02 — **QUIC ON**. The SG opens UDP `:8443` in Phase 14. **Warning sign:** any task setting `enable-quic-frontend=false`.

### Pitfall D: PII-scrubber mangles the GPG URL
**What goes wrong:** The executor's prompt redaction tooling can replace `https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY` with a placeholder (it did in `67faeb3`). A mangled `rpm_key` URL → GPG import fails → RPM install fails (or someone reaches for `--nogpgcheck`). **Avoid:** port from `51c5f1f`; verify the literal URL in the committed file. **Warning sign:** `<MRCLEAN…>` or any non-URL in `rpm_key`.

### Pitfall E: xdcv build number ≠ server build number
**What goes wrong:** Reusing `20103` for `nice-xdcv` (it is `688`) in a hardcoded install path. **Avoid:** keep the prior role's `find … patterns: "nice-xdcv-*.rpm"` glob; split `dcv_build_server`/`dcv_build_xdcv` in defaults. **Warning sign:** `find` returns empty for the xdcv RPM.

### Pitfall F: SELinux AVC is live-only; relabel ≠ policy
**What goes wrong:** Assuming a green permissive bake proves SELinux is fine. AVCs only surface under enforcing after the hardening reboot (Phase 15). **Avoid:** restorecon at bake (insurance); treat AVC-clean as a Phase-15 residual, not a Phase-13 gate. **Warning sign:** none at bake — that's the trap.

### Pitfall G: forgetting `semanage` is not installed
**What goes wrong:** A `semanage fcontext` task fails because `policycoreutils-python-utils` isn't present (it is NOT a DCV dep). **Avoid:** add it to `dcv_runtime_deps` dnf (AL2023 core), exactly as the xrdp role does. **Warning sign:** "semanage: command not found".

## Code Examples

### Oneshot virtual-session unit (port verbatim from prior role)
```ini
# Source: git show 51c5f1f:ansible/roles/dcv/templates/dcv-virtual-session.service.j2
[Unit]
Description=Amazon DCV virtual session for {{ dev_user }}
After=dcvserver.service
Requires=dcvserver.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/bin/dcv create-session --owner {{ dev_user }} --type virtual {{ dev_user }}-session
ExecStop=/usr/bin/dcv close-session {{ dev_user }}-session

[Install]
WantedBy=multi-user.target
```

### colord polkit rules (copy from xrdp)
```javascript
// Source: ansible/roles/xrdp/files/45-allow-colord.rules (this repo)
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.") === 0) {
        return polkit.Result.YES;
    }
});
```

### `/etc/pam.d/dcv` (model on xrdp-sesman.pam)
```
# Source pattern: ansible/roles/xrdp/files/xrdp-sesman.pam
#%PAM-1.0
auth        include     password-auth
account     include     password-auth
session     required    pam_loginuid.so
session     optional    pam_lastlog.so quiet
session     include     password-auth
password    include     password-auth
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| QUIC OFF (SSM-tunnel posture) | QUIC ON (direct-connect) | v4.0 REQUIREMENTS pivot (2026-06) | dcv.conf `enable-quic-frontend=true`; UDP `:8443` SG ingress (Phase 14) |
| DCV auto-cert | Role-generated FIPS-clean cert at `/etc/dcv/dcv.{pem,key}` | this phase (DCV-05) | FIPS handshake survives |
| Prior role (no cert/SELinux/assert) | + cert + fcontext/restorecon + RDP-13-grade assert | this phase | Survives hardened baseline; bake fails loud if broken |
| `NICE DCV` branding / 2024.0 | `Amazon DCV` 2025.0 (2025-10-22) | 2024.0 rename / 2025.0 release | Package names unchanged (`nice-dcv-*`); `amzn2023` tarball |

**Deprecated/outdated:**
- `.planning/research/PITFALLS.md` Pitfall 4 + `SUMMARY.md` `enable-quic-frontend=false` — superseded by the direct-connect QUIC-on decision. Use REQUIREMENTS.md.
- The objective's "dcv.conf certificate paths" framing — no such dcv.conf key; cert is path/name-fixed.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | NICE-GPG-KEY URL is `https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY` | Airgap Install | LOW — verified in `51c5f1f` + AWS adminguide; risk is the PII-scrubber re-mangling it (Pitfall D), which the planner must guard against |
| A2 | DCV binary paths are `/usr/bin/dcvserver`, `/usr/bin/dcv`, `/usr/bin/Xdcv` | Bake-Assert, SELinux | LOW-MED — `/usr/bin/dcv` corroborated by the prior role's unit; confirm exact paths at first bake (`rpm -ql nice-dcv-server`) and adjust the stats |
| A3 | `dcv_tarball_sha256` empty on first bake, filled after | Install, CLAUDE.md | LOW — deferred-pin per CLAUDE.md §9; GPG signature is the integrity gate until filled |
| A4 | `desktop_vnc_password != "changeme"` assert is a tolerated `no-changeme` hook false-positive | Project Constraints | LOW — the surviving secrets-role asserts carry it; planner may rephrase to be safe |
| A5 | The AL2023 default desktop (GNOME) renders in the virtual session without an explicit `--init` | GNOME Wiring | MED — the prior role relied on this and it rendered live this session per research; Phase 15 UAT confirms; fallback is an explicit `--init`/`~/.xsession` |
| A6 | restorecon over RPM paths is sufficient (no custom fcontext type needed for DCV, unlike xrdp) | SELinux | MED — DCV's distro-path RPM gets sane default labels vs xrdp's `/usr/local`; AVC-clean is only provable at Phase 15; fallback is a scoped audit2allow module |

**Note:** these `[ASSUMED]` items are the discuss-phase / planner confirmation surface. None block the bake; A2/A5/A6 resolve at first bake / Phase 15.

## Open Questions

1. **Exact DCV binary install paths**
   - Known: the oneshot unit uses `/usr/bin/dcv`; RPMs are vendor `amzn2023`.
   - Unclear: precise paths of `dcvserver` + `Xdcv` for the bake-assert stats.
   - Recommendation: at first bake run `rpm -ql nice-dcv-server nice-xdcv | grep -E '/bin/|/sbin/'` and set the assert paths from that; the assert design is path-agnostic.

2. **Does the AL2023 default give GNOME in the virtual session, or is `--init` needed?**
   - Known: AWS docs say the virtual session starts the default desktop; AL2023 default = GNOME; the prior role rendered GNOME live.
   - Unclear: whether a dconf/`~/.xsession` nudge is needed under the hardened image.
   - Recommendation: ship the simple default; add an explicit GNOME `--init` only if Phase 15 shows a wrong/empty desktop. Cheap to add later.

3. **secrets-bootstrap restart loop references `xrdp.service` (Phase 14 scope)**
   - Known: `devbox-secrets-bootstrap.sh.j2:67` restarts `code-server.service xrdp.service xrdp-sesman.service`; the service unit `Before=…xrdp…`. DCV password rotation needs `dcvserver`/`dcv-virtual-session` restarted to re-pick the PAM password.
   - Unclear: only the *timing* — the ROADMAP assigns this edit to Phase 14's removal sweep, but DCV is added in Phase 13 (alongside xrdp, not replacing it yet).
   - Recommendation: **leave for Phase 14** (as ROADMAP dictates) — it tolerates absent units (`systemctl list-unit-files` guard), so an un-edited loop won't break a Phase-13 bake; the dcv units simply aren't restarted on rotation until Phase 14. Flag for the planner so it isn't lost.

## Environment Availability

> Phase 13 is bake-time only (Packer/Ansible on the build host). Runtime AWS deps (S3 license, SG) are Phase 14/15. Bake-host needs:

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| HTTPS egress to `d1uj6qtbmh3dt5.cloudfront.net` | DCV tarball + GPG key (DCV-01) | ✓ (assumed — same as existing ffmpeg/mise downloads) | — | Vendor the tarball + key as build inputs (sha256 still enforced) |
| AL2023 core dnf repo | `policycoreutils-python-utils` (semanage) | ✓ (used by xrdp role) | AL2023 | none needed |
| `desktop` role baked first | GNOME for the session | ✓ (gate `layers.desktop`) | — | bake fails the PAM-password assert if secrets/desktop didn't run |

**Missing dependencies with no fallback:** none for the bake. (Runtime licensing is Phase 14 — bake succeeds under the 15-day grace.)

## Validation Architecture

> `workflow.nyquist_validation` is `false` in `.planning/config.json` — section intentionally omitted per the research-agent rule. Validation for this role is the **bake-time Ansible assert** (Pattern 6 / Bake-Assert List, DCV-04) plus the **Phase 15 live UAT** (AVC-clean, FIPS handshake, GNOME render, license — all out of Phase-13 scope). There is no unit-test framework in this IaC repo; the assert-in-the-bake is the established verification idiom (xrdp RDP-13 precedent).

## Security Domain

> `security_enforcement` is not set to `false` in config — section included. The whole point of DCV-05 is surviving the CIS-hardened baseline.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | `authentication=system` → PAM `/etc/pam.d/dcv` → `password-auth` (CIS faillock/pwquality); reuse secrets-role ec2-user password (no new secret) |
| V3 Session Management | yes (transport) | TLS on `:8443`; FIPS-clean cert; session owner `ec2-user`; stock `default.perm` (owner full access) |
| V5 Input Validation | partial | dcv.conf is templated (no user input); grep-gate against `authentication=none` |
| V6 Cryptography | yes | RSA-2048/sha256/SAN self-signed cert (FIPS-acceptable); never hand-roll crypto; openssl only; TLS never disabled |
| V10 Malicious Code / Supply Chain | yes | NICE-GPG-KEY signature verification + pinned sha256; no `--nogpgcheck`; no floating URL |

### Known Threat Patterns for DCV on hardened AL2023

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| `authentication=none` passwordless desktop | Elevation of Privilege | Keep `authentication=system`; bake-assert / grep-gate against `none` |
| Plaintext stream (TLS off) | Information Disclosure | TLS always on; FIPS-clean cert; never set no-tls |
| Unverified vendor RPM (supply chain) | Tampering | NICE-GPG-KEY + sha256; `disable_gpg_check: false` |
| Non-FIPS cert rejected → fallback weak path | Spoofing / DoS | RSA-2048/sha256/SAN cert at the fixed path; bake-assert SAN |
| SELinux AVC silently kills session (server "active") | DoS | restorecon at bake; audit2allow scoped module if Phase-15 AVCs; never `setenforce 0` |
| Over-broad cert/key perms | Information Disclosure | `dcv`:`dcv` 0600 (AWS-mandated) |

## Sources

### Primary (HIGH confidence)
- AWS DCV config-param reference — https://docs.aws.amazon.com/dcv/latest/adminguide/config-param-ref.html — exact keys/defaults/types for `connectivity` (web-port 8443, quic-port 8443, enable-quic-frontend default Linux=true), `security` (authentication default `system`, pam-service-name `dcv`, NO certificate key), `session-management` (create-session = console only)
- AWS DCV starting sessions — https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-start.html — "Amazon DCV doesn't support automatic virtual sessions"; `dcv create-session --type virtual --init` syntax; "Linux … don't get a default console session"
- AWS DCV manage-cert — https://docs.aws.amazon.com/dcv/latest/adminguide/manage-cert.html — cert MUST be `/etc/dcv/dcv.pem`+`dcv.key`, owner `dcv`, chmod 600, hot-reload 2022.0+
- AWS DCV Linux prereq — https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html — virtual sessions need NO system X server, NO XDummy; non-GPU = Mesa software GL; AL2023 default desktop = GNOME (`dnf groupinstall Desktop`)
- AWS DCV install Linux — https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html — AL2023 RPM names/builds, NICE-GPG-KEY import
- AWS what's-new — https://aws.amazon.com/about-aws/whats-new/2025/10/amazon-dvc-releases-version-2025-0/ — DCV 2025.0 released 2025-10-22 (current latest)
- Repo git history — `git show 51c5f1f:ansible/roles/dcv/` (the corrected prior role = port base), `67faeb3` (mangled GPG URL — do NOT use), `78e169b` (GPG URL fix), `d3bd9a0` (revert = licensing, not install)
- Repo — `ansible/roles/xrdp/{tasks/main.yml,defaults/main.yml,files/}` (FIPS cert + SAN assert + semanage fcontext + restorecon + colord .rules + PAM-delegate + RDP-13 bake-assert — all directly portable), `ansible/roles/desktop/tasks/main.yml` (GNOME the session renders), `ansible/playbook.yml` (wiring slot + hardening-last + post-hardening Xorg guard), `ansible/roles/hardening/defaults/main.yml` (CIS 2.2.1 override), `ansible/roles/secrets/templates/devbox-secrets-bootstrap.*` (restart loop — Phase 14)
- Repo — `.planning/REQUIREMENTS.md` (authoritative QUIC-on/direct-connect/virtual decisions), `.planning/ROADMAP.md` (Phase 13 success criteria), `.planning/phases/11-…/11-VERIFICATION.md` (the adversarial FIPS/SELinux/colord/PAM lessons proven on this host)

### Secondary (MEDIUM confidence)
- amazondcv.com download index — tarball filename + builds (server 20103, xdcv 688) — cross-checked via WebSearch against the CloudFront URL

### Tertiary (LOW confidence)
- WebSearch summaries of DCV version numbers — corroborated by the AWS what's-new page (promoted to verified)

## Metadata

**Confidence breakdown:**
- Standard stack / install: HIGH — exact RPMs/builds/URLs verified; prior role downloaded successfully; airgap idiom matches existing roles
- dcv.conf keys / session mechanism: HIGH — every key + the "no auto-virtual" + "no cert key" facts read directly from the AWS config-param reference + session guide this session
- FIPS cert / SELinux / bake assert: HIGH — copied verbatim from the shipped, adversarially-verified xrdp role; only paths change
- GNOME-in-virtual-session render / AVC-clean under enforcing: MEDIUM — proven live in prior research but the *hardened-image* re-proof is the Phase 15 UAT (A5/A6), not a Phase-13 gate

**Research date:** 2026-06-19
**Valid until:** 2026-07-19 (stable — DCV 2025.0 is current; prior role + xrdp recipes are committed and won't drift)
