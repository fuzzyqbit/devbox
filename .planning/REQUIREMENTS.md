# Requirements — Milestone v4.1 Google Chrome in desktop role

**Goal:** Every desktop bake ships Google Chrome, installed from Google's signed dnf repo at bake time.

**Shape:** No new role, no new layer flag — Chrome is unconditional desktop content inside the existing `desktop` role, applied whenever `layers.desktop` is on. Version policy is latest-at-bake (Google's repo serves only the current stable; historic RPMs are not hosted); remediation for a bad version is a rebake, matching the SPAL/xrdp precedent (CLAUDE.md §8).

---

## v4.1 Requirements

### Chrome (CHROME)

- [ ] **CHROME-01**: Operator can launch Google Chrome from the GNOME desktop (DCV or xrdp session) on every desktop bake.
- [ ] **CHROME-02**: Chrome installs from Google's official signed dnf repo — baked `.repo` config + GPG key, `gpgcheck=1`, no `--nogpgcheck` (GPG posture consistent with CLAUDE.md §2/§8 and the SPAL precedent).

---

## Future Requirements (deferred)

- **CHROME-03 (deferred 2026-07-24, re-scope):** SBOM/build-manifest capture of the exact baked Chrome version as a stated requirement. Note: the existing SBOM pass inventories all packages regardless, so the version lands in `/etc/devimage-sbom.cdx.json` anyway — dropped as a requirement, not as behavior.
- **CHROME-04 (deferred 2026-07-24, re-scope):** Dedicated bake-asserts (headless `--version` as `ec2-user`; W1-style post-hardening survival guard). Deviates from the dcv/xrdp/ai_tools bake-assert doctrine by operator choice; revisit if a bake ever ships a dead Chrome.
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
| CHROME-01 | Phase 17 | Pending |
| CHROME-02 | Phase 16 | Pending |

**Coverage:** 2/2 v1 (v4.1) requirements mapped — no orphans. CHROME-03/04 deferred (Future Requirements), intentionally unmapped.

---
*Defined: 2026-07-24 — milestone v4.1. Re-scoped 2026-07-24: CHROME-03/04 deferred; roadmap revised same day — Phases 16-17 mapped.*
