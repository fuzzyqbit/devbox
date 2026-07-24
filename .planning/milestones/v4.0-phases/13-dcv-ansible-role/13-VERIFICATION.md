---
phase: 13-dcv-ansible-role
verified: 2026-06-19
status: passed
status_note: "Bake-config CLEAR after opus adversarial review + CRITICAL-2 fix. The dcv role installs (airgap get_url+GPG+sha256, 3 non-GPU RPMs), configures dcv.conf (authentication=system, web-port=8443, QUIC on, no cert key, no create-session=true), delivers the FIPS cert as files at /etc/dcv/dcv.{pem,key} dcv:dcv 0600 (asserted path+owner+mode+SAN), creates a VIRTUAL session via a oneshot unit now wired with an explicit GNOME-on-Xorg --init launcher (CRITICAL-2 fix), relabels SELinux, is wired before hardening, and a RDP-13-grade bake assert proves it all. DCV-01..05 met at bake-config level. Live render/AVC/FIPS/license = Phase 15 UAT (DCV-11)."
score: DCV-01..05 bake-config verified; adversarial CLEAR after CRITICAL-2 fix
overrides_applied: 0
human_verification:
  - test: "DCV-11 (Phase 15 live UAT) — direct :8443 connect renders the GNOME virtual session + license resolves + AVC-clean under enforcing + FIPS TLS handshake"
    expected: "GNOME desktop renders (not blank/Wayland); login as ec2-user via PAM; no AVC; license OK"
    why_human: "Needs a baked AMI on a live instance + the SG (Phase 14) + the assumed S3 license path. Recorded at Phase 15."
---

# Phase 13: `dcv` Ansible Role — Verification Report

**Phase Goal:** A new `dcv` role installs+configures Amazon DCV (non-GPU) on AL2023 — airgap install, dcv.conf (auth=system, :8443, QUIC on), a virtual GNOME session, FIPS-safe cert + SELinux relabel, enabled service wired before hardening, with a bake assert. Requirements DCV-01..05.
**Verified:** 2026-06-19 (authored from opus adversarial-review evidence + a hand gate battery — per the milestone's "static verifier not trustworthy for infra" lesson; see feedback_adversarial_verify_infra)
**Status:** PASSED (bake-config) — adversarial CLEAR after the CRITICAL-2 GNOME-init fix.

## Requirements Coverage

| Req | Status | Evidence |
|-----|--------|----------|
| DCV-01 install (airgap, non-GPU) | SATISFIED | `dcv` role ports 51c5f1f base: `rpm_key` import of canonical `d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY` (not the PII-mangled token) BEFORE dnf; pinned `get_url` + deferred sha256; installs nice-dcv-server + nice-xdcv (globbed build) + nice-dcv-web-viewer + policycoreutils-python-utils; no GPU pkgs; no `--nogpgcheck`. (17b3a6b) |
| DCV-02 dcv.conf | SATISFIED | `authentication="system"`, `web-port=8443`, `enable-quic-frontend=true`; no `certificate=` key; `create-session=true` only in a "deliberately NOT setting" comment. Bake assert greps all three keys + asserts `authentication="none"`/`create-session=true` absent. (17b3a6b/e0f698a) |
| DCV-03 virtual session + GNOME | SATISFIED | oneshot `dcv-virtual-session.service` runs `dcv create-session --type virtual --owner ec2-user --init /etc/dcv/dcv-gnome-session.sh` (After/Requires=dcvserver). The `--init` GNOME-on-Xorg launcher (XDG_SESSION_TYPE=x11, llvmpipe software render, dbus-launch gnome-session) was added to close adversarial CRITICAL-2 (would otherwise render blank/Wayland). (17b3a6b + c13ad6d) |
| DCV-04 service + wiring + assert | SATISFIED | `- role: dcv` wired before `hardening` (grep-gate=1), gated `layers.dcv and layers.desktop`; `dcv: true` toggle; both units enabled; RDP-13-grade bake assert (binary + dcv.conf keys + session unit + cert + init script + is-enabled). xrdp left intact (Phase 14 removes it). (2b98793/e0f698a/c13ad6d) |
| DCV-05 SELinux + FIPS cert | SATISFIED | FIPS cert (RSA-2048/-sha256/SAN) as FILES at `/etc/dcv/dcv.{pem,key}` `dcv:dcv` `0600` (gen runs AFTER the RPM creates the `dcv` user; idempotent `creates:` guard); bake assert verifies path+owner+0600+SAN. SELinux restorecon over the DCV install paths before hardening. (f98dd7a/e0f698a) |

## Adversarial Review (opus) — VERDICT after fix: CLEAR (bake-config)

Confirmed sound: cert ordering (after RPM user-create), cert path/owner/mode/SAN + idempotency + assert, GPG canonical + before install, dcv.conf keys, fail-closed binary-path stats, dcv.conf INI dialect, port fidelity vs 51c5f1f (strict superset).

Findings:
- **CRITICAL-2 (CLOSED, c13ad6d):** virtual session had no `--init` → DCV's default-init would try the GNOME/Wayland default desktop, which Xdcv can't host → blank desktop, green bake. Fixed: shipped `/etc/dcv/dcv-gnome-session.sh` (GNOME-on-Xorg, software render), wired `--init`, defensive `WaylandEnable=false`, extended the bake assert to prove the init script present+executable + referenced by the unit.
- **CRITICAL-1 (CARRIED → Phase 14):** the `devbox-secrets-bootstrap` unit orders `Before=…xrdp` not `dcvserver`. Low severity for DCV (authentication=system reads the live OS password via PAM at connect time — no restart needed; only a negligible first-boot-race window before a human UAT). Phase 14 rewrites that unit (xrdp→dcv) and MUST add `dcvserver.service`/`dcv-virtual-session.service` to its `Before=`. Recorded as a Phase-14 requirement.
- **RISK-1 (live-UAT):** SELinux relabel is best-effort (globs, failed_when:false); AVC-clean boot under enforcing is provable only at Phase 15.

## Live-UAT-only residuals (Phase 15 / DCV-11)
GNOME actually rendering in the virtual session; AVC-clean boot under SELinux enforcing; FIPS TLS handshake on :8443; QUIC data path; DCV licensing (S3 path — assumed reachable). All need a baked AMI + live instance + the Phase-14 SG.

## Carried to Phase 14
1. **CRITICAL-1:** secrets-bootstrap unit must order before + (re)handle `dcvserver` when it swaps xrdp→dcv.
2. **nice-xdcv vs CIS 2.2.1:** before reverting `amzn2023cis_rule_2_2_1`, verify `nice-xdcv` does not depend on `xorg-x11-server-common` (else the revert silently breaks DCV).

---
_Verified: 2026-06-19 — orchestrator, from opus adversarial-review evidence + hand gate battery._
