---
gsd_state_version: 1.0
milestone: v3.2
milestone_name: XRDP Remote Desktop
status: executing
stopped_at: 12-02 executed + committed (operator surface + docs → native RDP-over-SSM :3389, RDP-10); ready for 12-03.
last_updated: "2026-06-16T02:17:45.715Z"
last_activity: 2026-06-16
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 8
  completed_plans: 6
  percent: 75
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-02 after v3.0 milestone start)

**Core value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one command — without leaking credentials or exposing a vulnerable host to the public internet.
**Current focus:** Phase 12 — Network, Operator Surface + VNC/noVNC Removal

## Current Position

Phase: 12 (Network, Operator Surface + VNC/noVNC Removal) — EXECUTING
Plan: 3 of 4
Status: 12-02 complete (RDP-10 operator-surface half); ready to execute 12-03
Last activity: 2026-06-16 -- 12-02 executed + committed

## Performance Metrics (v1.0)

| Phase | Plans | Total wall | Avg/Plan |
|-------|------:|-----------:|---------:|
| Phase 1 | 3 | ~26 min | ~9 min |
| Phase 2 | 2 | ~22 min | ~11 min |
| Phase 3 | 2 | ~19 min (parallel) | ~9 min |
| Phase 4 | 3 | ~10 min (parallel) | ~7 min |
| **v1.0 total** | **10** | **~77 min execution** | **~8 min** |

Calendar window: 2026-05-13 17:04 → 2026-05-14 10:58 (~18 hours wall clock; ~77 min active executor time).
Commits: 66 in `b0bd004..7e63829`. Files changed: 75 (+14488 / −69 LOC).

**Trend:** Parallel-safe phases (3 + 4) demonstrably faster wall-clock than serial (1 + 2).

### v2.0 Performance Metrics

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 05 | 01 | 5min | 2 | 1 |
| 06 P01 | 5min | 1 tasks | 1 files |
| 06 P02 | 4min | 2 tasks | 3 files |
| Phase 12 P01 | ~4min | 2 tasks | 3 files |

### v3.2 Performance Metrics

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 11 | 01 | ~5min | 3 | 11 |
| 11 | 02 | 8min | 3 | 6 |
| 11 | 03 | ~10min | 2 | 4 |
| 12 | 02 | ~4min | 3 | 4 |

## Accumulated Context

See PROJECT.md Key Decisions table. Locked v1.0 decisions:

- SSM Parameter Store SecureString (vs Secrets Manager)
- Hybrid network posture (SSM SM + CIDR allowlist for web)
- Packer manifest → auto.tfvars AMI handoff
- Checkov (NOT tfsec / Trivy / KICS — supply-chain incidents March 2026)
- Parallel CI jobs; tiered pre-commit (fast at commit, slow at push)
- Terragrunt dropped post-v1.0; `./run` drives `tofu` directly with `-backend-config` flags

**v2.0 decisions:**

- Makefile is deleted as the final step (Phase 7) — not before CI and `./run` are verified working
- Research build order: dispatcher + guards → CI integration → docs/cleanup
- Existing `scripts/*.sh` stay as helpers called by `./run` (no consolidation into the script body)
- Standalone `./run` dispatcher: does not source `_common.sh`; lazy TF_STATE_BUCKET derivation; DEVBOX_USER regex validation added

**v3.0 decisions (at roadmap time):**

- Jupyter reuses the existing `secrets` role pattern (per-build random password → SSM SecureString `/devbox/${devbox_user}/jupyter-password`) — same as code-server / VNC
- Jupyter uses the existing `aws_security_group.devbox` with an added ingress rule for :8888 (no new SG) — governed by `var.allowed_web_cidrs`
- mise is binary-only: no committed `.mise.toml`, no migration of existing Ansible language layers
- Phase split: Phase 8 = Ansible/AMI work (Jupyter service + secrets + mise); Phase 9 = Terraform + `./run` operator surface
- `hardening` invariant enforced: Jupyter Ansible role inserted before `hardening` (JUP-08)

**v3.2 decisions (Phase 11 gap-closure 11-02):**

- Architecture: keep the xorgxrdp/Xorg backend (option a) — install `xorg-x11-server-Xorg` + `dbus-x11` from AL2023 core, accept CIS rule 2.2.1 as the single documented desktop deviation. No Xvnc pivot, no post-hardening reinstall kludge.
- CIS override `amzn2023cis_rule_2_2_1: false` lives only at the parent-role default site (`hardening/defaults`); the vendored `AMAZON2023-CIS` default stays `true` so the override survives a role bump.
- Every relaxed CIS control a future role-bump could silently re-impose gets a post-hardening `post_task` assert — turning a silent regression into a loud bake failure (the X-server guard is the first instance of this pattern).
- Bake asserts must prove the actual runtime (stat the X server + cert SAN), not just the role's own build artifacts.
- sesman boot-race fixed by dropping `StopWhenUnneeded` + `BindsTo` and relying on `WantedBy` + xrdp.service's one-directional `Requires`/`After` (W2).
- CLAUDE.md is git-untracked (commit effde0f); deviation docs that "must go in CLAUDE.md" are written to the operator's local copy, with the authoritative record in the relevant role's inline comment.

**v3.2 decisions (Phase 11 round-3 gap-closure 11-03):**

- xorg.conf is VENDORED in-repo (`ansible/roles/xrdp/files/xorg.conf`) + copied to `/etc/X11/xrdp/xorg.conf` (NOT `/etc/xrdp/xorg.conf`) + RDP-13 stat-asserted — removes the "assumed from make install" fragility; the path is where xorgxrdp 0.10.5 installs it and where Xorg's relative `-config` resolves. sesman.ini NOT edited.
- SELinux confinement of the source-built daemons uses an idempotent `semanage fcontext -a -t xrdp_exec_t '/usr/local/sbin/xrdp(-sesman)?'` BEFORE restorecon, with a command-only double-guard (when-check + already-defined/invalid/not-defined stderr tolerance) — no community.general dependency; tolerates re-bake and optional-type-absent. The AVC-clean enforcing boot is the RDP-14 residual.
- sesman login is positively gated (option a): `tsusers` group created + ec2-user appended (`append:true`); `tsadmins` NOT created (admins optional).
- `gnome-session` installed by name in the desktop role (no Debian `-xsession` variant on AL2023) — guards the GNOME-over-RDP black screen.
- The pre-existing `no-changeme` false-positive (`desktop_vnc_password != "changeme"`, line 7) remains tolerated — my new lines introduce no `changeme`; do not edit the pre-existing guard.

**v3.2 decisions (Phase 12 plan 12-01 — Terraform SG :3389 + noVNC scrub):**

- RDP-09: the EC2 SG opens inbound TCP `:3389` gated on `var.allowed_web_cidrs`, mirroring the `:8080` code-server ingress exactly; the `:6080` noVNC ingress is removed. SSM-first no-:22 posture, IMDSv2-only metadata, and all-outbound egress unchanged. TCP-only (no UDP 3389 — xrdp TLS does not require it).
- The `vnc-password` SSM param path `/devbox/<user>/vnc-password` and the `ssm_vnc_password_param` output KEY are RETAINED — it IS the RDP/PAM login password (locked credential model). Descriptions relabelled noVNC→RDP only; never renamed (renaming risks orphaning pre-baked AMIs for zero benefit).
- `novnc_url` TF output replaced by an `rdp_endpoint` NOTE output (RDP is a native-client / SSM-tunnel endpoint, not a browser URL). Terraform surface now has zero `:6080`/noVNC references; remaining noVNC residue (Ansible, `./run`/scripts, CLAUDE.md) is owned by later 12-xx plans.

**v3.2 decisions (Phase 12 plan 12-02 — operator surface + docs → native RDP over SSM):**

- RDP-10: the `./run` operator surface and operator docs point at native RDP-over-SSM `:3389`. The generic `cmd_devbox_port_forward` parser already forwards `3389` (locked decision D4) — NO code change to the parser; only help text, the `secrets-show` printed label, and the two `scripts/devbox-{start,status}.sh` connection-info lines were edited.
- The `/devbox/<user>/vnc-password` SSM fetch path in `run` is RETAINED unchanged — it IS the RDP/PAM login password (locked credential model). Only the human-facing label changed: `secrets-show` now prints `RDP login (ec2-user @ <host>:3389) password:` (path never renamed/removed).
- CLAUDE.md (§1/§2/§5/§7) documents connecting a native RDP client (mstsc/FreeRDP/Remmina) over `./run devbox-port-forward 3389`. CLAUDE.md is git-untracked (commit effde0f) → edited on-disk for the operator but NOT committed; the authoritative committed record lives in `run`/`scripts` + the 12-02 SUMMARY. Zero `:6080`/noVNC reference now remains in `run`, `scripts/`, or CLAUDE.md; `shellcheck` clean.

## Deferred / Carried Forward

| Category | Item | Status | Originated |
|----------|------|--------|-----------|
| Observability | CloudWatch metrics + login event shipping | v3 backlog | v1.0 init |
| Lifecycle | Idle auto-stop + scheduled nightly stop | v3 backlog | v1.0 init |
| Image lifecycle | Old AMI deregistration + inventory | v3 backlog | v1.0 init |
| Reproducibility | SSM `:NN` version suffix on Packer source | v3 follow-up | v1.0 Phase 3 |
| uat_gap | 05-HUMAN-UAT.md (3 scenarios) | partial — needs live AWS/devbox | v2.0 close |
| uat_gap | 06-HUMAN-UAT.md (3 scenarios) | partial — needs live AWS/devbox | v2.0 close |
| verification_gap | 05-VERIFICATION.md | human_needed | v2.0 close |
| verification_gap | 06-VERIFICATION.md | human_needed | v2.0 close |
| quick_task | 260520-be1-create-gitlab-ci-pipeline-packer-build-a | completed (has SUMMARY); unarchived orphan | v2.0 close (re-deferred v3.0) |
| uat_gap | 08-HUMAN-UAT.md (2 scenarios: Jupyter venv + mise --version) | partial — needs live AMI bake | v3.0 close |
| verification_gap | 08-VERIFICATION.md | human_needed — bake-time runtime checks | v3.0 close |
| tech_debt | WR-05: bootstrap .sh.j2 outside CI shellcheck glob | open follow-up | v3.0 close |

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260520-be1 | create gitlab CI pipeline: packer build AMI then tofu apply EC2 from that AMI | 2026-05-20 | 72f3157 | [260520-be1-create-gitlab-ci-pipeline-packer-build-a](./quick/260520-be1-create-gitlab-ci-pipeline-packer-build-a/) |
| 260602-add-golang-dev-tools | add 11 pinned Go developer tools (gopls, dlv, golangci-lint, govulncheck, …) to the golang role | 2026-06-02 | 88541f0 | [260602-add-golang-dev-tools](./quick/260602-add-golang-dev-tools/) |
| 260609-dif | enforce noVNC HTTPS-only via `novnc_proxy --ssl-only` (dropped the planned v3.1 nginx milestone) | 2026-06-09 | fb59449 | [260609-dif-enforce-https-only-on-novnc-via-novnc-pr](./quick/260609-dif-enforce-https-only-on-novnc-via-novnc-pr/) |

## Session Continuity

Last session: 2026-06-16T02:17:45.710Z
This session (2026-06-16): executed the 11-02 gap-closure plan — all 3 tasks committed atomically (ac3b3cb install X server + dbus-x11 + disable CIS 2.2.1 + fix layer gate; 54740e8 FIPS cert + SELinux relabel + sesman boot-race fix + colord .rules; a50abd1 extend RDP-13 + post-hardening X-server regression assert). All 4 CRITICAL + 3 HIGH + 3 RISK findings closed against the Xorg backend. Every task's automated verify printed PASS; hardening-stays-last grep-gate still = 1; vendored CIS default + 11-01-PLAN.md untouched. Two minor deviations (CLAUDE.md is gitignored → deviation doc on disk only; sesman comment reworded to clear the `! grep BindsTo/StopWhenUnneeded` gate).
This session (2026-06-16, round 3): executed the 11-03 gap-closure plan — both tasks committed atomically (3e0de34 vendor+assert /etc/X11/xrdp/xorg.conf + idempotent semanage `xrdp_exec_t` fcontext before restorecon + `policycoreutils-python-utils` runtime dep + deterministic `tsusers` gating; d4a4eff `gnome-session` by name in the desktop role). Closes the four round-3 BAKE-FIXABLE findings from adversarial review addendum #2 (CRITICAL #2 xorg.conf, CRITICAL #1 fcontext, HIGH tsusers, RISK gnome-session). Every task's automated verify printed PASS; fcontext add ordered before restorecon (line 406 < 424); hardening-stays-last grep-gate still = 1; 11-01/11-02-PLAN.md untouched. One self-introduced deviation (reworded the gnome-session comment to avoid tripping the plan's own `-xsession`/line-length gates). Pre-existing `no-changeme` false-positive on `desktop_vnc_password != "changeme"` (line 7) tolerated — no new `changeme` introduced.
This session (2026-06-16): executed Phase 12 plan 12-01 (Terraform SG :3389 + noVNC scrub) — both tasks committed atomically (7a665e4 add :3389 RDP ingress gated on var.allowed_web_cidrs + drop :6080 noVNC ingress + SG header comment; ba59556 scrub noVNC from outputs.tf/variables.tf, replace novnc_url with rdp_endpoint note, relabel ssm_vnc_password_param description with path retained). Every acceptance check passed: :3389 present + gated (1), 6080/noVNC residue across main.tf/outputs.tf/variables.tf (0), :8080 + no-:22 + egress + IMDSv2 intact, vnc-password SSM path retained (fixed-string match), rdp_endpoint added, ssm_vnc_password_param key unchanged. `tofu fmt -check` rc=0 + `tofu validate` Success. No `changeme` introduced. RDP-09 (network half) complete. No deviations.
This session (2026-06-16): executed Phase 12 plan 12-02 (operator surface + docs → native RDP over SSM, RDP-10) — Tasks 1+2 committed atomically (1393b15 relabel run port-forward help + secrets-show to RDP :3389, vnc-password SSM fetch path unchanged, no port-parser logic change per D4; 60b409c advertise RDP :3389 in devbox-start/status connection info). Task 3 edited CLAUDE.md §1/§2/§5/§7 on-disk (git-ignored → NOT committed). Every acceptance check passed: 0 6080/noVNC residue across run+scripts+CLAUDE.md; vnc-password path retained (fixed-string=2); `devbox-port-forward 3389` documented in CLAUDE.md; `shellcheck run scripts/devbox-start.sh scripts/devbox-status.sh` rc=0; `git ls-files CLAUDE.md` EMPTY (untracked); code-server/JupyterLab/§8-hardening surfaces intact; no `changeme` introduced. RDP-10 operator-surface half complete. No deviations (one harness note: executor shell runs errexit → re-ran gates with `set +e` and fixed-string grep for the `${DEVBOX_USER}` path).
Stopped at: 12-02 executed + committed; ready for 12-03.
Next: execute Phase 12 plan 12-03 (Ansible VNC/noVNC stack removal — RDP-11 — + revert of noVNC username fix 29de35b — RDP-12). Operator: local main is now ahead of origin — push pending.

## Operator Next Steps

- `DEVBOX_USER=$(whoami) ./run build` (needs AWS creds) — validates controller-side secrets publish, clears the 3 deferred v3.0 runtime UAT checks (Jupyter venv, mise, Go tools), and the `260609-dif` noVNC `--ssl-only` checks
- Optional: fix broken `.ansible-lint` config (`'parseable' was unexpected`); pre-existing `no-changeme` hook fires on `!= "changeme"` assert lines already on main (desktop/secrets) — hook pattern needs an exclusion, CI has no such gate
- `/gsd:new-milestone` — define the next milestone (Observability / Lifecycle / Image-lifecycle are queued in Pending)
