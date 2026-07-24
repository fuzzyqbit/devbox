# Phase 16 — Deferred Items (out-of-scope discoveries during 16-01 execution)

Discovered 2026-07-24 while running the Task 2 static gate sweep. None are caused by the
Phase 16 change (all blame-proven to predate this phase); per executor scope boundary they
are logged here, not fixed. The CI-authoritative gate scopes are green — these failures
exist only in the repo-wide local hook forms.

## 1. `pre-commit run --all-files` — 3 pre-existing failures

| Hook | File | Cause | Since |
|------|------|-------|-------|
| `no-changeme` | `ansible/roles/secrets/tasks/generate.yml:17,27` | The hook's tree-wide `git grep changeme` flags the *assertion guards* (`!= "changeme"`) that enforce SEC-01/02 — the guards are the point, but the hook exclusions (`:!*.md :!.planning/** :!.pre-commit-config.yaml`) don't carve them out | f4748954 (2026-05-13) / 47f68f41 (2026-06-19) |
| `check-yaml` | `.gitlab-ci.yml:439` | GitLab's `!reference` custom YAML tag is unparseable by check-yaml; the hook's exclude list covers `ansible/*.yml` + `.gitleaks.toml` only | pre-phase (`803ee79` and earlier) |
| `trailing-whitespace` | `.planning/milestones/v4.0-phases/10-xrdp-xorgxrdp-from-source-build-role/10-RESEARCH.md` | Trailing whitespace introduced by the v4.1 archival move (`ac0dce2`); hook auto-fix was reverted to keep this phase's footprint clean | ac0dce2 (2026-07-24) |

Suggested fix (future hygiene task): extend the `no-changeme` exclusions with
`":!ansible/roles/secrets/tasks/generate.yml"` (or match `= "changeme"` assignment form only),
add `.gitlab-ci.yml` to the check-yaml `exclude` (or use `--unsafe`), and whitespace-clean the
archived research doc.

## 2. `pre-commit run --hook-stage pre-push ansible-lint` — 4 pre-existing violations

The pre-commit hook lints the WHOLE repo; CI (authoritative, `.github/workflows/ci.yml` job
`ansible-lint`) runs `ansible-lint ansible/playbook.yml` (scoped). All 4 violations are outside
the CI scope; the CI-equivalent invocation with the same pinned v26.4.0 venv exits 0
(0 failures, 0 warnings, production profile) including the new Chrome block.

| Rule | File | Note |
|------|------|------|
| `load-failure` | `.gitlab-ci.yml:1` | same `!reference` tag as above (reported as warning) |
| `yaml[line-length]` | `.pre-commit-config.yaml:43` | no-changeme entry line (243 > 160) — Phase 1/4 content |
| `yaml[line-length]` | `.pre-commit-config.yaml:126` | grep-gate #8 entry line (167 > 160) — Phase 7 content |
| `role-name` | `ansible/roles/persistent-home` | hyphenated role dir (merged 2026-06-26); analog of the ai_tools rename (a4e1388) not applied to it |

Suggested fix (future hygiene task): either scope the pre-commit ansible-lint hook to
`ansible/` (matching CI) or rename `persistent-home` → `persistent_home` (ai_tools precedent)
and add `.gitlab-ci.yml` / `.pre-commit-config.yaml` to `.ansible-lint` `exclude_paths`.

## 3. Git hooks not installed in this clone

`.git/hooks/` contains samples only — `pre-commit install` (all three stages, CLAUDE.md §2) has
not been run in this working copy, so commit-time hooks did not fire on this phase's commits.
The full gate set was run manually instead (results above). Operator action: run the three
`pre-commit install` commands from CLAUDE.md §2.
