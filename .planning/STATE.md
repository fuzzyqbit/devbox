---
gsd_state_version: 1.0
milestone: v4.1
milestone_name: Google Chrome in desktop role
status: ready_to_plan
stopped_at: Completed 16-01-PLAN.md; Phase 16 awaiting verification.
last_updated: "2026-07-24T13:18:09.293Z"
last_activity: 2026-07-24
progress:
  total_phases: 2
  completed_phases: 2
  total_plans: 1
  completed_plans: 1
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (v4.1 Google Chrome in desktop role milestone started 2026-07-24)

**Core value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one command — without leaking credentials or exposing a vulnerable host to the public internet.
**Current focus:** Phase 16 — chrome-in-the-desktop-role

## Current Position

Phase: 17
Plan: Not started
Status: Ready to plan
Last activity: 2026-07-24

Progress: [██████████] 100%

### v4.1 Phase Map

| Phase | Goal | Requirements | Status |
|-------|------|--------------|--------|
| 16 | Chrome from Google's official signed dnf repo in `desktop` role (baked `.repo` + GPG key, `gpgcheck=1`, no new layer flag) | CHROME-02 | Executed (16-01 — `f778b56`; static gates green; awaiting verifier) |
| 17 | Live UAT gate — Chrome launches from GNOME desktop (DCV/xrdp) on live hardened instance | CHROME-01 | Not started (human/AWS; blocks milestone close) |

### v4.0 Phase Map (carried — live UAT open)

| Phase | Goal | Requirements | Status |
|-------|------|--------------|--------|
| 13 | `dcv` role: install + dcv.conf + virtual session + SELinux/FIPS + bake assert | DCV-01…05 | VERIFIED (bake-config; adversarial CLEAR after CRITICAL-2 fix) |
| 14 | Direct-connect SG (:8443 TCP+UDP) + xrdp/VNC removal + CIS 2.2.1 revert + operator surface | DCV-06…10 | VERIFIED (code; adversarial CLEAR — 2 independent opus reviewers) |
| 15 | Live UAT gate (license, render, AVC-clean, FIPS, QUIC, CIS revert safe) | DCV-11 | Pending — human/AWS (carried open; merged to main 2026-06-26) |

## Performance Metrics

<details>
<summary>v1.0 / v2.0 / v3.2 / v4.0 historical metrics (collapsed)</summary>

### v1.0

| Phase | Plans | Total wall | Avg/Plan |
|-------|------:|-----------:|---------:|
| Phase 1 | 3 | ~26 min | ~9 min |
| Phase 2 | 2 | ~22 min | ~11 min |
| Phase 3 | 2 | ~19 min (parallel) | ~9 min |
| Phase 4 | 3 | ~10 min (parallel) | ~7 min |
| **v1.0 total** | **10** | **~77 min execution** | **~8 min** |

Calendar window: 2026-05-13 17:04 → 2026-05-14 10:58 (~18 hours wall clock; ~77 min active executor time).

### v3.2

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 11 | 01 | ~5min | 3 | 11 |
| 11 | 02 | 8min | 3 | 6 |
| 11 | 03 | ~10min | 2 | 4 |
| 12 | 02 | ~4min | 3 | 4 |
| 12 | 03 | ~9min | 2 | 10 |
| 12 | 04 | ~6min | 2 | 5 |

### v4.0

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 13 | 01 | 5min | 2 | 7 |
| 13 | 02 | 3min | 2 | 3 |

</details>

### v4.1

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 16 | 01 | 6min | 2 | 1 |

## Accumulated Context

See PROJECT.md Key Decisions table.

**v4.1 roadmap decisions (at roadmap time; revised at 2026-07-24 re-scope):**

- **Coarse granularity → 2 phases:** one bake-time implementation phase (16) + one live-UAT gate (17), mirroring v4.0's DCV-11 pattern. CHROME-01 ("launch from the GNOME desktop") is only provable on a live bake the operator runs with AWS creds — a static verifier pass is not runtime proof (bake-green-but-dead lesson). No padding; the work clusters into exactly these two boundaries.
- **Re-scope (2026-07-24):** CHROME-03 (SBOM/manifest version capture as a stated requirement) and CHROME-04 (dedicated bake-asserts: headless `--version` as `ec2-user` + W1-style post-hardening guard) deferred to Future Requirements by operator choice — a deliberate deviation from the dcv/xrdp/ai_tools bake-assert doctrine; revisit if a bake ever ships a dead Chrome. The existing SBOM pass still inventories Chrome as ordinary behavior (dropped as requirement, not as behavior). v4.1 maps CHROME-01/02 only (2/2 coverage).
- **Chrome is unconditional desktop content** inside `ansible/roles/desktop/` — no new role, no new layer flag, no `vscode_desktop`-style sub-gate (operator decision). Applies whenever `layers.desktop` is on; non-desktop bakes unchanged.
- **Latest-at-bake over strict pin:** Google's repo hosts only the current stable (~4-6-week cadence; historic RPMs not hosted) — a pin would break every bake for no reproducibility gain. Remediation for a bad version = rebake (SPAL/xrdp precedent, CLAUDE.md §8).
- **GPG posture unchanged:** baked `.repo` config + Google GPG key, `gpgcheck=1`, no `--nogpgcheck` / `disable_gpg_check` — consistent with CLAUDE.md §2/§8 airgap posture.
- **Playbook invariants untouched:** `hardening` stays the last role in `ansible/playbook.yml`; `sbom.yml` stays the last import (both grep-gated).
- **Phase-17 UAT composes with the open live-UAT backlog** (DCV-11, xrdp 260707-o7s task 3, ai_tools first bake, kion-creds endpoints) — one bake + apply session can clear several gates. Next `tf-apply` replaces the instance.

**v4.1 execution decisions (16-01, 2026-07-24):**

- **Repo-wide local hook baselines are pre-existing-red:** `pre-commit run --all-files` (no-changeme, check-yaml, trailing-whitespace) and the repo-wide push-stage ansible-lint hook fail on content blame-proven to predate Phase 16; CI-authoritative scopes (grep-gates, gitleaks, `ansible-lint ansible/playbook.yml` pinned v26.4.0) are green including the Chrome block. Hygiene follow-ups logged in `phases/16-chrome-in-the-desktop-role/deferred-items.md`; git hooks are not installed in this clone (operator: run the three `pre-commit install` commands, CLAUDE.md §2).

<details>
<summary>v4.0 roadmap decisions + pitfalls (collapsed — carried until DCV-11 records)</summary>

- Coarse granularity → 3 phases (bake-time role → runtime SG/removal → live UAT).
- License infra OUT of scope (assumed external); residual risk verified at DCV-11 — if it fails, S3 gateway endpoint + scoped IAM become a documented follow-up.
- Direct-connect posture: SG opens `:8443` TCP+UDP gated on `var.allowed_web_cidrs`; QUIC ON; no `./run` port-forward for DCV; xrdp `:3389` re-added later by quick-task 260707-o7s (additive).
- Virtual session (Xdcv), non-GPU/software render; CIS 2.2.1 re-enabled for DCV-only builds, scoped OFF for xrdp builds (CLAUDE.md §8).
- Credential model unchanged: `authentication=system` reuses the `ec2-user` PAM password (`/devbox/<user>/vnc-password` path never renamed).
- Install airgap-compliant: pinned `get_url` from CloudFront + NICE GPG key + sha256; no `--nogpgcheck`, no S3-for-install.
- Pitfalls baked in: oneshot virtual-session unit; SELinux `restorecon -RvF` + never `setenforce 0`; FIPS-clean self-signed cert (RSA-2048/sha256/SAN); colord `45-allow-colord.rules`; dcv-gl "no GPU" log benign; grep-gate rejects `authentication=none`/TLS-off.

</details>

<details>
<summary>v1.0 / v2.0 / v3.0 / v3.2 locked decisions (collapsed — see PROJECT.md)</summary>

- SSM Parameter Store SecureString (vs Secrets Manager); hybrid network posture; Packer manifest → auto.tfvars handoff; Checkov; parallel CI + tiered pre-commit; Terragrunt dropped post-v1.0.
- v2.0: Makefile deleted last; standalone `./run` dispatcher.
- v3.0: Jupyter loopback-only on-demand; mise binary-only; hardening-invariant for new roles (JUP-08).
- v3.2: xorgxrdp/Xorg backend with CIS 2.2.1 deviation; removed/reverted in v4.0, then xrdp re-added from SPAL by 260707-o7s with 2.2.1 scoped off for xrdp builds.

</details>

## Deferred / Carried Forward

| Category | Item | Status | Originated |
|----------|------|--------|-----------|
| live_uat | v4.0 DCV-11 live UAT (license, render, AVC-clean, FIPS, QUIC, CIS-revert safe) | open — human/AWS | v4.0 Phase 15 |
| live_uat | xrdp 260707-o7s task 3 (live RDP login verify) + SPAL version pin fill-in | open — human/AWS | quick 260707-o7s |
| live_uat | ai_tools first-bake verify; kion-creds token endpoints (branch `feat/kion-creds`, unmerged) | open — human/AWS | 2026-07 merges |
| Observability | CloudWatch metrics + login event shipping | v3 backlog | v1.0 init |
| Lifecycle | Idle auto-stop + scheduled nightly stop | v3 backlog | v1.0 init |
| Image lifecycle | Old AMI deregistration + inventory | v3 backlog | v1.0 init |
| Reproducibility | SSM `:NN` version suffix on Packer source | v3 follow-up | v1.0 Phase 3 |
| uat_gap | 05/06/08-HUMAN-UAT.md scenarios | partial — needs live AWS/devbox | v2.0/v3.0 close |
| verification_gap | 05/06/08-VERIFICATION.md | human_needed | v2.0/v3.0 close |
| tech_debt | WR-05: bootstrap .sh.j2 outside CI shellcheck glob | open follow-up | v3.0 close |
| dcv_license | S3 gateway VPC endpoint + scoped IAM `s3:GetObject` on `dcv-license.<region>` | out of scope (assumed external); provision in-repo if target env stops providing it | v4.0 roadmap |
| dcv_v4x | GPU `nice-dcv-gl`, native-client docs, file transfer, multi-monitor, custom CA cert, SSM `:8443` TCP fallback | deferred | v4.0 roadmap |
| chrome_deferred | CHROME-03 SBOM/manifest version capture as stated requirement (behavior persists via existing SBOM pass) | deferred — re-scope 2026-07-24 | v4.1 re-scope |
| chrome_deferred | CHROME-04 dedicated bake-asserts (headless `--version` as `ec2-user`; W1-style post-hardening guard) | deferred — revisit if a bake ships a dead Chrome | v4.1 re-scope |
| chrome_followup | Chrome managed policies (`/etc/opt/chrome/policies/`); default-browser `xdg-settings` wiring | deferred — revisit at UAT | v4.1 requirements |

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260520-be1 | create gitlab CI pipeline: packer build AMI then tofu apply EC2 from that AMI | 2026-05-20 | 72f3157 | [260520-be1-…](./quick/260520-be1-create-gitlab-ci-pipeline-packer-build-a/) |
| 260602-add-golang-dev-tools | add 11 pinned Go developer tools to the golang role | 2026-06-02 | 88541f0 | [260602-add-golang-dev-tools](./quick/260602-add-golang-dev-tools/) |
| 260609-dif | enforce noVNC HTTPS-only via `novnc_proxy --ssl-only` | 2026-06-09 | fb59449 | [260609-dif-…](./quick/260609-dif-enforce-https-only-on-novnc-via-novnc-pr/) |
| 260611-jq2 | (prior DCV role — reverted at d3bd9a0; source for the v4.0 `dcv` role port) | — | 51c5f1f/67faeb3/8538ef3 | git history |
| 260707-o7s | add xrdp (RDP :3389) from SPAL — additive to DCV, PAM logins; **Tasks 1–2 committed, Task 3 live-verify pending** | 2026-07-07 | 1ab1835/33690e9 | [260707-o7s-xrdp-spal](./quick/260707-o7s-xrdp-spal/) |

## Session Continuity

Last session: 2026-07-24T13:16:52.832Z

- v4.1 re-scoped: CHROME-03 (SBOM capture as requirement) and CHROME-04 (dedicated
  bake-asserts) moved to Future Requirements. Roadmap revised: Phase 16 (bake-time
  implementation — CHROME-02) + Phase 17 (live UAT gate — CHROME-01), continuing
  numbering from v4.0's Phase 15. Coverage 2/2, no orphans.

- v4.0 roadmap archived at `milestones/v4.0-ROADMAP.md`; ROADMAP.md replaced for v4.1.
- v4.0 DCV-11 live UAT remains carried open (merged to main 2026-06-26 without it);
  Phase-17 UAT is planned to compose with that backlog in one live bake session.

Stopped at: Completed 16-01-PLAN.md (`f778b56` — Chrome block in the desktop role; static gates green).
Next: verifier for Phase 16, then Phase 17 (live UAT gate — composes with the open live-UAT backlog).

## Operator Next Steps

- **Plan Phase 16:** `/gsd:plan-phase 16` — Chrome install task block in
  `ansible/roles/desktop/`: baked Google `.repo` config + GPG key, `gpgcheck=1`
  install of `google-chrome-stable`, gated only by `layers.desktop` (no sub-flag);
  `hardening` stays last role, `sbom.yml` stays last import.

- **Open live-UAT backlog (human/AWS, one bake session can clear several):**
  `DEVBOX_USER=$(whoami) ./run build && ./run tf-init && ./run tf-apply && ./run start`, then
  from within `var.allowed_web_cidrs`: v4.0 DCV-11 checks (GNOME renders on `:8443`, license
  resolves, AVC-clean, FIPS TLS, QUIC, `repoquery --requires nice-xdcv` clean), xrdp `:3389`
  login (260707-o7s task 3 + SPAL pin fill-in), ai_tools first-bake verify, and — once
  Phase 16 lands — Chrome launch from the GNOME desktop (Phase 17). Record results in the
  respective UAT files. Note: the next `tf-apply` replaces the instance.
