# Roadmap: devbox

## Milestones

- ✅ **v1.0 — Security hardening + CI baseline** — Phases 1-4 (shipped 2026-05-14)
- ✅ **v2.0 — Run Script + GitLab CI Integration** — Phases 5-7 (shipped 2026-06-02)
- ✅ **v3.0 — Jupyter + mise** — Phases 8-9 (shipped 2026-06-02)
- 🚧 **v3.2 — XRDP Remote Desktop** — Phases 10-12 (active)

## Phases

<details>
<summary>✅ v1.0 — Security hardening + CI baseline (Phases 1-4) — SHIPPED 2026-05-14</summary>

Full detail: [milestones/v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [milestones/v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md)

</details>

<details>
<summary>✅ v2.0 — Run Script + GitLab CI Integration (Phases 5-7) — SHIPPED 2026-06-02</summary>

Replaced the Makefile with a single `./run` shell dispatcher that works locally and in CI,
wired the GitLab CI pipeline to call `./run`, and retired the Makefile entirely.

- [x] Phase 5: Run Script Core (1/1 plan) — `./run` dispatcher with all 20 commands + safety guards. Requirements: RUN-01…RUN-08
- [x] Phase 6: GitLab CI + Polish (2/2 plans) — CI delegates to `./run`; colored output + `./run doctor`. Requirements: CI-01…CI-04, POL-01, POL-02
- [x] Phase 7: Docs + Cleanup (1/1 plan) — CLAUDE.md → `./run`; Makefile deleted; grep-gate invariant. Requirements: DOC-01, DOC-02

Full detail: [milestones/v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [milestones/v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md)

</details>

<details>
<summary>✅ v3.0 — Jupyter + mise (Phases 8-9) — SHIPPED 2026-06-02</summary>

Added JupyterLab + the `mise` version manager to the baked AMI. Shipped JupyterLab as
**loopback-only, on-demand** (`./run jupyter` → `127.0.0.1:8888` over SSM; no systemd
service, no password, no TLS) after a mid-milestone pivot, plus a checksum-pinned `mise`
binary with system-wide shell activation (folded into the `devops` role).

- [x] Phase 8: Jupyter + mise AMI Layer (4/4 plans) — loopback `/opt/jupyter` venv + checksum-pinned mise. Requirements: JUP-01/08, MISE-01…03 (JUP-02/03/04 superseded)
- [x] Phase 9: Jupyter Operator Surface + Docs (1/1 plan) — `./run status` surfacing + DEVELOPER-LIFECYCLE docs. Requirements: JUP-07 (JUP-05/06 superseded)

Full detail: [milestones/v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md)

</details>

### 🚧 v3.2 — XRDP Remote Desktop (Active)

**Milestone Goal:** Replace the VNC/noVNC desktop stack with **xrdp built from vendored,
sha256-pinned source** (airgap-safe), authenticating via **PAM**, so operators connect with
a native RDP client and a full-length system password. The VNC scheme failed because
full-length password auth was structurally impossible (VeNCrypt `Plain` username problem,
`VncAuth` 8-char DES cap) and verification was deferred until it was too late — so this
milestone makes verification **first-class** and removes the VNC stack only **after** xrdp
is proven working.

**Build order (dependency spine):** install build toolchain + Xorg SDK from the AL2023
mirror → build/install xrdp → build/install xorgxrdp against the running Xorg ABI →
configure (`xrdp.ini` TLS, `sesman.ini` Xorg backend, `/etc/pam.d/xrdp-sesman`) → enable
systemd units → assert at bake → integrate network/operator surface → remove VNC → confirm
with a live RDP-login UAT. Each phase strictly depends on the prior one.

**Airgap invariant:** no network fetch at bake. xrdp + xorgxrdp source is vendored and
sha256-pinned (RDP-01, matching the repo's existing pinning convention); build dependencies
come from the AL2023 mirror only.

#### Phase 10: xrdp / xorgxrdp From-Source Build Role
**Goal**: A new `xrdp` Ansible role builds and installs xrdp and the xorgxrdp Xorg backend
from vendored, pinned source at bake — entirely offline — failing loudly if the Xorg SDK is
missing rather than producing a half-installed image.
**Depends on**: Phase 9 (v3.0 baked AMI layer is the foundation this role joins)
**Requirements**: RDP-01, RDP-02, RDP-03
**Success Criteria** (what must be TRUE):
  1. The bake completes with no network fetch from EPEL or upstream — xrdp and xorgxrdp
     source tarballs are vendored in-repo and verified against pinned version + sha256.
  2. The `xrdp` role installs the build toolchain + Xorg SDK from the AL2023 mirror, then
     compiles and installs xrdp and xorgxrdp against the running Xorg ABI.
  3. If a required build dependency — especially `xorg-x11-server-devel` — is unavailable,
     the bake fails with an explicit assertion (hard gate) instead of continuing.
**Plans**: TBD

**Notes**: `xorgxrdp` links the running Xorg server ABI, so `xorg-x11-server-devel`
availability (RDP-03) is a hard gate — the build must abort, not skip. The role's source
vendoring + sha256 pin (RDP-01) follows the same convention as the `mise` and Packer-source
pins already in the repo.

#### Phase 11: Service Config, PAM, Session + Bake Verification
**Goal**: xrdp runs as an enabled, TLS-protected systemd service on `:3389`, authenticates
`ec2-user` against the CIS-hardened PAM stack, launches the desktop session via the Xorg
(xorgxrdp) backend, and a bake-time assertion proves the binaries/modules are present and
the services are enabled — all with the `xrdp` role inserted **before** `hardening`.
**Depends on**: Phase 10 (binaries must exist before they can be configured + verified)
**Requirements**: RDP-04, RDP-05, RDP-06, RDP-07, RDP-08, RDP-13
**Success Criteria** (what must be TRUE):
  1. xrdp listens on `:3389` with TLS enabled (`security_layer` / `certificate` / `key_file`),
     reusing the existing self-signed cert pattern.
  2. `sesman.ini` is configured for the xorgxrdp (Xorg) backend — no Xvnc/VNC backend — and
     `/etc/pam.d/xrdp-sesman` delegates to `password-auth` so RDP logins inherit pwquality +
     faillock from the CIS PAM stack.
  3. xrdp + xrdp-sesman are enabled systemd services that start on boot, and the `xrdp` role
     is positioned **before** `hardening` in `ansible/playbook.yml` (hardening-stays-last
     invariant preserved, same rule as JUP-08 / CLAUDE.md §8).
  4. A bake-time assertion (RDP-13) confirms the xrdp + xorgxrdp binaries/modules are present
     and the services are enabled — the bake fails if not.
**Plans**: TBD

**Notes**: RDP-07 (an operator reaches the desktop session over RDP as `ec2-user` with the
`./run secrets-show` password) is delivered by this phase's config — it reuses the existing
`ec2-user` PAM password the `secrets` role already sets from SSM; **no new secret**. The
hardening-stays-last invariant is the same one enforced by the `grep-gates` hook + CI: the
`xrdp` role MUST be inserted before `hardening`, never after.

#### Phase 12: Network, Operator Surface + VNC/noVNC Removal
**Goal**: The operator reaches the new RDP desktop through the SG `:3389` ingress and a
`./run` SSM port-forward, and the obsolete VNC/noVNC stack — services, config, PAM file,
install, and the username-injection workaround — is fully removed, leaving no dead VNC
artifacts in the image. Removal happens last, only after xrdp is verified working in
Phase 11.
**Depends on**: Phase 11 (do not remove the working VNC path until xrdp is proven by the
bake assertion)
**Requirements**: RDP-09, RDP-10, RDP-11, RDP-12
**Success Criteria** (what must be TRUE):
  1. The Terraform security group exposes `:3389` (gated on `var.allowed_web_cidrs`) and drops
     `:6080`; the SSM-first posture (no public `:22`) is unchanged.
  2. `./run devbox-port-forward` tunnels `:3389`, and CLAUDE.md documents connecting with a
     native RDP client over SSM.
  3. The VNC/noVNC stack is removed — vncserver/novnc systemd services, `SecurityTypes Plain`,
     `/etc/pam.d/vnc`, and the noVNC install — with no dead VNC config left in the image.
  4. The noVNC username-injection workaround (`ansible/novnc-plain-username-fix.yml`, commit
     `29de35b`) is reverted/removed.
**Plans**: TBD

**Notes**: This is the irreversible-cleanup phase, so it is ordered last by design. The
workaround revert (RDP-12) follows the project's "kludges live in their own named playbook
imported by the main one" convention in reverse — the standalone fix playbook is removed and
its import dropped.

**Milestone-close gate — RDP-14 (human UAT):**
RDP-14 — a documented runtime UAT confirming a real RDP client authenticates via PAM and
renders the desktop on a **live instance** — requires a real AMI bake + AWS and so cannot be
verified at bake time. It is tracked as a **human-UAT gate that must be recorded before the
milestone closes**, consistent with prior milestones' deferred live-AWS UATs (v2.0's
deferred-at-close items). The milestone is not "shipped" until RDP-14 is recorded.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-4 | v1.0 | 10/10 | Complete | 2026-05-14 |
| 5. Run Script Core | v2.0 | 1/1 | Complete | 2026-05-27 |
| 6. GitLab CI + Polish | v2.0 | 2/2 | Complete | 2026-05-27 |
| 7. Docs + Cleanup | v2.0 | 1/1 | Complete | 2026-06-02 |
| 8. Jupyter + mise AMI Layer | v3.0 | 4/4 | Complete | 2026-06-02 |
| 9. Jupyter Operator Surface + Docs | v3.0 | 1/1 | Complete | 2026-06-02 |
| 10. xrdp / xorgxrdp From-Source Build Role | v3.2 | 0/TBD | Not started | - |
| 11. Service Config, PAM, Session + Bake Verification | v3.2 | 0/TBD | Not started | - |
| 12. Network, Operator Surface + VNC/noVNC Removal | v3.2 | 0/TBD | Not started | - |

## Shipped Milestones

| Version | Shipped | Phases | Plans | Requirements | Archive |
|---------|---------|-------:|------:|-------------:|---------|
| v1.0 — Security hardening + CI baseline | 2026-05-14 | 4 | 10 | 23/23 | [v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md) |
| v2.0 — Run Script + GitLab CI Integration | 2026-06-02 | 3 | 4 | DOC/RUN/CI/POL | [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) |
| v3.0 — Jupyter + mise | 2026-06-02 | 2 | 5 | 6 delivered / 5 superseded | [v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) |

## Pending (Deferred)

Carried from prior milestones; pick up in a future cycle:

- **Observability** (v3): CloudWatch metrics + login event shipping
- **Lifecycle** (v3): Idle auto-stop + scheduled nightly stop
- **Image lifecycle** (v3): Old AMI deregistration + inventory
- **Reproducibility follow-up** (v3): Pin Packer SSM parameter `:NN` version suffix (requires AWS creds)
