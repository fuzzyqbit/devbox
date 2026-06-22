---
phase: 14-direct-connect-sg-removal-cis-revert-operator
verified: 2026-06-22
status: passed
status_note: "Adversarial CLEAR (two independent opus reviewers, distinct lenses). Phase 14 removes xrdp completely, reverts CIS 2.2.1, opens the direct-connect SG (:8443 TCP+UDP gated on var.allowed_web_cidrs, :3389 dropped), retargets the post-hardening X-server guard /usr/libexec/Xorg→/usr/bin/Xdcv, swaps the secrets-bootstrap unit xrdp→dcvserver (closes carried CRITICAL-1), and cuts the operator surface + docs to direct DCV. Zero vnc/xrdp/3389 residue in tracked code (independently re-verified). DCV-06..10 met at code level. One LOW residual (CIS-2.2.1-revert render safety) is documented + deferred to the Phase-15 live UAT by design — no static guard can prove GNOME renders without the system Xorg."
score: DCV-06..10 code-verified; adversarial CLEAR (0 critical, 0 high)
overrides_applied: 0
human_verification:
  - test: "DCV-11 (Phase 15 live UAT) — CIS 2.2.1 revert is render-safe: repoquery --requires nice-xdcv shows no hidden xorg-x11-server-common dep AND the GNOME-on-Xorg virtual session actually renders without the system Xorg"
    expected: "nice-xdcv self-contained (or its deps survive hardening); GNOME desktop renders in the Xdcv virtual session; W1 guard passed because Xdcv genuinely survived, not by accident"
    why_human: "No static/bake check can prove 'GNOME renders without system Xorg' — needs a baked AMI on a live instance under SELinux enforcing. The W1 guard's fail_msg already names this repoquery check."
  - test: "DCV-11 (Phase 15) — direct :8443 TCP+UDP connect from within var.allowed_web_cidrs as ec2-user; QUIC data path; FIPS TLS handshake; SELinux AVC-clean enforcing; license resolves (S3 path assumed reachable)"
    expected: "Connects directly (no SSM tunnel), GNOME renders, QUIC works over UDP 8443, FIPS handshake completes, no AVCs, license OK"
    why_human: "Needs live AWS instance + the SG + the assumed S3 license path."
---

# Phase 14: Direct-Connect SG + xrdp Removal + CIS 2.2.1 Revert + Operator Surface — Verification Report

**Phase Goal:** Open the direct-connect security group (`:8443` TCP+UDP gated on `var.allowed_web_cidrs`, drop `:3389`); remove xrdp/xorgxrdp entirely; revert the v3.2 CIS 2.2.1 X-server exception; retarget the post-hardening X-server guard to `/usr/bin/Xdcv`; cut the operator surface + docs over to direct DCV. Requirements DCV-06..10.
**Verified:** 2026-06-22 (two independent opus adversarial reviewers, distinct lenses — removal/dependency + network/operator — per the milestone's "static verifier not trustworthy for infra" lesson; see feedback_adversarial_verify_infra. Load-bearing claims re-verified by hand by the orchestrator.)
**Status:** PASSED — adversarial CLEAR (0 critical, 0 high, 1 documented-and-deferred LOW).

## Requirements Coverage

| Req | Status | Evidence |
|-----|--------|----------|
| DCV-06 SG :8443 TCP+UDP, drop :3389 | SATISFIED | `terraform/main.tf:113-132` — three gated ingress rules (8080/tcp, 8443/tcp, 8443/udp), all `cidr_blocks = var.allowed_web_cidrs`; no 3389/rdp rule; egress `-1`/0.0.0.0/0 unchanged; `:22` absent; IMDSv2 `http_tokens=required` untouched. `tofu validate` → valid. (2dcbe60) |
| DCV-07 remove xrdp role + wiring + guard retarget + test playbook + xorg.conf | SATISFIED | `ansible/roles/xrdp/**` + `ansible/test-xrdp.yml` deleted; `layers.xrdp` toggle gone (`layer_config.yml`, `playbook.yml`); post-hardening guard retargeted `/usr/libexec/Xorg`→`/usr/bin/Xdcv` gated `layers.dcv and layers.desktop` (`playbook.yml:75-93`). (caacb14) |
| DCV-08 revert CIS 2.2.1 exception | SATISFIED | `amzn2023cis_rule_2_2_1: false` override removed from `hardening/defaults/main.yml` (reverted to vendored `true`); no dangling override anywhere. Render-safety is the Phase-15 gate (below). (caacb14) |
| DCV-09 full remnant removal (VNC/noVNC/xrdp) | SATISFIED | Re-verified by hand: `git grep -rinI vnc -- :!.planning` = **0 matches**; `git grep -rinIE 'xrdp\|xorgxrdp\|3389' -- :!.planning :!ansible/roles/dcv` = **0 matches** (only relabelled DCV provenance comments survive in the kept dcv role). (caacb14/2dcbe60/e4d2ab2 + credential rename 47f68f4) |
| DCV-10 operator surface → direct DCV :8443 | SATISFIED | `run`/`scripts/devbox-*.sh`/docs: DCV port-forward steps removed, code-server `:8080` SSM forward retained; new `docs/HOWTO-ACCESS-CODE-SERVER-DCV.md` + edited `DEVELOPER-LIFECYCLE.md` say direct-connect `https://<host>:8443`, login `ec2-user` + desktop password, no SSM tunnel; old RDP HOWTO deleted; `secrets-show` reads `/devbox/<user>/desktop-password`. (2dcbe60) |

## Adversarial Review (two independent opus reviewers) — VERDICT: CLEAR

**Reviewer A (removal / dependency / playbook lens):** CLEAR. Confirmed: xrdp role + test-xrdp.yml fully deleted; dcv role ships its own colord `.rules` + PAM + GNOME-on-Xorg init (the deps the removed xrdp role provided); `desktop` role changes are comment-only relabels (@Desktop, gnome-session, mesa-dri-drivers, llvmpipe intact); hardening still last (dcv immediately before); CIS 2.2.1 override cleanly reverted; carried CRITICAL-1 fully resolved.

**Reviewer B (network / operator / credential lens):** CLEAR. Confirmed: SG TCP+UDP :8443 both gated, :3389 fully removed, :22 absent, egress/IMDSv2 unchanged, `tofu validate` passes; `dcv_endpoint` output correct; credential rename round-trips (publish path == bootstrap-read path == secrets-show path == output), zero vnc residue; operator surface direct-connect-correct, code-server forward retained.

### Carried CRITICAL-1 (from 13-VERIFICATION) — CLOSED
`devbox-secrets-bootstrap.service.j2` now orders `Before=code-server.service dcvserver.service` (was `…xrdp.service xrdp-sesman.service`); `.sh.j2` reads `/devbox/$DEVBOX_USER/desktop-password` and restarts `dcvserver.service`. Ordering chain bootstrap→dcvserver→dcv-virtual-session is sound; `authentication=system` validates PAM at connect time, so chpasswd-before-session timing is fine.

### LOW (documented + deferred to Phase 15 by design — NOT a code change)
**CIS-2.2.1-revert render safety.** The post-hardening W1 guard + the in-role bake assert stat only `/usr/bin/Xdcv`. CIS 2.2.1 removes `xorg-x11-server-common` (cascading to `xorg-x11-server-Xorg`) — **not** Xdcv. If `nice-xdcv` does not hard-require `-common` but the GNOME-on-Xorg session needs X11 shared data it owns, the guard could pass-by-survival while the desktop is silently broken (classic bake-green/desktop-dead).
- **Why not fixed in code:** no static/bake check can prove "GNOME renders without the system Xorg." Every candidate file/package guard is a guess without a live host; worse, asserting `xorg-x11-server-common` *present* is backwards for this posture (the milestone reverted CIS 2.2.1 precisely so it gets removed — DCV is claimed self-contained). Adding a speculative guard risks false-failing a good bake. KISS/YAGNI.
- **Why LOW:** the risk is *documented, not silently assumed* — the W1 guard `fail_msg` (`playbook.yml:85-91`) already names `repoquery --requires nice-xdcv` as the Phase-15 check, and a documented fallback exists (`re-add amzn2023cis_rule_2_2_1: false`).
- **Phase-15 gate:** `repoquery --requires nice-xdcv` (no hidden `-common` dep) AND the GNOME virtual session actually renders. Recorded in `human_verification` above.

## "Enabled and running" — split correctly across bake vs runtime
The bake assert (`dcv/tasks/main.yml:427-443`) runs `systemctl is-enabled dcvserver dcv-virtual-session` and fails the build if either is not enabled at boot — **"enabled" is covered at bake.** "running"/`is-active` is NOT a bake check by design (services don't run during a Packer build; the AMI isn't the final booted instance) — it is a Phase-15 live-UAT check.

## Live-UAT-only residuals (Phase 15 / DCV-11)
CIS-2.2.1-revert render safety (above); direct :8443 TCP+UDP connect within the CIDR; QUIC over UDP; FIPS TLS handshake; SELinux AVC-clean enforcing; `dcvserver`/`dcv-virtual-session` `is-active`; license resolves (S3 path assumed reachable). All need a baked AMI + live instance.

---
_Verified: 2026-06-22 — orchestrator, from two independent opus adversarial reviews (distinct lenses) + hand re-verification of load-bearing claims._
