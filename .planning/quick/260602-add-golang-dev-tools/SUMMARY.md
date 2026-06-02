---
type: quick
slug: add-golang-dev-tools
created: 2026-06-02
completed: 2026-06-02
status: complete
commit: 88541f0
---

# Summary: Add Go developer tools

Added 11 pinned Go developer tools to the `golang` role.

## What was done

- `ansible/roles/golang/defaults/main.yml` — added a `go_tools` list of `{path, bin}` entries,
  each pinned to an exact `@vX.Y.Z` resolved live from the Go module proxy on 2026-06-02.
- `ansible/roles/golang/tasks/main.yml` — added one loop task that runs
  `{{ go_bin }}/go install {{ item.path }}` as `{{ dev_user }}` with `GOPATH`/`GOBIN`/`GOCACHE`/`HOME`
  set, idempotent via `creates: $GOPATH/bin/{{ item.bin }}`.

## Tools + pinned versions

| tool | pkg@version |
|------|-------------|
| gopls | golang.org/x/tools/gopls@v0.22.0 |
| goimports | golang.org/x/tools/cmd/goimports@v0.45.0 |
| dlv | github.com/go-delve/delve/cmd/dlv@v1.26.3 |
| golangci-lint | github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 |
| staticcheck | honnef.co/go/tools/cmd/staticcheck@v0.7.0 |
| govulncheck | golang.org/x/vuln/cmd/govulncheck@v1.3.0 |
| gofumpt | mvdan.cc/gofumpt@v0.10.0 |
| gotestsum | gotest.tools/gotestsum@v1.13.0 |
| gotests | github.com/cweill/gotests/gotests@v1.9.0 |
| mockgen | go.uber.org/mock/mockgen@v0.6.0 |
| air | github.com/air-verse/air@v1.65.3 |

## Verification

- Both files parse (`yaml.safe_load`); `go_tools` has 11 entries.
- No invariant impact: `golang` role position unchanged, `hardening` stays last.
- **Runtime (deferred to a bake):** `go install` reaching the module proxy + each binary
  landing in `~/go/bin` can only be confirmed on `./run build`. golangci-lint's project
  discourages `go install` (binary version metadata reports "unknown"); functional but
  noted — switch to the release binary if version reporting matters.

## Notes / follow-ups

- golangci-lint installed via `go install` (uniform with the others). If `golangci-lint version`
  reporting matters, swap to the release tarball (like devtools' shellcheck/ripgrep pattern).
- Commit: `88541f0`.
