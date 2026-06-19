# Roadmap: devbox

## Milestones

- ✅ **v1.0 — Security hardening + CI baseline** — Phases 1-4 (shipped 2026-05-14)
- ✅ **v2.0 — Run Script + GitLab CI Integration** — Phases 5-7 (shipped 2026-06-02)
- ✅ **v3.0 — Jupyter + mise** — Phases 8-9 (shipped 2026-06-02)
- 🪦 **v3.2 — XRDP Remote Desktop** — Phases 10-12 (code-complete; superseded by v4.0 before RDP-14 UAT ran)
- 🚧 **v4.0 — Amazon DCV Remote Desktop** — Phases 13-15 (active, branch `feat/dcv`)

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

<details>
<summary>🪦 v3.2 — XRDP Remote Desktop (Phases 10-12) — CODE-COMPLETE, SUPERSEDED by v4.0</summary>

Replaced the VNC/noVNC stack with xrdp built from vendored, sha256-pinned source (PAM auth,
native RDP client). Shipped code-complete 2026-06-16 (phases 10-12, adversarially verified);
**RDP-14 live UAT was the only open gate and never ran** — DCV was re-validated as the
preferred path and v4.0 supersedes this milestone, removing the xrdp/xorgxrdp role and its
SG/operator-surface wiring. v3.2 planning records retained below + under `.planning/phases/10–12/`.

- [x] Phase 10: xrdp / xorgxrdp From-Source Build Role (1/1 plan) — Requirements: RDP-01, RDP-02, RDP-03
- [x] Phase 11: Service Config, PAM, Session + Bake Verification (3/3 plans) — Requirements: RDP-04…08, RDP-13
- [x] Phase 12: Network, Operator Surface + VNC/noVNC Removal (4/4 plans) — Requirements: RDP-09…12
- ⏭️ RDP-14 (live RDP-login UAT) — never ran; superseded by v4.0 DCV-11. Not re-run (xrdp retired).

</details>

### 🚧 v4.0 — Amazon DCV Remote Desktop (Active)

**Milestone Goal:** Replace the remote-desktop stack with **Amazon DCV**. A new `dcv` Ansible
role installs/configures `dcvserver` on AL2023 (non-GPU, virtual session rendering GNOME);
**xrdp/xorgxrdp and any VNC/noVNC remnants are removed entirely**. DCV is reached by **direct
connect** — TCP **and** UDP `:8443` gated on `var.allowed_web_cidrs` (QUIC enabled, viable
because access is direct, not SSM-tunneled); `:22` stays absent and the CIDR allowlist is the
perimeter. Reverses v3.2.

**Branch:** `feat/dcv`

**Build order (dependency spine):** the `dcv` role is the foundation everything builds on
(it ports the proven prior role at git `51c5f1f`/`67faeb3`/`8538ef3` + adds the gaps the prior
attempt missed — QUIC-on, FIPS-safe cert, SELinux relabel, virtual-session auto-create, bake
assert) → then the direct-connect SG + irreversible xrdp/VNC removal + CIS 2.2.1 revert +
operator surface (done after the new role exists so removal frees the old role slot the new
one fills) → then the live UAT, which is the only place that can prove license-resolves,
GNOME-renders, AVC-clean-under-enforcing, FIPS-handshake, QUIC-works, and that the CIS revert
is safe.

**Credential model (unchanged):** the DCV login is the existing `ec2-user` PAM password the
`secrets` role generates per build, publishes to SSM (`/devbox/<user>/vnc-password`, path
unchanged — relabelled only), and the boot bootstrap applies via `chpasswd`. DCV
`authentication=system` validates it through PAM. No new secret.

**Out of scope (assumed external — see REQUIREMENTS.md Assumptions):** the DCV license path
(S3 VPC endpoint + IAM `s3:GetObject` on `dcv-license.<region>`) is assumed reachable from the
target environment. This milestone does **NOT** provision it. The residual licensing risk is
verified — not silently assumed — at the live UAT (DCV-11): if licensing does not resolve, the
endpoint + IAM become a documented follow-up.

**Invariants preserved:** `hardening` stays the last role in `ansible/playbook.yml`; the
`vnc-password` SSM param path is never renamed; install stays airgap-compliant (pinned
`get_url` + NICE GPG key + sha256, no S3-for-install, no `--nogpgcheck`).

#### Phase 13: `dcv` Ansible Role (install + config + session + SELinux/FIPS + bake assert)
**Goal**: A new `dcv` role bakes an AMI that installs the non-GPU Amazon DCV server package set,
configures `dcv.conf` (PAM auth, TLS, QUIC enabled, `:8443`, owner `ec2-user`), auto-creates a
virtual GNOME session at boot, survives the CIS-hardened baseline (SELinux relabel + FIPS-safe
cert), enables `dcvserver` before `hardening`, and proves it all with a bake-time assertion.
**Depends on**: Phase 12 (v3.2 baked AMI layer is the foundation this role joins; the `desktop`
role supplies the GNOME the virtual session renders, the `secrets` role supplies the PAM password)
**Requirements**: DCV-01, DCV-02, DCV-03, DCV-04, DCV-05
**Success Criteria** (what must be TRUE):
  1. The bake installs `nice-dcv-server`, `nice-dcv-web-viewer`, and `nice-xdcv` (no
     `nice-dcv-gl` / GPU packages) via a version-pinned `get_url` from the AWS DCV CloudFront
     host with the `NICE-GPG-KEY` imported and a sha256 checksum verified — airgap-compliant,
     no S3-for-install, no `--nogpgcheck`.
  2. `dcv.conf` is configured with `authentication=system` (PAM), TLS on, **QUIC enabled**
     (`enable-quic-frontend=true`), `web-port=8443`, and session owner `ec2-user`.
  3. After boot, a DCV **virtual** session (`Xdcv`, software render) exists rendering the GNOME
     desktop owned by `ec2-user` — DCV does not auto-create one, so the role wires a oneshot
     unit and/or `dcv.conf` auto-session.
  4. `dcvserver` is an enabled systemd service, the `dcv` role is wired into `playbook.yml`
     strictly **before** `hardening` (hardening-stays-last invariant = 1), and a bake-time
     assertion confirms the DCV binaries + session config are present (bake fails if not).
  5. DCV survives the hardened baseline: SELinux relabel leaves the install AVC-clean-capable
     and the self-signed TLS cert is FIPS-safe (RSA-2048 / sha256 / SAN), reusing the v3.2
     cert + relabel recipe.
**Plans**: 2 plans
- [x] 13-01-PLAN.md — `dcv` role: airgap install + dcv.conf (auth=system, QUIC on, :8443) + FIPS cert + oneshot virtual session + colord/PAM + SELinux relabel (DCV-01/02/03/05)
- [ ] 13-02-PLAN.md — playbook wiring (before hardening) + `dcv: true` toggle + RDP-13-grade bake assert (binary/conf-keys/cert path+owner+0600+SAN/units enabled) (DCV-04/05)
**UI hint**: yes

#### Phase 14: Direct-Connect SG + xrdp/VNC Removal + CIS Revert + Operator Surface
**Goal**: The operator reaches DCV by direct connect — the SG opens `:8443` TCP **and** UDP
gated on `var.allowed_web_cidrs` and the xrdp `:3389` ingress is dropped — while the obsolete
xrdp/xorgxrdp role and every VNC/noVNC remnant are removed, the CIS 2.2.1 X-server exception is
reverted (virtual sessions use `Xdcv`, not system Xorg), and `secrets-show` + operator docs are
relabelled to direct DCV `:8443` connect. Removal happens after the `dcv` role exists.
**Depends on**: Phase 13 (do not remove the old remote-desktop path until the new `dcv` role is
in place and bake-proven; the `dcv` role fills the playbook slot xrdp vacates)
**Requirements**: DCV-06, DCV-07, DCV-08, DCV-09, DCV-10
**Success Criteria** (what must be TRUE):
  1. The Terraform security group exposes `:8443` **TCP and UDP** gated on
     `var.allowed_web_cidrs` (UDP required for QUIC; direct connect, no SSM tunnel); the xrdp
     `:3389` ingress is dropped; `:22` absence, IMDSv2-only metadata, and egress are unchanged.
  2. The `xrdp`/`xorgxrdp` role, its `playbook.yml` wiring + layer toggle, the post-hardening
     Xorg `post_task` guard, `ansible/test-xrdp.yml`, and the vendored `xorg.conf` are removed.
  3. The CIS 2.2.1 X-server exception (`amzn2023cis_rule_2_2_1: false`) is reverted — committed
     pending the Phase 15 UAT confirming `Xdcv` renders without system Xorg (documented fallback
     if not).
  4. All VNC/noVNC and xrdp remnants are removed across ansible/terraform/run/scripts — a
     repo-wide completeness check returns no dead remote-desktop config (the kept `vnc-password`
     credential path is the only intentional residue).
  5. `secrets-show` + operator docs target **direct DCV `:8443` connect** (browser at
     `https://<host>:8443` or native client, within the allowed CIDR) with no `./run`
     port-forward step for DCV; the `ec2-user` SSM credential path is unchanged, labels updated
     noVNC/RDP → DCV.
**Plans**: TBD
**UI hint**: yes

#### Phase 15: Live UAT Gate (milestone-close)
**Goal**: DCV is proven end-to-end on a live private instance — the gate the prior DCV attempt
and the v3.2 RDP-14 UAT never cleared. This is a documented human-run runtime UAT, not a
bake-time deliverable; it confirms the properties only a live FIPS/SELinux-enforcing instance
can demonstrate, including the residual licensing risk left out of scope.
**Depends on**: Phase 14 (the SG must open `:8443` TCP+UDP and the removal/CIS-revert must be in
the AMI under test before the live connect can validate them)
**Requirements**: DCV-11
**Success Criteria** (what must be TRUE):
  1. Operator bakes → applies → connects **directly** (TCP+UDP `:8443`, within the allowed CIDR)
     as `ec2-user` with the `./run secrets-show` password, and the GNOME virtual session renders.
  2. The DCV license resolves — `dcv create-session` succeeds and the server log shows no
     `ORIGIN_OBJECT_MISSING` past first connect (confirming the externally-assumed license path
     is in fact reachable; if not, the S3 endpoint + IAM are recorded as a follow-up).
  3. The instance is SELinux AVC-clean under enforcing (`ausearch -m AVC -ts boot` shows no
     DCV/Xorg denials after first connect), the FIPS TLS handshake completes on `:8443`, and the
     QUIC (UDP) data path works.
  4. The CIS 2.2.1 revert is confirmed safe — `Xdcv` renders the GNOME virtual session without
     the system Xorg installed — and the result is recorded before the milestone closes.
**Plans**: TBD (human UAT gate — recorded, not coded)
**UI hint**: yes

**Notes**: DCV-11 is the milestone-close gate, modelled as a human-UAT gate (like v3.2's
RDP-14), not a bake-time deliverable — it requires a real AMI bake + live AWS. The milestone is
not "shipped" until DCV-11 is recorded. Because the license infra is out of scope (assumed
external), this UAT is also where the residual licensing risk is verified rather than silently
assumed.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-4 | v1.0 | 10/10 | Complete | 2026-05-14 |
| 5. Run Script Core | v2.0 | 1/1 | Complete | 2026-05-27 |
| 6. GitLab CI + Polish | v2.0 | 2/2 | Complete | 2026-05-27 |
| 7. Docs + Cleanup | v2.0 | 1/1 | Complete | 2026-06-02 |
| 8. Jupyter + mise AMI Layer | v3.0 | 4/4 | Complete | 2026-06-02 |
| 9. Jupyter Operator Surface + Docs | v3.0 | 1/1 | Complete | 2026-06-02 |
| 10. xrdp / xorgxrdp From-Source Build Role | v3.2 | 1/1 | Complete (superseded) | 2026-06-15 |
| 11. Service Config, PAM, Session + Bake Verification | v3.2 | 3/3 | Complete (superseded) | 2026-06-16 |
| 12. Network, Operator Surface + VNC/noVNC Removal | v3.2 | 4/4 | Complete (superseded) | 2026-06-16 |
| 13. `dcv` Ansible Role | v4.0 | 1/2 | In Progress|  |
| 14. Direct-Connect SG + xrdp/VNC Removal + CIS Revert + Operator Surface | v4.0 | 0/? | Not started | - |
| 15. Live UAT Gate | v4.0 | 0/? | Not started | - |

## Shipped Milestones

| Version | Shipped | Phases | Plans | Requirements | Archive |
|---------|---------|-------:|------:|-------------:|---------|
| v1.0 — Security hardening + CI baseline | 2026-05-14 | 4 | 10 | 23/23 | [v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md) |
| v2.0 — Run Script + GitLab CI Integration | 2026-06-02 | 3 | 4 | DOC/RUN/CI/POL | [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) |
| v3.0 — Jupyter + mise | 2026-06-02 | 2 | 5 | 6 delivered / 5 superseded | [v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) |
| v3.2 — XRDP Remote Desktop | code-complete 2026-06-16; **superseded by v4.0** (RDP-14 UAT never ran) | 3 | 8 | RDP-01…13 (RDP-14 superseded) | `.planning/phases/10–12/` + git history (`main` through `5ad3309`) |

## Pending (Deferred)

Carried from prior milestones; pick up in a future cycle:

- **Observability** (v3): CloudWatch metrics + login event shipping
- **Lifecycle** (v3): Idle auto-stop + scheduled nightly stop
- **Image lifecycle** (v3): Old AMI deregistration + inventory
- **Reproducibility follow-up** (v3): Pin Packer SSM parameter `:NN` version suffix (requires AWS creds)
- **DCV license infra in-repo** (v4.0): provision the S3 gateway VPC endpoint + scoped IAM `s3:GetObject` on `dcv-license.<region>` if the target environment stops providing it (assumed external in v4.0; verified at DCV-11)
- **DCV v4.x** (deferred): GPU acceleration (`nice-dcv-gl`), native-client packaging/docs, file transfer, multi-monitor, custom CA TLS cert, optional SSM port-forward fallback for `:8443` TCP
