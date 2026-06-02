---
type: quick
slug: add-golang-dev-tools
created: 2026-06-02
status: complete
---

# Quick Task: Add Go developer tools

Install a pinned set of Go developer CLI tools into the baked AMI, in the existing
`golang` role (they require Go + GOPATH, which that role sets up).

## Approach

`go install pkg@<pinned-version>` as the dev user into `$GOPATH/bin` (already on PATH via
the role's `.bashrc` block). Versions pinned from the Go module proxy (2026-06-02), no
floating refs — honors the project version-pinning invariant. Idempotent via `creates:`.

## Tools (11)

gopls, goimports, dlv (delve), golangci-lint (v2), staticcheck, govulncheck, gofumpt,
gotestsum, gotests, mockgen, air.

## Files

- `ansible/roles/golang/defaults/main.yml` — `go_tools` list (path + bin per tool)
- `ansible/roles/golang/tasks/main.yml` — loop task: `go install` per tool, dev-user, pinned
