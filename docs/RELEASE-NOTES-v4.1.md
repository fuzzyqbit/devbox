# Release Notes — v4.1 Google Chrome in desktop role

**Status:** code-complete, pushed to `main` (`07b0ca5`), CI green. Milestone closes after
the Phase 17 live UAT (launch Chrome in a GNOME session on a real instance).

## What's new

### Google Chrome baked into every desktop image (Phase 16, CHROME-02)

`google-chrome-stable` now installs during every `layers.desktop: true` bake, from
Google's official signed dnf repo — no new layer flag, no sub-gate; Chrome is
unconditional desktop content.

- **Trust chain:** Google's Linux signing key is imported via `rpm_key`; the baked
  `/etc/yum.repos.d/google-chrome.repo` carries `gpgcheck=1`; the dnf install keeps
  `disable_gpg_check: false`. GPG posture unchanged (CLAUDE.md §2/§8).
- **Self-healing repo config:** the baked `.repo` content is byte-identical to what
  Chrome's own RPM `%post` writes, so the RPM's unconditional overwrite at install is a
  content no-op and Chrome's daily cron finds nothing to "fix".
- **Version policy — latest-at-bake:** Google's repo hosts only the current stable
  (historic RPMs are not published), so a strict pin is impossible; each bake captures
  the then-current version, recorded by the existing SBOM pass. Remediation for a bad
  version is a rebake (same accepted tradeoff as SPAL/xrdp).
- Playbook invariants intact: `hardening` stays the last role, `sbom.yml` the last
  import; append-only change to `ansible/roles/desktop/tasks/main.yml`.

### dnf versionlock + salt-minion freeze (quick task 260724-dh7)

The `base` role now installs `python3-dnf-plugin-versionlock` and locks
`salt-minion` to the version already present on the source AMI — **before** the
bake-time full-image update, so `dnf update *` can never bump it past the lock.

- Pin-by-observation: `dnf versionlock add` captures the installed NEVRA at bake time;
  no version literal lives in the playbook. Each bake re-captures from the then-current
  source AMI.
- Conditional: images without salt-minion (public AL2023 minimal AMI) skip cleanly with
  a logged note instead of failing.
- Extensible via `dnf_versionlock_packages` in `ansible/roles/base/defaults/main.yml`.
- Unlock on-box: `dnf versionlock delete salt-minion`; or rebake to re-capture.

### CI

- New `bats` job runs the kion-creds unit suite (35 tests) on every PR/push; shellcheck
  job extended to cover the kion role shell files, test mocks, and bats files.
  (Supports the unmerged `feat/kion-creds` branch — see below.)

## Previously shipped, previously unreleased (v3.0 → v4.1)

No release was tagged between v3.0 (2026-06-02) and v4.1; the following landed on
`main` in that window and appears in release notes for the first time here.

- **v4.0 Amazon DCV remote desktop** (merged 2026-06-26): new `dcv` role — non-GPU
  DCV server on AL2023, PAM auth, TLS + QUIC, virtual GNOME session via `Xdcv` —
  reached by **direct connect** on `:8443` (TCP+UDP) gated on `var.allowed_web_cidrs`;
  airgap license path via the regional `dcv-license.<region>` S3 bucket (VPC endpoint +
  scoped IAM assumed present). Replaced the v3.2 from-source xrdp stack and removed
  VNC/noVNC entirely.
- **xrdp re-added from SPAL** (quick-task `260707-o7s`, merged 2026-07-13): RDP on
  `:3389` as a **second, WebGL-free desktop path, additive to DCV** — a fallback for
  jumpbox browsers without WebGL, not a DCV replacement. `xrdp`/`xorgxrdp` install from
  SPAL (Supplementary Packages for Amazon Linux; Amazon-signed repo, GPG on, but
  packages are as-is EPEL9 rebuilds with **no AWS CVE tracking** — documented operator
  tradeoff, CLAUDE.md §8; remediation is rebake). Requires the system Xorg, so CIS rule
  2.2.1 is scoped OFF for xrdp builds only (post-hardening assert guards the X server);
  DCV-only builds keep 2.2.1 enforced. Login: `ec2-user` + desktop password from
  `./run secrets-show`.
- **Persistent `/home` EBS volume** (merged 2026-06-26): separate volume survives AMI
  swaps/instance replacement (`prevent_destroy`), DLM snapshots; decommission requires
  an explicit `tofu state rm` first (CLAUDE.md §7).
- **ai_tools role** (PR #6, merged 2026-07-14): pinned agentic AI CLIs (claude-code,
  codex, opencode) as npm globals in `/usr/local`; no auth baked — operators log in at
  runtime, creds persist on the `/home` volume.
- **SBOM pass** (PR #5): every bake ends with checksum-pinned syft writing a CycloneDX
  inventory to `/etc/devimage-sbom.cdx.json` + a per-bake copy fetched to `sbom/`.
- **ansible-core baked** (PR #4) and **CI baseline fixes** (PR #3: lint config, checkov,
  tofu-validate unhang, push-trigger scoped to main).

## In flight (not in this release)

- **`feat/kion-creds`** (branch, review-clean, unmerged): `kion-creds` CLI + login-shell
  hook fetching short-term AWS credentials from Kion (`layers.kion`, default off). Token
  endpoint verified against the live org Kion; remaining endpoint shapes confirm at
  first use.

## Upgrade notes

- Rebake required to pick up Chrome and the versionlock: `./run build && ./run tf-apply`.
  **The next `tf-apply` replaces the instance** (pending since the 2026-07-13
  root-volume-encryption change); the persistent `/home` volume survives by design.
- Open live-UAT backlog rides the same bake: DCV (v4.0), xrdp `:3389`, ai-tools
  first-bake, SBOM first exercise, Chrome launch (Phase 17), versionlock proof.

## Known issues / advisories

- Google signing-key trust is TLS-only at bake time (no fingerprint assert) — accepted;
  hardening snippet on file in `16-REVIEW.md` (WR-01).
- Pre-existing, unrelated to this release: unpinned ffmpeg download in the desktop role
  (CR-01, tracked for a future quick task); `no-changeme` hook false-positives on the
  secrets role's guard asserts.

---
*Phase 16 verification: 4/4 must-haves passed (2026-07-24). Requirements: CHROME-02
delivered; CHROME-01 at Phase 17 UAT; CHROME-03/04 deferred by operator decision.*
