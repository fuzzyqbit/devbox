# Requirements — Milestone v3.2 XRDP Remote Desktop

**Goal:** Replace the VNC/noVNC desktop stack with xrdp built from vendored, pinned source (airgap-safe), authenticating via PAM, so operators connect with a native RDP client and a full-length system password.

**Credential model:** the RDP login is the `ec2-user` PAM password the `secrets` role already generates per build, publishes to SSM (`/devbox/<user>/vnc-password`), and the boot bootstrap applies via `chpasswd`. No new secret; PAM is the auth boundary.

---

## v3.2 Requirements

### Build & Packaging (airgap-safe)

- [x] **RDP-01**: xrdp and xorgxrdp source tarballs are vendored and pinned by version + sha256 (matching the repo's pinning convention), so the bake requires no network fetch from EPEL or upstream.
- [x] **RDP-02**: The `xrdp` Ansible role installs the build toolchain + Xorg SDK from the AL2023 mirror, then builds and installs xrdp and xorgxrdp from the pinned source against the running Xorg ABI.
- [x] **RDP-03**: The build fails loudly (assert) at bake time if a required build dependency — especially `xorg-x11-server-devel` — is unavailable, rather than producing a half-installed image.

### Service & Configuration

- [ ] **RDP-04**: xrdp listens on `:3389` with TLS enabled (`security_layer`/`certificate`/`key_file`), reusing the existing self-signed cert pattern.
- [ ] **RDP-05**: `sesman.ini` is configured for the xorgxrdp (Xorg) backend — no Xvnc/VNC backend.
- [ ] **RDP-06**: `/etc/pam.d/xrdp-sesman` delegates to `password-auth` so RDP logins inherit the CIS-hardened PAM stack (pwquality, faillock), consistent with the rest of the image.
- [ ] **RDP-07**: An operator logs into the desktop session over RDP as `ec2-user` with the `./run secrets-show` password and reaches the installed desktop environment.
- [ ] **RDP-08**: xrdp + xrdp-sesman are enabled as systemd services and start on boot; the role inserts before `hardening` (hardening-stays-last invariant preserved).

### Network & Operator Surface

- [ ] **RDP-09**: The Terraform security group exposes `:3389` (gated on `var.allowed_web_cidrs`) and drops `:6080`; the SSM-first posture (no public `:22`) is unchanged.
- [ ] **RDP-10**: `./run devbox-port-forward` tunnels `:3389`; operator docs (CLAUDE.md) describe connecting with a native RDP client over SSM.

### Removal & Cleanup

- [ ] **RDP-11**: The VNC/noVNC stack is removed — vncserver/novnc systemd services, `SecurityTypes Plain`, `/etc/pam.d/vnc`, and the noVNC install — leaving no dead VNC config in the image.
- [ ] **RDP-12**: The noVNC username-injection workaround (`ansible/novnc-plain-username-fix.yml`, commit `29de35b`) is reverted/removed.

### Verification (first-class — not deferred)

- [ ] **RDP-13**: A bake-time assertion confirms the xrdp and xorgxrdp binaries/modules are present and the services are enabled.
- [ ] **RDP-14**: A documented runtime UAT confirms a real RDP client authenticates via PAM and renders the desktop on a live instance — recorded before the milestone closes.

---

## Out of Scope

- **Browser-based desktop access** — RDP is native-client only this milestone; no Apache Guacamole RDP→HTML5 gateway (deferred; revisit if browser access becomes a requirement).
- **GPU/3D acceleration, audio redirection, clipboard/drive redirection** — beyond a working authenticated desktop session.
- **Multi-user / multi-session** — single operator (`ec2-user`), consistent with the project model.
- **Migrating off the self-signed cert** — RDP TLS reuses the existing self-signed pattern; real CA-issued certs are out of scope.

---

## Traceability

Phase → requirement mapping (from `.planning/ROADMAP.md`, Phases 10-12). Every RDP-01…RDP-14 maps to exactly one phase; RDP-14 is the live-instance human-UAT gate that closes the milestone.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RDP-01 | Phase 10 — xrdp/xorgxrdp from-source build role | Complete |
| RDP-02 | Phase 10 — xrdp/xorgxrdp from-source build role | Complete |
| RDP-03 | Phase 10 — xrdp/xorgxrdp from-source build role | Complete |
| RDP-04 | Phase 11 — Service config, PAM, session + bake verification | Pending |
| RDP-05 | Phase 11 — Service config, PAM, session + bake verification | Pending |
| RDP-06 | Phase 11 — Service config, PAM, session + bake verification | Pending |
| RDP-07 | Phase 11 — Service config, PAM, session + bake verification | Pending |
| RDP-08 | Phase 11 — Service config, PAM, session + bake verification | Pending |
| RDP-13 | Phase 11 — Service config, PAM, session + bake verification | Pending |
| RDP-09 | Phase 12 — Network, operator surface + VNC/noVNC removal | Pending |
| RDP-10 | Phase 12 — Network, operator surface + VNC/noVNC removal | Pending |
| RDP-11 | Phase 12 — Network, operator surface + VNC/noVNC removal | Pending |
| RDP-12 | Phase 12 — Network, operator surface + VNC/noVNC removal | Pending |
| RDP-14 | Milestone-close gate (live-instance human UAT) | Pending |

**Coverage:** 14/14 requirements mapped — no orphans, no duplicates.
