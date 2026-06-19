# Architecture Research

**Domain:** AWS IaC remote-desktop integration — replacing the xrdp/VNC desktop stack with Amazon DCV (new `dcv` Ansible role + S3-VPC-endpoint/IAM license path) on a Packer/Ansible-baked AL2023 AMI provisioned by OpenTofu.
**Researched:** 2026-06-18
**Confidence:** HIGH (repo-internal evidence read at file:line; DCV behaviour confirmed against official AWS docs; the prior DCV role recovered from git history is the proven foundation)

> **Headline finding — the work is mostly already done once.** A complete, syntax-verified `dcv` role already existed in git history (commits `df9f098`/`67faeb3`/`8538ef3`, quick-task `260611-jq2`) and was reverted **solely** because the regional S3 license bucket was unreachable in the airgapped VPC (`d3bd9a0`: "license unobtainable in airgap"). DCV was then **re-validated working live** this session once the license path was understood. v4.0 = **port that proven role back** + **add the license infra it was missing** (S3 gateway VPC endpoint + IAM `s3:GetObject`) + **remove xrdp** (which v3.2 added as the stopgap). This research maps both halves against the *actual* current `terraform/` and `ansible/`.

---

## Standard Architecture

### System Overview

```
┌───────────────────────────────────────────────────────────────────────┐
│  BAKE TIME (Packer + Ansible)            ansible/playbook.yml roles[]    │
├───────────────────────────────────────────────────────────────────────┤
│  base→…→secrets→vscode→desktop→[ dcv ]→hardening(LAST,invariant)         │
│                          │        │                                     │
│              GNOME(@Desktop) │     │ installs nice-dcv-server, nice-xdcv,│
│              gnome-session   │     │ nice-dcv-web-viewer (tarball/RPM);  │
│                              │     │ /etc/dcv/dcv.conf (auth=system,     │
│   secrets role ──────────────┘     │ web-port 8443); dcv-virtual-session │
│   ec2-user PAM pw → SSM             │ systemd unit; enable dcvserver;     │
│   /devbox/<u>/vnc-password          │ SELinux relabel                     │
│                                     ▼                                     │
│                          DCV runs VIRTUAL session → its own Xdcv X server │
│                          (NOT the system /usr/libexec/Xorg)               │
└───────────────────────────────────────────────────────────────────────┘
            │ AMI handoff (data aws_ami filter at tofu apply)
            ▼
┌───────────────────────────────────────────────────────────────────────┐
│  RUNTIME (OpenTofu — terraform/)                                         │
├───────────────────────────────────────────────────────────────────────┤
│  aws_instance.devbox (private subnet, IMDSv2, instance profile)          │
│     ├─ aws_security_group.devbox                                         │
│     │     ingress :8080 code-server  (var.allowed_web_cidrs)  KEEP       │
│     │     ingress :8443 DCV TCP       (var.allowed_web_cidrs)  ADD       │
│     │     ingress :8443 DCV UDP       (only IF QUIC)           OPTIONAL   │
│     │     ingress :3389 xrdp                                   REMOVE     │
│     │     egress all (SSM channels)                            KEEP      │
│     ├─ aws_iam_role.devbox + inline policy                               │
│     │     ssm:GetParameter on /devbox/<u>/*   KEEP                       │
│     │     kms:Decrypt (ViaService ssm)        KEEP                       │
│     │     s3:GetObject on dcv-license.<region>/*   ADD  ◄── make-or-break │
│     │     + AmazonSSMManagedInstanceCore (managed)  KEEP                 │
│     └─ NEW: aws_vpc_endpoint.s3 (Gateway) + route-table association ◄──── │
│              so the PRIVATE instance can reach the regional license bucket│
└───────────────────────────────────────────────────────────────────────┘
            │ DCV server periodically GETs dcv-license.<region>/… over the
            ▼ S3 gateway endpoint, authorised by the IAM s3:GetObject stmt
        Operator: ./run devbox-port-forward 8443  → SSM tunnel → DCV web/native client
                  (or, CIDR allowlisted, https://<private-ip>:8443 directly)
```

### Component Responsibilities

| Component | Responsibility | Implementation (this repo) |
|-----------|----------------|----------------------------|
| `dcv` Ansible role (NEW) | Install DCV server/xdcv/web-viewer; write `dcv.conf`; create + enable the virtual session; enable `dcvserver`; SELinux relabel | Port `ansible/roles/dcv/` from git `51c5f1f` (defaults/tasks/handlers + 2 templates). Runs **between `desktop` and `hardening`** |
| `desktop` role (EXISTING) | Provide GNOME (`@Desktop`, `gnome-shell`, `gnome-session`, fonts, mesa) for the DCV virtual session to render | `ansible/roles/desktop/tasks/main.yml:4-20`. DCV needs this — gate `dcv` on `layers.desktop` |
| `secrets` role (EXISTING) | Generate the `ec2-user` PAM password, publish to SSM, apply at boot via `chpasswd` | `ansible/roles/secrets/`; `dcv.conf` `authentication="system"` reuses this PAM credential — **no new secret** |
| `hardening` role (EXISTING) | CIS Level-2 baseline; **MUST stay last** (grep-gate + CLAUDE.md §8) | `ansible/roles/hardening/`. DCV role inserts before it, identical to where `xrdp` sits today |
| `aws_security_group.devbox` (EXISTING, edit) | Network perimeter: gate desktop/web ports on `var.allowed_web_cidrs`; no public `:22` | `terraform/main.tf:106-142`. Add :8443, drop :3389 |
| `aws_iam_role.devbox` + policy (EXISTING, edit) | Instance entitlements: SSM param read, KMS decrypt, SSM core | `terraform/main.tf:33-95`. Add `s3:GetObject` on the license bucket |
| `aws_vpc_endpoint.s3` (NEW) | Let the **private** instance reach the regional DCV license bucket without internet | New resource in `terraform/main.tf` (Gateway type, associated to the instance subnet's route table) |
| `./run` + `scripts/` (EXISTING, edit) | Operator surface: port-forward, secrets-show, status/start banners | `run`, `scripts/devbox-{start,status}.sh`. Swap 3389→8443; relabel "RDP login" → "DCV login" |

---

## Recommended Project Structure

### Ansible — the new `dcv` role (port from git `51c5f1f`)

```
ansible/roles/dcv/
├── defaults/main.yml                       # dcv_version/dcv_build pins, dcv_web_port: 8443,
│                                           #   dcv_tarball_sha256 (pin after first bake), dev_user/home
├── tasks/main.yml                          # assert PAM pw set → import NICE GPG → download tarball
│                                           #   (checksum-gated) → extract → install 3 RPMs →
│                                           #   template dcv.conf → template + enable session unit →
│                                           #   enable dcvserver → SELinux relabel → cleanup
├── handlers/main.yml                       # reload systemd
└── templates/
    ├── dcv.conf.j2                          # [security] authentication="system"
    │                                        # [connectivity] web-port={{ dcv_web_port }}
    │                                        # [session-management] create-session=true (see Pattern 3)
    └── dcv-virtual-session.service.j2       # oneshot: dcv create-session --type virtual --owner ec2-user
```

### Terraform — license infra additions (all in `terraform/main.tf`; vars/outputs adjacent)

```
terraform/
├── main.tf            # EDIT SG (add :8443 / drop :3389); EDIT IAM policy (add s3:GetObject);
│                      # ADD aws_vpc_endpoint.s3 (Gateway) + aws_vpc_endpoint_route_table_association
├── variables.tf       # EDIT allowed_web_cidrs/associate_public_ip/allow_open_ingress descriptions
│                      #   (":3389"→":8443"); ADD var.route_table_id (or data-source it — see below)
└── outputs.tf         # EDIT rdp_endpoint → dcv_endpoint; relabel ssm_vnc_password_param description
```

### Structure Rationale

- **`dcv` role between `desktop` and `hardening`:** byte-identical placement to the current `xrdp` role (`playbook.yml:59`). DCV's virtual session needs GNOME (desktop role) and PAM auth (secrets role, gated on vscode-or-desktop), and **must** finish before `hardening` so SELinux relabels and any config land before CIS locks the box — and so the hardening-stays-last invariant holds.
- **License infra in Terraform, not Ansible:** licensing is a **runtime** dependency (the server periodically GETs the bucket), not a bake step. The bake succeeds without it (DCV ships a 15-day grace — see Pitfall 1), but a long-lived instance needs the endpoint+IAM. This is exactly why v4.0 lists it as "first-class scope" and why the old role failed only at **runtime** licensing, not at bake.
- **Gateway endpoint (not Interface):** S3 gateway endpoints are free, route-table-based, and the AWS DCV docs explicitly prescribe a **gateway** endpoint for no-internet instances. An interface endpoint would cost money and is unnecessary for S3.

---

## Architectural Patterns

### Pattern 1: License-via-Gateway-Endpoint + scoped IAM (the make-or-break)

**What:** The DCV server auto-detects EC2 and periodically fetches a license object from the regional bucket `dcv-license.<region>`. For a **private** instance, two things must both be true: (a) a network path to S3 — an **S3 Gateway VPC endpoint** associated with the instance subnet's route table; and (b) an IAM grant — `s3:GetObject` on `arn:aws:s3:::dcv-license.<region>/*` on the instance profile.
**When to use:** Always, for this repo — the devbox is private-only (`associate_public_ip` default `false`, `variables.tf:51-55`; reached via SSM + VPC-internal routes).
**Trade-offs:** Gateway endpoint is free and low-risk but is **route-table-scoped** — it only helps subnets whose route table is associated. Get the route table wrong and licensing silently fails after the 15-day grace.

**Example (Terraform — add to `terraform/main.tf`):**
```hcl
# IAM: append to the existing inline policy statements in aws_iam_role_policy.devbox_ssm_read
{
  Sid      = "ReadDcvLicense"
  Effect   = "Allow"
  Action   = "s3:GetObject"
  Resource = "arn:aws:s3:::dcv-license.${data.aws_region.current.region}/*"
}

# Network: S3 gateway endpoint + associate the instance subnet's route table
data "aws_subnet" "devbox" { id = var.subnet_id }   # to derive the VPC + route table

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-s3-gw" })
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = var.route_table_id   # SEE "VPC/route-table reality" below
}
```

> **Endpoint policy:** an S3 gateway endpoint defaults to a **full-access** endpoint policy (`{"Action":"*","Resource":"*","Principal":"*"}`). That default already allows the license GET. You may optionally tighten it to allow only `s3:GetObject` on `dcv-license.<region>/*` — but the **instance IAM policy** is the authoritative gate, so a restrictive endpoint policy is belt-and-braces, not required. Recommendation: ship the default endpoint policy (KISS); document the optional tightening.

### Pattern 2: PAM credential reuse (no new secret)

**What:** `dcv.conf` sets `authentication="system"`, so DCV authenticates against the OS PAM stack — i.e. the `ec2-user` password the `secrets` role already generates, publishes to `/devbox/<u>/vnc-password`, and applies via `chpasswd` at boot (`devbox-secrets-bootstrap.sh.j2:32-34,56`).
**When to use:** This repo's locked credential model — exactly what xrdp used (`/etc/pam.d/xrdp-sesman` → `password-auth`). DCV just consumes the same `ec2-user` password through PAM.
**Trade-offs:** Keeps the entire secrets pipeline untouched (generate/publish/bootstrap/IAM ARN/`secrets-show`). The only debt is the **cosmetic** SSM param name `vnc-password` — keep it (renaming creates orphans; the IAM ARN is a wildcard, but the path is hard-coded in 4+ places). Relabel human-facing strings "RDP/VNC login" → "DCV login".

**Example (the prior role's assert — port verbatim, reword the comment):**
```yaml
- name: Assert the PAM login password was set by the secrets role
  ansible.builtin.assert:
    that: [ desktop_vnc_password is defined, desktop_vnc_password | length > 0,
            desktop_vnc_password != "changeme" ]
  no_log: true
```
> Note: this `!= "changeme"` line is a known pre-existing `no-changeme` hook false-positive (the prior role carried it; it mirrors the surviving secrets-role asserts). It is acceptable — see Pitfalls.

### Pattern 3: Headless virtual session via oneshot systemd unit

**What:** DCV does **not** auto-create a session. A oneshot systemd unit (`After=dcvserver.service`, `Requires=dcvserver.service`) runs `dcv create-session --type virtual --owner ec2-user ec2-user-session` at boot.
**When to use:** Headless cloud desktop with no physical console — exactly this box.
**Trade-offs:** Virtual session starts **DCV's own Xdcv X server**, NOT the system `/usr/libexec/Xorg`. This is the single most consequential difference from xrdp (see the CIS 2.2.1 decision below). Two valid mechanisms exist — pick one, don't do both:
1. **Oneshot unit** (the prior role's choice, `dcv-virtual-session.service.j2`) — explicit, observable, easy to assert.
2. **`dcv.conf` `[session-management] create-session=true` + `owner`** — DCV auto-creates on service start. Fewer moving parts.

**Recommendation:** keep the **oneshot unit** (proven, matches the prior role, gives a clean bake-assert target `systemctl is-enabled dcv-virtual-session`). Confirm at the live UAT that the session actually renders GNOME.

### Pattern 4: Airgap-tolerant download with deferred sha256 pin

**What:** Download the DCV tarball from the AWS CDN (`d1uj6qtbmh3dt5.cloudfront.net`) with an **optional** sha256 (`dcv_tarball_sha256` empty until pinned), mirroring the `xrdp`/`devops`/`devtools` get_url convention. Install RPMs from the extracted tarball.
**When to use:** Consistent with the project's "download-based, sha256-pinned, no S3-for-install, no private mirror" airgap posture (PROJECT.md v4.0 target features).
**Trade-offs:** The deferred-pin is a known stub (CLAUDE.md §9 pattern). Pin after first bake. NICE GPG key import (`rpm_key`) gates RPM signature verification — keep `disable_gpg_check: false`.

---

## Data Flow

### License acquisition flow (runtime — the thing that was broken)

```
dcvserver.service starts
    ↓ detects EC2 via IMDS (IMDSv2 already enforced, main.tf:155-160)
    ↓ resolves regional bucket  dcv-license.<region>
    ↓ S3 GET over the S3 Gateway VPC endpoint  (NEW aws_vpc_endpoint.s3)
    ↓ authorised by instance-profile  s3:GetObject on dcv-license.<region>/*  (NEW IAM stmt)
    ↓
License valid → `dcv create-session` succeeds → operator connects
(Without endpoint+IAM: 15-day grace, then ORIGIN_OBJECT_MISSING / "no license available")
```

### Operator connect flow

```
./run devbox-port-forward 8443           (run:379-435 — ALREADY accepts any port, no code change)
    ↓ AWS-StartPortForwardingSession over SSM data channel (does NOT traverse the SG)
    ↓
localhost:8443 → DCV web client (browser) or native DCV client
    ↓ authenticate as ec2-user with the /devbox/<u>/vnc-password (./run secrets-show)
    ↓ PAM (authentication="system") validates → GNOME virtual session renders
```
Alternative (CIDR-allowlisted operator): `https://<private-ip>:8443` directly through the SG ingress.

### Key Data Flows

1. **Credential flow (unchanged):** secrets role generates → SSM SecureString → boot oneshot `chpasswd` → PAM → DCV `authentication="system"`. Same chain xrdp used.
2. **AMI handoff (unchanged):** Packer manifest → `data "aws_ami"` filter → `tofu apply`. The new `dcv` layer just changes what's baked in.

---

## VPC / Subnet / Route-table reality (the endpoint's hard dependency)

**The repo does NOT create a VPC.** It consumes an **existing/external** one:

- `variable "vpc_id"` (no default — required) `terraform/variables.tf:23-26`
- `variable "subnet_id"` (no default — required) `terraform/variables.tf:28-31`
- `aws_instance.devbox.subnet_id = var.subnet_id` `terraform/main.tf:150`
- `aws_security_group.devbox.vpc_id = var.vpc_id` `terraform/main.tf:109`

There is **no `aws_vpc`, `aws_subnet`, or `aws_route_table` resource anywhere in `terraform/`** — the operator supplies a pre-existing VPC + subnet (consistent with the "lives inside a private VPC reached over peering/DX/VPN" model, CLAUDE.md §4 Step 2).

**Implication for the gateway endpoint:** the endpoint must associate with **the route table that the instance's subnet uses**. The repo currently knows only the subnet ID, not its route table. Three options:

| Option | Mechanism | Trade-off |
|--------|-----------|-----------|
| **A (recommended)** | Add `variable "route_table_id"` (operator supplies it, same pattern as `vpc_id`/`subnet_id`) | Explicit, no fragile lookups; one more required var. Matches the repo's "operator supplies network" convention. |
| B | `data "aws_route_table" { subnet_id = var.subnet_id }` to discover it | Zero new vars, but fails if the subnet has no explicit association (falls back to the **main** route table — `data.aws_route_table` does resolve the main table in that case, so this is usually fine). |
| C | Associate the VPC's **main** route table via `data "aws_vpc" { id = var.vpc_id }` + `aws_vpc.main_route_table_id` | Works only if the instance subnet uses the main table; brittle. |

**Recommendation: Option B as the default (data-source the subnet's route table — least operator burden), with Option A (`var.route_table_id`) as an override** for operators whose subnet routing is unusual. Flag this as the single most important correctness decision for the license phase — a wrong route table = silent license failure after 15 days.

---

## CIS rule 2.2.1 X-server exception — RE-EVALUATE: can be REVERTED with DCV virtual sessions

This is a load-bearing decision the question explicitly asks for.

**Background (current state):** `amzn2023cis_rule_2_2_1: false` in `ansible/roles/hardening/defaults/main.yml:37`. CIS 2.2.1 removes `xorg-x11-server-common` (a dep of `xorg-x11-server-Xorg`). xrdp's xorgxrdp backend exec's the **system** `/usr/libexec/Xorg` (`sesman.ini` `param=/usr/libexec/Xorg`), so the rule had to be disabled or hardening would delete xrdp's X server. A `post_tasks` guard in `playbook.yml:68-90` asserts `/usr/libexec/Xorg` survived hardening.

**DCV virtual sessions are different.** A DCV **virtual** session starts **`Xdcv`** — DCV's own bundled X server (shipped by the `nice-xdcv` RPM, lives under the DCV install path, not `/usr/libexec/Xorg`). Confirmed by AWS docs: *"With virtual sessions, Amazon DCV starts an X server instance, Xdcv, and runs a desktop environment."* The prior role installed `nice-xdcv` and created a **virtual** session — it never referenced `/usr/libexec/Xorg`.

**Therefore:**
- If v4.0 uses **virtual** sessions (recommended, matches the prior proven role) → the system Xorg is **not** required → **CIS 2.2.1 can be REVERTED** (`amzn2023cis_rule_2_2_1` back to its CIS default / removed from the override) **AND** the `post_tasks` Xorg guard (`playbook.yml:68-90`) can be **deleted**. This is a security *win* — it re-closes the single accepted Level-2 deviation.
- If v4.0 ever switched to **console** sessions (captures the existing system desktop screen, needs the system Xorg) → the exception would have to **stay**. Console is single-session, Windows-or-Linux, root-managed — not what the prior role or the headless model wants.

**Recommendation: use virtual sessions and REVERT the CIS 2.2.1 exception + delete the Xorg post_tasks guard.** Caveat to verify at the live UAT: confirm `Xdcv` actually starts the GNOME virtual session without pulling the system Xorg. There is a known DCV-on-Linux nuance where some setups still want `xorg-x11-server-Xorg` present for GLX/`mesa-dri-drivers`; if the UAT shows the virtual session needs it, the fallback is to **keep `xorg-x11-server-Xorg` installed but leave CIS 2.2.1 enabled** only if it does not delete what DCV uses — flag as the one item that must be confirmed live before declaring the exception revertible. (Confidence: MEDIUM-HIGH that revert is correct; the live UAT is the gate.)

---

## Removal Inventory — xrdp + VNC remnants (complete; reuse the Phase-12 pattern)

> Legend — **DELETE** (whole file/block), **EDIT** (surgical), **KEEP** (listed to prove considered).

### Ansible — xrdp role + wiring
| # | Artifact | Path : line | Action | Risk |
|---|----------|-------------|--------|------|
| X1 | Entire `xrdp` role | `ansible/roles/xrdp/` (12 files: defaults, tasks, handlers, 3 templates, 6 files incl. vendored `xorg.conf`, PAM, systemd units, polkit rules) | DELETE dir | Self-contained; nothing else imports it |
| X2 | `- role: xrdp` block + when + comment | `ansible/playbook.yml:59-63` | DELETE | The `dcv` role replaces this slot |
| X3 | post_tasks Xorg guard (stat + assert, 2 tasks) | `ansible/playbook.yml:68-90` | DELETE | Only needed because xrdp used system Xorg; DCV virtual uses Xdcv |
| X4 | `xrdp: true` layer toggle + comment | `ansible/layer_config.yml:21-22` | EDIT → `dcv: true` | Add the new toggle, drop xrdp |
| X5 | CIS 2.2.1 override + its explanatory comment | `ansible/roles/hardening/defaults/main.yml:28-37` | DELETE (revert exception) | See CIS section above — virtual sessions don't need system Xorg. **Verify at live UAT.** |
| X6 | `test-xrdp.yml` top-level test playbook | `ansible/test-xrdp.yml` | DELETE | xrdp-specific test harness |
| X7 | secrets bootstrap restart loop names `xrdp.service xrdp-sesman.service` | `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:67` | EDIT → `code-server.service dcvserver.service dcv-virtual-session.service` | Else dead unit names + DCV pw-rotation won't restart the session |
| X8 | secrets bootstrap service `Before=...xrdp...` | `devbox-secrets-bootstrap.service.j2:5` | EDIT → `Before=code-server.service dcvserver.service` | Cosmetic-but-correct ordering |
| X9 | secrets comments mentioning xrdp/RDP/PAM | `secrets/defaults/main.yml:4`, `publish.yml:39,42`, `bootstrap.sh.j2:52-53,65` | EDIT comments | Reword "RDP/xrdp" → "DCV". KEEP all logic + the `vnc-password` param path |
| X10 | desktop role comments referencing "GNOME-over-RDP" / "RDP connection" | `desktop/tasks/main.yml:14,23`; `handlers/main.yml:3` | EDIT comments | Cosmetic; the GNOME install + screensaver-disable + handler all KEEP (DCV needs them) |

> **VNC remnants:** v3.2 already removed the VNC/noVNC stack (Phase 12 RDP-11/12; `tigervnc-server`, `vncserver.service`, `novnc.service`, `/etc/pam.d/vnc`, `xstartup`, the noVNC install, `novnc-plain-username-fix.yml`). A completeness grep (below) confirms nothing VNC-functional survives. The only residue is the **intentional** `vnc-password` SSM param name (keep) and the two `!= "changeme"` secrets asserts (keep).

### Terraform
| # | Artifact | Path : line | Action |
|---|----------|-------------|--------|
| T1 | `:3389` xrdp ingress block | `terraform/main.tf:119-125` | DELETE |
| T2 | `:8443` DCV TCP ingress (mirror :8080) | `terraform/main.tf` (insert after :117) | ADD |
| T3 | `:8443` DCV UDP ingress (QUIC) | `terraform/main.tf` | ADD **only if** QUIC enabled in dcv.conf — recommend NOT (TCP-only, matches prior role) |
| T4 | SG comment "Web ports (:8080, :3389)" | `terraform/main.tf:99-104` | EDIT → ":8080, :8443" |
| T5 | `rdp_endpoint` output | `terraform/outputs.tf:21-24` | EDIT → `dcv_endpoint` ("https://<ip>:8443 — DCV web/native client, or ./run devbox-port-forward 8443") |
| T6 | `ssm_vnc_password_param` output desc "RDP/desktop login" | `terraform/outputs.tf:41-44` | EDIT desc → "DCV login password"; KEEP key + value path |
| T7 | `private_ip` output desc "...code-server/RDP..." | `terraform/outputs.tf:6-9` | EDIT → DCV |
| T8 | var descriptions naming `:3389`/RDP | `variables.tf:54,66,82` (associate_public_ip / allowed_web_cidrs / allow_open_ingress) | EDIT → ":8443"/DCV |
| T9 | IAM `s3:GetObject` license statement | `terraform/main.tf:53-78` (append to policy) | ADD (Pattern 1) |
| T10 | `aws_vpc_endpoint.s3` + route-table association | `terraform/main.tf` (new) | ADD (Pattern 1) |

### Operator surface + docs
| # | Artifact | Path : line | Action |
|---|----------|-------------|--------|
| O1 | `cmd_devbox_port_forward` port logic | `run:379-435` | KEEP — already accepts 8443; edit only the inline example comments (`run:392-394`) and help block (`run:516-518`) 3389→8443 |
| O2 | `cmd_secrets_show` label "RDP login (ec2-user @ <host>:3389)" | `run:470` | EDIT → "DCV login (ec2-user @ <host>:8443)" |
| O3 | `secrets-show` help "code-server and RDP login passwords" | `run:522` | EDIT → "DCV login" |
| O4 | `secrets-show` SSM fetch of `/devbox/<u>/vnc-password` | `run:458-466` | KEEP path; only label (O2) changes |
| O5 | `scripts/devbox-start.sh:70,72` "RDP desktop :3389" | `scripts/devbox-start.sh` | EDIT → DCV :8443 |
| O6 | `scripts/devbox-status.sh:54,61` "RDP desktop :3389" | `scripts/devbox-status.sh` | EDIT → DCV :8443 |
| O7 | `firewalld-docker-fix.yml:6` comment "(…, RDP :3389)" | `ansible/firewalld-docker-fix.yml` | EDIT comment → "DCV :8443"; body unchanged (sets zone=docker; no per-port rule) |
| O8 | CLAUDE.md §1/§4/§5/§7 RDP/:3389 references | `CLAUDE.md` | EDIT → DCV :8443, native/web DCV client over SSM; add a DCV-connect troubleshooting entry |

### Completeness greps (run after removal)
```bash
# No xrdp/3389/xorgxrdp functional artifacts remain (allow the kept vnc-password path + secrets asserts):
git grep -nIE 'xrdp|xorgxrdp|3389' -- ':!.planning/**' | grep -vE 'vnc-password|!= "changeme"'   # expect: empty
git grep -nIE 'tigervnc|vncserver|novnc|/etc/pam\.d/vnc|6080' -- ':!.planning/**'                  # expect: empty
test ! -d ansible/roles/xrdp && echo "xrdp role gone"
# hardening still last (grep-gate #9):
[ "$(grep -E '^[[:space:]]*-[[:space:]]*role:' ansible/playbook.yml | tail -1 | grep -c 'hardening')" -eq 1 ] && echo OK
# :8443 ingress gated on allowlist; :8080 kept; IAM license stmt present:
grep -A5 'from_port   = 8443' terraform/main.tf | grep -q 'var.allowed_web_cidrs' && echo OK
grep -q 'dcv-license' terraform/main.tf && echo OK
```

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1 operator / 1 instance (this project) | Single virtual session, oneshot create. No license server, no Connection Gateway — EC2 auto-licensing is sufficient. This is the entire design envelope. |
| Multiple sessions on one box | DCV supports multiple virtual sessions; not in scope (single-operator model, PROJECT.md Out of Scope). |
| GPU acceleration | Console session + GPU instance would be needed; out of scope. Virtual session is CPU-rendered, fine for a dev desktop. |

**First bottleneck:** none architectural for one operator. The realistic failure mode is **operational**: the license route-table association being wrong (silent 15-day failure) — covered by Pitfall 1.

---

## Anti-Patterns

### Anti-Pattern 1: Treating licensing as a bake-time step (or abandoning DCV over it)
**What people do:** Conclude "the bake can't reach the license bucket, so DCV is unusable in airgap" — exactly what happened in `d3bd9a0`.
**Why it's wrong:** Licensing is a **runtime** check with a **15-day grace**. The bake succeeds regardless. The fix is runtime infra (endpoint + IAM), not a bake change.
**Do this instead:** Keep the role download-based; add the S3 gateway endpoint + `s3:GetObject` IAM in Terraform so the running instance licenses itself. (This is the v4.0 thesis.)

### Anti-Pattern 2: Associating the S3 gateway endpoint with the wrong route table
**What people do:** Create the endpoint, associate it with the VPC main route table, assume done.
**Why it's wrong:** Gateway endpoints are route-table-scoped. If the instance subnet uses a *different* (explicit) route table, S3 still isn't routed → license fails after grace.
**Do this instead:** Data-source the instance subnet's route table (Option B) or take `var.route_table_id` explicitly (Option A). Verify the prefix-list route lands in the table the instance actually uses.

### Anti-Pattern 3: Keeping the CIS 2.2.1 exception "to be safe" with virtual sessions
**What people do:** Leave `amzn2023cis_rule_2_2_1: false` + the Xorg post-guard "just in case."
**Why it's wrong:** It perpetuates the only accepted Level-2 CIS deviation for an X server that virtual-session DCV (Xdcv) does not use — needless attack surface.
**Do this instead:** Revert the exception + delete the guard; confirm at the live UAT that the Xdcv virtual session renders without the system Xorg. (Keep a documented fallback if the UAT proves otherwise.)

### Anti-Pattern 4: Renaming the `vnc-password` SSM param "for cleanliness"
**What people do:** Rename `/devbox/<u>/vnc-password` → `dcv-password`.
**Why it's wrong:** The path is hard-coded in bootstrap, outputs, secrets-show, and any in-flight AMIs; renaming orphans them for zero functional gain (IAM ARN is a wildcard).
**Do this instead:** Keep the param name; relabel human-facing text to "DCV login password."

---

## Integration Points

### External Services
| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Amazon S3 (regional `dcv-license.<region>`) | DCV server auto-GETs over **S3 Gateway VPC endpoint**; authorised by instance-profile `s3:GetObject` | Resource ARN `arn:aws:s3:::dcv-license.<region>/*`. Partition-sensitive (`aws-us-gov` etc.) — use `aws` (commercial). 15-day grace if unreachable. |
| AWS DCV CDN (`d1uj6qtbmh3dt5.cloudfront.net`) | Bake-time `get_url` of the server tarball + `rpm_key` for NICE GPG | Install-time only; airgap override = mirror the tarball (sha256 pin enforced regardless). |
| AWS SSM (Session Manager + Parameter Store) | Port-forward :8443 (bypasses SG); fetch `vnc-password` SecureString at boot | Unchanged from current posture; `AmazonSSMManagedInstanceCore` + KMS-decrypt IAM stay. |
| AWS IMDS (IMDSv2) | DCV reads instance identity to self-license | Already enforced (`metadata_options http_tokens=required`, `main.tf:155-160`). DCV needs IMDS access — satisfied. |

### Internal Boundaries
| Boundary | Communication | Notes |
|----------|---------------|-------|
| `dcv` role ↔ `desktop` role | DCV virtual session execs the GNOME session from `@Desktop`/`gnome-session` | Gate `dcv` on `layers.desktop`; desktop must run first. |
| `dcv` role ↔ `secrets` role | `authentication="system"` → ec2-user PAM password from secrets pipeline | Assert `desktop_vnc_password` is set; no new secret. |
| `dcv` role ↔ `hardening` role | DCV must finish (SELinux relabel, config) before CIS locks down; hardening stays LAST | Same ordering contract xrdp had. |
| Terraform SG ↔ DCV server | :8443 TCP ingress gated on `var.allowed_web_cidrs` | UDP only if QUIC (not recommended). |
| Terraform IAM/endpoint ↔ DCV licensing | The runtime license path | The make-or-break addition. |

---

## Recommended Phase Build Order

Dependency-driven (the license infra must exist before the live UAT can license; removal is safe to do alongside since the new role replaces the old slot):

1. **Phase A — `dcv` role install + config (bake-time).** Port `ansible/roles/dcv/` from git `51c5f1f`; wire into `playbook.yml` between `desktop` and `hardening`; add `dcv: true` to `layer_config.yml`. Pin `dcv_version`/`dcv_build`; add SELinux relabel + a bake-time assert (binaries, `/etc/dcv/dcv.conf`, `dcvserver` + `dcv-virtual-session` enabled), mirroring the xrdp RDP-13 assert discipline. *Output: an AMI that bakes green and runs DCV under the 15-day grace.*

2. **Phase B — License infra + SG (Terraform, runtime).** Add the S3 Gateway VPC endpoint + route-table association (resolve the route table — Option B default, Option A override); append the `s3:GetObject` IAM statement; add :8443 TCP SG ingress; drop :3389. Update var/output descriptions. *Output: a running instance that licenses itself past 15 days. This is the make-or-break.*

3. **Phase C — xrdp/VNC removal + CIS revert + operator surface.** Delete the `xrdp` role + playbook block + post_tasks Xorg guard + `test-xrdp.yml`; revert the CIS 2.2.1 override; fix the secrets bootstrap restart loop + service ordering; flip operator surface 3389→8443 and relabel "RDP"→"DCV" across `./run`/scripts/CLAUDE.md/firewalld comment. Run the completeness greps. *Output: no dead remote-desktop config; clean invariants.*

4. **Phase D — Live UAT (milestone-close gate).** Bake → `tf-apply` → start → `./run devbox-port-forward 8443` → connect a DCV client as `ec2-user` with the `secrets-show` password → confirm GNOME virtual session renders **and** the license resolves (no `ORIGIN_OBJECT_MISSING`) past first connect. **Confirm here whether the CIS 2.2.1 revert is safe** (Xdcv renders without system Xorg). *Output: DCV proven end-to-end on a live instance — the gate v3.2's RDP-14 never reached.*

> A/C can largely proceed in parallel (C's removal frees the role slot A fills), but **B must precede D** — the UAT licenses only if the endpoint+IAM exist.

---

## Sources

### Primary (HIGH — repo-internal, read at file:line)
- `ansible/playbook.yml`, `ansible/layer_config.yml`, `ansible/firewalld-docker-fix.yml`, `ansible/test-xrdp.yml`
- `ansible/roles/xrdp/{tasks/main.yml,defaults/main.yml}` (what to remove), `ansible/roles/desktop/tasks/main.yml` (GNOME the DCV session needs), `ansible/roles/secrets/{defaults,tasks/publish,templates/devbox-secrets-bootstrap.*}` (credential reuse)
- `ansible/roles/hardening/defaults/main.yml:28-37` (CIS 2.2.1 override to re-evaluate)
- `terraform/{main.tf,variables.tf,outputs.tf}` (SG/IAM/instance-profile + proof the VPC/subnet/route-table are external `var.vpc_id`/`var.subnet_id`, no `aws_vpc`/`aws_route_table` in-repo)
- `run`, `scripts/devbox-{start,status}.sh`, `CLAUDE.md` (operator surface)
- **git history — the proven prior DCV role:** `51c5f1f`/`67faeb3`/`df9f098`/`8538ef3` (`ansible/roles/dcv/` defaults/tasks/handlers/templates) and `bc47512:.planning/quick/260611-jq2-…/260611-jq2-SUMMARY.md` (decisions: virtual session, PAM reuse, port 8443, deferred sha256 pin); `d3bd9a0` revert ("license unobtainable in airgap")
- `.planning/PROJECT.md` (v4.0 milestone scope), `.planning/REQUIREMENTS.md` (v3.2 RDP-* being removed), `.planning/phases/12-…/12-RESEARCH.md` (the removal-inventory pattern reused here)

### Secondary (HIGH — official AWS docs, verified 2026-06-18)
- [Step 2: License the Amazon DCV Server](https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-license.html) — IAM `s3:GetObject` on `arn:aws:s3:::dcv-license.{region}/*`; gateway VPC endpoint for no-internet instances; 15-day grace; IMDS requirement; partition note
- [Understanding Amazon DCV sessions](https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-intro.html) & [Starting Amazon DCV sessions](https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-start.html) — virtual session starts **Xdcv** (its own X server), not the system Xorg; DCV does not auto-create a session
- [Changing the DCV TCP/UDP ports](https://docs.aws.amazon.com/dcv/latest/adminguide/manage-port-addr.html) & [Enabling QUIC](https://docs.aws.amazon.com/dcv/latest/adminguide/enable-quic.html) — default TCP 8443; UDP 8443 only when `enable-quic-frontend=true`
- [Gateway VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/userguide/vpce-gateway.html) — route-table-scoped, free, S3-supported

---
*Architecture research for: Amazon DCV remote-desktop integration (new `dcv` role + S3-VPC-endpoint/IAM license path) replacing the xrdp/VNC stack on the devbox AL2023 AMI*
*Researched: 2026-06-18*
