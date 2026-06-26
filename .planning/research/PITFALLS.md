# Pitfalls Research

**Domain:** Amazon DCV remote desktop on a CIS-hardened (SELinux enforcing + FIPS), airgapped, SSM-port-forward-only, single-operator AL2023 EC2
**Researched:** 2026-06-18
**Confidence:** HIGH (5 already proven live this session; new ones verified against AWS DCV official docs + the v3.2 xrdp adversarial findings in `.planning/phases/11-…/11-VERIFICATION.md`)

> **Read this first.** Five of these were hit live this session — their fix is *confirmed*, not theoretical.
> The single highest-risk pitfall is **the airgap license path (Pitfall 1)**: without an S3 gateway
> VPC endpoint + scoped IAM, `dcv create-session` fails with `ORIGIN_OBJECT_MISSING` and DCV is dead
> on arrival. It already cost one full abandonment (`d3bd9a0`, "license unobtainable in airgap"). It is
> make-or-break for the entire milestone.
>
> **Naming note for the planner:** AWS docs call the AL2023 build `amzn2023`, but the RPM the package
> manager actually pulls is **el9-derived** (`nice-dcv-server-…el9` / `…amzn2023`). The package auto-creates
> a `dcv` system user. The systemd service is **`dcvserver`** (not `dcv`).
> DCV 2024.0+ **enables QUIC (UDP 8443) by default** — this is the root of Pitfall 4 and a regression
> vs older DCV mental models.

---

## Critical Pitfalls

### Pitfall 1: Airgap license — `ORIGIN_OBJECT_MISSING` (ALREADY HIT LIVE — fix CONFIRMED)

**What goes wrong:**
`dcv create-session` (or the auto-console-session) fails; the server log shows `ORIGIN_OBJECT_MISSING`
or a licensing/credential error. DCV on EC2 has no license *file* — the server detects it is on EC2 and
periodically fetches a license object from the **regional S3 bucket `dcv-license.<region>`**. On a private,
no-public-internet instance that S3 GET silently fails, DCV falls back to the 30-day eval license behavior,
and once that path is broken, no session can be created. This is the exact blocker that caused DCV to be
abandoned once (`d3bd9a0`) before it was re-validated live this session.

A second, *correlated* failure surfaces in the logs as the AWS SDK message
**"skipping credential provider, no session"** — the SDK credential chain never resolved the instance role,
so even with the endpoint in place the GET is unauthenticated. Root causes: (a) the IAM instance role lacks
`s3:GetObject` on the license bucket, or (b) IMDS is not yielding the role (IMDSv2 hop-limit 1 inside a
container, or no instance profile attached).

**Why it happens:**
The license dependency is invisible at bake time — the AMI builds green, the package installs fine, the
service starts. The failure only appears at *session create* on a private instance. Developers assume "DCV
on EC2 is free and license-less" (true) and miss that "license-less" still means "must reach an S3 object."

**How to avoid (CONFIRMED fix, two parts — both required):**
1. **S3 gateway VPC endpoint** (`com.amazonaws.<region>.s3`, type `Gateway`) attached to the instance's
   route table, with an endpoint policy that at minimum allows `s3:GetObject` on
   `arn:aws:s3:::dcv-license.<region>/*` (a too-tight endpoint policy is itself a trap — see Pitfall 10).
   The SG/NACL must allow outbound HTTPS (443) to the S3 prefix list.
2. **IAM instance-role policy** (exact ARN from AWS docs):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       { "Effect": "Allow", "Action": "s3:GetObject",
         "Resource": "arn:aws:s3:::dcv-license.{{region}}/*" }
     ]
   }
   ```
   Add to the existing `aws_iam_role.devbox` (the same role already carrying `AmazonSSMManagedInstanceCore`
   + the `/devbox/${devbox_user}/*` SSM policy). Region must match the *instance's* region (Pitfall 10).
   Note `aws-cn`/`aws-us-gov`/`aws-eusc` partition variants for non-commercial regions.

**Warning signs:**
`grep -i 'license\|ORIGIN_OBJECT_MISSING\|no session' /var/log/dcv/server.log`; `dcv create-session` returns
non-zero; `aws s3 ls s3://dcv-license.<region>/` from the instance hangs (endpoint missing) or returns
AccessDenied (IAM missing). `curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/`
returning empty ⇒ IMDS/role problem.

**Phase to address:** **Terraform/networking phase** (S3 gateway endpoint + IAM policy on `aws_iam_role.devbox`)
co-built with the `dcv` role. This is the milestone's make-or-break item — front-load it.

**Cross-ref:** This is *new* relative to xrdp (xrdp has no license dependency at all — it was the entire
reason DCV was dropped for xrdp in v3.2). It is the v4.0-specific blocker.

---

### Pitfall 2: No session — DCV does not auto-create one (ALREADY HIT LIVE — fix CONFIRMED)

**What goes wrong:**
`dcvserver` starts cleanly, listens on 8443, the web client loads… and there is nothing to connect to.
DCV does **not** create a session on its own. A fresh server has zero sessions; the client shows
"no session" / a blank session picker.

**Why it happens:**
Operators expect VNC/xrdp semantics (service up ⇒ desktop available). DCV decouples the server daemon from
sessions; a session must be explicitly created (`dcv create-session`) or auto-created via config.

**How to avoid (CONFIRMED fix):**
For a single-operator console desktop, configure auto-creation in `/etc/dcv/dcv.conf`:
```ini
[session-management]
create-session = true

[session-management/automatic-console-session]
owner = "ec2-user"
```
This makes `dcvserver` create a `console` session owned by `ec2-user` at startup. (Alternative: a systemd
oneshot running `dcv create-session --type=console --owner ec2-user console` after `dcvserver`, but the
dcv.conf path is simpler and idempotent.)

**Warning signs:** `dcv list-sessions` returns empty after boot; client connects but shows no session.

**Phase to address:** **`dcv` role — service config (dcv.conf) phase.**

**Cross-ref:** Conceptually mirrors the xrdp "sesman must spawn the session" wiring, but DCV's mechanism is
declarative config, not a PAM/sesman handshake.

---

### Pitfall 3: Console session won't attach / stuck "connecting" — Wayland + no seat0 (ALREADY HIT LIVE — fix CONFIRMED)

**What goes wrong:**
The `console` session exists but the client spins on "connecting" forever (or shows a black screen). A DCV
**console** session attaches to the *physical* (seat0) X display managed by gdm. If gdm brought up a
**Wayland** session, DCV cannot attach (DCV does not support Wayland). If no graphical user session is
actually live on seat0, there is nothing to attach to.

**Why it happens:**
AL2023's gdm defaults to Wayland where possible. The existing `desktop` role installs GNOME but does **not**
set `WaylandEnable=false` (that requirement lived in the xrdp `startwm.sh` Xorg-forcing path, which does
*not* apply to a DCV console session driven by gdm). Without an autologin or a running seat0 session, the
console session has no live X to attach to.

**How to avoid (CONFIRMED fix — two parts):**
1. **Disable Wayland in gdm** (`/etc/gdm/custom.conf`):
   ```ini
   [daemon]
   WaylandEnable=false
   ```
   then ensure `systemctl get-default` == `graphical.target` (set it if not).
2. **Provide a live seat0 session.** For a headless single-operator box, enable gdm **autologin** for
   `ec2-user` so a GNOME-on-Xorg session is active on seat0 at boot for the console session to attach to:
   ```ini
   [daemon]
   AutomaticLoginEnable=true
   AutomaticLogin=ec2-user
   ```
   (Autologin on a headless box is acceptable here: the auth boundary is SSM/IAM + the TLS-on-8443 DCV layer,
   not the local console which has no physical access.)

> **Planner alternative worth surfacing:** a DCV **virtual session** (`--type=virtual`, via `nice-xdcv`)
> sidesteps gdm/seat0/Wayland entirely — it spins its own Xdcv server and does **not** need autologin or
> `WaylandEnable=false`. For a single headless operator, *virtual* is arguably the lower-risk default and
> dodges Pitfalls 3, 8-gdm, and the autologin security smell. Console gives "the literal physical desktop";
> virtual gives "a private desktop." Recommend the planner evaluate virtual-first. If virtual: install
> `nice-xdcv` and (for GPU-less OpenGL) ensure Mesa is present; XDummy is **not** needed for virtual.

**Warning signs:** `loginctl` shows no `seat0` graphical session; `ps aux | grep Xorg` empty or shows
`Xwayland`; client "connecting" never completes; `journalctl -u gdm` shows a Wayland session.

**Phase to address:** **`desktop`/`dcv` session-backend phase** (decide console-vs-virtual; wire gdm
WaylandEnable + autologin if console).

**Cross-ref:** Directly transfers from xrdp ADDENDUM #1 ("needs Xorg NOT Wayland; active seat0").
The xrdp role forced this via `XDG_SESSION_TYPE=x11` in `startwm.sh`; DCV console needs it at the **gdm**
layer instead.

---

### Pitfall 4: Web client stuck "connecting" with a healthy server — QUIC over UDP 8443 (ALREADY HIT LIVE — fix CONFIRMED)

**What goes wrong:**
Server is healthy, license OK, session exists, TLS handshake on 8443 succeeds, the web UI loads and
authenticates — then the display data channel never establishes and the client hangs at "connecting."
DCV **2024.0+ enables QUIC (UDP 8443) by default.** Auth runs over WebSocket/TCP (which is why login
*succeeds*), but the data channel attempts **QUIC over UDP 8443**. Over an SSM port-forward (TCP only —
SSM cannot tunnel UDP) or with UDP 8443 closed in the SG, the data channel is unreachable and the session
hangs. This is the canonical "auth works, screen never paints" symptom.

**Why it happens:**
The TCP-only nature of SSM port-forwarding is invisible to DCV. The default-on QUIC (a 2024.0 change) means
a config that "worked" in older DCV mental models now silently breaks behind SSM.

**How to avoid (CONFIRMED fix — pick one; for SSM, the first):**
- **Disable QUIC** (required for the SSM-port-forward posture) in `/etc/dcv/dcv.conf`:
  ```ini
  [connectivity]
  enable-quic-frontend = false
  ```
  Forces all transport (auth + data) onto WebSocket/TCP 8443, which SSM *can* tunnel. **This is the correct
  choice for this project** — the operator reaches DCV only via `./run` SSM port-forward.
- *Or* open UDP 8443 in the SG **and** give the client a direct UDP path — but SSM cannot carry UDP, so this
  only helps a future direct-CIDR posture, not the SSM path. Do not rely on it for the SSM milestone.

**Warning signs:** web client authenticates then hangs; `enable-quic-frontend` unset/true in dcv.conf;
SG has no UDP 8443 rule; works on a direct browser-to-instance test (if you ever open the CIDR) but not
over `./run devbox-port-forward`.

**Phase to address:** **`dcv` role dcv.conf phase** (set `enable-quic-frontend=false`) **+ Terraform SG phase**
(8443 **TCP**; do NOT add UDP for the SSM posture — adding it implies a path that doesn't exist over SSM and
invites the false assumption that UDP is usable).

**Cross-ref:** No xrdp analog (RDP is single-port TCP 3389). This is a DCV-transport-specific trap and a
*default-changed-in-2024.0* regression risk.

---

### Pitfall 5: `dcv-gl` "disabled" / no GPU messages — BENIGN, not an error (ALREADY HIT LIVE — confirmed non-issue)

**What goes wrong (nothing, actually):**
Logs show `dcv-gl` disabled, "no GPU", or OpenGL falling back to software/Mesa. On a non-GPU instance
(the default `instance_type` here is general-purpose, no GPU) this is **expected and correct** — DCV uses
software (Mesa/llvmpipe) rendering. `nice-dcv-gl` is the *GPU-sharing* package and is irrelevant without a GPU.

**Why it happens:**
The message reads like a failure. Operators chase it as the cause of a "connecting" hang when the real
cause is Pitfall 1/3/4.

**How to avoid:**
**Do not install `nice-dcv-gl` / `nice-dcv-gltest`** on a non-GPU box (they are explicitly optional and
GPU-only; `nice-dcv-gl` isn't even available on aarch64). Ensure `mesa-dri-drivers` / `mesa-libGL` are present
for software OpenGL (the `desktop` role already installs `mesa-dri-drivers`). Document the message as benign
so it doesn't burn debugging time. For non-GPU **console** sessions you DO need the **XDummy** virtual
framebuffer driver (`xorg-x11-drv-dummy`) + an `/etc/X11/xorg.conf` Dummy Device/Monitor/Screen stanza
(see Pitfall 12) — that's a *separate* requirement from dcv-gl.

**Warning signs:** Time spent debugging a benign log line. (No real failure.)

**Phase to address:** **`dcv` role + docs** (omit dcv-gl; document the benign message; ensure XDummy for
console). Add a one-liner to operator troubleshooting.

**Cross-ref:** Mirrors the xrdp "no-GPU DRMDevice falls back to software cleanly (glamor=FALSE; llvmpipe)"
de-risked finding — same "software render is fine" conclusion.

---

### Pitfall 6: SELinux enforcing — no DCV-shipped policy; AVCs on the agent / session launcher (NEW)

**What goes wrong:**
`hardening` sets SELinux **enforcing** and reboots into it (last role). DCV does **not** ship its own SELinux
policy module or document required booleans (verified: no `dcv`-specific policy exists upstream; the AWS
adminguide is silent on SELinux). Under enforcing, the `dcvserver` agent, the session-launcher exec into the
X/GNOME session, the `/var/run/dcv` sockets, and the dcv-auth helper can hit **AVC denials** that silently
kill session creation while `dcvserver.service` stays `active` — the exact "green but broken" pattern the
xrdp phase fought (ADDENDUM #2 finding #2).

DCV installs from a **vendor RPM**, so its binaries land in distro paths (`/usr/bin/dcv*`, `/usr/libexec`,
systemd unit) and are more likely to carry sane labels than xrdp's source-built `/usr/local/sbin` binaries —
but the *runtime* exec-into-user-session + socket transitions are the risk surface, not just file labels.

**Why it happens:**
The AMI builds and even boots permissive during bake; SELinux only becomes enforcing **after the hardening
reboot**, and the first confined session-create only happens at live UAT. Bake is green; the denial is invisible
until a real connect.

**How to avoid:**
1. **Plan for `restorecon`** over DCV's installed paths after install (cheap insurance, same pattern as the
   xrdp role's `restorecon -RvF`), and confirm the RPM-provided systemd unit + binaries carry expected types.
2. **Bake-time permissive capture is impossible** (enforcing only post-reboot), so add a **live-UAT gate**
   that runs `ausearch -m AVC,USER_AVC -ts boot` (or `ausearch -c dcv`) after the first connect and asserts
   zero DCV-related denials — analogous to the xrdp RDP-14 "AVC-clean enforcing boot" residual.
3. If denials appear: generate a scoped policy module with `ausearch … | audit2allow -M dcv_local &&
   semodule -i dcv_local.pp`, vendored into the role (do **not** set SELinux permissive — that defeats the
   entire hardening posture and the project's invariants). Booleans to check first:
   `getsebool -a | grep -E 'xserver|domain_can_mmap|daemons'` (e.g. `xserver_object_manager`,
   `domain_can_mmap_files`) before reaching for a custom module.

**Warning signs:** `dcvserver.service` active but `dcv create-session` fails only under enforcing;
`ausearch -m AVC -ts recent` shows `comm="dcv*"` / `Xorg` denials; works when you temporarily
`setenforce 0` (diagnostic only — never ship that).

**Phase to address:** **`dcv` role (restorecon + optional vendored policy module)** + **live-UAT verification
gate** (AVC-clean enforcing boot). Front-load the *plan* even though proof is live-only.

**Cross-ref:** Directly transfers from xrdp ADDENDUM #2 #2 ("relabel ≠ policy for daemons; AVC only appears
at first boot under enforcing → confirmable only at live UAT") and the FINAL verdict residual #1
("AVC-clean boot under SELinux enforcing"). DCV is *lower* risk than xrdp here (distro-path RPM vs
`/usr/local` source build) but the runtime-exec surface is the same.

---

### Pitfall 7: FIPS mode — DCV TLS handshake on 8443 under the kernel FIPS provider (NEW)

**What goes wrong:**
`hardening` runs `fips-mode-setup --enable` and reboots. DCV terminates TLS on 8443 with a **self-signed
cert it auto-generates at first start** (`/etc/dcv/dcv.pem` or per the `[security]` config). Under FIPS, the
OpenSSL/kernel crypto policy rejects weak algorithms, MD5/SHA-1 signatures, small/odd RSA keys, and (in
strict mode) certs lacking a SubjectAltName. If DCV's auto-generated cert or its negotiated cipher suite
isn't FIPS-acceptable, the TLS handshake on 8443 fails and the web client cannot even load.

**Why it happens:**
DCV's default cert generation predates the operator's FIPS posture and isn't guaranteed FIPS-clean
(algo/key-size/SAN). FIPS is enabled in the *last* role, after the `dcv` role configured everything — so the
handshake is never exercised under FIPS until live UAT.

**How to avoid:**
1. **Replace DCV's auto-cert with a FIPS-clean self-signed cert** generated by the `dcv` role using the exact
   pattern already proven for xrdp: `openssl req -x509 -nodes -newkey rsa:2048 -sha256 …
   -addext "subjectAltName=DNS:devbox"` (RSA-2048, SHA-256, **with SAN** — CN-only certs fail FIPS-strict
   TLS). Point dcv.conf `[security] certificate=`/`certificate-key=` at it (or DCV's default cert path).
   The xrdp role's cert task (`tasks/main.yml` cert-gen + the RDP-13 SAN assert) is a copy-paste template.
2. **Bake assert** the cert algo/size/SAN: `openssl x509 -in <dcv cert> -noout -text` and assert
   `subjectAltName` present + RSA ≥ 2048 + sha256 — exactly the xrdp RDP-13 cert-SAN proof.
3. **Live-UAT gate:** confirm the TLS handshake actually completes under the runtime FIPS provider
   (`openssl s_client -connect localhost:8443` from the instance after the FIPS reboot) — bake can't prove
   the runtime provider's behavior.

**Warning signs:** web client fails to load / TLS error in browser; `openssl s_client -connect localhost:8443`
errors under FIPS but works with `OPENSSL_FORCE_FIPS_MODE=0`; DCV log shows TLS/cert init failure;
auto-cert is CN-only or sha1.

**Phase to address:** **`dcv` role cert phase (FIPS-clean cert + SAN + bake assert)** + **live-UAT gate
(handshake under FIPS)**.

**Cross-ref:** Directly transfers from xrdp HIGH ("FIPS mode may reject the rsa:2048/no-SAN self-signed cert
in the TLS handshake") and the FINAL residual #2 ("FIPS TLS handshake live-only"). Same cert recipe applies.

---

### Pitfall 8: CIS rule collisions — X server purge, gdm, fonts, /tmp noexec, PAM (NEW — partly proven via xrdp)

**What goes wrong:**
The CIS role runs (inside `hardening`, **last**) and can remove or break things DCV needs, *after* the `dcv`
role installed them. Concrete collisions, verified against the vendored `AMAZON2023-CIS` defaults:

- **CIS 2.2.1 removes `xorg-x11-server-common`** (`amzn2023cis_rule_2_2_1: true` by default). `-common` is a
  dependency of `xorg-x11-server-Xorg`, which a DCV **console** session needs. Hardening runs after `dcv`,
  so it would delete the X server at the end of the bake. **Already solved in-repo for xrdp:**
  `ansible/roles/hardening/defaults/main.yml` sets `amzn2023cis_rule_2_2_1: false` with a documented
  desktop-exception comment + a post-hardening guard assert. **DCV inherits this fix for free** — but the
  planner must confirm it stays set (it's the single accepted CIS deviation) and that the post-hardening
  X-present guard is retained when xrdp is removed. *(Virtual sessions via `nice-xdcv` need their own Xdcv,
  not the system Xorg — confirm whether 2.2.1 still matters if you go virtual-only.)*
- **gdm / Wayland (Pitfall 3).** CIS section 1.7.x configures login banners but (verified) does **not** set
  GDM autologin or Wayland — so DCV's `WaylandEnable=false` + autologin are *additive*, not fighting CIS.
  No collision, but they are the operator's responsibility (CIS won't add them).
- **Fonts.** DCV/GNOME need fonts; CIS doesn't purge them, but the minimal AL2023 base may lack them.
  The `desktop` role already installs `dejavu-*`; ensure DCV's GNOME session has usable fonts (AWS lists
  `gnu-free-*` / `dejavu` for the desktop). Low risk, but a missing-fonts session renders boxes.
- **/tmp & /dev/shm noexec/nodev/nosuid (CIS 1.1.2.x / 1.1.8.x).** Defaults are `true`. **Verified mitigation:**
  on this EBS-rooted AMI `/tmp` is **not a separate partition**, and the fstab branch only fires when `/tmp`
  is a real mount; the systemd `tmp.mount` branch fires only when `amzn2023cis_tmp_svc` (default `true`).
  **This is a live trap to check:** if `tmp.mount` gets enabled with `noexec`, any DCV/X/GNOME component that
  exec's from `/tmp` (some session helpers, dbus, GL shader caches) breaks. DCV's runtime dirs are under
  `/var/run/dcv` and `/var/lib/dcv` (not `/tmp`), so risk is moderate — but `/dev/shm` `noexec` can bite X
  shared-memory / MIT-SHM and some GL paths. **Plan a live check:** `mount | grep -E '/tmp|/dev/shm'` post-bake
  and a connect test; if a component fails on noexec, relocate its tmpdir (e.g. `TMPDIR=/var/tmp`) rather than
  weakening the mount.
- **PAM (CIS authselect `sssd with-sudo`, faillock, pwquality).** DCV authenticates the web/native login
  against the system PAM stack (`dcv` PAM service / `system-auth`). The CIS-hardened PAM (authselect sssd
  profile + faillock) must still let `ec2-user` authenticate with the secrets-role password. xrdp solved the
  analogous problem by delegating its PAM file to `password-auth`. **Plan:** provide/confirm a `/etc/pam.d/dcv`
  that delegates to `system-auth`/`password-auth` and verify faillock doesn't lock `ec2-user` out, and that
  `pam_loginuid`/`pam_systemd` don't block the DCV session (xrdp RISK: "`pam_loginuid.so required` may block
  the sesman session").
- **colord / polkit (GNOME color-manager auth popup).** A GNOME session over a remote display hits the
  colord polkit prompt and hangs waiting for auth the operator can't satisfy. xrdp shipped a
  `45-allow-colord.rules` polkit rule (note: `.pkla` is **ignored** on AL2023 polkit 121+ — must be `.rules`).
  **DCV's GNOME session needs the same colord polkit `.rules` allow** — reuse the xrdp `files/45-allow-colord.rules`.

**Why it happens:**
`hardening` is the LAST role by invariant, so every CIS removal/lockdown lands *after* `dcv` set things up.
The bake is green because the package is present at install time; the CIS purge/mount/PAM change happens later
in the same run (or at the reboot).

**How to avoid:**
- Keep `amzn2023cis_rule_2_2_1: false` (already set) + the post-hardening X-present guard; document it as the
  single accepted CIS deviation (it already is).
- Add a **post-hardening bake assert** that the X server, gdm, fonts, DCV binaries, and dcv.conf survive the
  hardening pass (mirror the xrdp RDP-13 "stat everything after hardening" approach — *assert the end state,
  not the install-time state*).
- Provide the `dcv` PAM file (delegate to `system-auth`/`password-auth`) + colord polkit `.rules`.
- **Live-check** `/tmp` and `/dev/shm` mount options and that DCV/X components tolerate them.

**Warning signs:** post-bake `rpm -q xorg-x11-server-Xorg` missing; `systemctl status gdm` failed;
session renders empty/boxes (fonts); auth denied (PAM/faillock); GNOME hangs on a colord popup;
`mount` shows `noexec` on `/tmp` or `/dev/shm` and an X/GL component fails.

**Phase to address:** **hardening-defaults phase (keep 2.2.1=false + guard)** + **`dcv` role (PAM file, colord
.rules, post-hardening asserts)** + **live-UAT gate (mount/noexec + auth)**.

**Cross-ref:** This is the richest transfer from the xrdp phase — ADDENDUM #1 CRITICAL #2 (2.2.1 deletes X),
ADDENDUM #2 HIGH (tsusers/PAM gating), RISK (`.pkla`→`.rules`, `pam_loginuid`), and the FINAL "no CIS
package-purge collision beyond 2.2.1" verdict all apply. The 2.2.1 fix is *already in the repo*.

---

### Pitfall 9: Airgap INSTALL of the DCV packages — CloudFront, not AL2023 repos / GitHub (NEW)

**What goes wrong:**
The DCV RPMs do **not** come from the AL2023 dnf repos or GitHub — they are downloaded from AWS's CloudFront
(`https://d1uj6qtbmh3dt5.cloudfront.net/…`) as a versioned `.tgz` of RPMs, GPG-signed with the **NICE-GPG-KEY**
(also CloudFront-hosted). The project's airgap policy (CLAUDE.md / PROJECT.md) says install is download-based
("github/vendor, **no S3-for-install**, no private mirror") and consistent with the existing `get_url` +
checksum + GPG approach (ffmpeg static, mise, jdx). Failure modes: (a) Packer's build network can't reach
CloudFront ⇒ bake fails at download; (b) GPG key not imported ⇒ `dnf install` of the local RPM fails signature
check (or, worse, `--nogpgcheck` is used and supply-chain integrity is lost); (c) an unpinned "latest" URL
(`nice-dcv-amzn2023-x86_64.tgz`) makes the build non-reproducible — it violates the project's pin-everything
invariant; (d) the `el9`-vs-`amzn2023` filename confusion installs the wrong RPM.

**Why it happens:**
DCV isn't in any standard repo, so people reach for the convenient `latest` URL and skip GPG. The CloudFront
host is opaque (no obvious version in the hostname). The "amzn2023" label vs the el9-derived RPM trips people.

**How to avoid:**
1. **Pin an exact version** (e.g. `2025.0-20103`) and the exact per-OS filename
   (`nice-dcv-server-2025.0.20103-1.amzn2023.x86_64.rpm` from the `…amzn2023-x86_64.tgz`). Do **not** use the
   `latest.html` floating URLs — same discipline as the Packer source-AMI `:NN` pin and the committed lockfiles.
2. **Import + verify the GPG key by checksum:** `rpm --import https://…/NICE-GPG-KEY`, then `dnf install`
   the local RPM so the signature is checked. Record a sha256 of the `.tgz` and assert it post-download
   (matches the project's mise/jdx checksum-pin pattern). **Never** `--nogpgcheck`.
3. **Use `get_url` with the pinned URL + a `checksum:`** (Ansible verifies it) — the role's existing idiom.
4. **Confirm CloudFront reachability is part of the bake network** (Packer builds in a VPC that can egress
   HTTPS to CloudFront, same as it already does for ffmpeg/mise/Galaxy). This is *bake-time* egress, distinct
   from the *runtime* S3-license endpoint (Pitfall 1) — don't conflate them.

**Warning signs:** bake fails at the DCV download/extract; `dnf` reports "package not signed" or
"NOKEY"; build pulls a different version on a re-bake (no pin); RPM arch/OS mismatch errors;
someone added `--nogpgcheck` to make it "work."

**Phase to address:** **`dcv` role — install phase** (pinned URL + GPG import + checksum + `get_url`).

**Cross-ref:** New for DCV, but the *mechanism* is identical to the existing ffmpeg-static / mise / jdx
download-and-checksum pattern in the `desktop`/`devops` roles, and to the from-source xrdp `get_url` approach.
The project already does airgap-style vendor downloads; DCV just adds GPG-signature verification on top.

---

### Pitfall 10: License bucket region match + endpoint policy + offline behavior (NEW)

**What goes wrong:**
Three sub-traps around Pitfall 1's plumbing:
1. **Region mismatch.** The bucket is `dcv-license.<region>` for the *instance's* region. If the IAM ARN or
   the operator's mental model uses the wrong region (e.g. role region ≠ instance region, or a hardcoded
   `us-east-1` while the instance is elsewhere), the GET 404s ⇒ `ORIGIN_OBJECT_MISSING` even with the
   endpoint + IAM "in place." `AWS_REGION` is operator-controlled in this project, so this is a live risk.
2. **Over-tight S3 gateway endpoint policy.** A gateway endpoint policy that only allows the operator's own
   tfstate bucket (a plausible existing posture) will **block** the DCV license GET. The endpoint policy must
   *also* allow `s3:GetObject` on `arn:aws:s3:::dcv-license.<region>/*` (and the AL2023 dnf/SSM buckets if
   those also traverse the endpoint). A default "allow all" endpoint policy avoids this but is broader.
3. **Offline / caching behavior.** DCV checks the license **periodically**, not only at boot. It caches a
   valid license for a grace window, so a box can *appear* fine after first license, then start failing
   sessions later if the endpoint/IAM regresses. Conversely, a *stopped* instance that the operator restarts
   weeks later must re-reach S3 on next check. Don't assume "it worked once ⇒ permanently licensed."

**Why it happens:**
The region is parameterized (`AWS_REGION`), the endpoint policy is easy to scope too tightly for security,
and the periodic/cached nature of the check makes intermittent failures look random.

**How to avoid:**
- Derive the license ARN region from the **instance's** region (same var that drives the AMI/bucket), not a
  literal. Add a bake/runtime doctor check: `aws s3 ls s3://dcv-license.$(curl -s …/meta-data/placement/region)/`
  succeeds.
- Make the S3 gateway endpoint policy explicitly include the `dcv-license.<region>` resource (or use a
  documented broad policy). Don't silently inherit a tfstate-only endpoint policy.
- Document that DCV re-checks the license periodically; a long-stopped instance must regain S3 reachability
  on restart. Surface license health in `./run status`/doctor.

**Warning signs:** `ORIGIN_OBJECT_MISSING` despite endpoint+IAM present (⇒ region/endpoint-policy);
sessions work right after bake then fail days later (⇒ caching/regression); `AWS_REGION` differs from
the instance's actual region.

**Phase to address:** **Terraform networking/IAM phase (region-derived ARN + endpoint policy)** + **`./run`
doctor/status (license reachability check)**.

**Cross-ref:** New (xrdp had no license). This is the "second-order" version of Pitfall 1 — the plumbing is
right but a detail (region/policy/caching) defeats it.

---

### Pitfall 11: dcv.conf gotchas — web auth, session owner, display, TLS/no-TLS (NEW)

**What goes wrong:**
`/etc/dcv/dcv.conf` has several footguns that produce a server that "runs" but is wrong or insecure:
- **`[security] authentication`** — defaults to `system` (PAM). If set to `none` (a common "just make it work"
  shortcut), **anyone reaching 8443 gets the desktop with no password** — catastrophic even behind SSM, and a
  direct violation of the project's secure-by-default invariant. Keep `authentication=system`.
- **`[security] no-tls-strict` / disabling TLS** — DCV must keep TLS on (the project is HTTPS-only everywhere:
  code-server `cert: true`, noVNC `--ssl-only`). Do not disable TLS on 8443. (And see Pitfall 7 — the cert
  must be FIPS-clean.)
- **Session owner mismatch** — `automatic-console-session owner` must be the user with the live seat0 session
  (`ec2-user`); a mismatch ⇒ the session is created but the operator can't connect to it / it can't attach.
- **`[connectivity] web-port` / `web-listen-endpoints`** — default 8443; if changed, the SG, `./run`
  port-forward, and docs must all agree. Bind to the right interface (don't accidentally bind loopback-only
  if the SSM forward expects 8443 on the instance's listener — though loopback-only + SSM is actually a
  *valid hardening* choice, mirroring the Jupyter loopback model; decide deliberately).
- **`enable-quic-frontend`** — see Pitfall 4; must be `false` for SSM.
- **`[session-management] create-session`** — see Pitfall 2; must be `true` for auto-create.

**Why it happens:**
dcv.conf has many sections; copy-pasted "get it working" snippets from blogs often disable auth/TLS or set
the wrong owner. The file looks done but encodes a security hole or an attach failure.

**How to avoid:**
Template dcv.conf in the `dcv` role with explicit, asserted values: `authentication=system`, TLS on +
FIPS-clean cert, `enable-quic-frontend=false`, `create-session=true`, `automatic-console-session owner=ec2-user`,
web on 8443. **Bake-assert** the security-sensitive keys (no `authentication=none`, TLS not disabled) the same
way CLAUDE.md's grep-gates assert other invariants — consider a grep-gate that fails the build if
`authentication\s*=\s*none` appears in any tracked DCV config.

**Warning signs:** `grep -E 'authentication|no-tls|enable-quic|owner' /etc/dcv/dcv.conf` shows `none`/TLS-off/
QUIC-on/wrong-owner; passwordless connect succeeds (auth=none); plaintext on 8443.

**Phase to address:** **`dcv` role dcv.conf phase + a security grep-gate** (mirror the `no-changeme` /
hardening-last gate pattern).

**Cross-ref:** New for DCV, but the *secure-by-default* discipline (HTTPS-only, auth always on, assert it in
a gate) is the project's established pattern (code-server `cert: true`, noVNC `--ssl-only`, gitleaks/no-changeme
gates).

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `--nogpgcheck` on the DCV RPM install | Bake "just works" if GPG import is fiddly | Silent supply-chain hole; violates pin-everything posture | **Never** — import NICE-GPG-KEY + checksum the tgz |
| `enable-quic-frontend=true` "for performance" | Better LAN streaming | Breaks the SSM-port-forward path (UDP can't tunnel) — the only access path here | **Never** while SSM is the access path |
| `authentication=none` to skip password debugging | Instant connect during dev | Passwordless desktop reachable on 8443; breaks secure-by-default | **Never** |
| `setenforce 0` / SELinux permissive to dodge AVCs | Session works immediately | Defeats the entire hardening milestone; violates project posture | **Never** — use restorecon + audit2allow scoped module |
| Floating `nice-dcv-…latest` download URL | Always "newest" | Non-reproducible bake; violates lockfile/AMI-pin invariants | **Never** — pin exact version + checksum |
| DCV **console** session w/ gdm autologin | "Real" physical desktop | Autologin + Wayland/seat0 fragility + 2.2.1 X dependency | OK for single headless op; **virtual** session is lower-risk — evaluate first |
| Disable TLS on 8443 to debug the cert | Removes FIPS handshake variable | Plaintext desktop; breaks HTTPS-only invariant | **Never** — fix the cert (FIPS-clean + SAN) instead |
| Broad "allow all S3" gateway endpoint policy | License GET just works | Wider data-egress surface than needed | Acceptable short-term; tighten to dcv-license + dnf + tfstate later |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| S3 license bucket (`dcv-license.<region>`) | Assuming "DCV on EC2 is license-free ⇒ no S3 needed" | Free of *cost*, but requires reachable S3 GET: gateway VPC endpoint + IAM `s3:GetObject` on the regional bucket |
| IMDS / instance role | Role attached but IMDS hop-limit/IMDSv2 blocks the credential chain ("no session" in SDK log) | Confirm instance profile attached + IMDSv2 reachable; `…/meta-data/iam/security-credentials/` returns the role |
| S3 gateway endpoint policy | Inheriting a tfstate-only endpoint policy that blocks the license GET | Endpoint policy must also allow `dcv-license.<region>` (+ dnf/SSM buckets if they traverse it) |
| SSM Session Manager port-forward | Expecting it to tunnel QUIC/UDP 8443 | SSM is TCP-only — disable QUIC; forward TCP 8443 only |
| CloudFront DCV download | Floating `latest` URL + `--nogpgcheck` | Pin exact version filename; import NICE-GPG-KEY; checksum the tgz; let dnf verify the sig |
| gdm (console session) | Leaving Wayland on / no seat0 session | `WaylandEnable=false` + autologin (or use a virtual session and skip gdm entirely) |
| System PAM (CIS authselect/faillock) | DCV PAM service not delegating to system-auth ⇒ auth denied | Provide `/etc/pam.d/dcv` delegating to `system-auth`/`password-auth`; verify faillock/loginuid don't block |

## Performance Traps

Patterns that work at small scale but fail as usage grows. *(Single-operator project — scale traps are minimal; these are the relevant ones.)*

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| QUIC-off ⇒ all data over TCP/WebSocket | Slightly higher latency on lossy links vs QUIC | Accept it — SSM is TCP-only anyway; tune frame rate / quality in dcv.conf if needed | Only matters on high-latency/lossy WAN; SSM masks the choice |
| Software (Mesa/llvmpipe) rendering, no GPU | Heavy 3D/GL apps sluggish | Expected on non-GPU; if 3D needed, move to a g4dn + NVIDIA + nice-dcv-gl | When the operator runs GPU-bound workloads |
| `/dev/shm` too small or `noexec` (CIS) | X MIT-SHM / GL shader failures, slow paint | Check `/dev/shm` size + exec; relocate caches if noexec bites | Heavy desktop apps; immediately if a component exec's from shm |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| `authentication=none` in dcv.conf | Passwordless desktop on 8443 — full RCE-equivalent if 8443 ever reachable | Keep `authentication=system`; grep-gate against `authentication=none` |
| Disabling TLS on 8443 | Plaintext desktop stream; breaks HTTPS-only invariant | Keep TLS on; FIPS-clean cert (Pitfall 7) |
| `setenforce 0` / permissive to silence AVCs | Defeats SELinux hardening for the whole box | restorecon + scoped audit2allow module; never ship permissive |
| Over-broad IAM (`s3:*` or `*` resource) for the license | Larger blast radius than `GetObject` on one bucket | Scope to `s3:GetObject` on `arn:aws:s3:::dcv-license.<region>/*` exactly |
| gdm autologin without compensating controls | Local "anyone at console" — but box is headless | Acceptable *only* because there is no physical console + SSM/IAM + TLS are the real boundary; document it |
| Opening UDP 8443 in the SG "just in case" | Widens attack surface for a path SSM can't even use | Don't — 8443 **TCP** only for the SSM posture |
| `--nogpgcheck` on the vendor RPM | Unverified binary in the hardened image | Import NICE-GPG-KEY + checksum tgz; dnf verifies sig |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Chasing the benign `dcv-gl disabled` / "no GPU" log | Hours lost debugging a non-error | Document it as expected on non-GPU; don't install dcv-gl |
| "Auth works but screen never paints" (QUIC) misread as a server bug | Operator can't connect, blames DCV | Document the QUIC-over-SSM symptom + the `enable-quic-frontend=false` fix in `./run` troubleshooting |
| No session after boot ⇒ "DCV is broken" | Confusion vs VNC/xrdp expectations | Auto-create the console/virtual session in dcv.conf; document `dcv list-sessions` |
| GNOME colord polkit popup hangs the session | Desktop appears frozen on connect | Ship the `45-allow-colord.rules` polkit allow (reuse xrdp's) |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces — verify at live UAT, not just at bake.

- [ ] **DCV server installed:** bake green, but did it license? Verify `dcv create-session` succeeds **on a
      private instance** (not just `dcvserver` active) — Pitfall 1.
- [ ] **Session exists:** `dcvserver` up ≠ session present — verify `dcv list-sessions` non-empty post-boot — Pitfall 2.
- [ ] **Console session attaches:** verify `loginctl` shows a seat0 GNOME-on-Xorg session + `WaylandEnable=false` — Pitfall 3.
- [ ] **Web client paints:** auth succeeding ≠ display channel up — verify the desktop **renders over `./run`
      SSM port-forward** with `enable-quic-frontend=false` — Pitfall 4.
- [ ] **Survives hardening:** verify X server, gdm, fonts, DCV binaries, dcv.conf **still present after the
      hardening reboot** (assert the end state, not install-time) — Pitfall 8.
- [ ] **AVC-clean under enforcing:** `ausearch -m AVC -ts boot` shows no DCV/Xorg denials after first connect — Pitfall 6.
- [ ] **FIPS handshake:** `openssl s_client -connect localhost:8443` completes under the runtime FIPS provider — Pitfall 7.
- [ ] **Auth + TLS not weakened:** `grep -E 'authentication|no-tls|enable-quic' /etc/dcv/dcv.conf` shows
      system/TLS-on/QUIC-off — Pitfall 11.
- [ ] **Install integrity:** version pinned + GPG-verified + checksummed; no `latest` URL, no `--nogpgcheck` — Pitfall 9.
- [ ] **License region:** ARN region == instance region; endpoint policy allows `dcv-license.<region>` — Pitfall 10.
- [ ] **xrdp/VNC/noVNC fully removed:** no dead remote-desktop config, no stale `:3389`/`:6080` SG rules,
      no orphaned roles in the playbook (milestone scope).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| 1 License `ORIGIN_OBJECT_MISSING` | MEDIUM | Add S3 gateway endpoint + IAM `s3:GetObject` on `dcv-license.<region>`; `tf-apply`; restart `dcvserver`; verify `aws s3 ls s3://dcv-license.<region>/` from the box |
| 2 No session | LOW | Add `create-session=true` + auto-console-session to dcv.conf; restart `dcvserver` (or run `dcv create-session` once) |
| 3 Console won't attach (Wayland/seat0) | LOW–MEDIUM | `WaylandEnable=false` + autologin; or pivot to a virtual session (no gdm) |
| 4 QUIC hang over SSM | LOW | `enable-quic-frontend=false`; restart `dcvserver`; reconnect over SSM |
| 6 SELinux AVCs | MEDIUM | `ausearch … \| audit2allow -M dcv_local && semodule -i dcv_local.pp`; vendor the module into the role; rebake |
| 7 FIPS TLS fail | MEDIUM | Regen FIPS-clean cert (RSA-2048/sha256/SAN), point dcv.conf at it, restart; rebake with the cert task |
| 8 CIS purged X / broke PAM | MEDIUM–HIGH | Confirm `2.2.1=false` + guard; add PAM delegate + colord .rules; re-assert end state; rebake |
| 9 Airgap install fail | LOW | Pin exact version URL + import GPG + checksum; rebake |
| 11 dcv.conf insecure/wrong | LOW | Fix the key, restart `dcvserver`; add the grep-gate so it can't regress |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 Airgap license | **Terraform networking/IAM** (S3 gateway endpoint + IAM on `aws_iam_role.devbox`) | `aws s3 ls s3://dcv-license.<region>/` + `dcv create-session` succeed on a **private** instance (live gate) |
| 2 No session | `dcv` role — dcv.conf | `dcv list-sessions` non-empty after boot (bake-assert config key; live-confirm) |
| 3 Console attach (Wayland/seat0) | `desktop`/`dcv` session-backend (or choose virtual) | `loginctl` seat0 + `WaylandEnable=false`; client attaches (live gate) |
| 4 QUIC over SSM | `dcv` role dcv.conf + Terraform SG (8443 TCP) | `enable-quic-frontend=false` asserted; desktop paints over `./run` SSM forward (live gate) |
| 5 dcv-gl benign | `dcv` role (omit dcv-gl) + docs | dcv-gl not installed; benign message documented |
| 6 SELinux AVCs | `dcv` role (restorecon + optional module) | `ausearch -m AVC -ts boot` clean after first connect (live gate) |
| 7 FIPS TLS | `dcv` role cert phase | cert SAN/algo/size bake-asserted; `s_client` handshake under FIPS (live gate) |
| 8 CIS collisions | hardening-defaults (keep 2.2.1=false + guard) + `dcv` role (PAM, colord .rules, post-hardening asserts) | post-hardening stat asserts; auth + render (live gate) |
| 9 Airgap install | `dcv` role — install (pinned URL + GPG + checksum) | bake fails on bad sig/checksum; version pin present (grep-gate) |
| 10 License region/endpoint | Terraform networking/IAM + `./run` doctor | region-derived ARN; endpoint policy includes dcv-license; doctor license check |
| 11 dcv.conf security | `dcv` role dcv.conf + grep-gate | grep-gate rejects `authentication=none`/TLS-off; QUIC-off + auth=system asserted |

## Sources

- AWS — Install the Amazon DCV Server on Linux (AL2023 packages, NICE-GPG-KEY, CloudFront URLs): https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html — **HIGH**
- AWS — Prerequisites for Linux Amazon DCV servers (GNOME `@Desktop`, `WaylandEnable=false`, XDummy `xorg-x11-drv-dummy`, X server / console-vs-virtual, Mesa software OpenGL): https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html — **HIGH**
- AWS — Step 2: License the Amazon DCV Server (EC2 S3 license, exact IAM ARN `s3:GetObject` on `dcv-license.{region}/*`, gateway VPC endpoint, eval-license fallback, partitions): https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-license.html — **HIGH**
- AWS — Disabling the QUIC UDP transport protocol (`[connectivity] enable-quic-frontend=false`; QUIC default-on since 2024.0; auth over WebSocket, data over QUIC/UDP): https://docs.aws.amazon.com/dcv/latest/adminguide/disable-quic.html — **HIGH**
- AWS — Starting Amazon DCV sessions / session-management (no auto-session; `create-session=true` + `automatic-console-session owner`): https://docs.aws.amazon.com/dcv/latest/adminguide/managing-sessions-start.html — **HIGH**
- AWS re:Post — Unable to license DCV (`ORIGIN_OBJECT_MISSING`, endpoint/IAM root causes): https://repost.aws/questions/QU64puCu8OSySAzLNPJuTRPA/unable-to-license-dcv — **MEDIUM**
- AWS re:Post — Install GUI on AL2023 (DCV + GNOME on AL2023, practical steps): https://repost.aws/articles/ARq0LbVvRwTRukVpS6Zt1uZw/ — **MEDIUM**
- In-repo — `.planning/phases/11-service-config-pam-session-bake-verification/11-VERIFICATION.md` (xrdp adversarial findings: CIS 2.2.1 deletes X; FIPS no-SAN cert rejection; SELinux relabel≠policy/AVC-only-at-enforcing-boot; `.pkla`→`.rules` polkit; `pam_loginuid`; colord popup; software render OK) — **HIGH (proven on this exact host)**
- In-repo — `ansible/roles/hardening/defaults/main.yml` + `tasks/main.yml` (SELinux enforcing + FIPS enabled in last role + reboot; `amzn2023cis_rule_2_2_1=false` desktop exception already set) — **HIGH**
- In-repo — `ansible/roles/AMAZON2023-CIS/` (2.2.1 X purge; 1.1.2.x/1.1.8.x noexec mount rules gated on separate partition / `amzn2023cis_tmp_svc`; 1.7.x banners; authselect sssd PAM) — **HIGH**
- In-repo — `ansible/roles/xrdp/` (transferable FIPS-clean cert task w/ SAN, `semanage fcontext`+restorecon, firewalld port-open, colord `.rules`, PAM-delegate, bake-assert patterns) — **HIGH**
- In-repo — `ansible/roles/desktop/tasks/main.yml` (`@Desktop` + `gnome-session` + `mesa-dri-drivers` already installed; no WaylandEnable/autologin yet — gap for DCV console) — **HIGH**
- Live this session — Pitfalls 1–5 reproduced and fixed on a running instance (license endpoint+IAM, dcv.conf create-session, Wayland+seat0, QUIC-off, dcv-gl-benign) — **HIGH (empirical)**

---
*Pitfalls research for: Amazon DCV on a CIS-hardened (SELinux enforcing + FIPS), airgapped, SSM-only AL2023 EC2*
*Researched: 2026-06-18*
