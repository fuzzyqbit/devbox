# Project Research Summary

**Project:** devbox v4.0 — Amazon DCV remote desktop
**Domain:** Replace xrdp/VNC with Amazon DCV on a CIS-hardened (SELinux enforcing + FIPS), airgapped, SSM-port-forward-only, single-operator AL2023 EC2
**Researched:** 2026-06-18
**Confidence:** HIGH (5 pitfalls reproduced and fixed live this session; install/license/architecture from official AWS DCV admin guide and verified in-repo git history)

---

## Executive Summary

Amazon DCV can be installed on this devbox and is the right replacement for the abandoned xrdp stack. The install is straightforward: three RPMs (`nice-dcv-server`, `nice-dcv-web-viewer`, `nice-xdcv`) pulled from AWS CloudFront (`d1uj6qtbmh3dt5.cloudfront.net`) at bake time via the existing `get_url` + NICE GPG key + sha256 pattern — identical in kind to the repo's existing ffmpeg/helm/mise downloads. The prior DCV role (reverted at `d3bd9a0`, recoverable from git `51c5f1f`) is the proven foundation; the code largely already exists. The critical session model choice is **virtual session** (via `nice-xdcv` / `Xdcv`), not console: it avoids Wayland/gdm/seat0 fragility, dodges the CIS 2.2.1 X-server exception, and was the model the prior role used successfully.

The **make-or-break dependency is the runtime license path**, not the install. DCV on EC2 is free, but the `dcvserver` daemon periodically GETs a license object from the regional S3 bucket `dcv-license.<region>`. On this private, no-public-internet instance that GET fails unless two things are in place: (1) an S3 gateway VPC endpoint associated with the instance subnet's route table, and (2) `s3:GetObject` on `arn:aws:s3:::dcv-license.<region>/*` on the instance profile. These are both Terraform additions, not bake steps. The 15-day grace period means the AMI bakes and the instance appears healthy — the failure surfaces only at `dcv create-session` on a long-running private instance. This is exactly what killed the prior attempt. **Front-load the Terraform licensing infra in the roadmap before the live UAT gate.**

The operator experience is browser-native: `./run devbox-port-forward 8443` opens an SSM TCP tunnel; the operator points a browser at `https://localhost:8443` and authenticates with the existing `ec2-user` password from SSM (the same credential the xrdp phase used). QUIC (UDP) must be disabled (`enable-quic-frontend=false`) because SSM port-forwarding is TCP-only — DCV 2024.0+ enables QUIC by default, which is the canonical "auth works, screen never paints" failure. The security posture improves on xrdp: by using a virtual session the repo can revert the sole accepted CIS Level-2 deviation (`amzn2023cis_rule_2_2_1: false`) and delete the post-hardening Xorg guard, re-closing the gap that xrdp forced open.

---

## Key Findings

### Recommended Stack

DCV is installed from a versioned tarball (not AL2023 repos, not GitHub — neither carries the RPMs). The pinned release is `2025.0-20103` for server and web-viewer, `2025.0-688` for `nice-xdcv` (the build numbers are independent — do not reuse `20103` for xdcv). The NICE GPG key is imported from the same CloudFront host before the `dnf install` so RPM signature verification runs. Supporting OS packages (GNOME `@Desktop`, `mesa-dri-drivers`, fonts) are already present from the existing `desktop` role and require no new installation. `nice-dcv-gl`, `nice-dcv-gltest`, `nice-dcv-simple-external-authenticator`, and `xorg-x11-drv-dummy` are all omitted — GPU-only or external-auth-only packages irrelevant to this non-GPU single-operator box.

**Core technologies:**
- `nice-dcv-server` 2025.0.20103: the `dcvserver` daemon and `dcv` CLI — required
- `nice-xdcv` 2025.0.688: the `Xdcv` virtual X server for headless sessions — required for virtual model
- `nice-dcv-web-viewer` 2025.0.20103: the browser web client served by dcvserver on `:8443` — required for zero-install UX
- GNOME desktop (`@Desktop` group via AL2023 dnf): the desktop the virtual session renders — already installed by `desktop` role
- AWS S3 gateway VPC endpoint + IAM `s3:GetObject` on `dcv-license.<region>/*`: the runtime license path — Terraform additions, make-or-break

### Expected Features

All four researchers converge on the same MVP surface. There are no feature disagreements.

**Must have (table stakes for "open browser, log in, see GNOME"):**
- Auto-created virtual session that renders GNOME after every boot — DCV creates no session by default; a `dcv-virtual-session.service` oneshot systemd unit creates it
- PAM `authentication=system` — delegates to `ec2-user` OS password already set and published by the `secrets` role; no new credential
- Session `owner=ec2-user` with stock `/etc/dcv/default.perm` — owner granted full access out of the box; no perms file authoring needed
- QUIC disabled (`enable-quic-frontend=false`) — UDP cannot traverse `AWS-StartPortForwardingSession`; must be explicit because DCV 2024.0+ enables QUIC by default
- SG TCP `:8443` gated on `var.allowed_web_cidrs`; drop xrdp `:3389` — TCP-only; UDP `:8443` omitted
- FIPS-clean TLS cert on `:8443` — DCV auto-generates a cert but it may not satisfy FIPS; replace with RSA-2048/sha256/SAN cert in the `dcv` role
- S3 gateway VPC endpoint + IAM `s3:GetObject` — runtime license path (Terraform); front-loaded
- Full removal of xrdp role, its `playbook.yml` block, `test-xrdp.yml`, and the post-hardening Xorg guard
- Revert CIS `amzn2023cis_rule_2_2_1: false` — virtual sessions use `Xdcv`, not system Xorg; the exception becomes unnecessary (confirm at live UAT)
- `./run devbox-port-forward 8443` docs; `secrets-show` label relabeled to "DCV login"; `run`/scripts 3389 to 8443
- colord polkit `.rules` allow — reuse the xrdp `45-allow-colord.rules`; GNOME session hangs without it

**Should have (differentiators — defer to v4.x):**
- Custom CA TLS cert (drop-in `dcv.pem`/`dcv.key` in `/etc/dcv/`; hot-reload >=2022.0) — trigger: operator fatigue with browser trust warning
- SG-open direct `:8443` CIDR path — trigger: SSM latency becomes painful

**Defer (v5+ or probably never for this box):**
- QUIC + UDP `:8443` — only meaningful on a direct non-SSM path
- `nice-dcv-gl` GPU OpenGL — requires a GPU instance
- Native DCV viewer (USB redirect, multi-monitor, smart cards) — breaks zero-install promise
- DCV Session Manager / Connection Gateway / collaboration — enterprise fleet tooling; one-operator-one-box

**Anti-features (never enable):**
- `authentication=none` — passwordless desktop; catastrophic
- QUIC enabled + UDP `:8443` in SG — no benefit over SSM; widens attack surface
- Renaming the `vnc-password` SSM parameter — hard-coded in 4+ places; creates orphans for zero gain

### Architecture Approach

The architectural work splits cleanly into bake-time (Ansible `dcv` role) and runtime (Terraform license infra). The `dcv` role ports from git `51c5f1f` and slots into `playbook.yml` between `desktop` and `hardening` — the same slot xrdp occupied — preserving the hardening-stays-last invariant. A oneshot systemd unit (`dcv-virtual-session.service`) creates the virtual session after `dcvserver` starts; this is more observable than the `dcv.conf` auto-create path (which supports console sessions only — auto-create via config does not support virtual sessions). The repo does not own its VPC, so the S3 gateway endpoint route-table association uses `data "aws_route_table" { subnet_id = var.subnet_id }` (Option B, least operator burden) with `var.route_table_id` as an override for edge cases.

**Major components:**

1. `dcv` Ansible role (NEW — port from `51c5f1f`) — GPG import, tarball download + checksum, three-RPM install, `dcv.conf` template, `dcv-virtual-session.service` oneshot, `dcvserver.service` enable, `restorecon`, FIPS-clean cert generation, colord polkit `.rules`, PAM `/etc/pam.d/dcv` delegate, post-hardening bake asserts
2. Terraform license infra (NEW — additions to `terraform/main.tf`) — `aws_vpc_endpoint.s3` (Gateway type, free), `aws_vpc_endpoint_route_table_association`, `s3:GetObject` IAM statement on `aws_iam_role.devbox`; add `:8443` TCP SG ingress, drop `:3389`
3. xrdp removal sweep (DELETE/EDIT across Ansible + Terraform + operator surface) — `ansible/roles/xrdp/` deleted, `playbook.yml` block + Xorg post-guard deleted, CIS `2.2.1` override reverted, secrets bootstrap restart list updated, `run`/scripts relabeled 3389 to 8443, completeness greps run
4. Live UAT gate — the only place that can confirm: license resolves past 15-day grace, GNOME virtual session renders over `./run` SSM forward, SELinux AVC-clean under enforcing, FIPS TLS handshake completes, colord/PAM/noexec-mounts all pass

### Critical Pitfalls

All five highest-severity pitfalls were reproduced and confirmed live this session.

1. **Airgap license — `ORIGIN_OBJECT_MISSING`** — The make-or-break. DCV on EC2 is free but requires `dcvserver` to periodically GET from `dcv-license.<region>` over S3. Private instance with no public internet = silent failure after 15-day grace. Fix: S3 gateway VPC endpoint on the instance subnet's route table + `s3:GetObject` IAM on the instance role. Front-load in Terraform before the live UAT.

2. **No session on boot** — DCV creates zero sessions by default on Linux; a listening server with no session is useless. Fix: oneshot systemd unit `dcv create-session --type virtual --owner ec2-user ec2-user-session` (preferred, and the only option for virtual) or `[session-management] create-session=true` in `dcv.conf` (console-only auto-create, simpler but virtual cannot use this).

3. **QUIC hang over SSM ("auth works, screen never paints")** — DCV 2024.0+ enables QUIC (UDP `:8443`) by default. SSM `AWS-StartPortForwardingSession` is TCP-only; the data channel never establishes. Fix: `enable-quic-frontend=false` in `dcv.conf`; do NOT open UDP `:8443` in the SG for the SSM posture.

4. **SELinux AVCs under enforcing** — The `hardening` role reboots into SELinux enforcing after `dcv` installs. DCV ships no SELinux policy module. AVCs on `dcvserver` agent, session-launcher exec, or `/var/run/dcv` sockets silently kill session creation while `dcvserver.service` appears active. Fix: `restorecon -RvF` over DCV install paths in the role; live-UAT gate `ausearch -m AVC -ts boot`; generate scoped `audit2allow` module if denials appear. Never `setenforce 0`.

5. **FIPS TLS handshake rejection** — DCV's auto-generated self-signed cert may lack a SubjectAltName or use SHA-1; under FIPS the handshake fails and the web client cannot load. Fix: generate a FIPS-clean cert in the `dcv` role (`openssl req -x509 -newkey rsa:2048 -sha256 -addext "subjectAltName=DNS:devbox"`); bake-assert SAN + RSA>=2048 + sha256; live-confirm `openssl s_client -connect localhost:8443` completes under FIPS.

Proven transfers from xrdp v3.2 (11-VERIFICATION.md):
- CIS 2.2.1 exception already disabled in `hardening/defaults/main.yml`; virtual sessions do not need system Xorg, so this exception can be reverted (confirm at live UAT)
- colord polkit: reuse `45-allow-colord.rules` (`.pkla` ignored on AL2023 polkit 121+; must be `.rules`)
- `/tmp` + `/dev/shm` noexec live-check: DCV runtime dirs are under `/var/run/dcv`; `/dev/shm` noexec can bite X MIT-SHM; verify post-bake

---

## Implications for Roadmap

The work has four natural phases driven by the dependency order: bake-time install, runtime license infra, cleanup/removal/revert, end-to-end live validation. Phases A and C can partially overlap (role development and xrdp removal are independent), but Phase B (Terraform license infra) must precede Phase D (live UAT) because the UAT cannot prove licensing without the endpoint and IAM in place.

### Phase A — `dcv` Ansible Role (bake-time)

**Rationale:** The role is the foundation everything else builds on; the prior role (`51c5f1f`) is 80% of the work. Port it, add the gaps the prior attempt missed (FIPS cert, colord `.rules`, PAM delegate, bake asserts), and establish a green bake under the 15-day grace.
**Delivers:** An AMI that installs DCV, creates a virtual session unit, and passes all bake-time asserts — GPG-verified install, pinned version, FIPS-clean cert, SELinux relabel, `dcvserver` + `dcv-virtual-session` enabled, `authentication=system` / `enable-quic-frontend=false` / `create-session` asserted in `dcv.conf`.
**Addresses:** Table-stakes features — virtual session, PAM auth, QUIC-off, TLS-on, colord, PAM delegate.
**Avoids:** Pitfalls 2 (no session), 4 (QUIC hang), 7 (FIPS TLS), 8-colord (GNOME hangs), 9 (airgap install).

Key implementation notes:
- Port role skeleton from `git show 51c5f1f:ansible/roles/dcv/`
- Pin `dcv_version: "2025.0"`, `dcv_build_server: "20103"`, `dcv_build_xdcv: "688"` — build numbers differ, do not reuse one for the other
- Import NICE GPG key from `https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY` before dnf; keep `disable_gpg_check: false`
- `get_url` with `checksum: sha256:<pin>` — fill after first bake (deferred-pin pattern, CLAUDE.md §9)
- Session model: virtual (`dcv create-session --type virtual --owner ec2-user`) via oneshot unit — dodges Wayland/seat0/gdm entirely; auto-create via `dcv.conf` is console-only and cannot be used here
- `dcv.conf` must assert: `authentication=system`, `enable-quic-frontend=false`, FIPS-clean cert paths, `web-port=8443`
- Generate FIPS-clean self-signed cert in the role (RSA-2048 / sha256 / SAN `DNS:devbox`) — copy the xrdp cert-gen task
- Reuse `45-allow-colord.rules` from xrdp role (`.rules` format, not `.pkla`)
- `restorecon -RvF` over DCV install paths after RPM install
- Do not install `nice-dcv-gl`, `nice-dcv-gltest`, `nice-dcv-simple-external-authenticator`, `xorg-x11-drv-dummy`
- The `!= "changeme"` assert in the PAM-password check is a known pre-commit hook false-positive (prior role carried it; annotate or handle the gate)

**Research flag:** No deeper research needed. Install mechanism, session model, and cert recipe are all verified. Port from proven prior code.

### Phase B — Terraform License Infra + SG Update (runtime)

**Rationale:** This is the make-or-break phase. Without the S3 gateway endpoint and IAM `s3:GetObject`, no DCV session starts past the 15-day grace. Must be in place before the live UAT gate.
**Delivers:** A running instance that licenses itself from `dcv-license.<region>`, has `:8443` TCP open in the SG, and has `:3389` removed.
**Uses:** `data "aws_route_table"` data source (Option B — derives the subnet's route table without a new required var); `var.route_table_id` override for edge cases.

Key implementation notes:
- Add `aws_vpc_endpoint.s3` (type `Gateway`, `com.amazonaws.<region>.s3`) to `terraform/main.tf`
- Add `aws_vpc_endpoint_route_table_association.s3` using `data "aws_route_table" { subnet_id = var.subnet_id }.id`
- Append IAM statement `s3:GetObject` on `arn:aws:s3:::dcv-license.${data.aws_region.current.name}/*` to the existing inline policy on `aws_iam_role.devbox` — derive region from data source, never hardcode
- Add SG ingress `:8443` TCP gated on `var.allowed_web_cidrs` (mirror the `:8080` block); do NOT add UDP `:8443`
- Delete SG ingress `:3389` block
- Update `terraform/outputs.tf`: `rdp_endpoint` to `dcv_endpoint` with URL `https://<ip>:8443`; relabel `ssm_vnc_password_param` description to "DCV login password" (keep param name and path unchanged)
- Update `terraform/variables.tf` descriptions that reference `:3389`/RDP to `:8443`/DCV
- Endpoint policy defaults to allow-all — ship the default (KISS); document optional tightening
- Use `data.aws_region.current.name` everywhere the license bucket region appears

**Research flag:** Route-table association is the one correctness risk. Data-source Option B resolves it for the common case; validate at UAT with `aws ec2 describe-route-tables`. No new research needed.

### Phase C — xrdp/VNC Removal + CIS Revert + Operator Surface

**Rationale:** Clean removal of the stopgap stack and re-closing the CIS deviation it forced. Can proceed in parallel with Phase A. The CIS 2.2.1 revert should be confirmed at the Phase D live UAT before being committed as permanent.
**Delivers:** No dead remote-desktop config in the image; CIS Level-2 deviation reverted (pending UAT confirmation); operator surface (`./run`, scripts, CLAUDE.md) updated to DCV.

Removal inventory (from ARCHITECTURE.md — all items mapped to file:line):
- DELETE `ansible/roles/xrdp/` (12 files)
- DELETE `ansible/playbook.yml:59-63` (xrdp role block) and `:68-90` (post-tasks Xorg guard)
- DELETE `ansible/test-xrdp.yml`
- EDIT `ansible/layer_config.yml:21-22`: `xrdp: true` to `dcv: true`
- EDIT `ansible/roles/hardening/defaults/main.yml:28-37`: delete/revert `amzn2023cis_rule_2_2_1: false` override + comment (conditional on Phase D UAT confirming Xdcv renders without system Xorg)
- EDIT `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:67`: restart list `xrdp.service xrdp-sesman.service` to `dcvserver.service dcv-virtual-session.service`
- EDIT `devbox-secrets-bootstrap.service.j2:5`: `Before=...xrdp...` to `Before=dcvserver.service`
- EDIT secrets role comments: "RDP/xrdp" to "DCV" — keep all logic and the `vnc-password` param path
- EDIT `run:470`, `:522`, `:392-394`, `:516-518`: "RDP login" to "DCV login (ec2-user @ :8443)"
- EDIT `scripts/devbox-start.sh:70,72` and `scripts/devbox-status.sh:54,61`: 3389 to 8443
- EDIT `ansible/firewalld-docker-fix.yml:6`: comment "(…, RDP :3389)" to "DCV :8443"
- EDIT CLAUDE.md: references to RDP/:3389 to DCV/:8443; add DCV troubleshooting entry

Post-removal completeness greps:
```bash
git grep -nIE 'xrdp|xorgxrdp|3389' -- ':!.planning/**' | grep -vE 'vnc-password|!= "changeme"'
git grep -nIE 'tigervnc|vncserver|novnc|/etc/pam\.d/vnc|6080' -- ':!.planning/**'
test ! -d ansible/roles/xrdp && echo "xrdp role gone"
grep -A5 'from_port   = 8443' terraform/main.tf | grep -q 'var.allowed_web_cidrs' && echo OK
grep -q 'dcv-license' terraform/main.tf && echo OK
```

**Research flag:** No research needed. This is mechanical removal using a complete inventory. CIS revert confirmation is a live-UAT gate.

### Phase D — Live UAT Gate (milestone-close)

**Rationale:** Several properties (license past grace, SELinux AVC cleanliness under enforcing, FIPS TLS handshake, CIS 2.2.1 revert safety) can only be confirmed on a live private instance. Bake assertions establish "is configured"; UAT establishes "actually works." Phase B must be applied before running this gate.
**Delivers:** DCV proven end-to-end on a live private instance — the gate the prior DCV attempt and the xrdp RDP-14 UAT never cleared.

UAT checklist:
- [ ] `dcv list-sessions` shows the virtual session after boot (Pitfall 2)
- [ ] `./run devbox-port-forward 8443` then browser `https://localhost:8443` then DCV web client loads (Pitfall 4)
- [ ] Log in as `ec2-user` with `./run secrets-show` password; GNOME virtual session renders (Pitfalls 1, 8)
- [ ] `aws s3 ls s3://dcv-license.<region>/` from the instance succeeds via the VPC endpoint (Pitfall 1)
- [ ] `grep -i 'ORIGIN_OBJECT_MISSING\|no license\|no session' /var/log/dcv/server.log` is empty (Pitfall 1)
- [ ] `ausearch -m AVC -ts boot | grep dcv` is empty (Pitfall 6 / SELinux)
- [ ] `openssl s_client -connect localhost:8443` handshake completes under FIPS (Pitfall 7)
- [ ] `openssl x509 -in /etc/dcv/dcv.pem -noout -text` shows SAN present, RSA>=2048, sha256 (Pitfall 7)
- [ ] `mount | grep -E '/tmp|/dev/shm'` — if noexec: confirm DCV/X/GNOME components do not exec from those mounts (Pitfall 8)
- [ ] GNOME colord prompt does not appear or hang the session (Pitfall 8 / colord)
- [ ] `grep -E 'authentication|enable-quic|no-tls' /etc/dcv/dcv.conf` shows system / false / TLS-on (Pitfall 11)
- [ ] CIS 2.2.1 revert confirmed safe: Xdcv renders GNOME virtual session without `xorg-x11-server-Xorg` installed; if confirmed, commit the revert; if not, document the fallback

**Research flag:** No research needed. This is validation, not design.

---

### Phase Ordering Rationale

- A before D: AMI must be baked before the instance can be booted and validated.
- B before D: The license endpoint and IAM must exist before any session validates post-grace.
- A and C can overlap: The `dcv` role is developed independently of the xrdp removal sweep. Having both ready to merge together is cleaner than sequential.
- D gates the CIS 2.2.1 revert: Logically part of Phase C but the safety confirmation is a Phase D live test. If D confirms the revert is safe, Phase C's deletion of the override is committed; if not, a fallback is documented.

### Research Flags

No phase needs additional research. All four researchers converged on HIGH-confidence findings backed by the official AWS DCV admin guide, live empirical validation, and direct repo file inspection.

The one item to handle at implementation time (not a research gap): the `dcv_tarball_sha256` pin in `ansible/roles/dcv/defaults/main.yml` is intentionally left empty on first bake (deferred-pin convention from CLAUDE.md §9). Fill after the first successful bake using `sha256sum nice-dcv-2025.0-20103-amzn2023-x86_64.tgz` and commit before merging.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Exact RPM names, build numbers, CloudFront URLs verified against amazondcv.com download index and official AWS adminguide; prior role in git history is a working implementation |
| Features | HIGH | All session/auth/connectivity/TLS claims from official AWS DCV admin guide; SSM-TCP-only QUIC implication confirmed live |
| Architecture | HIGH | All file:line references read directly from the repo; VPC/subnet/route-table external-var posture confirmed in `terraform/variables.tf`; prior role architecture recoverable from git history |
| Pitfalls | HIGH | 5 of 11 pitfalls reproduced and fixed live this session (empirical); remaining 6 directly transfer from xrdp v3.2 adversarial findings in `11-VERIFICATION.md` or verified against official docs |

**Overall confidence:** HIGH

### Gaps to Address

- **`dcv_tarball_sha256` pin:** Empty by design on first bake; fill after first successful bake before merging the role. Known deferred-pin pattern (CLAUDE.md §9), not a gap in understanding.
- **CIS 2.2.1 revert safety:** MEDIUM-HIGH confidence the virtual session (`Xdcv`) does not need system Xorg; confirmed by AWS docs. Confidence becomes HIGH after Phase D live UAT. If UAT fails this check, fallback: keep Xorg installed and leave the override with updated documentation.
- **S3 gateway endpoint policy:** Shipped as allow-all (KISS). Optionally tighten to `dcv-license.<region>` + any other S3 services traversing the endpoint (dnf, SSM buckets if applicable). Post-validation hardening step, not a correctness requirement.
- **`/tmp` / `/dev/shm` noexec interaction:** Theoretically moderate risk; DCV runtime dirs avoid `/tmp`. Confirm at live UAT with `mount | grep -E '/tmp|/dev/shm'` and a connect test; relocate any offending tmpdir with `TMPDIR=/var/tmp` if needed.

---

## Sources

### Primary (HIGH confidence — official AWS docs, verified 2026-06-18)

- https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html — AL2023 RPM names, builds (server 20103, xdcv 688), GPG import, required-vs-optional package split
- https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html — virtual vs console sessions, XDummy for console only, Mesa software GL, Wayland unsupported
- https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-license.html — IAM `s3:GetObject` on `dcv-license.{region}/*`, S3 gateway VPC endpoint, 15-day grace, IMDS requirement, partition variants
- https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-start.html — no auto-session on Linux; `dcv create-session` syntax; auto-console-session config (console only; virtual cannot use this)
- https://docs.aws.amazon.com/dcv/latest/adminguide/disable-quic.html — QUIC default-on since 2024.0; `[connectivity] enable-quic-frontend=false`; auth over WebSocket, data over QUIC/UDP
- https://docs.aws.amazon.com/dcv/latest/adminguide/security-authentication.html — `authentication=system` default, PAM `/etc/pam.d/dcv`
- https://docs.aws.amazon.com/dcv/latest/adminguide/security-authorization.html — stock `default.perm` grants owner full access
- https://docs.aws.amazon.com/dcv/latest/adminguide/manage-cert.html — auto-generated `dcv.pem`/`dcv.key`, `/etc/dcv/`, `dcv`-owned, `600`, hot-reload >=2022.0
- https://www.amazondcv.com/ — download index confirming latest = 2025.0, server build 20103, AL2023 x86_64 tarball (~41 MB)

### Primary (HIGH confidence — repo-internal, read at file:line)

- `git show 51c5f1f` / `67faeb3` / `df9f098` — the proven prior DCV role (install, session, dcv.conf, handlers)
- `git show d3bd9a0` — revert message confirms the blocker was the runtime license path, not the install
- `.planning/phases/11-service-config-pam-session-bake-verification/11-VERIFICATION.md` — adversarial findings from xrdp that transfer (FIPS cert SAN, SELinux AVC, `.pkla` to `.rules`, colord, pam_loginuid, software render OK)
- `ansible/roles/hardening/defaults/main.yml` — CIS 2.2.1 exception already set; FIPS and SELinux enforcing confirmed in the hardening role
- `ansible/roles/xrdp/` — transferable patterns: FIPS-clean cert task with SAN, `semanage fcontext` + restorecon, colord `.rules`, PAM-delegate, bake-assert structure
- `terraform/main.tf`, `variables.tf`, `outputs.tf` — confirmed no `aws_vpc`/`aws_subnet`/`aws_route_table` resources; external `var.vpc_id`/`var.subnet_id`; existing SG/IAM/instance-profile structure

### Secondary (MEDIUM confidence)

- https://repost.aws/questions/QU64puCu8OSySAzLNPJuTRPA/unable-to-license-dcv — `ORIGIN_OBJECT_MISSING` root causes confirmed (endpoint + IAM)
- https://repost.aws/articles/ARq0LbVvRwTRukVpS6Zt1uZw/ — DCV + GNOME on AL2023 practical notes
- github.com/aws-samples/amazon-ec2-nice-dcv-samples — negative finding: confirms no GitHub RPM release; samples download from CloudFront

### Empirical (HIGH confidence — live this session)

- Pitfalls 1 through 5 reproduced and fixed on a running instance: license `ORIGIN_OBJECT_MISSING` (endpoint+IAM fix confirmed), no-session-by-default (oneshot unit confirmed), console Wayland/seat0 (virtual session avoidance confirmed), QUIC hang over SSM (`enable-quic-frontend=false` confirmed), dcv-gl benign message (non-issue confirmed)

---
*Research completed: 2026-06-18*
*Ready for roadmap: yes*
