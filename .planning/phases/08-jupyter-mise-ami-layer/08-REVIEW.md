---
phase: 08-jupyter-mise-ami-layer
reviewed: 2026-06-02T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - ansible/roles/mise/defaults/main.yml
  - ansible/roles/mise/tasks/main.yml
  - ansible/roles/jupyter/defaults/main.yml
  - ansible/roles/jupyter/handlers/main.yml
  - ansible/roles/jupyter/tasks/main.yml
  - ansible/roles/jupyter/templates/jupyter.service.j2
  - ansible/roles/secrets/defaults/main.yml
  - ansible/roles/secrets/tasks/generate.yml
  - ansible/roles/secrets/tasks/publish.yml
  - ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2
  - ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2
  - ansible/playbook.yml
  - ansible/layer_config.yml
  - .pre-commit-config.yaml
  - .github/workflows/ci.yml
findings:
  critical: 1
  warning: 6
  info: 5
  total: 12
status: resolved
resolution: loopback-on-demand-pivot
resolved_at: 2026-06-02T00:00:00Z
---

# Phase 8: Code Review Report

**Reviewed:** 2026-06-02
**Depth:** standard

> **Resolution (2026-06-02):** After this review, the operator pivoted JupyterLab to
> **loopback-only, on-demand** (`./run jupyter` → `127.0.0.1:8888` over SSM; no systemd
> unit, no TLS, no password). This eliminated the network-exposed listener, which
> **resolves CR-01** (auth-floor bypass) and the Jupyter-specific warnings
> **WR-01/WR-02/WR-04** (the password is gone entirely). **WR-05** (the bootstrap `.sh.j2`
> is outside CI's shellcheck glob) remains a valid, pre-existing follow-up — the bootstrap
> script still exists for code-server/VNC. Info items (IN-01..05) match pre-existing repo
> conventions. See commits e671856, 988115a, 93a9af6, 1bd0d7e.
**Files Reviewed:** 15
**Status:** issues_found

## Summary

Phase 08 adds a `mise` role, a `jupyter` role, extends `secrets` for a per-build
Jupyter password, and wires both new roles plus two grep-gate invariants into the
build. The secrets-handling design is sound on the happy path: the cleartext
password is generated in-memory with `no_log`, published only as an SSM
SecureString, and the boot oneshot writes only the hashed value to a 0600 config.
The intentional `ipykernel==6.29.5` pin (Python 3.9 floor) is consistent across
defaults, tasks, and summary — not flagged.

However, the review surfaced one BLOCKER: the Jupyter HTTPS server has **no
authentication floor** if the boot oneshot is skipped (the common second-boot /
config-deleted / SSM-failure paths), because the systemd unit only *orders* after
the bootstrap rather than *depending* on it, and the ExecStart sets no token. Six
WARNINGs cover defense-in-depth gaps (password passed as a process argument, no
cert/key idempotency guard, the bootstrap template escaping shellcheck coverage,
a missing `mise` checksum-fail-fast story, and a non-atomic key-permission
window). Info items are convention/consistency nits.

## Critical Issues

### CR-01: Jupyter server starts with no password AND no token when boot oneshot is skipped

**File:** `ansible/roles/jupyter/templates/jupyter.service.j2:7,13-19` and `ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2:6`

**Issue:**
`jupyter.service` enforces auth solely through `c.PasswordIdentityProvider.hashed_password`,
which is written *only* by `devbox-secrets-bootstrap.sh`. The unit relationship is
`After=devbox-secrets-bootstrap.service` (ordering only) — there is no
`Requires=`, `BindsTo=`, or `ConditionPathExists=` guard tying Jupyter's start to
the config actually existing. The bootstrap unit is gated by
`ConditionPathExists=!/var/lib/devbox/secrets-applied`, so it runs **exactly
once, ever**. Consequently, on any boot where the marker exists but the config
does not, Jupyter starts unauthenticated. Reachable scenarios:

1. **Second boot after the user deletes `~/.jupyter/jupyter_server_config.py`** — marker
   present, condition false, bootstrap does not re-run, Jupyter starts with the
   config gone.
2. **Bootstrap partial failure** — the script `touch`es the marker *before* the
   restart loop (line 88-89), but if the config write earlier failed in a way that
   left the file empty/removed out of band, the marker still suppresses re-run.
3. **`secrets-applied` restored from a snapshot/AMI re-bake** without the per-user
   home config.

The ExecStart passes no `--ServerApp.token=...` and no `--ServerApp.password=...`,
so with the config file absent JupyterLab falls back to its built-in default. On a
service started by systemd (non-interactive, no stdout token capture), this is an
HTTPS server on `0.0.0.0:8888` reachable by anyone in `allowed_web_cidrs` with at
best a token that no operator ever sees and at worst (depending on jupyter-server
version defaults / `--ServerApp.token=''` being inferred) no auth at all. The unit
header comment claims "This unit alone never starts an open server" — that claim
is only true on the single first boot.

**Fix:** Make the server refuse to start without its auth config, independent of
the one-shot's run-once marker. Add a hard dependency and a config-presence guard
to the unit:

```ini
[Unit]
Description=JupyterLab
After=network.target devbox-secrets-bootstrap.service
Requires=devbox-secrets-bootstrap.service
# Refuse to start if the password config was never written / was removed.
ConditionPathExists={{ dev_home }}/.jupyter/jupyter_server_config.py

[Service]
...
# Belt-and-braces: never silently fall back to no-auth.
ExecStartPre=/usr/bin/grep -q 'hashed_password' {{ dev_home }}/.jupyter/jupyter_server_config.py
```

Additionally, decouple the run-once marker from password-config presence: either
drop the `ConditionPathExists=!...secrets-applied` guard for the config-writing
portion, or split the idempotency marker so a missing Jupyter config re-triggers
just the Jupyter hash/write block. (The current single marker also blocks
SSH-key/CIDR-independent re-provisioning of *all three* services — see WR-02.)

## Warnings

### WR-01: Jupyter cleartext password is passed as a command-line argument (visible in process table)

**File:** `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:64-67`

**Issue:** The cleartext password is interpolated into the Python `-c` program text:
`passwd('${JUPYTER_PWD}')`. The fully-expanded argument — including the cleartext
secret — is visible in `/proc/<pid>/cmdline` and to any `ps` observer for the life
of the hashing subprocess. The boot oneshot runs as root early in boot, so the
exposure window is small and the box is single-tenant, but this is an unnecessary
cleartext-on-the-argv leak that the rest of the design carefully avoids
(everything else uses stdin/env). Note the contrast with the VNC path two lines
up, which correctly pipes the secret via stdin (`printf '%s' "$VNC_PWD" | ... vncpasswd -f`).

**Fix:** Pass the secret via stdin or environment, not argv:

```bash
JUPYTER_HASH=$(JPW="$JUPYTER_PWD" /opt/jupyter/bin/python3 -c \
  'import os; from jupyter_server.auth import passwd; print(passwd(os.environ["JPW"]))' 2>/dev/null) \
  || JUPYTER_HASH=$(JPW="$JUPYTER_PWD" /opt/jupyter/bin/python3 -c \
  'import os; from jupyter_server.auth import passwd; print(passwd(os.environ["JPW"], algorithm="sha256"))')
```

This also closes the latent injection vector in WR-04 by removing string
interpolation into the program text entirely.

### WR-02: Run-once marker is written before the restart loop, so a restart failure leaves services on stale/no config with no retry

**File:** `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:85-97`

**Issue:** `touch /var/lib/devbox/secrets-applied` (line 89) runs *before* the
service restart loop (lines 93-97). The inline comment justifies this as avoiding
re-rotation of `~/.vnc/passwd`. The trade-off, however, is that if every
`systemctl restart` in the loop fails (units masked, dbus not ready, etc.), the
script still exits 0 (the loop swallows failures with `|| echo WARN`), the marker
is set, and the oneshot will **never run again** — leaving the services running on
whatever config they had before (or failing to come up) with no automatic
recovery. Combined with CR-01, a failed Jupyter restart here means the next manual
`systemctl start jupyter` brings up a server whose config may not have been picked
up.

**Fix:** Track restart success and only set the completion marker if the critical
services actually restarted, or make the loop's failures fatal for required
services:

```bash
restart_failed=0
for svc in code-server.service vncserver.service novnc.service jupyter.service; do
  if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
    systemctl restart "$svc" || { echo "ERROR: failed to restart $svc" >&2; restart_failed=1; }
  fi
done
[[ "$restart_failed" -eq 0 ]] || exit 1   # leave marker unset so oneshot retries next boot
install -d -m 0755 /var/lib/devbox
touch /var/lib/devbox/secrets-applied
```

(If VNC re-rotation on retry is genuinely unacceptable, split the marker per-service.)

### WR-03: `systemctl list-unit-files` matches *templates and disabled units*, so the guard does not actually prove the unit is installed/startable

**File:** `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:93-94`

**Issue:** The loop guards each restart with
`systemctl list-unit-files "$svc" >/dev/null 2>&1`. `list-unit-files` returns exit
0 even when the argument matches nothing on some systemd versions (it returns the
header and exits 0), and conversely lists units that are present-but-not-installed.
The intent ("tolerate units that aren't installed") is better served by checking
the unit's load state. As written, the guard can both (a) attempt to restart a
non-existent unit and (b) is redundant with the `|| echo WARN` fallback.

**Fix:** Use a load-state check that is unambiguous:

```bash
if systemctl cat "$svc" >/dev/null 2>&1; then
    systemctl restart "$svc" || echo "WARN: failed to restart $svc" >&2
fi
```

### WR-04: Latent shell/Python-string injection via password interpolation (currently masked only by the generator charset)

**File:** `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2:64-67`

**Issue:** `passwd('${JUPYTER_PWD}')` embeds the SSM-sourced value directly inside a
single-quoted Python literal inside a double-quoted shell string. Today this is
safe *only* because `generate.yml` restricts the charset to `ascii_letters,digits`
(no `'`, `"`, `\`, `$`, newline). That safety is non-local: it depends on a value
set in a different file in a different role, fetched at runtime from SSM (a
mutable store an operator could overwrite by hand). If the charset is ever widened
(e.g. to add symbols for entropy), or if the SSM parameter is set to a value
containing a single quote, this breaks the Python parse at best and executes
attacker-controlled Python at worst. This is the classic "data interpolated into
code" anti-pattern flagged by `security.md`.

**Fix:** Same as WR-01 — pass the secret through `os.environ`, never into the
program text. That makes the code injection-proof regardless of charset.

### WR-05: The bootstrap shell template is never linted by shellcheck (CI nor pre-commit reliably covers `*.sh.j2`)

**File:** `.github/workflows/ci.yml:149` and `.pre-commit-config.yaml:62-67`

**Issue:** The most security-sensitive script in the repo —
`devbox-secrets-bootstrap.sh.j2`, which handles three cleartext secrets — is not
covered by shellcheck. CI runs `shellcheck scripts/*.sh` (line 149), which only
matches `scripts/*.sh`; the template lives under `ansible/roles/.../templates/` and
has a `.sh.j2` extension. The pre-commit `shellcheck` hook uses `types: [shell]`,
but a Jinja-templated `.sh.j2` is not reliably identified as `shell` by
pre-commit's `identify` (the `.j2` extension and embedded `{{ }}` defeat both
extension- and shebang-based detection in the general case), so it is silently
skipped there too. The result: a file full of `set -euo pipefail`, command
substitution, and heredocs gets zero static analysis.

**Fix:** Add an explicit shellcheck pass for the template (rendered or with
template directives stubbed). Minimal CI addition:

```yaml
- name: shellcheck bootstrap template
  run: |
    # strip Jinja so shellcheck can parse; treat {{...}} as a literal token
    sed -E 's/\{\{[^}]*\}\}/x/g' ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2 \
      | shellcheck -s bash -
```

### WR-06: No fail-fast / surfaced error if the `mise` checksum mismatches at a future version bump, and no cleanup of a partial download

**File:** `ansible/roles/mise/tasks/main.yml:2-7`

**Issue:** The checksum verification itself is correct and mandatory (good). The
concern is operational robustness: `get_url` with `dest: {{ mise_install_dir }}/mise`
writes directly to the final path `/usr/local/bin/mise`. On a checksum mismatch
`get_url` does fail the play (good), but because there is no staging-then-move,
the failure-mode story depends entirely on `get_url`'s internal temp handling, and
the `mode: "0755"` is applied to a file that — on a successful-download-but-wrong-checksum
race — must never become executable. More importantly, there is no `force`/`changed_when`
discipline: a future `mise_version` bump with a stale `mise_checksum_sha256` will
fail loudly (intended), but the error will read as a generic checksum failure with
no pointer to "update both fields together." This is a maintainability/robustness
gap, not an active vulnerability.

**Fix:** Add an assertion that version and checksum are co-pinned, and a clear
failure message, e.g. a preceding `assert` that `mise_checksum_sha256 | length == 64`
and a task comment instructing bumpers to update both `defaults/main.yml` fields
atomically. Optionally download to a temp path and `copy remote_src` into place so
a bad artifact never lands on `$PATH`.

## Info

### IN-01: Handlers use the non-FQCN short name `systemd:` while phase-08 tasks standardized on FQCN

**File:** `ansible/roles/jupyter/handlers/main.yml:3`

**Issue:** Every task file added in this phase uses `ansible.builtin.*` FQCN (a
stated convention in the summaries), but the new `jupyter/handlers/main.yml` uses
the bare `systemd:` module name. It matches the *pre-existing* `desktop`/`vscode`
handlers, so it is internally consistent with the repo's handler style but
inconsistent with the phase's own task-file convention. ansible-lint's `fqcn` rule
will flag this. Low impact; note for convention consistency.

**Fix:** `ansible.builtin.systemd:` and `name: Reload systemd` (capitalized, per
ansible-lint `name[casing]`).

### IN-02: Handler/task `name` casing will trip ansible-lint `name[casing]`

**File:** `ansible/roles/jupyter/handlers/main.yml:2` (`reload systemd`)

**Issue:** ansible-lint's default profile requires names to start with a capital
letter. `reload systemd` (lowercase) matches the legacy handlers but violates the
rule the phase otherwise honors in its task names.

**Fix:** Capitalize: `Reload systemd`.

### IN-03: TLS key has a brief world-readable window between `openssl` and the permission-fix task

**File:** `ansible/roles/jupyter/tasks/main.yml:30-47`

**Issue:** `openssl req` writes `jupyter-key.pem` under the process umask (typically
0022 → 0644) and a *separate* later task tightens it to 0640. Between the two tasks
the private key is group/other-readable. This is a bake-time-only window on a
single-tenant builder and exactly mirrors the existing `desktop` noVNC pattern, so
it is consistent (not a regression), but it remains a real (small) exposure.

**Fix:** Pass `-keyout` to a path created with `umask 077`, or wrap the cert task
to set the key mode in the same step (e.g. `creates`-guarded shell that runs
`umask 077` before `openssl`). Apply to both `jupyter` and `desktop` for parity.

### IN-04: Cert/key idempotency keyed only on the cert; deleting just the key leaves a perms task pointed at a missing file

**File:** `ansible/roles/jupyter/tasks/main.yml:30-47`

**Issue:** The generate task uses `creates: {{ jupyter_cert_dir }}/jupyter-cert.pem`.
If the key (but not the cert) is removed, openssl is skipped yet the subsequent
`file` permission task targets `jupyter-key.pem`, which will error on a missing
path. Edge case, but it is a dead/half-reachable path.

**Fix:** Either guard `creates` on both files or set permissions inside the same
`creates`-guarded generation step.

### IN-05: `mise` activation via `eval "$(mise activate bash)"` in `/etc/profile.d` runs for every interactive bash login system-wide

**File:** `ansible/roles/mise/tasks/main.yml:13-16`

**Issue:** The activation hook is checksum-pinned upstream output (accepted in the
threat model T-08-02), so this is not a security finding. Noting only that
`eval`-ing dynamic command output in a global `profile.d` script is the kind of
pattern the project's review rules call out; the mitigating control (pinned
binary) is documented inline, which is the right call. No change required; recorded
for completeness so it is not re-flagged later.

---

_Reviewed: 2026-06-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
