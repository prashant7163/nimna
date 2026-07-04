# cmd/relay/

The relay's main package — the single binary (`go run ./cmd/relay`;
`go build ./cmd/relay` drops `relay` in the module root, git-ignored;
plain `go build ./...` only compiles, writing nothing). Thin wiring of
`internal/server`: listen address via `-listen` flag or
`NIMNA_RELAY_LISTEN` (default `127.0.0.1:9440`), lifecycle-only slog to
stderr, graceful shutdown on SIGINT/SIGTERM. No logic lives here.

Its import graph contains no protocol crypto — the relay never derives
topics. Checked per session:
`go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto'` must be 0
(CI-asserted from Session 5).
