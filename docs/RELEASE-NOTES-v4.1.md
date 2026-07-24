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
