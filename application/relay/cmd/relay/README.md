# cmd/relay/

The relay's main package — the single binary (`go run ./cmd/relay`;
`go build ./cmd/relay` drops `relay` in the module root, git-ignored;
plain `go build ./...` only compiles, writing nothing). Thin wiring of
`internal/server`: listen address via `-listen` flag or
`NIMNA_RELAY_LISTEN` (default `127.0.0.1:9440`), lifecycle-only slog to
stderr, graceful shutdown on SIGINT/SIGTERM. No logic lives here.

Push configuration (all default-empty; nothing set = push-less mode):
`-push-sink` / `NIMNA_RELAY_PUSH_SINK` selects the TEST-ONLY HTTP sink
that stands in for the push platforms during done-checks. The real
APNs/FCM credential slots are named now and consumed in Session 6:
`NIMNA_RELAY_APNS_KEY_FILE`, `NIMNA_RELAY_APNS_KEY_ID`,
`NIMNA_RELAY_APNS_TEAM_ID`, `NIMNA_RELAY_APNS_TOPIC`,
`NIMNA_RELAY_FCM_SA_FILE`. Credentials are deployment configuration —
env / mounted file paths only, never repository content (spec §4).

Its import graph contains no protocol crypto — the relay never derives
topics. Checked per session:
`go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto'` must be 0
(CI-asserted from Session 5).
