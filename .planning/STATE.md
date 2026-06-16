---
gsd_state_version: 1.0
milestone: v3.2
milestone_name: XRDP Remote Desktop
status: executing
stopped_at: 11-02 gap-closure executed (3/3 tasks, commits ac3b3cb/54740e8/a50abd1) — all 4 CRITICAL + 3 HIGH + 3 RISK findings closed against the Xorg backend. Phase 11 awaits an adversarial re-verification pass before it is marked done.
last_updated: "2026-06-16T00:30:04.613Z"
last_activity: 2026-06-16 -- Phase 11 plan 11-02 gap-closure executed
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 3
  completed_plans: 3
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-02 after v3.0 milestone start)

**Core value:** A single operator can spin up, hibernate, and tear down a reproducible, hardened cloud workstation with one command — without leaking credentials or exposing a vulnerable host to the public internet.
**Current focus:** Phase 11 — service-config-pam-session-bake-verification

## Current Position

Phase: 11 (service-config-pam-session-bake-verification) — EXECUTED, awaiting re-verification
Plan: 2 of 2 (11-02 gap-closure complete)
Status: All 11-02 tasks committed; ready for an adversarial re-verification pass
Last activity: 2026-06-16 -- Phase 11 plan 11-02 gap-closure executed

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

### v3.2 Performance Metrics

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 11 | 01 | ~5min | 3 | 11 |
| 11 | 02 | 8min | 3 | 6 |

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

Last session: 2026-06-15 — Resumed Phase 11. Its verification was corrected from "passed" to FAILED last session: the static gsd-verifier passed 7/7 but an adversarial (opus) review found 4 CRITICAL runtime blockers (no X server installed; CIS 2.2.1 deletes the X server xorgxrdp needs; xrdp layer-gated on `layers.xrdp` alone instead of `and layers.desktop`; RDP-13 assert blind to all of it). This session: clarified the 3 options and the operator chose **(a)** — keep xorgxrdp, install `xorg-x11-server-Xorg`+`dbus-x11`, set `amzn2023cis_rule_2_2_1=false` as a documented desktop exception. Decision recorded in 11-VERIFICATION.md ADVERSARIAL ADDENDUM.
This session (2026-06-16): executed the 11-02 gap-closure plan — all 3 tasks committed atomically (ac3b3cb install X server + dbus-x11 + disable CIS 2.2.1 + fix layer gate; 54740e8 FIPS cert + SELinux relabel + sesman boot-race fix + colord .rules; a50abd1 extend RDP-13 + post-hardening X-server regression assert). All 4 CRITICAL + 3 HIGH + 3 RISK findings closed against the Xorg backend. Every task's automated verify printed PASS; hardening-stays-last grep-gate still = 1; vendored CIS default + 11-01-PLAN.md untouched. Two minor deviations (CLAUDE.md is gitignored → deviation doc on disk only; sesman comment reworded to clear the `! grep BindsTo/StopWhenUnneeded` gate).
Stopped at: 11-02 executed; Phase 11 awaits an adversarial re-verification pass before being marked done.
Next: re-verify Phase 11 with an adversarial pass (confirm the bake would now be GREEN-and-runnable), then `/gsd:plan-phase 12` (Terraform SG :3389 + `./run` port-forward + VNC/noVNC removal incl. revert of noVNC username fix 29de35b + RDP-14 live UAT). Operator: local main is now 20 commits ahead of origin — push pending.

## Operator Next Steps

- `DEVBOX_USER=$(whoami) ./run build` (needs AWS creds) — validates controller-side secrets publish, clears the 3 deferred v3.0 runtime UAT checks (Jupyter venv, mise, Go tools), and the `260609-dif` noVNC `--ssl-only` checks
- Optional: fix broken `.ansible-lint` config (`'parseable' was unexpected`); pre-existing `no-changeme` hook fires on `!= "changeme"` assert lines already on main (desktop/secrets) — hook pattern needs an exclusion, CI has no such gate
- `/gsd:new-milestone` — define the next milestone (Observability / Lifecycle / Image-lifecycle are queued in Pending)
