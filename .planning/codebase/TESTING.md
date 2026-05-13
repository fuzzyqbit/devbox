# Testing Patterns

**Analysis Date:** 2026-05-13

## Honest summary

**There is no test suite.** This is an IaC repository with no application code, no test framework, no CI pipeline, no fixtures, and no enforced lint gates at commit time. The only quality gates that run today are:

1. `make validate` — runs `packer validate` and `terragrunt validate` (`Makefile:37-39`). Schema/syntax only.
2. `make fmt` — runs `packer fmt`, `terraform fmt`, `terragrunt hclfmt` (`Makefile:44-48`). Format-only; does not fail on diffs (uses `fmt`, not `fmt -check`).
3. The full Packer build (`make build` → `make tg-plan`/`tg-apply`) IS the integration test. There is no faster smoke test in between `validate` and "build an AMI" / "launch an EC2 instance".

The only vendored testing config in the tree belongs to the upstream `AMAZON2023-CIS` role (`ansible/roles/AMAZON2023-CIS/.pre-commit-config.yaml`, `.ansible-lint`, `.yamllint`) and is **not** wired into this repo's Makefile, pre-commit hooks, or any CI runner. It would only execute if a maintainer of that role ran `pre-commit run` inside that subdirectory.

Treat the rest of this document as reference for what *could* serve as smoke-test surface, not what currently runs.

## Test Framework

**Runner:** None.
**Assertion Library:** None.
**Config:** None.

There is no `test/`, `tests/`, `spec/`, `molecule/`, or equivalent directory. `find` over the repo returns zero test files outside the vendored CIS role.

## Run Commands (today's surface)

```bash
make validate    # packer validate + terragrunt validate (Makefile:37-39)
make fmt         # packer fmt + terraform fmt + terragrunt hclfmt (Makefile:44-48)
make build       # full Packer build — produces an AMI; the actual integration test
make tg-plan     # Terragrunt plan against an existing AMI (Makefile:58-59)
make tg-apply    # Apply (interactive) (Makefile:61-62)
make tg-destroy  # Tear down (Makefile:67-68)
make status      # Verify the deployed instance is reachable (Makefile:100-101)
```

There is no `make test`, `make lint`, `make check`, or `make ci` target.

## What Each Existing Gate Actually Checks

### `make validate` (`Makefile:37-39`)

```makefile
validate: init
	cd packer && packer validate .
	DEVBOX_USER=$(DEVBOX_USER) terragrunt validate
```

- **`packer validate .`** — parses every `*.pkr.hcl` in `packer/`, type-checks variables, confirms required plugins are installable. Does NOT contact AWS, does NOT run Ansible.
- **`terragrunt validate`** — runs `terraform validate` after Terragrunt resolves the source and inputs. Confirms HCL parses, all required variables are set, provider versions resolve, and resource arguments type-check. Does NOT contact AWS, does NOT detect drift.

What it misses:
- Format violations (`terraform fmt -check` is not run).
- Linter findings (`tflint`, `ansible-lint`, `yamllint`, `shellcheck` are all installed by the image build but never run against this repo).
- Anything detectable only at `plan` time (missing AMI IDs, invalid AMIs, unreachable subnets, IAM permission gaps).
- Ansible playbook syntax (no `ansible-playbook --syntax-check`).

### `make fmt` (`Makefile:44-48`)

Uses `fmt` not `fmt -check`. **Will silently rewrite files** rather than failing. Treat this as a developer convenience, not a gate. A real gate would be:

```bash
packer fmt -check . && terraform fmt -check terraform/ && terragrunt hclfmt --check
```

There is no `make fmt-check`.

### `make init` (`Makefile:34-35`)

Runs `packer init .` to install plugins declared in `packer/devimage.pkr.hcl:1-12` (amazon ≥1.3.0, ansible ≥1.1.0). Required transitively for `make validate` since `validate` depends on `init`. Not a quality gate.

## What is Available But Unwired

These tools are installed onto the built AMI by `ansible/roles/devtools/tasks/main.yml` and `ansible/roles/terraform/tasks/main.yml`, but are NOT invoked against this repo's own source by any Makefile target, hook, or CI workflow:

| Tool | Installed by | Could check |
|------|--------------|-------------|
| `shellcheck` v0.10.0 | `ansible/roles/devtools/tasks/main.yml:7-33` | `scripts/*.sh` quality |
| `tflint` v0.53.0 | `ansible/roles/terraform/tasks/main.yml:19-35` | `terraform/*.tf` deeper lints |
| `terraform-docs` v0.18.0 | `ansible/roles/terraform/tasks/main.yml:37-55` | `terraform/` doc drift |
| `yq` v4.44.3 | `ansible/roles/devtools/tasks/main.yml:164-169` | YAML structural checks |

`ansible-lint` and `yamllint` configs exist only inside the vendored `AMAZON2023-CIS` role (`ansible/roles/AMAZON2023-CIS/.ansible-lint`, `ansible/roles/AMAZON2023-CIS/.yamllint`) and are scoped to that role's `site.yml`. Neither tool is installed for use against this repo's own playbooks. There is no root-level `.ansible-lint` or `.yamllint`.

## CI

**Absent.** There is no `.github/workflows/`, no `.gitlab-ci.yml`, no `Jenkinsfile`, no `.circleci/` directory. Confirmed by `ls`:

```text
$ ls -la .github .gitlab-ci.yml Jenkinsfile .circleci 2>&1
ls: .circleci: No such file or directory
ls: .github: No such file or directory
ls: .gitlab-ci.yml: No such file or directory
ls: Jenkinsfile: No such file or directory
```

Nothing runs `make validate` (or anything else) automatically on push, PR, or merge. All gates are developer-discipline-only.

## Pre-commit

The only `.pre-commit-config.yaml` in the tree lives inside the vendored CIS role at `ansible/roles/AMAZON2023-CIS/.pre-commit-config.yaml` and is wired to that role's own `site.yml` (see line 54: `entry: python3 -m ansiblelint --force-color site.yml -c .ansible-lint`). It would not execute on changes to this repo's first-party files even if `pre-commit install` were run, because the config is not at repo root.

There is no root-level pre-commit configuration.

## Smoke-Test Surface (recommended commands, not currently wired)

If you need to add the lightest possible "did I break the world?" check before opening a PR, this is the practical command set, in order of cost:

### Cheapest (seconds, no AWS)

```bash
# Format check (does not currently exist as a target)
packer fmt -check ./packer
terraform fmt -check -recursive ./terraform
terragrunt hclfmt --check

# Syntax / schema validate (this IS make validate)
make validate

# Ansible syntax check — would catch missing roles, malformed YAML, undefined vars referenced by name
ansible-playbook --syntax-check ansible/playbook.yml
ansible-playbook --syntax-check ansible/firewalld-docker-fix.yml

# Bash linting
shellcheck scripts/*.sh

# YAML lint (would need a root .yamllint or use the CIS-role one as a template)
yamllint ansible/

# Ansible lint (would need a root .ansible-lint)
ansible-lint ansible/playbook.yml
```

### Medium (seconds, contacts AWS read-only)

```bash
# Terragrunt plan against a throwaway DEVBOX_USER — surfaces missing AMI, invalid IDs,
# IAM permission issues. Does not provision.
make tg-plan DEVBOX_USER=ci-smoke
```

### Expensive (minutes, provisions resources)

```bash
# Full image build via Packer. THIS is the integration test today — it builds an AMI
# end-to-end, exercising every Ansible role enabled in ansible/layer_config.yml.
make build

# Full apply against the AMI produced above.
make tg-apply DEVBOX_USER=ci-smoke

# Verify the instance is reachable and the lifecycle scripts work.
make status DEVBOX_USER=ci-smoke
make stop DEVBOX_USER=ci-smoke
make start DEVBOX_USER=ci-smoke

# Tear down.
make tg-destroy DEVBOX_USER=ci-smoke
```

## Makefile Targets That Act as Test Gates

| Target | File | Acts as |
|--------|------|---------|
| `init` | `Makefile:34-35` | Plugin install prerequisite for `validate` |
| `validate` | `Makefile:37-39` | The only existing "lint"-shaped gate — Packer + Terragrunt schema/syntax |
| `fmt` | `Makefile:44-48` | Format rewrite (not a check) |
| `tg-init` | `Makefile:52-53` | First-time backend bootstrap; failure here means the user-scoped S3/DynamoDB backend setup is broken |
| `tg-plan` | `Makefile:58-59` | Smoke test for "Terraform would succeed against AWS" |
| `build` | `Makefile:41-42` | Full integration test (Packer + Ansible end-to-end). The de facto regression suite. |
| `status` | `Makefile:100-101` | Post-deploy reachability check via `scripts/devbox-status.sh` |

`clean` (`Makefile:105-107`) is housekeeping, not a gate.

## Coverage

**Not measured.** No coverage concept applies to IaC linting/validation, and the repo has no unit tests to measure coverage of. The closest analogue is "what % of roles are exercised by `make build`?" — answer: every role with `layers.<name>: true` in `ansible/layer_config.yml`, which is currently **all roles** (`ansible/layer_config.yml:5-19`). The `containers` layer's dependent workaround (`firewalld-docker-fix.yml`) only runs when `layers.containers` is truthy (`ansible/firewalld-docker-fix.yml:32-33`), and that condition is satisfied by the current config.

## Gaps Worth Naming

1. **No `make lint`** — `shellcheck`, `tflint`, `ansible-lint`, `yamllint` are all available but unwired.
2. **No `make fmt-check`** — `make fmt` rewrites files instead of failing on diffs, so a stale-format PR can sneak through.
3. **No CI** — every gate is local and discretionary.
4. **No `ansible-playbook --syntax-check`** in `make validate` — `terragrunt validate` covers Terraform but nothing covers the Ansible side until Packer reaches the provisioner stage minutes into a build.
5. **No `tg-plan` in `make validate`** — `validate` does not contact AWS, so AMI-ID typos, missing subnets, or IAM regressions only surface at `tg-apply` time.
6. **No Packer plugin lock check** — `packer init` will resolve `>= 1.3.0` to whatever is current; there is no committed `.pkr.hcl.lock` (it is `.gitignore`d at `.gitignore:3`).
7. **No drift detection** — nothing scheduled to run `tg-plan` against deployed environments to catch out-of-band changes.

---

*Testing analysis: 2026-05-13*
