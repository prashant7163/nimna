# cmd/relay/

The relay's main package — the single binary (`go run ./cmd/relay`,
`go build ./...` drops `relay` two levels up, git-ignored). Session 1
scaffold: prints a version line. Server wiring lands here in Session 3;
the logic it wires will live in `internal/` packages.
