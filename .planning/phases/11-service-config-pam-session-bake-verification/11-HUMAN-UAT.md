---
status: partial
phase: 11-service-config-pam-session-bake-verification
source: [11-VERIFICATION.md]
started: 2026-06-16
updated: 2026-06-16
---

## Current Test

[awaiting human testing — requires `./run build` + a running EC2 instance with :3389 reachable]

The Phase 11 bake-config is adversarially CLEAR (3 review rounds; no remaining
bake-fixable green-but-broken blocker). The tests below are the runtime properties
that are *inherently* unprovable at bake-config time and gate RDP-14 / milestone close.

## Tests

### UAT-1 — Live RDP login → GNOME renders (RDP-14, milestone-close gate)
**Steps:**
1. `DEVBOX_USER=$(whoami) ./run build` (bakes the AMI with the xrdp role)
2. `./run tf-apply && ./run start`
3. Open `:3389` (Phase 12 SG ingress + `./run` port-forward) from a native RDP client
   (mstsc / FreeRDP / Remmina) to `localhost:3389`
4. Authenticate as `ec2-user` with the password from `./run secrets-show`
**Expected:** GNOME desktop renders; no "Access denied"; no black screen; no
color-manager auth popup hanging the session; `id` in a terminal shows `ec2-user`.

### UAT-2 — SELinux enforcing: no xrdp/Xorg AVC denials
**Steps:** On the running instance: `getenforce` → `Enforcing`; then
`ausearch -m avc -ts boot 2>/dev/null | grep -i 'xrdp\|xorg'` (or `journalctl -b | grep -i 'avc.*denied'`).
**Expected:** No AVC denials for xrdp / xrdp-sesman / Xorg. (Mitigation in place:
`xrdp_exec_t` fcontext on the source-built `/usr/local/sbin` binaries; this confirms
the confined-domain transition actually works under enforcing.)

### UAT-3 — FIPS TLS handshake on :3389
**Steps:** Confirm FIPS (`fips-mode-setup --check` / `sysctl crypto.fips_enabled`),
then complete an RDP TLS handshake from the client (UAT-1 connecting proves it).
**Expected:** TLS handshake completes under the kernel FIPS provider; no cert/digest
rejection. (Cert is RSA-2048 + sha256 + `subjectAltName=DNS:devbox`.)

### UAT-4 — Service health on a cold boot
**Steps:** `systemctl is-active xrdp xrdp-sesman` after a reboot.
**Expected:** Both `active` (sesman boot-race fixed: no StopWhenUnneeded/BindsTo;
WantedBy=multi-user.target).

## Notes
- firewalld host allow for :3389 and the EC2 security-group ingress are **Phase 12**
  deliverables (network/operator surface). UAT-1 depends on Phase 12 being applied.
- All four tests require live AWS — they cannot be run from the controller workstation
  alone. Record results here before closing the v3.2 milestone.
