# Phase 9: Jupyter Operator Surface + Docs - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning
**Source:** Synthesized from the Phase 8 loopback re-scope (ROADMAP Phase 9 amendment)

<domain>
## Phase Boundary

Phase 8 shipped JupyterLab as a **loopback-only, on-demand** capability: an isolated
`/opt/jupyter` venv launched via `./run jupyter` (`jupyter lab --ip=127.0.0.1`), reached
over an SSM port-forward. No systemd service, no TLS, no password (SSM/IAM is the auth
boundary).

This phase is the **operator-surface + documentation polish** for that capability. It is
small and code-light. It does NOT add infrastructure.

**In scope:**
- Surface JupyterLab in `./run status` output (a hint that it is available on demand).
- Document the `./run jupyter` + `:8888` SSM port-forward access flow in
  `docs/DEVELOPER-LIFECYCLE.md` (and align CLAUDE.md if useful — note CLAUDE.md is
  gitignored/untracked in this repo, so docs/ is the canonical operator reference).

**Out of scope (superseded by the Phase 8 loopback pivot):**
- Any `aws_security_group.devbox` ingress rule for `:8888` (JUP-05 — dropped; nothing is
  network-exposed).
- Surfacing a Jupyter password via `./run secrets-show` (JUP-06 — dropped; no password exists).
- A dedicated `./run jupyter-port-forward` command (operator decision in Phase 8: reuse the
  manual SSM port-forward; `devbox-port-forward` stays code-server-only).
</domain>

<decisions>
## Implementation Decisions (LOCKED)

### Access model — preserve Phase 8 loopback posture
- JupyterLab binds `127.0.0.1:8888` only; reached via a manual SSM port-forward
  (`AWS-StartPortForwardingSession`, `portNumber=8888`). No SG rule, no password, no TLS.
- The access command is `./run jupyter` (launches on demand) + a second-shell port-forward.

### `./run status` surfacing
- Add a JupyterLab line to the **Connection Info** block in `scripts/devbox-status.sh`
  (alongside the existing code-server `:8080` / noVNC `:6080` lines, ~lines 50–58).
- Wording must make clear it is **on-demand + loopback** (e.g. "JupyterLab (on-demand):
  ./run jupyter, then forward :8888"), NOT a always-on URL like the code-server line.
  Do NOT imply a network-reachable `https://<ip>:8888` — it is loopback-only.

### Documentation
- Add a JupyterLab subsection to `docs/DEVELOPER-LIFECYCLE.md` after the
  "Browser IDE (code-server on :8080)" section (~line 80), documenting:
  `./run jupyter` → note the printed token URL → in a second shell run the `:8888`
  SSM port-forward → open `http://127.0.0.1:8888/lab?token=...`.
- Add a row to the quick-reference table (~line 133): "JupyterLab → `./run jupyter`".
- Explicitly note: no password (loopback + SSM/IAM is the auth boundary).

### Claude's Discretion
- Exact wording of the status line and doc prose.
- Whether to also touch README (optional; DEVELOPER-LIFECYCLE.md is the canonical surface).
- Whether plans are split or a single plan (the phase is small — a single plan is acceptable).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 8 outcome (what this phase documents/surfaces)
- `.planning/phases/08-jupyter-mise-ami-layer/08-02-SUMMARY.md` — jupyter role (loopback venv); read the Amendment section
- `.planning/phases/08-jupyter-mise-ami-layer/08-03-SUMMARY.md` — secrets revert; read the Amendment section
- `scripts/devbox-jupyter.sh` — the `./run jupyter` launcher (loopback + the port-forward guidance it already prints)
- `run` — the `cmd_jupyter` dispatch + help entry (lines ~372, ~474, ~521)

### Files this phase edits
- `scripts/devbox-status.sh` — Connection Info block (the status surfacing)
- `docs/DEVELOPER-LIFECYCLE.md` — operator lifecycle doc (the access-flow documentation + quick-ref table)

### Requirements
- `.planning/REQUIREMENTS.md` — JUP-07 (amended); JUP-05/JUP-06 superseded
- `.planning/ROADMAP.md` — Phase 9 goal + success criteria + re-scope note
</canonical_refs>
