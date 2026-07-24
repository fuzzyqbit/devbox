---
phase: 14-direct-connect-sg-removal-cis-revert-operator
plan: 01
subsystem: terraform-security-group
tags: [terraform, security-group, dcv, network-perimeter]
requires: []
provides: [":8443 TCP+UDP DCV ingress gated on var.allowed_web_cidrs", "dcv_endpoint output"]
affects: [terraform/main.tf, terraform/outputs.tf, terraform/variables.tf]
tech-stack:
  added: []
  patterns: ["mirror the :8080 ingress block for the two :8443 blocks", "delimiter-bound port descriptions"]
key-files:
  created: []
  modified: [terraform/main.tf, terraform/outputs.tf, terraform/variables.tf]
decisions:
  - "Kept the SSM credential path as /devbox/<user>/desktop-password (the credential was already renamed vnc-password→desktop-password in commit 47f68f4; the plan's vnc-password references were stale — preserving the live path avoids orphaning bootstrap/secrets-show, per Anti-Pattern B)"
  - "Added :8443 UDP (QUIC) alongside :8443 TCP per DCV-06; supersedes the older ARCHITECTURE.md TCP-only line which assumed SSM tunneling"
metrics:
  duration: ~25m (combined wave)
  completed: 2026-06-19
---

# Phase 14 Plan 01: Terraform Security Group DCV Cutover Summary

Flipped the Terraform SG from the obsolete xrdp `:3389` ingress to direct-connect Amazon DCV `:8443` (TCP + UDP/QUIC), both gated on `var.allowed_web_cidrs`, and renamed `rdp_endpoint`→`dcv_endpoint`.

## What changed

- **terraform/main.tf**: dropped the `:3389` RDP ingress block; added a `:8443` TCP block and a `:8443` UDP block, both mirroring the existing `:8080` block's structure and gating on `var.allowed_web_cidrs`. Updated the SG header comment `:8080, :3389`→`:8080 code-server, :8443 DCV TCP+UDP`. `:8080`, egress-all, `:22` absence, and `create_before_destroy` untouched.
- **terraform/outputs.tf**: renamed `rdp_endpoint`→`dcv_endpoint` (value `https://<ip>:8443`, DCV web/native client, direct in-CIDR — no port-forward); relabeled `private_ip` desc `code-server/RDP`→`code-server/DCV`; relabeled `ssm_desktop_password_param` desc `RDP/desktop`→`DCV/desktop`. The `/devbox/<user>/desktop-password` SSM path is preserved.
- **terraform/variables.tf**: relabeled three descriptions (`associate_public_ip`, `allowed_web_cidrs`, `allow_open_ingress`) RDP/:3389→DCV/:8443; no logic/validation changes.

## Verification

- `tofu validate` → `Success! The configuration is valid.`
- `:8443` TCP+UDP gated on `var.allowed_web_cidrs`; `protocol = "(tcp|udp)"` count = 3 (8080 tcp + 8443 tcp + 8443 udp); zero `3389` in main.tf.
- `output "dcv_endpoint"` present; no `rdp_endpoint`/`RDP`/`3389` in outputs.tf or variables.tf.

## Deviations from Plan

**1. [Rule 1 - Bug] SSM credential path is `desktop-password`, not `vnc-password`**
- **Found during:** Task 2 (outputs/variables edit)
- **Issue:** The plan referenced `rdp_endpoint`, `ssm_vnc_password_param`, and a `/devbox/<user>/vnc-password` SSM path. The actual tree already had `ssm_desktop_password_param` / `/devbox/<user>/desktop-password` (the credential was renamed in commit 47f68f4 before these plans were re-checked).
- **Fix:** Preserved the live `desktop-password` path everywhere (renaming would orphan bootstrap + secrets-show — Anti-Pattern B). Relabel-only on the descriptions.
- **Files modified:** terraform/outputs.tf
- **Commit:** 2dcbe60

## Self-Check: PASSED
- terraform/main.tf, outputs.tf, variables.tf modified — verified in commit 2dcbe60.
- Commit 2dcbe60 verified via `git rev-parse`.
