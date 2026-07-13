---
phase: quick-260707-o7s-xrdp-spal
plan: 01
subsystem: infra
tags: [xrdp, xorgxrdp, spal, al2023, rdp, ansible, terraform, pam, gnome, tls]

# Dependency graph
requires:
  - phase: 13-14 (Amazon DCV role)
    provides: "dcv role patterns (secrets-reuse assert, FIPS cert recipe, PAM delegate, SELinux relabel, static bake asserts), GNOME-on-Xorg software-render launcher, desktop-gated ordering, :8443 SG posture"
  - phase: secrets role
    provides: "ec2-user desktop_password (SSM SecureString) reused by xrdp PAM — no new secret"
provides:
  - "ansible/roles/xrdp: SPAL-sourced xrdp + xorgxrdp (RDP :3389), PAM->password-auth, GNOME-on-Xorg startwm.sh, TLS-hardened xrdp.ini, services enabled, static bake asserts"
  - "Terraform :3389/tcp SG ingress gated on var.allowed_web_cidrs (mirrors DCV :8443, TCP-only)"
  - "CLAUDE.md (local guide) SPAL caveat + RDP operator note + :3389 troubleshooting + deferred-pin follow-up"
affects: [remote-desktop, hardening-ordering, spal, live-uat]

# Tech tracking
tech-stack:
  added: [xrdp, xorgxrdp, spal-release, "SPAL (amazonlinux-spal) repo"]
  patterns:
    - "SPAL enable via the Amazon-signed spal-release package (not a hand-written .repo file)"
    - "system-release version-floor assert via package_facts + version test (loose)"
    - "additive second remote-desktop path — mirror dcv role, do not modify it"

key-files:
  created:
    - ansible/roles/xrdp/defaults/main.yml
    - ansible/roles/xrdp/files/xrdp-sesman.pam
    - ansible/roles/xrdp/files/startwm.sh
    - ansible/roles/xrdp/tasks/main.yml
  modified:
    - ansible/playbook.yml
    - ansible/layer_config.yml
    - terraform/main.tf
    - terraform/variables.tf
    - CLAUDE.md  # edited on disk only — gitignored in this repo (commit effde0f), NOT committed

key-decisions:
  - "SPAL enabled via Amazon-signed spal-release (drops amazonlinux-spal.repo + imports GPG keys); GPG check stays ON for every dnf install"
  - "xrdp is purely additive to DCV — dcv role, its SG, and its operator surface are byte-for-byte unchanged"
  - "TLS-hardened xrdp.ini (security_layer=tls, crypt_level=high, FIPS-safe self-signed cert) — bake asserts reject the weak security_layer=rdp"
  - "CLAUDE.md is gitignored (local-only operator guide, commit effde0f) — doc edits applied on disk, NOT force-committed"

patterns-established:
  - "SPAL package source: assert system-release floor first, enable via spal-release, install version-pinned (deferred-pin)"
  - "Role-local vars carry the xrdp_ prefix (xrdp_version, xrdp_xorgxrdp_version, xrdp_spal_min_system_release)"

requirements-completed: [XRDP-01, XRDP-02, XRDP-03, XRDP-05]  # code/bake-time complete; XRDP-04 (runtime) pending Task 3 human-verify

# Metrics
duration: ~25min
completed: 2026-07-07
---

# Quick Task 260707-o7s: xrdp (RDP :3389) from SPAL Summary

**A new SPAL-sourced `xrdp` Ansible role (xrdp + xorgxrdp, PAM->password-auth reusing the existing ec2-user desktop password, GNOME-on-Xorg software-render startwm.sh, TLS-hardened xrdp.ini, static bake asserts) wired before `hardening`, plus a Terraform :3389/tcp SG ingress mirroring the DCV :8443 posture — a second, WebGL-free remote-desktop path additive to Amazon DCV.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-07-07T17:45Z (approx)
- **Completed:** 2026-07-07T22:10Z (Tasks 1-2; Task 3 blocking human-verify pending)
- **Tasks:** 2 of 3 executed (Task 3 is a BLOCKING checkpoint:human-verify — stopped as designed)
- **Files modified:** 9 (8 committed across 2 commits + CLAUDE.md applied on-disk, gitignored)

## Accomplishments

- **`ansible/roles/xrdp`** — full bake-time role: dev_user PAM-password assert (ported from dcv), SPAL system-release floor gate (package_facts + `version` test), SPAL enable via `spal-release`, version-pinned (deferred-pin) `dnf install xrdp xorgxrdp` (GPG on), `/etc/pam.d/xrdp-sesman` -> password-auth, GNOME-on-Xorg software-render `/etc/xrdp/startwm.sh`, FIPS-safe TLS cert + `ini_file` hardening of `/etc/xrdp/xrdp.ini` (security_layer=tls, crypt_level=high), `systemctl enable xrdp xrdp-sesman`, SELinux relabel, and a static bake-assert block (artifacts + PAM/TLS content + is-enabled).
- **Wired before `hardening`** (hardening stays last — grep-gate PASS), gated on `layers.xrdp and layers.desktop`; `xrdp: true` added to `layer_config.yml`.
- **Terraform `:3389/tcp` SG ingress** gated on `var.allowed_web_cidrs` (TCP-only — no UDP/QUIC unlike DCV), mirroring the DCV `:8443` TCP block; SG header comment + `allowed_web_cidrs` description updated. `tofu fmt -check` + `tofu validate` PASS.
- **DCV untouched** — the dcv role, its `:8443` TCP+UDP ingress, and its operator surface are byte-for-byte unchanged (additive only).
- **Operator docs** applied to the local CLAUDE.md guide (SPAL not-CVE-tracked / not-AWS-supported caveat, RDP connect note, `:3389` troubleshooting entry, xrdp deferred-pin §9 follow-up).

## Task Commits

Each executed task was committed atomically (code only):

1. **Task 1: Create the `xrdp` role + wire before `hardening`** - `1ab1835` (feat)
2. **Task 2: Terraform `:3389/tcp` SG ingress + CLAUDE.md docs** - `33690e9` (feat)
   _(CLAUDE.md docs applied on-disk only — gitignored in this repo; see Deviations.)_
3. **Task 3: Runtime / adversarial verification** - **NOT RUN — BLOCKING `checkpoint:human-verify`.** Requires a live baked + launched instance and an RDP client inside `var.allowed_web_cidrs`. Stopped as designed. See "Pending Human Verification" below.

**Plan metadata (SUMMARY/STATE):** handled by the orchestrator (quick-task docs commit).

## Files Created/Modified

- `ansible/roles/xrdp/defaults/main.yml` - deferred-pin version vars (`xrdp_version`, `xrdp_xorgxrdp_version`), `xrdp_spal_min_system_release` floor, dev_user/dev_home
- `ansible/roles/xrdp/files/xrdp-sesman.pam` - `/etc/pam.d/xrdp-sesman` delegating auth/account/session/password to `password-auth` (dcv.pam body verbatim; only header differs)
- `ansible/roles/xrdp/files/startwm.sh` - GNOME-on-Xorg + llvmpipe software-render session launcher (mirrors dcv-gnome-session.sh)
- `ansible/roles/xrdp/tasks/main.yml` - the full install/config/enable/assert task list (see Accomplishments)
- `ansible/playbook.yml` - `- role: xrdp` inserted after `dcv`, before `hardening`, gated on xrdp+desktop
- `ansible/layer_config.yml` - `xrdp: true`
- `terraform/main.tf` - `:3389/tcp` ingress + SG header comment
- `terraform/variables.tf` - `allowed_web_cidrs` description now names `:3389`
- `CLAUDE.md` - SPAL caveat (§8 adjacent note), RDP connect note (§5), `:3389` troubleshooting (§7), deferred-pin follow-up (§9) — **applied on disk; gitignored (not committed)**

## Decisions Made

- **SPAL via `spal-release`** — used the Amazon-signed core-repo package (installs `/etc/yum.repos.d/amazonlinux-spal.repo` + imports SPAL GPG keys) rather than hand-writing a `.repo` file, per `<spal_facts>`. Avoids a drift-prone hardcoded baseurl/GPG key and keeps GPG verification on.
- **TLS cert perms** — `root:xrdp 0640` (not dcv's `dcv:dcv 0600`), so the `xrdp` daemon user can read the key. Runtime handshake correctness is proven by Task 3.
- **`create: false`** on the `xrdp.ini` `ini_file` edits — fails the bake loudly if the SPAL xrdp RPM ever stops shipping `/etc/xrdp/xrdp.ini` (layout-regression tripwire).

## Deviations from Plan

### Auto-fixed / adjusted

**1. [Rule 3 - Blocking / lint] System-release read via `package_facts` instead of `command: rpm -q`**
- **Found during:** Task 1 (SPAL floor gate)
- **Issue:** The plan described gathering `system-release` via `rpm -q` / a command. A raw `command: rpm` trips ansible-lint `command-instead-of-module` and needs a manual `changed_when`.
- **Fix:** Used `ansible.builtin.package_facts` (module-based, lint-clean) and asserted `ansible_facts.packages['system-release'][0].version is version(xrdp_spal_min_system_release, '>=', version_type='loose')`. Same dotted-numeric AL2023 floor semantics, cleaner.
- **Files modified:** ansible/roles/xrdp/tasks/main.yml
- **Verification:** YAML parse OK; best-effort ansible-lint shows no new command-instead-of-module flag for this task.
- **Committed in:** `1ab1835`

**2. [Rule 3 - Convention / lint] Role-local vars given the `xrdp_` prefix**
- **Found during:** Task 1
- **Issue:** The plan named `xorgxrdp_version` and `spal_min_system_release`. ansible-lint's `var-naming[no-role-prefix]` (production profile) wants role-local vars prefixed with the role name; these two are new-to-role (unlike `dev_user`/`dev_home`, which mirror dcv and are also play-level vars).
- **Fix:** Renamed to `xrdp_xorgxrdp_version` and `xrdp_spal_min_system_release`. `xrdp_version` (already prefixed) is unchanged; the plan's must-have `defaults contains "xrdp_version"` still holds. `dev_user`/`dev_home` kept unprefixed to mirror dcv exactly (accepted precedent — the committed dcv role produces the identical local-lint flag).
- **Files modified:** ansible/roles/xrdp/defaults/main.yml, ansible/roles/xrdp/tasks/main.yml
- **Verification:** YAML parse OK; refs updated in tasks/main.yml.
- **Committed in:** `1ab1835`

**3. [Rule 4 - Policy boundary] CLAUDE.md is gitignored — doc edits applied on disk, NOT force-committed**
- **Found during:** Task 2 (staging the CLAUDE.md docs)
- **Issue:** The plan lists `CLAUDE.md` in `files_modified` and requires the SPAL caveat / RDP note there. But this repo **deliberately gitignores CLAUDE.md** — `.gitignore:21` ("Claude Code ... per-repo guide, not project files"), established by commit `effde0f chore: untrack CLAUDE.md (local-only operator guide)`. `git add CLAUDE.md` is refused; the file has never been tracked since `effde0f`.
- **Decision:** Did **NOT** `git add -f` / force-commit — that would reverse a deliberate maintainer decision (an architectural/policy override outside auto-fix authority, Rule 4). Instead the doc edits are applied **on disk**, which is exactly how this repo consumes CLAUDE.md (a local operator guide). XRDP-05's operator-facing doc outcome is satisfied in the repo's actual model.
- **Impact:** The SPAL caveat / RDP note / troubleshooting / deferred-pin follow-up live in the local CLAUDE.md and are NOT in git history. If the maintainers want these version-controlled, they must consciously re-track CLAUDE.md (reverting `effde0f`) or relocate the note into a tracked doc (e.g. PROJECT.md / a phase doc) — a policy call for the human.
- **Files modified:** CLAUDE.md (on disk only)
- **Committed in:** n/a (intentionally uncommitted; noted in `33690e9` commit body)

---

**Total deviations:** 3 (2 lint/convention auto-adjustments, 1 policy-boundary decision surfaced for the human).
**Impact on plan:** No scope creep. Adjustments 1-2 keep the role CI-lint-clean and consistent with the naming convention. Adjustment 3 respects an explicit repo policy and is surfaced for a human decision; the operator-facing docs are live on disk regardless.

## Known Stubs / Deferred-pins (intentional)

- `xrdp_version: ""` and `xrdp_xorgxrdp_version: ""` in `ansible/roles/xrdp/defaults/main.yml` are **empty by design** (deferred-pin, mirrors dcv's `dcv_tarball_sha256: ""` and the Packer SSM `:NN` posture, CLAUDE.md §9). Empty = install the latest in the *versioned* SPAL repo; resolve at first bake via `dnf list --repo=amazonlinux-spal xrdp xorgxrdp` and fill both to pin exact version-release strings. This is not a blocking stub — the versioned SPAL repo already provides determinism; the explicit pin is the belt-and-braces follow-up. Tracked in CLAUDE.md §9.

## Issues Encountered

- **Local ansible-lint mismatch (environmental, non-blocking):** the workstation has ansible-lint v6.22.2 + ansible-core 2.15 + old collections; CI is authoritative (ansible-lint **v26.4.0**, ansible-core ≥2.16, `.ansible-lint` `profile: production`). The local `.ansible-lint` even rejects `parseable`. Verified the xrdp role produces **only** the same residual local flags (`dev_user`/`dev_home` no-role-prefix, `systemctl is-enabled` command-instead-of-module) that the already-committed, CI-linted **dcv role** produces — i.e. accepted precedent. No project config was touched (out of scope). The authoritative lint runs in CI (`ansible-lint ansible/playbook.yml`) and on `pre-push`.

## Pending Human Verification — Task 3 (BLOCKING checkpoint:human-verify)

**This is the runtime / adversarial half that defeats "bake green, service dead." It needs live AWS + an RDP client inside `var.allowed_web_cidrs` and CANNOT be automated. The static bake asserts (in the role) prove the artifacts exist and the services are ENABLED; the SG ingress is applied by `tf-apply`. Everything automatable is automated.**

Run on a live baked + launched instance and record results in `.planning/quick/260707-o7s-xrdp-spal/260707-o7s-VERIFICATION.md`:

1. `DEVBOX_USER=$(whoami) ./run build && ./run tf-init && ./run tf-apply && ./run start` (the bake must SUCCEED — the static xrdp asserts fail loudly if any artifact is missing or a service is not enabled).
2. `./run devbox-ssm`, then: `systemctl is-active xrdp xrdp-sesman` (expect active/active); `sudo ss -tlnp | grep ':3389'` (expect xrdp LISTEN on 0.0.0.0:3389); `sudo ausearch -m avc -ts boot 2>/dev/null | grep -i xrdp || echo "no xrdp AVCs"`.
3. Adversarial PAM/RDP auth (loopback, no GUI). Get the password via `./run secrets-show` (desktop-password), then EITHER `xfreerdp /v:127.0.0.1:3389 /u:ec2-user /p:'<pw>' +auth-only /cert:ignore` (exit 0 == full RDP+PAM auth path OK) OR `sudo dnf install -y pamtester && pamtester xrdp-sesman ec2-user authenticate`. A WRONG password MUST be rejected (repeat with a bad password → failure).
4. From inside `var.allowed_web_cidrs`, point an RDP client (mstsc / Remmina / FreeRDP GUI) at `<host>:3389`, log in as ec2-user + desktop password, confirm a GNOME desktop renders (not blank / not a Wayland failure).
5. Confirm DCV `:8443` is still reachable and unchanged (additive).

**Resume signal:** type "approved" once steps 1-5 pass. If any step fails, capture the evidence (bake assert output, `systemctl status xrdp xrdp-sesman`, `ss` output, xfreerdp/pamtester error, or Xorg/session log). Likely culprits: SPAL system-release floor, xrdp binary path skew (`rpm -ql xrdp | grep sbin`), xorgxrdp module path (lib vs lib64: `rpm -ql xorgxrdp | grep xorg/modules`), PAM not delegating to password-auth, TLS cert/key perms the daemon can't read, or startwm.sh not rendering GNOME.

## Next Steps / Readiness

- **Human:** run Task 3 live verification (above) and record `260707-o7s-VERIFICATION.md`. Optionally resolve the SPAL version pin at first bake (§9 deferred-pin).
- **Human (policy):** decide whether the CLAUDE.md SPAL/RDP docs should be version-controlled (would require re-tracking CLAUDE.md against `effde0f`, or moving the note into a tracked doc).

## Self-Check: PASSED

- Files: all 9 present on disk (8 tracked/committed + CLAUDE.md on-disk, gitignored).
- Commits: `1ab1835` (Task 1) and `33690e9` (Task 2) both exist in git history.
- No unexpected file deletions in either commit.

---
*Quick task: 260707-o7s-xrdp-spal*
*Completed (Tasks 1-2): 2026-07-07 — Task 3 pending BLOCKING human-verify*
