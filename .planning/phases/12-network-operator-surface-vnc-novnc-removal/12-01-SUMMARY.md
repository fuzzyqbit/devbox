---
phase: 12-network-operator-surface-vnc-novnc-removal
plan: 01
subsystem: infra
tags: [terraform, opentofu, security-group, rdp, xrdp, novnc-removal, ec2, aws]

# Dependency graph
requires:
  - phase: 11-xrdp-remote-desktop
    provides: xrdp/TLS desktop on :3389 (Xorg backend, PAM auth via the ec2-user password published to SSM /devbox/<user>/vnc-password)
  - phase: 02-network-exposure-remediation
    provides: allowlist-gated web ingress pattern (var.allowed_web_cidrs), SSM-first no-:22 posture, empty-list-refusal validation
provides:
  - "EC2 security group ingress for RDP :3389 (TCP), gated on var.allowed_web_cidrs, mirroring the :8080 code-server posture"
  - "Removal of the :6080 noVNC SG ingress (network attack surface retired)"
  - "rdp_endpoint Terraform output (native RDP client / SSM port-forward note; replaces novnc_url)"
  - "noVNC->RDP relabelling across TF outputs + variable descriptions; vnc-password SSM param path retained"
affects: [12-02-ssm-port-forward-rdp, 12-03-vnc-novnc-ansible-removal, RDP-14-live-uat]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "RDP perimeter ingress lives in the EC2 SG, gated on the same var.allowed_web_cidrs allowlist as code-server :8080 (RDP-09)"
    - "RDP endpoint surfaced as a note output (not a browser URL) because RDP needs a native client / SSM tunnel, not a browser"

key-files:
  created: []
  modified:
    - terraform/main.tf
    - terraform/outputs.tf
    - terraform/variables.tf

key-decisions:
  - "Gate :3389 on var.allowed_web_cidrs (mirror :8080) rather than SSM-only — RDP-09 is explicit and locked; SSM path (RDP-10) is complementary and bypasses the SG"
  - "TCP-only :3389 ingress (no UDP 3389) — xrdp's TLS path does not require the UDP transport (research T2 protocol note)"
  - "Retain the SSM param path /devbox/<user>/vnc-password and the output key ssm_vnc_password_param — it IS the RDP/PAM login password (locked credential model); relabel descriptions only, do NOT rename (orphan risk, zero benefit)"
  - "Replace the novnc_url browser-URL output with an rdp_endpoint note output (RDP is not a browser URL)"

patterns-established:
  - "Pattern: swap one allowlist-gated web port for another (6080 noVNC -> 3389 RDP) — net attack-surface reduction with identical Phase-2-approved posture"

requirements-completed: [RDP-09]

# Metrics
duration: ~4min
completed: 2026-06-16
---

# Phase 12 Plan 01: Terraform SG :3389 + noVNC removal Summary

**EC2 security group now permits inbound RDP :3389 gated on `var.allowed_web_cidrs` (mirroring the :8080 code-server ingress) and the :6080 noVNC ingress is gone; all noVNC references scrubbed from the Terraform surface (outputs + variable descriptions), with `novnc_url` replaced by an `rdp_endpoint` note and the vnc-password SSM param path retained.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-06-16T02:01:33Z
- **Completed:** 2026-06-16T02:06:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added a TCP `:3389` RDP ingress to `aws_security_group.devbox`, gated on `var.allowed_web_cidrs` — exact mirror of the existing `:8080` code-server block (description, protocol, cidr_blocks).
- Removed the `:6080` noVNC ingress block (network half of the VNC/noVNC retirement; the weaker noVNC perimeter path is gone).
- Updated the SG header comment from "Web ports (:8080, :6080)" to "Web ports (:8080, :3389)".
- Replaced the `novnc_url` browser-URL output with an `rdp_endpoint` note output (native RDP client / `./run devbox-port-forward 3389` guidance — not a browser URL).
- Relabelled the `ssm_vnc_password_param` description to "RDP/desktop login password (the ec2-user PAM password)" while keeping the value path `/devbox/${var.devbox_user}/vnc-password` and the output key unchanged (no rename cascade).
- Updated the `private_ip`, `associate_public_ip`, `allowed_web_cidrs`, and `allow_open_ingress` descriptions from noVNC -> RDP.
- Verified survivors intact: `:8080` code-server ingress, the no-:22 SSM-first posture, IMDSv2-only metadata, and all-outbound egress are untouched.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add :3389 RDP ingress, drop :6080, update SG header comment** - `7a665e4` (feat)
2. **Task 2: Scrub noVNC from outputs.tf + variables.tf; replace novnc_url with rdp_endpoint; relabel vnc-password output** - `ba59556` (feat)

**Plan metadata:** (final docs commit — this SUMMARY + STATE/ROADMAP/REQUIREMENTS updates)

## Files Created/Modified
- `terraform/main.tf` - Added `:3389` RDP ingress (gated on `var.allowed_web_cidrs`); removed `:6080` noVNC ingress; updated SG header comment.
- `terraform/outputs.tf` - Replaced `novnc_url` with `rdp_endpoint`; relabelled `ssm_vnc_password_param` description (path retained); updated `private_ip` description.
- `terraform/variables.tf` - Updated `associate_public_ip`, `allowed_web_cidrs`, and `allow_open_ingress` descriptions (noVNC -> RDP).

## Decisions Made
- **SG-gated :3389 (not SSM-only):** RDP-09 text is explicit and locked; the SSM port-forward path (RDP-10, plan 12-02) is orthogonal and always works because it bypasses the SG.
- **TCP-only :3389:** mirrored the :8080 `protocol = "tcp"` exactly; no UDP 3389 block (xrdp TLS does not require it).
- **vnc-password param retained, relabelled only:** it is the RDP/PAM login password per the locked credential model; renaming the path or output key would risk an orphan (pre-baked AMIs read the old key) for zero benefit.
- **novnc_url -> rdp_endpoint note (not a URL):** RDP needs a native client or SSM tunnel, so a browser-URL output would be misleading.

## Deviations from Plan

None - plan executed exactly as written.

The only structural nuance: the `:3389` block was created by replacing the `:6080` block in place (which already sat immediately after the `:8080` block at the required insertion point), rather than adding a separate block and then deleting :6080. The resulting file is byte-identical to what the plan's "insert after :117 + delete :119-125" steps would produce, and all acceptance greps pass.

## Issues Encountered
- **Shell verification ergonomics (not a code issue):** the active login shell aborts compound `grep`-based verification chains on the first non-matching `grep` (exit 1). Re-ran each acceptance check as isolated count captures (`grep -c ... || true`) to read the real results. No impact on the deliverable — `tofu fmt -check` (rc=0) and `tofu validate` ("Success! The configuration is valid.") both pass.

## Tooling Verification
- `tofu` v1.10.6 available. `tofu fmt -check` → rc=0 (no diff). `tofu validate` → Success, configuration valid.
- No `changeme` literal introduced in any touched Terraform file (0 matches across main.tf / outputs.tf / variables.tf).
- Acceptance greps: `:3389` present + gated (1); `6080`/`noVNC` residue across main.tf/outputs.tf/variables.tf (0); `:8080` code-server ingress (1); `/devbox/${var.devbox_user}/vnc-password` path retained (1, fixed-string match); `rdp_endpoint` output present (1); `ssm_vnc_password_param` key unchanged (1).

## User Setup Required
None - no external service configuration required. (Live verification of RDP-09 reachability on :3389 is part of the RDP-14 live UAT at milestone close, which requires a bake + `tf-apply` — explicitly out of scope for this implementation plan.)

## Next Phase Readiness
- Plan 12-02 (`./run devbox-port-forward` :3389 + docs for native RDP over SSM) can proceed — it is complementary to this SG change and bypasses the SG.
- Plan 12-03 (Ansible VNC/noVNC stack removal + noVNC username-fix revert) can proceed independently — no file conflict with this Terraform-only change.
- The Terraform surface now contains zero `:6080`/noVNC references; the remaining noVNC residue lives in Ansible, `./run`/scripts, and CLAUDE.md (addressed by later 12-xx plans per the research inventory).

## Self-Check: PASSED

- `terraform/main.tf`, `terraform/outputs.tf`, `terraform/variables.tf` modified and committed.
- `.planning/phases/12-network-operator-surface-vnc-novnc-removal/12-01-SUMMARY.md` FOUND.
- Task commit `7a665e4` FOUND.
- Task commit `ba59556` FOUND.

---
*Phase: 12-network-operator-surface-vnc-novnc-removal*
*Completed: 2026-06-16*
