# Quick Task 260707-o7s: add xrdp support from SPAL repo - Context

**Gathered:** 2026-07-07
**Status:** Ready for planning

<domain>
## Task Boundary

Add xrdp (RDP remote desktop) support to the devbox AMI, sourcing the xrdp
packages from **SPAL** (Supplementary Packages for Amazon Linux) — the AL2023
EPEL9-rebuild repository — rather than building from source or using EPEL
(EPEL is not binary-compatible with AL2023). xrdp is added as a **second**
remote-desktop path alongside the existing Amazon DCV role (additive, not a
replacement). PAM password logins must work.

Motivation: the DCV web client requires WebGL, which is unavailable on the
operator's constrained jumpbox (software GL / no GPU / Chrome SwiftShader
removed). xrdp speaks RDP on :3389 and needs no browser WebGL, so it survives
the jumpbox where DCV-in-browser does not.
</domain>

<decisions>
## Implementation Decisions

### Package source — SPAL, version-pinned
- Enable the **SPAL** repo (Supplementary Packages for Amazon Linux) via a
  dedicated `/etc/yum.repos.d/` repo file in the ansible role, then
  `dnf install xrdp xorgxrdp`.
- **Pin the xrdp package version** (`xrdp-<ver>`) in the role for
  determinism — the closest we get to the repo's SHA-pin invariant (CLAUDE.md)
  when installing from a package repo. Repo packages are GPG-signed by SPAL.
- SPAL is the AWS-sanctioned EPEL replacement for AL2023; EPEL itself is NOT
  binary-compatible with AL2023 and `amazon-linux-extras` does not exist.

### Relationship to DCV — additive (keep DCV)
- **Keep the existing DCV role and operator surface intact.** xrdp is an
  ADDITIONAL desktop path, not a replacement. Do not remove/modify the DCV
  role, its SG rules, or its `./run` commands. ("keep dcv for now and add xrdp")

### PAM logins — REQUIRED (explicit user requirement)
- xrdp auth goes through `xrdp-sesman` → PAM. The role MUST ensure
  `/etc/pam.d/xrdp-sesman` is present and configured so `ec2-user` can log in
  with the desktop password. SPAL's xrdp package ships a PAM file; the role
  must verify/repair it for AL2023 (the from-source Phase 10 role used
  `--with-pam-rules=redhat`; the SPAL package equivalent must be validated).
- **Reuse the existing `ec2-user` desktop password** already provisioned by the
  `secrets` role for DCV (SSM SecureString, surfaced via `./run secrets-show`).
  No new secret. PAM authenticates against the system password for ec2-user.

### Scope — role + network + operator
- **Ansible role** `xrdp`: SPAL repo file + version-pinned install + service
  enable + PAM config + xorgxrdp session backend. Reuses the existing desktop
  environment role.
- **Terraform**: security-group ingress `:3389/tcp` gated on
  `var.allowed_web_cidrs` (same allowlist pattern as DCV :8443). Direct-connect
  in-CIDR, consistent with the DCV posture.
- **Operator**: a `./run` connect note / helper for RDP (mirrors the DCV
  connect guidance). Login: `ec2-user` + desktop password.

### Invariants (CLAUDE.md — MUST honor)
- The `xrdp` role MUST be inserted **before `hardening`** in
  `ansible/playbook.yml` (C1 — hardening stays last).
- Any SPAL/AL2023 quirk workaround goes in its **own named playbook**
  (`ansible/xrdp-<quirk>-fix.yml`), imported by the main playbook — NOT inline
  in the role (C7 / workaround-layout rule).
- No `changeme` literal; no retired `make <target>` invocations.

### Docs — SPAL caveat
- Document in CLAUDE.md that SPAL packages are **not CVE-tracked and not
  covered by AWS Support Plans** — patches only when upstream provides. This is
  an accepted tradeoff (user chose SPAL over from-source).

### Verification — adversarial post-bake (added by orchestrator)
- Static "installed ✓" ≠ xrdp actually accepts an RDP session (the operator's
  "bake green, service dead" history). Plan MUST include a runtime verification
  step: confirm `xrdp`/`xrdp-sesman` services active, `:3389` listening, and a
  PAM auth path that a real RDP client would exercise — not just `rpm -q xrdp`.

### Claude's Discretion
- Exact xrdp/xorgxrdp version to pin (resolve against current SPAL contents).
- Whether the `./run` operator piece is a full subcommand or a documented
  `aws ssm`/direct-connect note this iteration.
- xrdp.ini / sesman.ini hardening specifics (TLS cert, crypt level) consistent
  with the existing DCV/CIS posture.
</decisions>

<specifics>
## Specific Ideas

- Prior art in-repo: Phase 10 (`.planning/phases/10-xrdp-xorgxrdp-from-source-build-role/`)
  built xrdp 0.10.6 + xorgxrdp 0.10.5 from source with a leading
  `ansible.builtin.assert` dep guard and `--with-pam-rules=redhat`. Reuse its
  PAM/session learnings; swap the from-source build for the SPAL package install.
- DCV role is the sibling pattern for: SG CIDR gating, secrets reuse, service
  enable, and the post-hardening service-alive assert in `ansible/playbook.yml`.
</specifics>

<canonical_refs>
## Canonical References

- AWS: EPEL compatibility in AL2023 / SPAL — https://docs.aws.amazon.com/linux/al2023/ug/epel.html
- xrdp upstream — https://github.com/neutrinolabs/xrdp ; xorgxrdp — https://github.com/neutrinolabs/xorgxrdp
- In-repo: CLAUDE.md §8 invariants; `ansible/roles/dcv/`, `ansible/roles/desktop/`, `ansible/roles/secrets/`; Phase 10 planning docs.
</canonical_refs>
