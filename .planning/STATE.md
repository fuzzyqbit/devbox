---
gsd_state_version: 1.0
milestone: v4.0
milestone_name: — Amazon DCV Remote Desktop
status: awaiting-human-uat
stopped_at: Phase 14 verified (adversarial CLEAR); only Phase 15 live UAT remains (human/AWS)
last_updated: "2026-06-22T12:17:17.792Z"
last_activity: 2026-06-22
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 7
  completed_plans: 7
  percent: 67
---

# Project State

## Project Reference

See: .planning/PROJECT.md (v4.0 Amazon DCV Remote Desktop milestone started 2026-06-15)

**Core value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one command — without leaking credentials or exposing a vulnerable host to the public internet.
**Current focus:** Phase 15 — live UAT (human/AWS); all code-level work (Phases 13–14) verified.

## Current Position

Phase: 14 (direct-connect SG + xrdp removal + CIS revert + operator) — VERIFIED (adversarial CLEAR)
Plan: 5 of 5 complete
Status: All bake-time/code work done + verified. Only Phase 15 live UAT (human/AWS) remains to close v4.0.
Last activity: 2026-06-22
Branch: feat/dcv (pushed; NOT merged to main)

Progress: [█████████·] code 100% — milestone gated on the human Phase-15 UAT

### v4.0 Phase Map

| Phase | Goal | Requirements | Status |
|-------|------|--------------|--------|
| 13 | `dcv` role: install + dcv.conf + virtual session + SELinux/FIPS + bake assert | DCV-01…05 | VERIFIED (bake-config; adversarial CLEAR after CRITICAL-2 fix) |
| 14 | Direct-connect SG (:8443 TCP+UDP) + xrdp/VNC removal + CIS 2.2.1 revert + operator surface | DCV-06…10 | VERIFIED (code; adversarial CLEAR — 2 independent opus reviewers) |
| 15 | Live UAT gate (license, render, AVC-clean, FIPS, QUIC, CIS revert safe) | DCV-11 | Pending — human/AWS (blocks milestone close) |

## Performance Metrics

<details>
<summary>v1.0 / v2.0 / v3.2 historical metrics (collapsed)</summary>

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

</details>

v4.0: no metrics yet (roadmap just created).
| Phase 13 P01 | 5min | 2 tasks | 7 files |
| Phase 13 P02 | 3min | 2 tasks | 3 files |

## Accumulated Context

See PROJECT.md Key Decisions table.

**v4.0 roadmap decisions (at roadmap time):**

- **Coarse granularity → 3 phases**, matching the research's dependency-driven build order (bake-time role → runtime SG/removal → live UAT). No padding; the work clusters into exactly these three boundaries.
- **License infra is OUT of scope** (assumed reachable externally — REQUIREMENTS.md Assumptions). NO Terraform license/VPC-endpoint/IAM phase is created. The residual licensing risk (`ORIGIN_OBJECT_MISSING` past 15-day grace — the exact blocker that scrapped DCV in `d3bd9a0`) is *verified, not silently assumed*, at the live UAT (DCV-11). If it fails, the S3 gateway endpoint + scoped IAM become a documented follow-up (already listed in ROADMAP Pending).
- **Direct-connect posture (CHANGED from research's SSM assumption):** the SG opens `:8443` **TCP and UDP** gated on `var.allowed_web_cidrs`; **QUIC is ENABLED** (`enable-quic-frontend=true`) because access is direct, not SSM-tunneled. There is NO `./run` port-forward step for DCV. The xrdp `:3389` ingress is dropped. (NB: the research SUMMARY/PITFALLS were written for an SSM-port-forward posture and recommend QUIC-OFF + TCP-only — that recommendation is **superseded** by the v4.0 direct-connect decision in PROJECT.md/REQUIREMENTS.md; honour QUIC-ON + UDP for v4.0.)
- **Virtual session (Xdcv), non-GPU/software render** — lets DCV-08 REVERT the v3.2 CIS 2.2.1 X-server exception + delete the post-hardening Xorg guard (virtual sessions use `Xdcv`, not system `/usr/libexec/Xorg`). The revert is committed in Phase 14 but its *safety* is a Phase 15 live-UAT gate; documented fallback (keep Xorg, leave override) if the UAT disproves it.
- **Prior `dcv` role is recoverable from git** (`51c5f1f` / `67faeb3` / `8538ef3`, quick-task `260611-jq2`; reverted at `d3bd9a0` solely for the airgap-license blocker). Phase 13 ports it + adds the gaps the prior attempt missed: FIPS-clean cert (RSA-2048/sha256/SAN), colord `.rules`, PAM `/etc/pam.d/dcv` delegate, SELinux relabel, bake asserts. ~80% of the role already exists.
- **Removal (DCV-07/08/09) is the irreversible-cleanup work — sequenced AFTER the `dcv` role is in place** (Phase 14, not Phase 13) so the new role fills the playbook slot xrdp vacates. The live UAT (DCV-11) is last.
- **Credential model unchanged:** `authentication=system` reuses the `ec2-user` PAM password from the `secrets` role (`/devbox/<user>/vnc-password`, path NEVER renamed — relabel-only; hard-coded in 4+ places). No new secret.
- **Install airgap-compliant:** pinned `get_url` from CloudFront (`d1uj6qtbmh3dt5.cloudfront.net`) + NICE GPG key import + sha256 (deferred-pin per CLAUDE.md §9 — fill `dcv_tarball_sha256` after first bake before merge). Build numbers differ per package (`dcv_build_server` ≠ `dcv_build_xdcv`) — do not reuse one for the other. No `--nogpgcheck`, no S3-for-install.
- **`hardening` stays the last role** (grep-gate + CLAUDE.md §8 invariant) — the `dcv` role inserts between `desktop` and `hardening`, the same slot xrdp held.

**Pitfalls to bake in (from .planning/research/PITFALLS.md):**

- No auto-session: DCV creates zero sessions; wire a oneshot `dcv create-session --type virtual --owner ec2-user` unit (virtual cannot use `dcv.conf` console auto-create).
- SELinux AVCs under enforcing: `restorecon -RvF` over DCV paths in the role; AVC-clean confirmed only at live UAT; never `setenforce 0` — vendor a scoped `audit2allow` module if denials appear.
- FIPS TLS: DCV's auto-cert may lack SAN / use SHA-1; generate a FIPS-clean self-signed cert in the role + bake-assert SAN/RSA≥2048/sha256; handshake confirmed at UAT.
- colord polkit: ship `45-allow-colord.rules` (`.pkla` ignored on AL2023 polkit 121+) or the GNOME session hangs.
- dcv-gl "no GPU" log is BENIGN on non-GPU — do not install `nice-dcv-gl`; document the message.
- Security grep-gate: reject `authentication=none` / TLS-off in tracked DCV config (mirror the no-changeme gate). The `!= "changeme"` PAM-password assert ported from the prior role is a known no-changeme hook false-positive — annotate/handle the gate.

<details>
<summary>v1.0 / v2.0 / v3.0 / v3.2 locked decisions (collapsed — see PROJECT.md)</summary>

- SSM Parameter Store SecureString (vs Secrets Manager); hybrid network posture; Packer manifest → auto.tfvars handoff; Checkov; parallel CI + tiered pre-commit; Terragrunt dropped post-v1.0.
- v2.0: Makefile deleted last; standalone `./run` dispatcher.
- v3.0: Jupyter loopback-only on-demand; mise binary-only; hardening-invariant for new roles (JUP-08).
- v3.2: xorgxrdp/Xorg backend with CIS 2.2.1 as the single documented deviation; post-hardening regression asserts; vendored xorg.conf + idempotent semanage fcontext; tsusers gating; `gnome-session` by name. **All of this is removed/reverted in v4.0** — DCV virtual sessions make the Xorg dependency and the CIS deviation unnecessary.

</details>

## Deferred / Carried Forward

| Category | Item | Status | Originated |
|----------|------|--------|-----------|
| Observability | CloudWatch metrics + login event shipping | v3 backlog | v1.0 init |
| Lifecycle | Idle auto-stop + scheduled nightly stop | v3 backlog | v1.0 init |
| Image lifecycle | Old AMI deregistration + inventory | v3 backlog | v1.0 init |
| Reproducibility | SSM `:NN` version suffix on Packer source | v3 follow-up | v1.0 Phase 3 |
| uat_gap | 05/06/08-HUMAN-UAT.md scenarios | partial — needs live AWS/devbox | v2.0/v3.0 close |
| verification_gap | 05/06/08-VERIFICATION.md | human_needed | v2.0/v3.0 close |
| tech_debt | WR-05: bootstrap .sh.j2 outside CI shellcheck glob | open follow-up | v3.0 close |
| dcv_license | S3 gateway VPC endpoint + scoped IAM `s3:GetObject` on `dcv-license.<region>` | out of scope (assumed external); provision in-repo if target env stops providing it | v4.0 roadmap |
| dcv_v4x | GPU `nice-dcv-gl`, native-client docs, file transfer, multi-monitor, custom CA cert, SSM `:8443` TCP fallback | deferred | v4.0 roadmap |

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260520-be1 | create gitlab CI pipeline: packer build AMI then tofu apply EC2 from that AMI | 2026-05-20 | 72f3157 | [260520-be1-…](./quick/260520-be1-create-gitlab-ci-pipeline-packer-build-a/) |
| 260602-add-golang-dev-tools | add 11 pinned Go developer tools to the golang role | 2026-06-02 | 88541f0 | [260602-add-golang-dev-tools](./quick/260602-add-golang-dev-tools/) |
| 260609-dif | enforce noVNC HTTPS-only via `novnc_proxy --ssl-only` | 2026-06-09 | fb59449 | [260609-dif-…](./quick/260609-dif-enforce-https-only-on-novnc-via-novnc-pr/) |
| 260611-jq2 | (prior DCV role — reverted at d3bd9a0; source for the v4.0 `dcv` role port) | — | 51c5f1f/67faeb3/8538ef3 | git history |

## Session Continuity

Last session: 2026-06-22 (resume → Phase 14 adversarial review + verification)

- Ran the pending Phase 14 adversarial review: two independent opus reviewers, distinct lenses (removal/dependency + network/operator). Both VERDICT: CLEAR (0 critical, 0 high).
- Orchestrator hand-re-verified the load-bearing claims: SG :8443 TCP+UDP both gated on var.allowed_web_cidrs + :3389 gone (main.tf:113-132); `git grep vnc` = 0, `git grep xrdp|xorgxrdp|3389` (excl .planning + dcv role) = 0; hardening last (playbook.yml:65) with dcv before it (59); is-enabled bake assert present (dcv/tasks/main.yml:427-443).
- Carried CRITICAL-1 (secrets-bootstrap ordering xrdp→dcvserver) confirmed CLOSED.
- One LOW residual (CIS-2.2.1-revert render safety) is documented + deferred to Phase 15 by design — no static guard can prove "GNOME renders without system Xorg"; the W1 guard fail_msg already names the `repoquery --requires nice-xdcv` Phase-15 check. Deliberately NOT code-changed (a speculative guard would risk false-failing a good bake; KISS/YAGNI).
- Wrote 14-VERIFICATION.md (status: passed). No code changes this session — Phase 14 stands as committed.

Stopped at: Phase 14 verified. Milestone v4.0 is code-complete; only the human Phase-15 live UAT remains.
Next: human runs the Phase-15 live UAT (needs live AWS + reachable S3 license path), then merge feat/dcv → main.

## Operator Next Steps

- **Phase 15 live UAT (human/AWS):** `DEVBOX_USER=$(whoami) ./run build && ./run tf-init && ./run tf-apply && ./run start`, then from within `var.allowed_web_cidrs` browse `https://<host>:8443` (or native DCV client), login `ec2-user` + `./run secrets-show` desktop password. Confirm: GNOME virtual session renders (not blank/Wayland); license resolves (no ORIGIN_OBJECT_MISSING past grace); SELinux AVC-clean under enforcing (`ausearch -m avc -ts boot`); FIPS TLS handshake on :8443; QUIC over UDP 8443; `systemctl is-active dcvserver dcv-virtual-session`; CIS-2.2.1-revert safe (`repoquery --requires nice-xdcv` shows no `xorg-x11-server-common`). Record results in a 15-*-UAT.md.
- After UAT passes: merge `feat/dcv` → `main`.
