---
phase: 02-network-exposure-remediation
plan: 02
subsystem: operator-ux-makefile-scripts
tags:
  - operator-ux
  - makefile
  - aws-ssm-session-manager
  - bash-scripts
requirements: []
provides:
  - make-target.devbox-ssm
  - make-target.devbox-port-forward
  - make-target.devbox-allowlist-me
  - scripts/devbox-ssm.sh
  - scripts/devbox-allowlist-me.sh
affects:
  - scripts/devbox-status.sh (connection-info block rewritten — SSM-first)
  - scripts/devbox-start.sh (post-start connection-info rewritten — SSM-first)
  - Makefile (.PHONY + help + 3 new recipes)
key-files:
  created:
    - path: scripts/devbox-ssm.sh
      range: "1-61"
    - path: scripts/devbox-allowlist-me.sh
      range: "1-88"
  modified:
    - path: scripts/devbox-status.sh
      range: "3-4 (shellcheck source directive), 48-64 (connection-info block rewritten — was 47-53 pre-plan)"
    - path: scripts/devbox-start.sh
      range: "3-4 (shellcheck source directive), 65-71 (SC2034 directive on retained KEY_NAME query), 72-79 (connection-info block rewritten — was 70-75 pre-plan)"
    - path: Makefile
      range: "1 (.PHONY), 29-33 (help SSM access stanza), 111-138 (three new recipes)"
decisions:
  - "Single-port-forwarding for :8080 only — AWS-StartPortForwardingSession document accepts one port per session. Operators needing :6080 use `make devbox-allowlist-me` or open a second port-forward session. Trade-off documented inline at Makefile:114-116."
  - "Pre-flight `command -v session-manager-plugin` duplicated between scripts/devbox-ssm.sh and the Makefile devbox-port-forward recipe — acceptable 4-line duplication over a fourth single-purpose script (YAGNI)."
  - "Atomic-write pattern (temp file + mv) in scripts/devbox-allowlist-me.sh prevents partial-write on Ctrl-C — defense in depth alongside Terraform's cidrhost() validation."
  - "Defensive array-expansion form `\${EXTRA_CIDRS[@]+\"\${EXTRA_CIDRS[@]}\"}` used in scripts/devbox-allowlist-me.sh:69 so `set -u` doesn't trip when no `--extra-cidr` is passed. Auto-fix from Rule 1 (would otherwise crash the happy path)."
  - "shellcheck disable directives (SC1091 source-following, SC2034 unused KEY_NAME) added inline to the in-scope scripts to satisfy the plan's shellcheck-zero-warnings gate; no behavior change. KEY_NAME query in devbox-start.sh retained per plan instruction (cleanup is out of scope)."
metrics:
  duration_minutes: 12
  tasks_completed: 5
  files_modified: 3
  files_created: 2
  commits: 5
  completed_date: 2026-05-14
---

# Phase 2 Plan 02: Operator UX Layer (Makefile + SSM-first scripts) Summary

## One-liner

Operator UX layer landed on top of 02-01's SSM-first posture — three new `make` targets (`devbox-ssm`, `devbox-port-forward`, `devbox-allowlist-me`), two new shell scripts (`scripts/devbox-ssm.sh`, `scripts/devbox-allowlist-me.sh`), and the two pre-existing lifecycle scripts (`devbox-status.sh`, `devbox-start.sh`) reprinted with SSM-first connection-info blocks; stale `ssh -i ~/.ssh/${KEY_NAME}.pem` instructions purged from every surfaced operator string.

## Files created

| Path | Lines | Purpose |
|------|-------|---------|
| `scripts/devbox-ssm.sh` | 1-61 | Pre-flights `session-manager-plugin`; sources `_common.sh` for `init_devbox` (which resolves `instance_id`/`aws_region` from terragrunt outputs); exec's `aws ssm start-session --target $INSTANCE_ID --region $REGION`. |
| `scripts/devbox-allowlist-me.sh` | 1-88 | `curl --max-time 5 https://checkip.amazonaws.com` → IPv4 regex validation → atomic write of `./allowlist.auto.tfvars` with `allowed_web_cidrs = ["$IP/32"]` → prints `make tg-apply` next-step. Supports repeatable `--extra-cidr` for office ranges. |

## Files modified

| Path | Lines touched | Change |
|------|---------------|--------|
| `scripts/devbox-status.sh` | 3-4 (added `# shellcheck source=_common.sh disable=SC1091`); 48-64 (rewrote the entire `if [[ "$STATE" == "running" ... ]]; then ... fi` block — was lines 47-53 pre-plan) | Connection-info block prints SSM start-session command unconditionally on `running` state (no longer gated on PUBLIC_IP != "N/A"); browser URLs annotated with `(requires your IP in allowed_web_cidrs)`; surfaces both `make devbox-port-forward` (no-public-ingress) and `make devbox-allowlist-me && make tg-apply` (recovery) paths. |
| `scripts/devbox-start.sh` | 3-4 (added `# shellcheck source=_common.sh disable=SC1091`); 65-71 (added `# shellcheck disable=SC2034` directive on retained KEY_NAME query); 72-79 (rewrote post-start Connection Info block — was 70-75 pre-plan) | SSH command line replaced with SSM equivalent; browser URLs annotated; first-time-run hint surfaces `make devbox-allowlist-me && make tg-apply`. |
| `Makefile` | 1 (`.PHONY` extended); 29-33 (new `SSM access` help stanza); 111-138 (three new recipes after `status:`) | Three new `.PHONY` targets wired in; `help` lists them under a clearly-named section between Instance lifecycle and Secrets. `devbox-ssm` and `devbox-allowlist-me` shell out to their respective scripts; `devbox-port-forward` inlines a `session-manager-plugin` pre-flight + `aws ssm start-session --document-name AWS-StartPortForwardingSession --parameters portNumber=8080`. |

## Tasks executed

| # | Task | Commit |
|---|------|--------|
| 1 | Create `scripts/devbox-ssm.sh` | `72280fa` |
| 2 | Create `scripts/devbox-allowlist-me.sh` | `bb9eaf9` |
| 3 | Rewrite connection-info blocks in `devbox-status.sh` and `devbox-start.sh` | `9b90008` |
| 4 | Add `devbox-ssm` / `devbox-port-forward` / `devbox-allowlist-me` to `Makefile` + help | `7bf3d67` |
| 5 | Smoke-test the wiring (revealed one comment-rephrase needed in `devbox-ssm.sh`) | `86816ed` |

All five tasks executed in plan order. No tasks deferred. No tasks split.

## Verification commands run

### 1. shellcheck on all four in-scope scripts

```bash
$ shellcheck scripts/devbox-ssm.sh scripts/devbox-allowlist-me.sh scripts/devbox-status.sh scripts/devbox-start.sh
exit=0
```

(Out-of-scope: `scripts/devbox-stop.sh` and `scripts/_common.sh` still emit SC1091/SC2034 informational findings from before this plan started; left untouched per the scope-boundary rule.)

### 2. `bash -n` (syntactic) on all four in-scope scripts

```bash
$ bash -n scripts/devbox-ssm.sh scripts/devbox-allowlist-me.sh scripts/devbox-status.sh scripts/devbox-start.sh
all 4 OK
```

### 3. Make targets dry-run (no AWS calls)

```bash
$ make -n devbox-ssm DEVBOX_USER=testuser
DEVBOX_USER=testuser ./scripts/devbox-ssm.sh

$ make -n devbox-allowlist-me
./scripts/devbox-allowlist-me.sh

$ make -n devbox-port-forward DEVBOX_USER=testuser
set -euo pipefail; \
	command -v session-manager-plugin >/dev/null 2>&1 || { \
	  echo "ERROR: session-manager-plugin not installed. brew install --cask session-manager-plugin" >&2; \
	  exit 1; \
	}; \
	INSTANCE_ID=$(DEVBOX_USER=testuser terragrunt output -raw instance_id); \
	REGION=$(DEVBOX_USER=testuser terragrunt output -raw aws_region); \
	echo "Forwarding :8080 from $INSTANCE_ID to localhost..."; \
	echo "Browse to https://localhost:8080 (code-server)."; \
	echo "For noVNC :6080, run 'make devbox-allowlist-me' or open a second forwarding session."; \
	echo "Ctrl-C to stop forwarding."; \
	exec aws ssm start-session \
	  --target "$INSTANCE_ID" \
	  --region "$REGION" \
	  --document-name AWS-StartPortForwardingSession \
	  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

### 4. `make help` lists the SSM access section

```bash
$ make help | grep -A 5 'SSM access'
SSM access (Phase 2 — replaces public :22 ingress)
  devbox-ssm           Open an SSM Session Manager shell to the devbox
  devbox-port-forward  Forward :8080 from the devbox to localhost over SSM
  devbox-allowlist-me  Resolve your public IP and write allowlist.auto.tfvars

Secrets
```

### 5. No stale `ssh -i ~/.ssh/` in any script

```bash
$ ! grep -rF "ssh -i ~/.ssh/" scripts/
PASS
```

(After Task 5 commit `86816ed` — the original Task 1 header comment in `scripts/devbox-ssm.sh` referenced the literal string in describing what the new script REPLACES, which tripped the smoke gate. Rephrased to "per-operator-key SSH-over-public-:22 flow" — no behavior change.)

### 6. Captive-portal regex defense (synthetic)

The script-side IPv4 regex was exercised against a fake captive-portal HTML payload via a stub `curl` on `PATH`:

```bash
# Stub curl returns "<html>captive portal redirect</html>"
$ PATH=/tmp/stub:$PATH scripts/devbox-allowlist-me.sh
Resolving public IP from https://checkip.amazonaws.com ...
ERROR: checkip.amazonaws.com returned unexpected payload: '<html>captiveportalredirect</html>'

Are you behind a captive portal, or is curl blocked?
Override manually:
  echo 'allowed_web_cidrs = ["YOUR.IP.HERE/32"]' > ./allowlist.auto.tfvars
exit=1
```

Then exercised with a stub returning `203.0.113.42`:

```bash
$ PATH=/tmp/stub:$PATH scripts/devbox-allowlist-me.sh
Resolving public IP from https://checkip.amazonaws.com ...

Wrote ./allowlist.auto.tfvars:
----------------------------------------
# AUTO-GENERATED by make devbox-allowlist-me on 2026-05-14T02:08:31Z
# Operator: me
# Public IP at time of write: 203.0.113.42
# Refresh by re-running 'make devbox-allowlist-me' after IP changes.
# Gitignored — see .gitignore Phase-2 stanza.
allowed_web_cidrs = ["203.0.113.42/32"]
----------------------------------------

Next: make tg-apply
exit=0
```

Both the failure-mode and happy path work as designed.

### 7. 02-01 outputs are still present (dependency check)

```bash
$ grep -q 'output "instance_id"' terraform/outputs.tf && echo OK
OK
$ grep -q 'output "aws_region"' terraform/outputs.tf && echo OK
OK
$ grep -q 'output "ssm_start_session_command"' terraform/outputs.tf && echo OK
OK
```

### 8. `ssm_start_session_command` output is NOT consumed by any script (intentional)

```bash
$ if grep -r "ssm_start_session_command" scripts/ 2>/dev/null; then echo "INFO: scripts read the prebuilt output"; else echo "INFO: scripts build the command themselves (preferred)"; fi
INFO: scripts build the command themselves (preferred)
```

Scripts construct the SSM command from `instance_id` + `aws_region` rather than reading the pre-built string — keeps them resilient to future output renames, and avoids quoting issues in cross-shell rendering.

## Threat model mitigations applied

| Threat ID | Mitigation in this plan | File:line evidence |
|-----------|-------------------------|---------------------|
| T-02-10 Tampering — captive-portal HTML written to tfvars | IPv4-shape regex (`^([0-9]{1,3}\.){3}[0-9]{1,3}$`) runs BEFORE the write; `curl --max-time 5` bounds the request; atomic temp-file write + `mv` prevents partial-write on Ctrl-C. Second-layer defense is 02-01's Terraform `cidrhost()` validation. | `scripts/devbox-allowlist-me.sh:47` (curl), `scripts/devbox-allowlist-me.sh:55` (regex), `scripts/devbox-allowlist-me.sh:75-83` (atomic mv) |
| T-02-11 Information Disclosure — operator IP into git | Atomic write targets exactly `./allowlist.auto.tfvars`, which 02-01 added to `.gitignore` (`*.auto.tfvars` + explicit `allowlist.auto.tfvars`). | `scripts/devbox-allowlist-me.sh:37` (default output path), `.gitignore` (added in 02-01 commit `f5b9581`) |
| T-02-12 Spoofing — DNS poisoning of checkip.amazonaws.com | Accepted per plan. HTTPS cert validation (curl default) protects against MITM; DNS-poisoning blast radius is broader than "wrong CIDR." | n/a (accepted) |
| T-02-13 DoS — missing `session-manager-plugin` | Pre-flight `command -v session-manager-plugin` check in BOTH `scripts/devbox-ssm.sh` AND the `Makefile` `devbox-port-forward` recipe; prints brew/Linux install recipe to stderr and exits 1. | `scripts/devbox-ssm.sh:35-50`, `Makefile:118-121` |
| T-02-14 EoP — port-forward exposes localhost:8080 to localhost attacker | Code-server password (Phase 1 SSM SecureString) gates the listener; port forward exposes the SAME authentication surface as direct ingress would — no privilege escalation introduced. Recommend operators Ctrl-C the forwarding session when not in use (will land in Phase 4 CLAUDE.md). | n/a (architectural; auth gate inherited from Phase 1) |
| T-02-15 Repudiation — operator denies port-forward session | `aws ssm start-session --document-name AWS-StartPortForwardingSession` is logged to CloudTrail with the document type visible in the event payload. Same audit story as a shell session. | n/a (AWS-default audit) |
| T-02-16 Information Disclosure — port-forward exposed on LAN | `AWS-StartPortForwardingSession` default binds to `127.0.0.1` (loopback) when `localBindAddress` parameter is absent. The `devbox-port-forward` recipe does NOT pass `localBindAddress`, so the loopback-only default applies. | `Makefile:131-134` (no `localBindAddress` in `--parameters`) |

No threat dispositions changed during execution. No new threat surface introduced beyond the planned scope.

## Operator quick-start cheat sheet (post-Phase-2)

The four-to-five commands a new operator needs to know:

```bash
# One-time setup (per workstation):
brew install --cask session-manager-plugin     # macOS — see plan user_setup for Linux

# One-time setup (per repo clone, after each public-IP change):
make devbox-allowlist-me                       # writes ./allowlist.auto.tfvars

# Daily lifecycle:
make start                                     # boot the instance
make status                                    # see Connection Info (SSM cmd + browser URLs)
make devbox-ssm                                # open an interactive shell (replaces ssh -i ...)
make devbox-port-forward                       # localhost:8080 → instance:8080 over SSM (code-server tunnel)
make stop                                      # halt the instance (no compute charges)

# Refresh allowlist after public IP changes:
make devbox-allowlist-me && make tg-apply
```

Pre-Phase-2 operators see migration steps in `02-01-SUMMARY.md` §Migration notes. The only new tool is `session-manager-plugin`; everything else is `make`-driven and ergonomically equivalent to the Phase 1 workflow.

## Trade-off log

1. **`devbox-port-forward` forwards :8080 only** — `AWS-StartPortForwardingSession` accepts a single `portNumber` per session. Operators who want :6080 (noVNC) forwarded can (a) add their IP to `allowed_web_cidrs` via `make devbox-allowlist-me` and use the public URL, or (b) open a second port-forward session with `portNumber=6080` manually. Inline comment at `Makefile:114-116` documents this; cheat-sheet hint in the port-forward recipe runtime output.

2. **`session-manager-plugin` pre-flight duplicated** between `scripts/devbox-ssm.sh:33-50` and `Makefile:118-121`. Acceptable 4-line duplication; abstracting into a fourth script ("preflight only") would be YAGNI for a check that pays its way at both call sites.

3. **`scripts/devbox-allowlist-me.sh` does NOT source `scripts/_common.sh`** — it doesn't need to resolve an instance, only operates on the operator workstation. Kept standalone with its own `set -euo pipefail` + arg-parse to maintain low coupling.

4. **`KEY_NAME` query retained in `scripts/devbox-start.sh:65-69`** — value is now unused in the rewritten output block. Plan explicitly says "leave it for now (cleanup is out of scope)." Added `# shellcheck disable=SC2034` directive with a one-line explanatory comment so the gate passes; future cleanup PR can drop the query entirely.

## Operator prereqs (consumed by Phase 4 DOC-01 quickstart)

| Dependency | Why | Install |
|------------|-----|---------|
| `session-manager-plugin` | Required by `make devbox-ssm` and `make devbox-port-forward`. The AWS CLI shells out to it for any `aws ssm start-session` invocation. | macOS: `brew install --cask session-manager-plugin`. Linux: see https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html |

Cross-reference: `02-01-SUMMARY.md` §"Operator Prereqs (consumed by Phase 4 DOC-01 quickstart)".

## Cross-reference

- `02-01-SUMMARY.md` — AWS-side change (SG :22 drop, web-port CIDR gate, `AmazonSSMManagedInstanceCore` policy attach, `output.ssm_start_session_command`).
- `02-RESEARCH.md` Pattern 4 (status script template), Pattern 5 (Makefile recipe template), §"Don't Hand-Roll" (operator IP discovery rationale).

## Deviations from plan

### Auto-fixed (Rule 1 — Bug)

**1. [Rule 1 — Bug] Defensive array expansion in `scripts/devbox-allowlist-me.sh`**

- **Found during:** Task 2 first dry-run.
- **Issue:** The plan's verbatim `for c in "${EXTRA_CIDRS[@]}"; do ... done` trips `set -u` ("unbound variable") in bash 4.x when no `--extra-cidr` flag is passed (the common case) because the array is uninitialized. The script would crash on the happy path.
- **Fix:** Use the indirect-expansion guard `${EXTRA_CIDRS[@]+"${EXTRA_CIDRS[@]}"}` which yields nothing when the array is unset and the elements when set. Standard bash idiom.
- **Files modified:** `scripts/devbox-allowlist-me.sh:69`
- **Commit:** `bb9eaf9` (folded into Task 2 commit).

### Auto-fixed (Rule 3 — Blocker)

**2. [Rule 3 — Blocker] SC1091 directive on `source "$SCRIPT_DIR/_common.sh"` lines**

- **Found during:** Task 3 verify gate (`shellcheck scripts/devbox-status.sh scripts/devbox-start.sh`).
- **Issue:** shellcheck emits SC1091 (info-level) on `source "$SCRIPT_DIR/_common.sh"` because it can't follow the path expression. The plan's verify line requires the script to pass shellcheck with no findings.
- **Fix:** Add `# shellcheck source=_common.sh disable=SC1091` directive immediately above each `source` line. No behavior change. Same pattern applied to the new `scripts/devbox-ssm.sh`.
- **Files modified:** `scripts/devbox-status.sh:3-4`, `scripts/devbox-start.sh:3-4`, `scripts/devbox-ssm.sh:11-12`
- **Commits:** Folded into Task 1 (`72280fa`) and Task 3 (`9b90008`).

**3. [Rule 3 — Blocker] SC2034 directive on retained `KEY_NAME` query in `scripts/devbox-start.sh`**

- **Found during:** Task 3 verify gate.
- **Issue:** Plan EXPLICITLY instructs leaving the pre-existing `KEY_NAME` query in place ("The redundant `KEY_NAME` resolution at `scripts/devbox-start.sh:64-68` is left in place (cleanup is out of scope)"). But removing the SSH line that used `KEY_NAME` means shellcheck now correctly flags it as SC2034 "unused variable."
- **Fix:** Add `# shellcheck disable=SC2034` directive with a one-line explanatory comment that points at the deferred cleanup. No behavior change.
- **Files modified:** `scripts/devbox-start.sh:65-71` (added 3 lines of comment + directive above the query).
- **Commit:** `9b90008` (folded into Task 3 commit).

**4. [Rule 3 — Blocker] Comment rephrase in `scripts/devbox-ssm.sh` for the smoke-gate**

- **Found during:** Task 5 final smoke test.
- **Issue:** The original Task 1 header comment in `scripts/devbox-ssm.sh` literally contained `ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@${PUBLIC_IP}` as part of "Replaces the old ... flow." The plan's Task 5 smoke gate `! grep -rF "ssh -i ~/.ssh/" scripts/` matched this comment string and failed.
- **Fix:** Reworded the comment to "per-operator-key SSH-over-public-:22 flow" — semantically equivalent, no literal string match. No behavior change.
- **Files modified:** `scripts/devbox-ssm.sh:2-3`
- **Commit:** `86816ed` (separate Task 5 commit — could not be folded retroactively into Task 1's already-pushed `72280fa`).

### Rule 2 — Missing critical functionality

None. All threat-model `mitigate` dispositions covered by the plan's listed deltas (verified in §"Threat model mitigations applied" above).

### Architectural (Rule 4)

None. No checkpoints encountered. Plan was `autonomous: true` end-to-end.

## Deferred items

None. All task-level verification gates passed.

## Self-Check: PASSED

Created files exist:

- `scripts/devbox-ssm.sh` — FOUND, executable (`-rwxr-xr-x`), 61 lines, contains `command -v session-manager-plugin` + `exec aws ssm start-session`.
- `scripts/devbox-allowlist-me.sh` — FOUND, executable, 88 lines, contains `curl -sS --max-time 5 https://checkip.amazonaws.com` + `allowed_web_cidrs = [`.

Modified files match plan:

- `scripts/devbox-status.sh` — FOUND (65 lines); contains `aws ssm start-session --target` + `allowed_web_cidrs` + `make devbox-allowlist-me`; no `ssh -i ~/.ssh/${KEY_NAME}.pem`.
- `scripts/devbox-start.sh` — FOUND (81 lines); contains `aws ssm start-session --target`; no `ssh -i ~/.ssh/${KEY_NAME}.pem`.
- `Makefile` — FOUND (165 lines); `.PHONY` contains `devbox-ssm devbox-port-forward devbox-allowlist-me`; `help` contains `SSM access (Phase 2`; three recipes (`devbox-ssm:`, `devbox-port-forward:`, `devbox-allowlist-me:`).

Commits exist in `git log`:

- `72280fa` — Task 1 (devbox-ssm.sh) FOUND
- `bb9eaf9` — Task 2 (devbox-allowlist-me.sh) FOUND
- `9b90008` — Task 3 (status/start rewrites) FOUND
- `7bf3d67` — Task 4 (Makefile targets) FOUND
- `86816ed` — Task 5 (smoke-gate comment fix) FOUND

Verdict: **COMPLETE**
