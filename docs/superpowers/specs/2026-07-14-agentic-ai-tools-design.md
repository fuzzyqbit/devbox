# Design: `ai-tools` role — bake agentic AI CLIs into the devbox AMI

Date: 2026-07-14
Status: approved (user, this date)

## Purpose

Bake three agentic AI coding CLIs into the AMI so every provisioned devbox has them
on PATH out of the box: Claude Code, OpenAI Codex CLI, opencode.

## Decisions (user-confirmed)

- **Tools:** `@anthropic-ai/claude-code`, `@openai/codex`, `opencode-ai` (all npm).
- **Auth: nothing baked.** No API keys, no provider config on the image (secrets
  invariant, CLAUDE.md §8). Operators authenticate at runtime (`claude` login flow,
  `codex` login, opencode auth); credentials land under `/home/ec2-user` on the
  persistent EBS volume and survive AMI swaps.
- **Install method:** npm global with `--prefix /usr/local`, one pinned version per
  tool (repo version-pin invariant). Rejected alternatives: mise-managed
  (contradicts MISE-03 zero-managed-tools), vendor install scripts (unpinned,
  self-updating, per-user).

## Role layout

```
ansible/roles/ai_tools/
├── defaults/main.yml
└── tasks/main.yml
```

### defaults/main.yml

```yaml
# [VERIFIED: registry.npmjs.org — 2026-07-14]
ai_tools_claude_code_version: "2.1.209"   # @anthropic-ai/claude-code
ai_tools_codex_version: "0.144.4"         # @openai/codex
ai_tools_opencode_version: "1.17.20"      # opencode-ai
ai_tools_npm_prefix: /usr/local
dev_user: ec2-user
dev_home: /home/ec2-user
```

Bump procedure: check the npm registry, update the pin, rebake.

### tasks/main.yml

1. `dnf: name=[nodejs20, nodejs20-npm] state=present` — idempotent; keeps the role
   self-contained (no dependency on the `devtools` layer toggle, which also
   installs nodejs20).
2. Three `npm install -g --prefix /usr/local <pkg>@<version>` commands, each with a
   `creates:` guard on the installed package dir under
   `/usr/local/lib/node_modules/` for idempotence.
3. Bake-asserts (dcv/xrdp pattern — bake-green-but-broken guard): for each of
   `/usr/local/bin/claude`, `/usr/local/bin/codex`, `/usr/local/bin/opencode`,
   stat the binary and run `<bin> --version`; assert both.

## Wiring

- `ansible/playbook.yml`: role entry after `devtools`, before `secrets`, gated
  `when: layers.ai_tools | default(false)`. Well before `hardening` (last-role
  invariant untouched).
- `ansible/layer_config.yml`: `ai_tools: true` with a one-line comment.

## Out of scope

- No IAM/Bedrock wiring, no SSM key plumbing, no MCP server config, no per-user
  dotfiles. Runtime auth only.
- No `./run` surface changes.

## Error handling / failure modes

- npm registry unreachable at bake → task fails, bake aborts (loud, correct).
- Version pin typo → npm install fails, bake aborts.
- Binary present but broken (bad node ABI, truncated install) → `--version`
  bake-assert fails.

## Testing

- `ansible-lint` production profile: 0 failures (CI + local).
- `ansible-playbook --syntax-check` on full import chain.
- CI: same 9-check gate set that passed PR #5; no new grep-gate interactions.
- Real bake (deferred with the other first-bake items): three version asserts run
  in-bake; syft SBOM (PR #5) catalogs the npm globals automatically.

## Delivery

Branch `feat/ai-tools-role` → PR → 9/9 checks → merge (same flow as PR #4/#5).
