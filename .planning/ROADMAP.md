# Roadmap: devbox

## Milestones

- ✅ **v1.0 — Security hardening + CI baseline** — Phases 1-4 (shipped 2026-05-14)
- ✅ **v2.0 — Run Script + GitLab CI Integration** — Phases 5-7 (shipped 2026-06-02)
- ✅ **v3.0 — Jupyter + mise** — Phases 8-9 (shipped 2026-06-02)
- 🪦 **v3.2 — XRDP Remote Desktop** — Phases 10-12 (code-complete; superseded by v4.0 before RDP-14 UAT ran)
- ✅ **v4.0 — Amazon DCV Remote Desktop** — Phases 13-15 (code-complete, merged 2026-06-26; Phase-15 live UAT carried open — see Pending)
- 🚧 **v4.1 — Google Chrome in desktop role** — Phases 16-17 (active)

Milestone archives: [milestones/](milestones/) — per-milestone ROADMAP + REQUIREMENTS
(v4.0: [v4.0-ROADMAP.md](milestones/v4.0-ROADMAP.md) · [v4.0-REQUIREMENTS.md](milestones/v4.0-REQUIREMENTS.md)).

## Current Milestone: v4.1 Google Chrome in desktop role

**Goal:** Every desktop bake ships Google Chrome, installed from Google's signed dnf repo
at bake time.

**Shape:** No new role, no new layer flag — Chrome is unconditional desktop content inside
the existing `ansible/roles/desktop/` role, applied whenever `layers.desktop` is on (unlike
the `vscode_desktop` sub-gate). Version policy is **latest-at-bake** (Google's repo serves
only the current stable; historic RPMs are not hosted); remediation for a bad version is a
rebake — matching the SPAL/xrdp precedent (CLAUDE.md §8).

**Re-scoped 2026-07-24:** CHROME-03 (SBOM/manifest version capture as a stated requirement)
and CHROME-04 (dedicated bake-asserts: headless `--version` check + W1-style post-hardening
guard) moved to Future Requirements. The existing SBOM pass still inventories every package
— including Chrome — as ordinary behavior, but neither item is a v4.1 deliverable or a
success criterion. v4.1 maps CHROME-01 and CHROME-02 only.

**Invariants preserved:** `hardening` stays the last role in `ansible/playbook.yml`;
`sbom.yml` stays the last import; GPG verification stays ON for every dnf install
(`gpgcheck=1`, no `--nogpgcheck`) — airgap posture consistent with CLAUDE.md §2/§8.

**Build order:** bake-time implementation first (Phase 16), then the live-UAT gate
(Phase 17) — "launch Chrome from the GNOME desktop" is only provable on a live bake,
mirroring the v4.0 DCV-11 pattern. Live-anything requires AWS creds the operator runs.

## Phases

- [ ] **Phase 16: Chrome in the desktop role** - `google-chrome-stable` from Google's official signed dnf repo (baked `.repo` + GPG key, `gpgcheck=1`) baked into every desktop bake, no new layer flag
- [ ] **Phase 17: Live UAT gate (milestone-close)** - Chrome proven launchable from the GNOME desktop (DCV or xrdp session) on a live hardened instance

## Phase Details

### Phase 16: Chrome in the desktop role
**Goal**: Every desktop bake ships Google Chrome installed from Google's official signed
dnf repo, with GPG verification on and no change to the playbook's invariant ordering.
**Depends on**: Nothing within v4.1 (extends the existing `ansible/roles/desktop/` role on
`main`; the v4.0 dcv + xrdp desktop paths supply the GNOME session Chrome renders in)
**Requirements**: CHROME-02
**Success Criteria** (what must be TRUE):
  1. A `layers.desktop: true` bake installs `google-chrome-stable` from Google's official
     dnf repo — baked `.repo` config + Google GPG key — with **no new layer flag**: Chrome
     applies unconditionally whenever the desktop layer is on (no `vscode_desktop`-style
     sub-gate).
  2. GPG verification stays ON for the Chrome install: `gpgcheck=1` in the baked `.repo`
     config and no `--nogpgcheck` / `disable_gpg_check` anywhere in the change (posture
     consistent with CLAUDE.md §2/§8 and the SPAL precedent).
  3. A `layers.desktop: false` bake is unchanged — no Google repo config, GPG key, or
     Chrome package lands outside the desktop layer.
  4. Playbook invariants hold: `hardening` remains the last role in `ansible/playbook.yml`
     and `sbom.yml` remains the last import; pre-commit + CI grep-gates stay green.
**Plans**: 1 plan

Plans:
- [ ] 16-01-PLAN.md — Chrome block (rpm_key → baked canonical `.repo` → dnf `google-chrome-stable`) appended to the desktop role + static verification sweep (lint, grep-gates, GPG posture, invariants)

### Phase 17: Live UAT gate (milestone-close)
**Goal**: Chrome is proven working where the operator actually uses it — launched from the
GNOME desktop of a live, hardened, SELinux-enforcing instance over DCV or xrdp. This is a
documented human-run runtime UAT (requires AWS creds + a live bake the operator runs), not
a bake-time deliverable — mirroring v4.0's DCV-11 gate.
**Depends on**: Phase 16 (Chrome must be in the AMI under test before the live launch can
validate it)
**Requirements**: CHROME-01
**Success Criteria** (what must be TRUE):
  1. From within the allowed CIDR, the operator bakes → applies → connects over DCV
     (`:8443`) or RDP (`:3389`), logs in as `ec2-user`, and launches Google Chrome from
     the GNOME desktop (app grid / launcher); a Chrome window renders usably under
     software rendering.
  2. Chrome runs on the hardened, SELinux-enforcing live instance without sandbox or AVC
     failures blocking startup (any required flags/policy recorded as a documented
     follow-up, not silently patched).
  3. The result is recorded in a `17-*-UAT.md` before the milestone closes.
**Plans**: TBD (human UAT gate — recorded, not coded)

**Notes**: This UAT composes with the open live-UAT backlog (v4.0 DCV-11, xrdp
quick-task 260707-o7s task 3, ai_tools first bake, kion-creds endpoints) — a single
bake + apply session can clear several gates. The next `tf-apply` replaces the instance.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-4 | v1.0 | 10/10 | Complete | 2026-05-14 |
| 5-7 | v2.0 | 4/4 | Complete | 2026-06-02 |
| 8-9 | v3.0 | 5/5 | Complete | 2026-06-02 |
| 10-12 | v3.2 | 8/8 | Complete (superseded by v4.0) | 2026-06-16 |
| 13-14 | v4.0 | 7/7 | Complete (verified; merged 2026-06-26) | 2026-06-19 |
| 15. Live UAT Gate (DCV-11) | v4.0 | — | Carried open (human/AWS) | - |
| 16. Chrome in the desktop role | v4.1 | 0/1 | Planned | - |
| 17. Live UAT gate | v4.1 | 0/? | Not started | - |

## Shipped Milestones

| Version | Shipped | Phases | Plans | Requirements | Archive |
|---------|---------|-------:|------:|-------------:|---------|
| v1.0 — Security hardening + CI baseline | 2026-05-14 | 4 | 10 | 23/23 | [v1-ROADMAP.md](milestones/v1-ROADMAP.md) · [v1-REQUIREMENTS.md](milestones/v1-REQUIREMENTS.md) |
| v2.0 — Run Script + GitLab CI Integration | 2026-06-02 | 3 | 4 | DOC/RUN/CI/POL | [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) |
| v3.0 — Jupyter + mise | 2026-06-02 | 2 | 5 | 6 delivered / 5 superseded | [v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) |
| v3.2 — XRDP Remote Desktop | code-complete 2026-06-16; **superseded by v4.0** (RDP-14 UAT never ran) | 3 | 8 | RDP-01…13 (RDP-14 superseded) | `.planning/milestones/` + git history (`main` through `5ad3309`) |
| v4.0 — Amazon DCV Remote Desktop | code-complete, merged 2026-06-26 (**DCV-11 live UAT carried open**) | 3 | 7 | DCV-01…10 (DCV-11 pending live) | [v4.0-ROADMAP.md](milestones/v4.0-ROADMAP.md) · [v4.0-REQUIREMENTS.md](milestones/v4.0-REQUIREMENTS.md) |

## Pending (Deferred)

Carried from prior milestones; pick up in a future cycle:

- **Open live-UAT backlog** (needs AWS creds + live bake; one session can clear several): v4.0 DCV-11, xrdp 260707-o7s task 3 (live RDP login), ai_tools first-bake verify, kion-creds token endpoints
- **Observability** (v3): CloudWatch metrics + login event shipping
- **Lifecycle** (v3): Idle auto-stop + scheduled nightly stop
- **Image lifecycle** (v3): Old AMI deregistration + inventory
- **Reproducibility follow-up** (v3): Pin Packer SSM parameter `:NN` version suffix (requires AWS creds)
- **xrdp/xorgxrdp SPAL version pin** (260707-o7s): fill `xrdp_version` / `xrdp_xorgxrdp_version` after first bake (CLAUDE.md §9)
- **DCV license infra in-repo** (v4.0): provision the S3 gateway VPC endpoint + scoped IAM `s3:GetObject` on `dcv-license.<region>` if the target environment stops providing it (assumed external in v4.0; verified at DCV-11)
- **DCV v4.x** (deferred): GPU acceleration (`nice-dcv-gl`), native-client packaging/docs, file transfer, multi-monitor, custom CA TLS cert, optional SSM port-forward fallback for `:8443` TCP
- **Chrome follow-ups** (v4.1 deferred, re-scope 2026-07-24): CHROME-03 SBOM/manifest version capture as a stated requirement (the SBOM pass inventories Chrome anyway — dropped as requirement, not behavior); CHROME-04 dedicated bake-asserts (headless `--version` as `ec2-user`; W1-style post-hardening guard — revisit if a bake ever ships a dead Chrome); managed policies under `/etc/opt/chrome/policies/`; default-browser wiring (`xdg-settings`) — revisit at UAT if GNOME defaults annoy
