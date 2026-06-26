# Stack Research — Amazon DCV on the devbox AMI (v4.0)

**Domain:** Remote-desktop server (Amazon DCV / dcvserver) baked into a hardened Amazon Linux 2023 x86_64 AMI via Packer + Ansible
**Researched:** 2026-06-18
**Confidence:** HIGH (install path + versions verified against AWS official adminguide + amazondcv.com download index; airgap reachability grounded in this repo's existing bake-time egress)

---

## VERDICT (install-source / airgap)

**DCV CAN be installed under the stated constraints. NOT BLOCKED.**

The DCV RPMs are distributed **only** from AWS CloudFront (`https://d1uj6qtbmh3dt5.cloudfront.net/...`) — there is **no** github release of the RPMs (verified: `aws-samples/amazon-ec2-nice-dcv-samples` only ships CFN/scripts that *download from that same CloudFront URL at runtime*), and they are **not** in the AL2023 dnf repos. So a literal "github-only" egress reading would block this.

**But that reading does not match how this repo actually bakes.** The existing playbook already pulls bake-time assets over arbitrary HTTPS from `johnvansickle.com` (ffmpeg), `get.helm.sh`, `dl.k8s.io`, `download.jetbrains.com`, `services.gradle.org`, `sh.rustup.rs`, `dl.flathub.org`, plus `github.com`/`raw.githubusercontent.com`. The operative posture is: **general outbound HTTPS is available at bake; the *runtime* instance has no public ingress and reaches AWS only via SSM + VPC endpoints.** CloudFront is just one more `get_url` host, identical in kind to `johnvansickle.com`. The prior reverted role (`260611-jq2`) already downloaded the DCV tarball from CloudFront successfully — **it was reverted for the runtime *license* fetch (S3 `dcv-license.<region>`), not the install download** (revert `d3bd9a0`).

**Recommended install source:** `get_url` the AL2023 server tarball from CloudFront at bake time, pinned to `2025.0-20103`, with a `sha256` checksum and the NICE GPG key imported first — exactly the prior role's mechanism. **Do not vendor the ~41 MB tarball into git** (binary bloat, no upstream signature benefit over GPG+sha256). If a future hardening pass tightens bake egress to a true allowlist, the fallback is to add `d1uj6qtbmh3dt5.cloudfront.net` to that allowlist (one host) or pre-stage the tarball as a build input — but neither is needed today.

**The real make-or-break is licensing, not install** — see "Licensing" below. v4.0 already scopes the fix (S3 gateway VPC endpoint + `s3:GetObject` on `dcv-license.<region>`).

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `nice-dcv-server` | 2025.0-20103 (`2025.0.20103-1.amzn2023.x86_64.rpm`) | The dcvserver daemon (`dcvserver.service`), `dcv` CLI, web/QUIC transport on `:8443` | Mandatory. The only required package; everything else is optional. Current latest (verified amazondcv.com index 2026-06). |
| `nice-xdcv` | 2025.0-688 (`nice-xdcv-2025.0.688-1.amzn2023.x86_64.rpm`) | Virtual-session X server (`Xdcv`) | Required for **virtual sessions** (headless, no GPU, no `gdm`/console X needed). This is the right model for this non-GPU devbox. Note the **different build number (688)** vs the server (20103). |
| `nice-dcv-web-viewer` | 2025.0-20103 (`nice-dcv-web-viewer-2025.0.20103-1.amzn2023.x86_64.rpm`) | Browser web client served by dcvserver | Required so the operator connects from a browser over the SSM `:8443` port-forward (mirrors the old code-server/noVNC browser UX). |

### Supporting Libraries (OS packages, from AL2023 dnf repos)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| GNOME desktop (`@Desktop` + `gnome-shell` + `gnome-session` + `mesa-dri-drivers` + fonts) | AL2023 repo | The desktop the DCV virtual session renders | **Already installed by the existing `desktop` role.** Do not re-add. DCV reuses it. |
| `glx-utils` (provides `glxinfo`) | AL2023 repo | Verify OpenGL software rendering inside the session | Optional but cheap; useful as a bake-time/UAT assertion that Mesa software GL works. On non-GPU, GL is Mesa software-rendered. |
| `pulseaudio-utils` | AL2023 repo | Microphone redirection support | Optional. Add only if mic redirect is a wanted feature; otherwise skip (YAGNI). |

### Packages NOT needed on this (non-GPU) instance

| Package | Build | Why skipped here |
|---------|-------|------------------|
| `nice-dcv-gl` | 2025.0-1112 | **GPU sharing only.** Needs an NVIDIA/AMD GPU + vendor driver. The devbox runs on a non-GPU instance type → omit. (Also unavailable for aarch64.) |
| `nice-dcv-gltest` | (ships in tarball) | Diagnostic OpenGL test app, paired with `nice-dcv-gl`. Omit with `nice-dcv-gl`. |
| `nice-dcv-simple-external-authenticator` (dcvsimpleextauth) | 2025.0-282 | Only for **external auth** (EnginFrame / token-broker flows). This devbox uses `authentication="system"` (PAM) reusing the ec2-user password the `secrets` role already sets → omit. |
| DCV USB drivers (`dcvusbdriverinstaller` + `dkms`) | — | USB remotization. Not needed for a browser dev workstation → omit. |
| `xorg-x11-drv-dummy` (XDummy) | AL2023 repo | Only needed for **console sessions** on non-GPU hosts. With **virtual sessions** (the recommended model) no X server / XDummy is required → omit. |

### Development / verification Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `dcv list-sessions` / `dcv create-session` | Session lifecycle | The session-creation systemd unit (`Type=oneshot`, `RemainAfterExit=true`) from the prior role is the correct pattern — DCV does NOT auto-create a session. |
| `dcvgldiag` | GPU/GL diagnostics | Ships with `nice-dcv-gl`; **not present on non-GPU** (we omit gl). Do not reference it in UAT for this instance. |
| `sha256sum` | Pin the tarball checksum after first bake | Required to fill `dcv_tarball_sha256` (see Install). |

## Install

**Mechanism (Ansible `dcv` role, mirrors the reverted `260611-jq2` role + this repo's ffmpeg/helm `get_url` convention):**

```yaml
# defaults/main.yml  (pin versions — REP posture, CLAUDE.md §9 deferred-pin pattern)
dcv_version: "2025.0"
dcv_build_server: "20103"     # nice-dcv-server / nice-dcv-web-viewer
dcv_build_xdcv: "688"         # nice-xdcv  (DIFFERENT build number — do not reuse 20103)
dcv_web_port: 8443
dcv_tarball_sha256: ""        # fill after first bake: sha256sum nice-dcv-2025.0-20103-amzn2023-x86_64.tgz
dev_user: ec2-user
dev_home: /home/ec2-user
```

```bash
# 1. Import GPG key BEFORE any RPM install (ansible.builtin.rpm_key)
sudo rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY

# 2. Download + verify the AL2023 x86_64 server tarball (~41 MB) over HTTPS at bake
#    get_url url=.../2025.0/Servers/nice-dcv-2025.0-20103-amzn2023-x86_64.tgz
#            checksum=sha256:<dcv_tarball_sha256>
wget https://d1uj6qtbmh3dt5.cloudfront.net/2025.0/Servers/nice-dcv-2025.0-20103-amzn2023-x86_64.tgz

# 3. Extract (tarball is a folder of RPMs), then dnf-install the THREE RPMs
#    (web-viewer/xdcv pull nice-dcv-server deps via dnf local install)
tar -xzf nice-dcv-2025.0-20103-amzn2023-x86_64.tgz
cd nice-dcv-2025.0-20103-amzn2023-x86_64
sudo dnf install -y \
  nice-dcv-server-2025.0.20103-1.amzn2023.x86_64.rpm \
  nice-dcv-web-viewer-2025.0.20103-1.amzn2023.x86_64.rpm \
  nice-xdcv-2025.0.688-1.amzn2023.x86_64.rpm
# disable_gpg_check: false  (key imported in step 1 → signature is verified)

# 4. Supporting OS packages from AL2023 dnf repos (optional)
sudo dnf install -y glx-utils            # glxinfo (verify Mesa software GL)
# sudo dnf install -y pulseaudio-utils   # only if mic redirect wanted
```

**GPG handling in airgap:** the GPG key is fetched from the **same CloudFront host** as the tarball (`https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY`). If that host is reachable for the 41 MB tarball, it is reachable for the ~3 KB key — no separate problem. (For belt-and-suspenders / true-airgap future, the small ASCII key MAY be vendored into `ansible/roles/dcv/files/NICE-GPG-KEY` and imported from the local copy; the tarball should NOT be vendored.) Watch for PII-scrubber mangling of the key URL — that bit the prior role (`78e169b` "restore NICE GPG key URL"); keep the literal URL intact.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Virtual session (`nice-xdcv`, no X server) | Console session (XDummy + `xorg-x11-drv-dummy` + running Xorg) | Only if you need a single shared "physical" console (e.g. GPU console sharing). For a single-operator headless box, virtual sessions are simpler and need no display manager. |
| `get_url` tarball from CloudFront at bake | Vendor tarball into git / pre-stage as build input | Only if bake egress is later locked to a strict allowlist that excludes CloudFront. Adds ~41 MB binary to the repo — avoid unless forced. |
| `get_url` from CloudFront | `dnf install` from a private/AWS mirror | Out of scope — PROJECT.md explicitly forbids private mirror + S3-for-install. |
| `authentication="system"` (PAM, reuse ec2-user secret) | `nice-dcv-simple-external-authenticator` | Only for token/external-broker auth (EnginFrame). Overkill for one operator. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `nice-dcv-gl` / `nice-dcv-gltest` | GPU-only; needs a GPU + vendor driver this instance doesn't have; aarch64-unavailable | Omit — Mesa software GL via `mesa-dri-drivers` (already installed by `desktop` role) |
| `most_recent`/`latest` tarball URL (`.../nice-dcv-amzn2023-x86_64.tgz`) | Non-deterministic — breaks REP-01 reproducibility invariant, mirrors the banned `most_recent = true` AMI anti-pattern | Pin the explicit `2025.0/Servers/nice-dcv-2025.0-20103-...` URL + `sha256` |
| Wayland desktop session | DCV does **not** support Wayland | Force X11/Xorg session; set `WaylandEnable=false` in `/etc/gdm/custom.conf` if `gdm` is ever in play (virtual sessions sidestep gdm entirely) |
| Vendoring the 41 MB tarball into git | Binary bloat, no signature win over GPG+sha256 | `get_url` + `sha256` + `rpm_key` |
| Relying on the 15-day grace license | DCV self-licenses for only 15 days without S3 reach, then sessions fail to start | S3 gateway VPC endpoint + `s3:GetObject` on `dcv-license.<region>` (v4.0 scope) |

## Licensing (the actual make-or-break — verified HIGH)

- **DCV is free on EC2.** No license server, no license file to install. (Verified: AWS adminguide + multiple sources.)
- **Mechanism:** `dcvserver` auto-detects it is on EC2 and **periodically reads the regional license object from S3** — bucket `dcv-license.<region>` (e.g. `dcv-license.us-east-1`). Required IAM on the instance role:
  ```json
  { "Effect": "Allow", "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::dcv-license.<region>/*" }
  ```
- **Airgap consequence:** with no public internet on the running instance, S3 must be reachable via an **S3 gateway VPC endpoint** (route-table entry), and the instance role must carry the `s3:GetObject` statement above. Without it, sessions fail with `ORIGIN_OBJECT_MISSING` / "No license available" — **this is exactly why `260611-jq2` was reverted** (`d3bd9a0`). Grace period without S3 reach is only **15 days**, so this is not optional.
- This is **infra/IAM/Terraform work**, separate from the Ansible install — flag it as its own roadmap item with a HARD dependency: the bake can succeed without it, but **no DCV session will start at runtime** until the endpoint + IAM are in place.

## Stack Patterns by Variant

**If non-GPU instance (this devbox, the default):**
- Install `nice-dcv-server` + `nice-xdcv` + `nice-dcv-web-viewer` only.
- Use **virtual sessions** → no X server, no XDummy, no display manager needed.
- GL is Mesa software rendering (already covered by `mesa-dri-drivers` from the `desktop` role).

**If GPU instance (future, out of current scope):**
- Add `nice-dcv-gl` (+ optional `nice-dcv-gltest`), install the NVIDIA/AMD driver, run `dcvgldiag` to verify, and configure a console/X session for hardware GL.

## Version Compatibility

| Package | Build | Notes |
|---------|-------|-------|
| `nice-dcv-server` | 2025.0.20103 | Same version the reverted role pinned; still current latest as of 2026-06. |
| `nice-dcv-web-viewer` | 2025.0.20103 | Tracks the server build (20103). Web client supported since DCV 2021.2+. |
| `nice-xdcv` | 2025.0.688 | **Build differs from the server (688 ≠ 20103)** — same DCV 2025.0 release train; the per-component build numbers are independent. Filename-glob the RPMs (`nice-xdcv-*.rpm`) as the prior role did rather than hardcoding `688` in the install path. |
| AL2023 (CIS-hardened) | minimal x86_64 | RPMs are `*.amzn2023.x86_64` (el9-compatible base, but use the `amzn2023` tarball, not `el9`). `hardening` role runs LAST — the `dcv` role must sit before it (like `xrdp` did) and SG `:8443` is opened in Terraform, not Ansible. |

## Sources

- https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html — HIGH — exact AL2023 RPM names, builds (server 20103, xdcv 688, gl 1112, simple-ext-auth 282), GPG import, required-vs-optional split, GPU-vs-non-GPU
- https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html — HIGH — virtual vs console sessions, XDummy only for console, Mesa software GL on non-GPU, Wayland-unsupported, `glx-utils`
- https://www.amazondcv.com/ (download index) — HIGH — latest = 2025.0, server build 20103, AL2023 x86_64 tarball `nice-dcv-2025.0-20103-amzn2023-x86_64.tgz` (~41 MB) from `d1uj6qtbmh3dt5.cloudfront.net/2025.0/Servers/...`
- AWS adminguide "Step 2: License the DCV server" + re:Post + NI-SP — HIGH — EC2 = free, no license server, S3 `dcv-license.<region>` + `s3:GetObject`, 15-day grace
- github.com/aws-samples/amazon-ec2-nice-dcv-samples — HIGH (negative finding) — confirms NO github RPM release; samples download from the same CloudFront URL
- Local repo: reverted role `git show 67faeb3/df9f098` (install mechanism), `78e169b` (GPG URL), `d3bd9a0` (revert reason = license, not install); `ansible/roles/desktop/tasks/main.yml` + `devops`/`devtools` (existing `get_url` egress hosts establishing CloudFront-class reachability at bake)

---
*Stack research for: Amazon DCV remote-desktop server on AL2023 (devbox v4.0)*
*Researched: 2026-06-18*
