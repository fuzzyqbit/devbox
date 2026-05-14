# Roadmap: devbox

**Milestone:** 1 — Security hardening + CI baseline
**Created:** 2026-05-13
**Granularity:** coarse (3-5 phases, 1-3 plans each)
**Mode:** yolo
**Parallelization:** enabled

## Goal

Close every CRITICAL and HIGH finding in `.planning/codebase/CONCERNS.md`, and install automated gates (CI + pre-commit) so they cannot regress. After this milestone, a devbox built and applied from `main` cannot ship `changeme` passwords, cannot expose itself to `0.0.0.0/0`, and cannot drift on tool versions without the change being explicit and reviewable.

## Phases

- [x] **Phase 1: Secrets remediation** — ✓ Complete 2026-05-13. SEC-01..SEC-05 all closed. Verification: `.planning/phases/01-secrets-remediation/01-VERIFICATION.md`.
- [x] **Phase 2: Network exposure remediation** — ✓ Complete 2026-05-13. Hybrid posture (SSM Session Manager for SSH, CIDR allowlist for :8080/:6080). NET-01..NET-04 all closed. Verification: `.planning/phases/02-network-exposure-remediation/02-VERIFICATION.md`.
- [x] **Phase 3: Reproducibility & version pinning** — ✓ Complete 2026-05-14. REP-01..REP-05 all closed (REP-04 with one follow-up: SSM `:NN` pin needs AWS creds; deferred to Phase 4). Verification: `.planning/phases/03-reproducibility-version-pinning/03-VERIFICATION.md`.
- [ ] **Phase 4: CI, pre-commit, and documentation** — Add GitHub Actions + `.pre-commit-config.yaml` covering fmt/validate/lint/security/secret-scan, populate `CLAUDE.md`, and document the firewalld-docker workaround with its retirement criteria.

## Phase Details

### Phase 1: Secrets remediation
**Goal**: Eliminate hardcoded `changeme` passwords for code-server and VNC, replace them with per-build randomized secrets delivered via AWS Secrets Manager / SSM Parameter Store, and gate the repo against future secret leaks.
**Depends on**: Nothing (first phase; closes 2 of 3 CRITICAL findings)
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, SEC-05
**Success Criteria** (what must be TRUE):
  1. Building an AMI from a clean clone produces a code-server password and a VNC password that are unique per build, and neither value ever appears in HCL, YAML, Jinja templates, or git history.
  2. A running devbox can read its own credentials from AWS Secrets Manager (or SSM Parameter Store) at boot via an EC2 instance profile, with no static AWS keys baked into the AMI.
  3. The hardcoded `key_name = "me"` is gone; each operator's `DEVBOX_USER` resolves to a per-operator key pair, and the rotation procedure is documented in `CLAUDE.md`.
  4. A test commit containing a fake AWS key or `password: changeme` is rejected by both pre-commit and CI via `gitleaks` (or equivalent) before merge.
**Suggested Plans**:
  - `1.1 code-server + VNC secret generation` (SEC-01, SEC-02): replace `password: changeme` in `ansible/roles/vscode/templates/config.yaml.j2` and `desktop_vnc_password` default in `ansible/roles/desktop/defaults/main.yml` with per-build generated values; fail the play if either is unset; fix the `creates:` guard on the VNC password task (`ansible/roles/desktop/tasks/main.yml:29-33`) so rotation actually rotates.
  - `1.2 Secret distribution via Secrets Manager + IAM instance profile` (SEC-03, SEC-04): write generated secrets to AWS Secrets Manager / SSM Parameter Store keyed by `${devbox_user}`; add an `aws_iam_role` + `aws_iam_instance_profile` to `terraform/main.tf` with least-privilege read access to that path; wire the EC2 boot to fetch them; replace `key_name = "me"` in `terragrunt.hcl` with `"${local.user}-devbox"` and document key upload + rotation.
  - `1.3 gitleaks in pre-commit and CI` (SEC-05): introduce `.pre-commit-config.yaml` with `gitleaks`/`detect-secrets`; wire the same scan into the CI workflow stub (Phase 4 expands the rest of CI). Smoke-test with a planted fake secret.
**Risks / Notes**:
  - Plans 1.1 and 1.2 share the Ansible roles `vscode` and `desktop`; serialize on shared files to avoid merge conflicts, but the Terraform IAM work in 1.2 is independent of 1.1 and can land first.
  - Decision needed in 1.2: Secrets Manager vs SSM Parameter Store. Bias to SSM Parameter Store (cheaper for personal use, simpler IAM). Record in PROJECT.md.
  - 1.3 introduces the `.pre-commit-config.yaml` file that Phase 4 will extend; coordinate the file layout up front to avoid rewrites.
**Parallelizable**: 1.2 (Terraform IAM) and 1.3 (gitleaks) can run in parallel with 1.1 (Ansible templates) since they touch disjoint files. 1.1 ↔ 1.2 share an integration point (where the secret value flows from Ansible into AWS) — coordinate the contract before parallelizing.
**Plans**: 3 plans
- [ ] 01-01-PLAN.md — code-server + VNC per-build random passwords; new `secrets` Ansible role; fix the broken VNC `creates:` guard (SEC-01, SEC-02). Wave 1.
- [ ] 01-02-PLAN.md — Publish SSM SecureStrings + IAM instance profile + IMDSv2 boot-time oneshot + per-operator SSH key + `make secrets-show` (SEC-03, SEC-04). Wave 2; depends on 01-01.
- [ ] 01-03-PLAN.md — gitleaks pre-commit + GitHub Actions workflow + `.gitleaks.toml` allowlist; planted-secret smoke test checkpoint (SEC-05). Wave 1; parallel with 01-01 and 01-02.

### Phase 2: Network exposure remediation
**Goal**: Replace the `0.0.0.0/0` ingress on SSH/code-server/noVNC with an operator-supplied CIDR allowlist or AWS SSM Session Manager, closing the third CRITICAL finding and removing the trivially-exploitable surface from every devbox.
**Depends on**: Phase 1 (defense-in-depth: passwords are no longer `changeme` before we narrow the network so we don't lock ourselves out of a still-vulnerable host)
**Requirements**: NET-01, NET-02, NET-03, NET-04
**Success Criteria** (what must be TRUE):
  1. `terraform apply` refuses to create the security group if `allowed_admin_cidr` is empty without an explicit override variable; the default no longer contains `0.0.0.0/0` anywhere in `terraform/main.tf`.
  2. The chosen access mechanism for SSH — either a narrowed CIDR allowlist or AWS SSM Session Manager (Terraform `aws_iam_role_policy_attachment` of `AmazonSSMManagedInstanceCore`, plus `ssm:StartSession` for the operator) — is implemented end-to-end and verified by a manual run (operator can reach SSH from inside their allowlisted network or via `aws ssm start-session`, and is rejected from outside).
  3. The decision between SSM Session Manager and CIDR allowlist is recorded in `PROJECT.md` → Key Decisions, with rationale and rollback note.
  4. `tfsec` (configured in Phase 4) reports zero HIGH/CRITICAL findings against `terraform/`.
**Suggested Plans**:
  - `2.1 SSH access decision + implementation` (NET-01, NET-04): record the SSM-vs-CIDR decision; if SSM, add the IAM policy attachments + VPC endpoints and remove the `:22` ingress rule entirely; if CIDR, add `var.allowed_admin_cidr` (list, no default), wire it through `terragrunt.hcl`, and drop the `0.0.0.0/0` literal.
  - `2.2 code-server + noVNC ingress restriction` (NET-02, NET-03): apply the same `allowed_admin_cidr` (or a separate `allowed_user_cidr`) to `:8080` and `:6080` ingress in `terraform/main.tf:36-60`; refuse to apply if empty.
**Risks / Notes**:
  - SSM Session Manager removes the `:22` ingress entirely but requires an instance profile (already added in Phase 1.2), VPC endpoints (or NAT), and operator-side `session-manager-plugin`. Bias toward SSM since the IAM groundwork is already laid.
  - Document the lockout-recovery procedure in `CLAUDE.md` — losing SSM and CIDR access on a stopped instance is recoverable; on a running instance it is not.
  - Existing devboxes will need a one-shot `terragrunt apply` after the change; flag this in the milestone changelog.
**Parallelizable**: 2.1 and 2.2 both edit `terraform/main.tf`; serialize them. Phase 2 as a whole can run in parallel with Phase 3 (different file domains: networking/IAM vs. version-pinning).
**Plans**: 2 plans
- [ ] 02-01-PLAN.md — Tighten Terraform: drop :22 ingress, gate :8080/:6080 on var.allowed_web_cidrs, attach AmazonSSMManagedInstanceCore to aws_iam_role.devbox, record NET-04 hybrid posture in PROJECT.md (NET-01, NET-02, NET-03, NET-04). Wave 1.
- [ ] 02-02-PLAN.md — Operator UX: make devbox-ssm / devbox-port-forward / devbox-allowlist-me targets + scripts; rewrite status/start connection-info blocks for SSM-first posture. Wave 2; depends on 02-01.

### Phase 3: Reproducibility & version pinning
**Goal**: Guarantee byte-deterministic builds by committing `.terraform.lock.hcl`, pinning every Galaxy collection and role to an exact version, pinning the Packer source AMI, and automating the AMI ID handoff from Packer to Terraform.
**Depends on**: Nothing structural; can run in parallel with Phase 2 (Phase 3 touches `ansible/requirements.yml`, `packer/devimage.pkr.hcl`, `terragrunt.hcl`, `.gitignore` — disjoint from Phase 2's `terraform/main.tf` ingress work)
**Requirements**: REP-01, REP-02, REP-03, REP-04, REP-05
**Success Criteria** (what must be TRUE):
  1. `.terraform.lock.hcl` is committed at `terraform/.terraform.lock.hcl`, removed from `.gitignore`, and is what CI uses (CI fails on lockfile drift).
  2. `ansible/requirements.yml` lists exact `version:` entries for `community.general`, `community.crypto`, and `ansible.posix`; the vendored CIS role's `collections/requirements.yml` is pinned to SHAs or tagged releases.
  3. `packer/devimage.pkr.hcl` resolves its source AMI via a pinned release-version SSM parameter (or a frozen AMI ID), not `most_recent = true` against an unpinned glob; building today and building next month produce the same starting image until the pin is intentionally bumped.
  4. After `make build`, the new AMI ID flows into `terragrunt apply` without a human edit to `terragrunt.hcl:29` — via `data "aws_ami"` filtered on `Builder=packer` + `Project=devimage` + most-recent tag, an SSM parameter written by a Packer post-processor, or an equivalent automation.
**Suggested Plans**:
  - `3.1 Lock files + collection pinning` (REP-01, REP-02, REP-03): remove `terraform/.terraform.lock.hcl` and root `.terraform.lock.hcl` from `.gitignore`; run `tofu providers lock` and commit; pin `ansible/requirements.yml` versions; audit and pin the vendored `ansible/roles/AMAZON2023-CIS/collections/requirements.yml` to SHAs or tags.
  - `3.2 Packer source AMI pin + AMI handoff automation` (REP-04, REP-05): replace `most_recent = true` in `packer/devimage.pkr.hcl:27-35` with an SSM-parameter or release-tag lookup; add a Packer post-processor that writes the resolved + built AMI IDs to SSM (`/devbox/ami/latest`) or a tagged manifest; replace `ami_id = "ami-..."` hand-copy in `terragrunt.hcl:25` with a `data "aws_ssm_parameter"` / `data "aws_ami"` lookup.
**Risks / Notes**:
  - Pinning Galaxy collections may surface breaking changes if the previously-floating versions were ahead of any tagged release; budget time to bump role tasks for any deprecated module signatures.
  - The AMI handoff automation requires Packer to have IAM permission to write SSM parameters or tag the AMI; this matches the principle from Phase 1.2 (instance profile pattern) but for the build user, not the runtime instance.
  - `3.1` and `3.2` are independent file sets and can be parallelized cleanly.
**Parallelizable**: 3.1 and 3.2 in parallel within Phase 3. Phase 3 in parallel with Phase 2 (disjoint files; only the optional IAM-policy-shape conversation overlaps, and that was already decided in Phase 1.2).
**Plans**: 2 plans
- [ ] 03-01-PLAN.md — Commit OpenTofu lockfile across 4 platforms; tighten hashicorp/aws to ~> 6.0; pin Galaxy collections with ==X.Y.Z; pin vendored CIS git-source collections to tagged refs (REP-01, REP-02, REP-03). Wave 1.
- [ ] 03-02-PLAN.md — Pin Packer source AMI via SSM Parameter Store :NN version pin; add Packer manifest post-processor; new `make packer-bake` target writes `users/${DEVBOX_USER}.auto.tfvars`; remove hand-copied ami_id from terragrunt.hcl (REP-04, REP-05). Wave 1.

### Phase 4: CI, pre-commit, and documentation
**Goal**: Install automated gates so every change to the repo is checked by `fmt`/`validate`/`lint`/`security`/`secret-scan` before merge, mirror those checks locally via pre-commit, and document the operator quickstart plus the firewalld-docker workaround with retirement criteria.
**Depends on**: Phases 1, 2, 3 (CI gates the work done in those phases; running CI earlier would force premature failure on known-pending issues). Phase 4 also extends the `.pre-commit-config.yaml` introduced by Phase 1.3.
**Requirements**: CI-01, CI-02, CI-03, CI-04, CI-05, CI-06, CI-07, DOC-01, DOC-02
**Success Criteria** (what must be TRUE):
  1. `.github/workflows/ci.yml` exists, runs on every push and PR, and a representative bad change (unformatted HCL, failing `ansible-lint`, a shellcheck violation, a Checkov HIGH, or a `gitleaks` hit) fails the build and blocks merge.
  2. `.pre-commit-config.yaml` at the repo root mirrors the CI checks tiered fast/slow (`tofu_fmt`, `terragrunt_fmt`, `packer fmt -check`, `shellcheck`, `gitleaks`, `no-changeme`, `pre-commit-hooks` boring suite, `grep-gates` on commit; `tofu_validate`, `packer validate`, `ansible-lint`, `checkov` on push) and `pre-commit run --all-files` passes on a clean tree.
  3. `CLAUDE.md` (currently empty) documents: operator quickstart (`make packer-bake`, `make tg-apply`, `make start`), required env vars (`DEVBOX_USER`, `AWS_REGION`), the bake → provision → start flow, the per-operator key procedure (from Phase 1), the SSM-vs-CIDR access posture (from Phase 2), the "hardening must remain last in `ansible/playbook.yml`" invariant, and the SSM `:NN` follow-up.
  4. `ansible/firewalld-docker-fix.yml` carries an explanatory header that states what the workaround does, why it's required today, the three acceptable replacements (CIS lifted; containers layer removed; per-port allowances in roles/hardening), the verification command (`firewall-cmd --get-default-zone`), and the conditions under which it can be retired.
**Suggested Plans**:
  - `4.1 GitHub Actions CI workflow` (CI-01, CI-02, CI-03, CI-04, CI-05, CI-06): create `.github/workflows/ci.yml` running 8 parallel jobs (fmt-check, tofu-validate, packer-validate, ansible-lint, ansible-syntax-check, shellcheck, checkov with `--hard-fail-on HIGH`, grep-gates); pin every action to its 40-char SHA; reuse Phase 1's `actions/checkout` SHA; create `.checkov.yaml` + `.ansible-lint` config files.
  - `4.2 Pre-commit tiered hooks` (CI-07): extend `.pre-commit-config.yaml` introduced by Phase 1.3 — fast hooks (`tofu_fmt`, `terragrunt_fmt`, `shellcheck`, `packer fmt -check`, pre-commit-hooks suite, `grep-gates`) at `pre-commit` stage; slow hooks (`tofu_validate`, `packer validate`, `ansible-lint==26.4.0`, `checkov`) at `pre-push` stage. Document the three `pre-commit install` invocations.
  - `4.3 Documentation pass` (DOC-01, DOC-02): populate `CLAUDE.md` (9 sections: what-this-is, prerequisites, env vars, per-operator setup, daily flow, rotations, troubleshooting, invariants, follow-ups); expand `ansible/firewalld-docker-fix.yml` header with 3 numbered retirement criteria + verification command + cross-reference to CLAUDE.md.
**Risks / Notes**:
  - Checkov may flag findings unrelated to Phases 1-3 (e.g. EBS encryption, missing CloudTrail); calibrate the failure threshold to HIGH/CRITICAL only for Milestone 1; defer MEDIUM/LOW to a follow-up. Triage real findings as they emerge — do NOT preemptively add `--skip-check` IDs (planner authority limit).
  - GitHub Actions runners must install OpenTofu, Packer, Terragrunt, Ansible; use SHA-pinned setup actions (opentofu/setup-opentofu, hashicorp/setup-packer, actions/setup-python) to match `ansible/roles/terraform/defaults/main.yml` versions and avoid CI-vs-AMI drift.
  - 04-01 and 04-02 BOTH consume `.checkov.yaml` + `.ansible-lint` — 04-01 creates them, 04-02's pre-push hooks reference them. Wave 1 disjoint-file safe but order-of-merge affects whether 04-02's Smoke 4 has the configs available; both plans handle the ordering gracefully.
**Parallelizable**: 04-01 and 04-02 touch disjoint files (`.github/workflows/ci.yml` + new configs vs. `.pre-commit-config.yaml`); 04-03 only touches `CLAUDE.md` + the Ansible header. All three plans are Wave 1 with `depends_on: []` — fully parallel.
**Plans**: 3 plans
- [ ] 04-01-PLAN.md — `.github/workflows/ci.yml` with 8 parallel SHA-pinned jobs + `.checkov.yaml` (hard-fail-on HIGH) + `.ansible-lint` (excludes vendored CIS role) (CI-01..CI-06). Wave 1.
- [ ] 04-02-PLAN.md — Extend `.pre-commit-config.yaml` with tiered fast/slow hooks: tofu_fmt/terragrunt_fmt/shellcheck/packer-fmt/grep-gates on pre-commit stage; tofu_validate/ansible-lint/packer-validate/checkov on pre-push stage (CI-07). Wave 1; parallel with 04-01 and 04-03.
- [ ] 04-03-PLAN.md — Populate `CLAUDE.md` (9-section operator quickstart) + expand `ansible/firewalld-docker-fix.yml` header with 3 retirement criteria + verification command (DOC-01, DOC-02). Wave 1; parallel with 04-01 and 04-02.

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Secrets remediation | 3/3 | ✓ Complete | 2026-05-13 |
| 2. Network exposure remediation | 2/2 | ✓ Complete | 2026-05-13 |
| 3. Reproducibility & version pinning | 2/2 | ✓ Complete | 2026-05-14 |
| 4. CI, pre-commit, and documentation | 0/3 | Planned | - |

## Parallelization Plan

Coarse-granularity execution with `parallelization=true` and `mode=yolo`:

- **Phase 1 must land first.** It closes 2 of 3 CRITICAL findings and lays the IAM instance-profile groundwork that Phase 2 (SSM option) reuses.
- **Phases 2 and 3 can run in parallel after Phase 1.** Phase 2 owns `terraform/main.tf` ingress + IAM policy for SSM; Phase 3 owns `ansible/requirements.yml`, `packer/devimage.pkr.hcl`, `.gitignore`, `.terraform.lock.hcl`, and the AMI-handoff change in `terragrunt.hcl`. Disjoint file sets.
- **Phase 4 lands last** because CI must gate the cleaned-up state, not the pre-cleanup state. All three Phase 4 plans (04-01, 04-02, 04-03) run in parallel — disjoint file sets.

Suggested ordering: `1 → (2 ∥ 3) → 4(01 ∥ 02 ∥ 03)`.

## Coverage

All 23 v1 requirements mapped to exactly one phase. No orphans.

| Requirement | Phase |
|-------------|-------|
| SEC-01 | Phase 1 |
| SEC-02 | Phase 1 |
| SEC-03 | Phase 1 |
| SEC-04 | Phase 1 |
| SEC-05 | Phase 1 |
| NET-01 | Phase 2 |
| NET-02 | Phase 2 |
| NET-03 | Phase 2 |
| NET-04 | Phase 2 |
| REP-01 | Phase 3 |
| REP-02 | Phase 3 |
| REP-03 | Phase 3 |
| REP-04 | Phase 3 |
| REP-05 | Phase 3 |
| CI-01 | Phase 4 (plan 04-01) |
| CI-02 | Phase 4 (plan 04-01) |
| CI-03 | Phase 4 (plan 04-01) |
| CI-04 | Phase 4 (plan 04-01) |
| CI-05 | Phase 4 (plan 04-01) |
| CI-06 | Phase 4 (plan 04-01) |
| CI-07 | Phase 4 (plan 04-02) |
| DOC-01 | Phase 4 (plan 04-03) |
| DOC-02 | Phase 4 (plan 04-03) |

**Totals:**
- v1 requirements: 23
- Mapped: 23 ✓
- Orphans: 0 ✓

---
*Roadmap created: 2026-05-13*
*Milestone scope: 1 — Security hardening + CI baseline*
*Last updated: 2026-05-14 after Phase 4 planning*
