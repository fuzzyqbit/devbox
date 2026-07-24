---
phase: 12-network-operator-surface-vnc-novnc-removal
verified: 2026-06-16
status: passed
status_note: "All four Phase-12 requirements (RDP-09/10/11/12) are code/config-level and fully met + adversarially verified. An opus adversarial review found no over-removal breakage, an intact RDP login chain, a correct SG, and a bake-safe firewalld task; its 2 findings (dead noVNC docs; a misleading firewalld comment) were closed in c34bff7 + ea1c0d3. The milestone-close RDP-14 live UAT (live RDP login → GNOME render) is NOT a Phase-12 requirement — it needs ./run build + a running instance and is tracked in 11-HUMAN-UAT.md."
score: 4/4 requirements (RDP-09/10/11/12); adversarial verdict CLEAR after 2 cleanups
overrides_applied: 0
human_verification:
  - test: "RDP-14 (milestone-close gate, NOT a Phase-12 requirement) — live RDP login as ec2-user → GNOME renders, over SG :3389 + ./run devbox-port-forward 3389"
    expected: "Desktop renders; PAM auth via the secrets password; no AVC under enforcing; FIPS TLS handshake completes"
    why_human: "Requires a baked AMI on a live EC2 instance. Recorded in 11-HUMAN-UAT.md; closes the v3.2 milestone."
---

# Phase 12: Network, Operator Surface + VNC/noVNC Removal — Verification Report

**Phase Goal:** Operator reaches the RDP desktop via SG :3389 + a `./run` SSM port-forward; the obsolete VNC/noVNC stack is fully removed — no dead VNC artifacts in the image — with nothing shared with a surviving feature removed.
**Verified:** 2026-06-16 (authored from adversarial evidence, per the milestone's "static verifier is not trustworthy for infra" lesson — see feedback_adversarial_verify_infra)
**Status:** PASSED — 4/4 requirements met; adversarial verdict CLEAR after 2 doc/comment cleanups.

---

## Requirements Coverage

| Req | Description | Status | Evidence |
|-----|-------------|--------|----------|
| RDP-09 | SG exposes :3389 (gated on `var.allowed_web_cidrs`), drops :6080; SSM-first/no-:22 unchanged | SATISFIED | `terraform/main.tf` :3389 ingress mirrors the :8080 block (gated on `var.allowed_web_cidrs`, tcp); :6080 ingress removed; `outputs.tf` `novnc_url`→`rdp_endpoint`; var descriptions noVNC→RDP. `tofu validate` Success. (12-01 commits 7a665e4/ba59556.) Host-firewalld :3389 task added in the xrdp role as a guarded defensive no-op (12-04 33c757d; comment corrected ea1c0d3). |
| RDP-10 | `./run devbox-port-forward` tunnels :3389; operator docs describe native RDP client over SSM | SATISFIED | `./run` port-forward help + `secrets-show` relabelled to RDP :3389 (value path kept); `scripts/devbox-{start,status}.sh` advertise RDP :3389; CLAUDE.md §1/§2/§5/§7 + `docs/HOWTO-ACCESS-CODE-SERVER-RDP.md` + `docs/DEVELOPER-LIFECYCLE.md` document the native-RDP-over-SSM flow. (12-02 commits + c34bff7.) |
| RDP-11 | VNC/noVNC stack removed (services, SecurityTypes Plain, /etc/pam.d/vnc, noVNC install) — no dead config | SATISFIED | desktop role excised of tigervnc-server (single dnf list item; GNOME/mesa/fonts/ffmpeg/VLC confirmed present), vncserver/novnc/xstartup templates `git rm`'d, vnc PAM + SecurityTypes gone; baked `devbox-secrets-bootstrap.{sh,service}.j2` swapped vncserver/novnc→xrdp/xrdp-sesman. Repo-wide RDP-11 completeness gate (`ansible/ terraform/ run scripts/`) returns CLEAN. (12-03 commits eba3017/73761ba.) |
| RDP-12 | Revert the noVNC username-injection workaround (29de35b) + drop its import | SATISFIED | `ansible/novnc-plain-username-fix.yml` deleted + its playbook.yml import dropped; hardening-stays-last grep-gate = 1. (12-04 dee1121.) |

---

## Adversarial Review (opus) — VERDICT: CLEAR (after 2 cleanups)

No CRITICAL: no over-removal (desktop role coherent — no dangling notify/template/var; GNOME/code-server/Jupyter intact; tigervnc removal orphaned nothing); RDP login chain intact (vnc-password SSM → bootstrap chpasswd → ec2-user → PAM password-auth → xrdp-sesman); SG correct; the new firewalld task is bake-safe (no-ops when firewall-cmd absent); hardening-stays-last held.

Two findings, both closed:
- **HIGH (closed, c34bff7):** `docs/HOWTO-ACCESS-CODE-SERVER-VNC.md` + `docs/DEVELOPER-LIFECYCLE.md` still instructed operators to use noVNC :6080 — the phase gate's scope (ansible/terraform/run/scripts) missed `docs/`. Renamed HOWTO → `-RDP.md`, rewrote both to the RDP :3389 flow; `grep` for noVNC/:6080 in `docs/` now returns nothing; no dangling reference to the old filename.
- **RISK (closed, ea1c0d3):** the host-firewalld :3389 task's comment falsely claimed firewalld is "already installed". Truth: firewalld is absent at xrdp-role time (minimal AMI; CIS host-firewall rules 3.4.* disabled; firewalld only installed by `firewalld-docker-fix.yml` as a containers=true post-play), so the task is a guarded defensive no-op and RDP reachability does not depend on it (SG is the perimeter; containers=true → docker-zone ACCEPT; containers=false → no firewalld). Comment corrected to state the truth; task logic unchanged.

---

## Milestone v3.2 — close status

Phases 10 (build), 11 (config — bake-config CLEAR), and 12 (network/removal — PASSED) are **code/bake-config complete**. The sole remaining gate is **RDP-14 (live UAT)** — a real RDP login on a baked, running instance — which needs `./run build` + AWS and is recorded in `11-HUMAN-UAT.md`. The milestone is not "shipped" until RDP-14 is recorded.

---

_Verified: 2026-06-16 — authored by orchestrator from opus adversarial review evidence._
