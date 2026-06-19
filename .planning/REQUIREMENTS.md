# Requirements — Milestone v4.0 Amazon DCV Remote Desktop

**Goal:** Replace the remote-desktop stack with **Amazon DCV**. A new `dcv` Ansible role installs/configures `dcvserver` on AL2023; **vncserver, noVNC, and xrdp/xorgxrdp are removed entirely.** Branch: `feat/dcv`.

**Credential model:** the DCV login is the existing `ec2-user` PAM password the `secrets` role generates per build, publishes to SSM (`/devbox/<user>/vnc-password`), and the boot bootstrap applies via `chpasswd`. DCV `authentication=system` validates it through PAM. No new secret; SSM param path unchanged (relabelled only).

**Access posture (CHANGED for DCV):** DCV is reached by **direct connect** — TCP **and** UDP `:8443` — gated on `var.allowed_web_cidrs`. **No SSM/SSH tunneling.** `:22` stays absent; the CIDR allowlist is the perimeter (same model as the `:8080` code-server ingress). QUIC is **enabled** (needs UDP), which is viable precisely because access is direct, not SSM-tunneled.

**Supersedes:** v3.2 (xrdp, code-complete; RDP-14 live UAT was the only open gate). v3.2 records retained under `.planning/phases/10–12/` + git history (`main` through `5ad3309`).

---

## Assumptions / External Prerequisites (NOT built by this milestone)

- **DCV license path is assumed reachable.** Operator decision (v4.0): the regional S3 license bucket `dcv-license.<region>` is reachable from the instance and the instance can `s3:GetObject` it (via an S3 VPC endpoint + IAM already present in the target environment). This milestone does **NOT** provision the S3 gateway VPC endpoint or the IAM grant.
  - ⚠ **Residual risk (documented, not silent):** if the target env lacks the route **or** the `s3:GetObject` permission, `dcvserver` fails to license with `ORIGIN_OBJECT_MISSING` after the 15-day grace — the exact failure that scrapped DCV in `d3bd9a0`. The live UAT (DCV-11) must confirm licensing resolves; if it does not, the endpoint + IAM become a follow-up.

---

## v4.0 Requirements

### DCV Server (Ansible role)

- [x] **DCV-01**: A new `dcv` role installs the **non-GPU** DCV server package set for AL2023 x86_64 — `nice-dcv-server`, `nice-dcv-web-viewer`, `nice-xdcv` — via a version-pinned `get_url` from the AWS DCV download host (CloudFront) with the `NICE-GPG-KEY` imported and a sha256 checksum verified. No `nice-dcv-gl` / GPU packages. Airgap-compliant: no S3-for-install, no private mirror, no `--nogpgcheck`.
- [x] **DCV-02**: `dcv.conf` is configured — `authentication=system` (PAM), TLS on (self-signed cert), **QUIC enabled** (`enable-quic-frontend=true`), `web-port=8443`, session owner `ec2-user`.
- [x] **DCV-03**: A DCV **virtual** session (`nice-xdcv` / Xdcv) is created at boot rendering the GNOME desktop owned by `ec2-user` (DCV does not auto-create — configured via dcv.conf auto-session and/or a oneshot unit). No GPU/GL — software rendering.
- [x] **DCV-04**: `dcvserver` is an enabled systemd service; the `dcv` role is wired into `ansible/playbook.yml` strictly **before** `hardening` (hardening-stays-last invariant preserved); a bake-time assertion proves the DCV binaries + session config are present.
- [x] **DCV-05**: DCV survives the hardened baseline — SELinux relabel (+ AVC-clean) and a FIPS-safe self-signed TLS cert (RSA-2048 / sha256 / SAN), reusing the v3.2 cert + relabel recipe.

### Network / Security Group (direct connect)

- [x] **DCV-06**: The security group exposes `:8443` **TCP and UDP** gated on `var.allowed_web_cidrs` (UDP required for QUIC; direct connect, no SSM tunnel); the xrdp `:3389` ingress is dropped; `:22` absence, IMDSv2-only metadata, and egress are unchanged.

### Removal (xrdp + VNC)

- [x] **DCV-07**: The `xrdp`/`xorgxrdp` role, its `playbook.yml` wiring + layer toggle, the post-hardening Xorg `post_task` guard, `ansible/test-xrdp.yml`, and the vendored `xorg.conf` are removed.
- [x] **DCV-08**: The CIS 2.2.1 X-server exception (`amzn2023cis_rule_2_2_1: false` in `hardening/defaults`) is reverted — DCV virtual sessions use `Xdcv`, not the system Xorg — confirmed safe at the live UAT.
- [x] **DCV-09**: All VNC/noVNC and xrdp remnants are removed across ansible/terraform/run/scripts — no dead remote-desktop config in the image (repo-wide completeness check).

### Operator Surface

- [x] **DCV-10**: `secrets-show` + operator docs target **direct DCV `:8443` connect** (browser at `https://<host>:8443` or native client, within the allowed CIDR) — no `./run` port-forward step for DCV. The `ec2-user` SSM credential is kept (path unchanged), labels updated noVNC/RDP→DCV.

### Live UAT (milestone-close gate)

- [ ] **DCV-11**: A documented runtime UAT on a live instance: bake → apply → connect **directly** (TCP+UDP `:8443`, within the allowed CIDR) as `ec2-user` → the GNOME virtual session renders **and** the license resolves; SELinux AVC-clean under enforcing; FIPS TLS handshake completes; QUIC path works; the CIS 2.2.1 revert confirmed safe. Recorded before the milestone closes.

---

## Future Requirements (deferred)

- GPU acceleration (`nice-dcv-gl` + driver) for GPU instance types.
- Provision the S3 license path in-repo (VPC endpoint + scoped IAM) if the target env stops providing it.
- DCV native-client packaging/docs, file transfer, multi-monitor, collaboration/Session Manager.
- Custom CA-issued TLS cert (drop-in replacing the self-signed).
- Optional SSM port-forward path for `:8443` TCP (QUIC would not tunnel) as a fallback access method.

## Out of Scope

- `authentication=none` / public (0.0.0.0) ingress — security posture forbids; the CIDR allowlist + PAM remain the boundary.
- Provisioning the S3 license endpoint/IAM (assumed reachable — see Assumptions).
- Keeping any xrdp/VNC/noVNC path "as fallback" — the milestone removes them entirely.
- Re-running the v3.2 RDP-14 UAT — xrdp is retired, not validated further.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DCV-01 | Phase 13 | Complete |
| DCV-02 | Phase 13 | Complete |
| DCV-03 | Phase 13 | Complete |
| DCV-04 | Phase 13 | Complete |
| DCV-05 | Phase 13 | Complete |
| DCV-06 | Phase 14 | Complete |
| DCV-07 | Phase 14 | Complete |
| DCV-08 | Phase 14 | Complete |
| DCV-09 | Phase 14 | Complete |
| DCV-10 | Phase 14 | Complete |
| DCV-11 | Phase 15 | Pending |

**Coverage:** 11/11 v4.0 requirements mapped, each to exactly one phase. No orphans, no duplicates.
