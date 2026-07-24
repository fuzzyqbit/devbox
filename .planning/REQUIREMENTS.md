# Requirements — Milestone v4.1 Google Chrome in desktop role

**Goal:** Every desktop bake ships Google Chrome, installed from Google's signed dnf repo at bake time.

**Shape:** No new role, no new layer flag — Chrome is unconditional desktop content inside the existing `desktop` role, applied whenever `layers.desktop` is on. Version policy is latest-at-bake (Google's repo serves only the current stable; historic RPMs are not hosted); remediation for a bad version is a rebake, matching the SPAL/xrdp precedent (CLAUDE.md §8).

---

## v4.1 Requirements

### Chrome (CHROME)

- [ ] **CHROME-01**: Operator can launch Google Chrome from the GNOME desktop (DCV or xrdp session) on every desktop bake.
- [ ] **CHROME-02**: Chrome installs from Google's official signed dnf repo — baked `.repo` config + GPG key, `gpgcheck=1`, no `--nogpgcheck` (GPG posture consistent with CLAUDE.md §2/§8 and the SPAL precedent).
- [ ] **CHROME-03**: The exact baked Chrome version is captured by the existing SBOM pass (`/etc/devimage-sbom.cdx.json` via `ansible/sbom.yml`) and visible in the build manifest; the latest-at-bake policy is documented in the role.
- [ ] **CHROME-04**: The bake fails loudly if Chrome is missing or cannot execute — headless `--version` bake-assert as `ec2-user`, plus a post-hardening survival guard (W1 pattern in `ansible/playbook.yml` post_tasks) if hardening could strip Chrome's dependencies.

---

## Future Requirements (deferred)

- Chrome policy management (managed preferences under `/etc/opt/chrome/policies/`) — no requirement yet; revisit if the desktop gains multi-operator use.
- Default-browser wiring (xdg-settings) — cosmetic; revisit at UAT if GNOME defaults annoy.

## Out of Scope

- **Strict Chrome version pin** — Google's repo hosts only the current stable; a pin breaks every bake on Chrome's ~4-6-week cadence for no reproducibility gain (the RPM it would pin disappears). Latest-at-bake + SBOM capture chosen instead.
- **Chromium / other browsers** — Chrome specifically requested; Chromium (EPEL) is a different support story.
- **New layer flag for Chrome** — operator decision: plain part of the desktop role, no sub-gate.

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CHROME-01 | — | Pending roadmap |
| CHROME-02 | — | Pending roadmap |
| CHROME-03 | — | Pending roadmap |
| CHROME-04 | — | Pending roadmap |

---
*Defined: 2026-07-24 — milestone v4.1.*
