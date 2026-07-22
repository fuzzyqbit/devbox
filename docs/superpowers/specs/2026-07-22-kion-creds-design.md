# Design: `kion-creds` — Kion AWS STAK fetcher for devbox

**Date:** 2026-07-22
**Status:** Approved (brainstorming session)
**Owner surface:** new Ansible role `kion`, layer-gated via `layers.kion`

## Problem

Operators working on the devbox need short-term AWS access keys (STAKs) for Kion-governed
AWS accounts. Today there is no on-box mechanism: credentials must be fetched elsewhere and
pasted in. The desired flow is: at interactive shell login the operator is prompted for
their Kion password and fresh credentials are written where the AWS CLI/SDKs find them.

## Decisions (from brainstorming Q&A)

| Decision | Choice |
|----------|--------|
| Kion auth method | Username + password (local/LDAP IDMS) |
| Trigger | Interactive shell login hook (`/etc/profile.d/`) + on-demand command |
| Tooling | Raw `curl` against the Kion REST API (no `kion-cli` binary baked) |
| Credential output | `~/.aws/credentials`, profile `default` (configurable), `chmod 600` |
| Project targeting | CLI flag: `kion-creds --id <project-number>` |
| Login-hook project ID | Last-used ID cached in `~/.config/kion-creds/state` |
| Multi account/CAR | Auto-select when exactly one; numbered interactive pick when several; `--car <name>` override |

## Components

### 1. `/usr/local/bin/kion-creds` (bash)

Invocation:

```
kion-creds --id 101          # explicit Kion project
kion-creds                   # reuse cached last-used project ID
kion-creds --id 101 --car developer --user alice
```

Flow:

1. Resolve username: `--user` flag → per-user config → cached state → `$USER`.
2. Prompt for Kion password via `read -s` on the tty. The password is held in memory only —
   never cached, never written to disk, never passed on a command line (curl reads the
   request body from stdin/heredoc so the password never appears in `ps`).
3. `POST ${KION_URL}/api/v3/token` with username/password → bearer access token
   (in-memory only).
4. Resolve project `<id>` → member accounts and the operator's cloud access roles (CARs)
   via the project account / project cloud-access-role endpoints.
   - Exactly one account+CAR pair → proceed silently.
   - Multiple → numbered list on the tty, operator picks. `--car` pre-filters by CAR name.
5. Request a STAK from the temporary-credentials endpoint for the chosen
   account + CAR.
6. Write access key / secret / session token to the target profile in
   `~/.aws/credentials` (create file `0600` if absent, update in place otherwise,
   preserving other profiles).
7. Persist non-secret state to `~/.config/kion-creds/state`: last-used project ID,
   username, STAK expiry timestamp.

### 2. `/etc/profile.d/kion-creds.sh` (login hook)

Runs for interactive shells only (guards: `$-` contains `i`, tty present — protects scp,
rsync, VS Code remote probes, cron).

- Valid creds per cached expiry timestamp (with configurable early-refresh fudge,
  default 5 min) → silent, zero network calls.
- Expired/absent creds and a cached project ID → invoke `kion-creds` (password prompt).
- No cached state (first ever login) → print one-line hint:
  `kion: no cached project — run 'kion-creds --id <project>' to fetch AWS credentials`.
- Failure of any kind (Kion unreachable, three failed password attempts, Ctrl-C) →
  warn and continue. The hook must never block or fail the login shell.

### 3. Config

- `/etc/kion-creds.conf` — baked by the role from Ansible vars:
  - `KION_URL` (required when `layers.kion` is enabled; bake fails if unset)
  - `KION_IDMS_ID` (default `1` — the username/password identity-source id)
  - `KION_AWS_PROFILE` (default `default`)
  - `KION_REFRESH_FUDGE_SECONDS` (default `300`)
  - `KION_STAK_TTL_SECONDS` (default `3600` — stamps the cached expiry; correct
    to the org's real STAK TTL at first use)
- Per-user override: `~/.config/kion-creds/config` (same keys, sourced after
  system conf; `KION_USERNAME` may be set here to pin the Kion username).

### 4. Ansible role `kion`

- New role following the `ai_tools` pattern: gated by `layers.kion` in `layer_config`,
  wired into `ansible/playbook.yml` **before** the `hardening` role (grep-gate invariant:
  `hardening` stays last).
- Tasks: install script + profile.d hook + rendered conf (templates, mode `0755`/`0644`),
  bake-assert (script executable, hook present, conf contains `KION_URL`).

## Error handling

- Every `curl`: explicit `--connect-timeout` / `--max-time`, retry on 5xx (small bounded
  count), no retry on 4xx.
- Distinct user-facing messages and exit codes per failure class: auth failure (bad
  password), network/unreachable, unknown project ID, no CAR access on project, malformed
  API response. API error bodies are quoted verbatim in the failure message.
- Non-tty invocation of `kion-creds` (no way to prompt) → clear error, non-zero exit.

## Security notes

- Password: memory only; `read -s`; request body never on argv; no logging of secrets.
- Bearer token: memory only, discarded on exit.
- STAK on disk only in `~/.aws/credentials` (`0600`) — standard AWS credential handling.
- State file contains no secrets (project ID, username, expiry timestamp).
- `set -euo pipefail`; shellcheck-clean (existing CI hook covers it).

## Testing

- **bats** unit tests with a mocked `curl` (PATH shim returning fixture JSON):
  happy path single CAR, multi-CAR pick, `--car` filter, cached-ID reuse,
  expiry check (fresh vs stale), auth failure, network failure, unknown project,
  non-tty guard, credentials-file update preserves foreign profiles.
- Bake asserts in the role (script present/executable, hook present, conf rendered).
- shellcheck via existing pre-commit/CI.

## Caveats / open items for plan phase

1. **Kion API paths vary by Kion version.** The plan phase must verify exact endpoint
   paths (token, project accounts, project CARs, temporary credentials) against the
   org's Kion instance (`/swagger` on the Kion host). The design assumes the v3 API
   family; adjust to the instance's published spec.
2. **Writing the `default` profile shadows instance-role (IMDS) credentials** for
   CLI/SDK calls on the box. Intended: operator work targets Kion-governed accounts.
   Operators can set `KION_AWS_PROFILE` to a named profile to keep IMDS default.
3. **SAML/IDMS browser-redirect users are out of scope** — username/password IDMS only.
4. `KION_URL` is org-specific and must be supplied as an Ansible var by the operator
   enabling `layers.kion`; it is not a secret but is not committed with a real value.
5. **Shell-startup coverage.** `/etc/profile.d/` fires for *login* shells only;
   code-server / VS Code terminals typically spawn interactive *non-login* shells.
   Plan phase must verify AL2023 startup-file behavior for the SSM shell, DCV
   terminal, and code-server terminal, and hook the interactive-non-login path too
   if needed (e.g. via `/etc/bashrc` drop-in), keeping the idempotent
   already-valid-creds fast path so double-sourcing stays silent.
