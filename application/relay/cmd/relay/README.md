# cmd/relay/

The relay's main package — the single binary (`go run ./cmd/relay`;
`go build ./cmd/relay` drops `relay` in the module root, git-ignored;
plain `go build ./...` only compiles, writing nothing). Thin wiring of
`internal/server`: flags/env for every spec §4 limit (each flag's default
seeds from its `NIMNA_RELAY_*` env var; flag wins; spec numbers are
spec-verbatim defaults — the full table lives in the
[relay README](../../README.md)), the ops metrics listener
(`-metrics-listen`, default `127.0.0.1:9441`, empty disables), graceful
shutdown on SIGINT/SIGTERM. No logic lives here.

Operational logging (note §19): lifecycle, a fixed-shape boot config
summary (limit values and listener addresses — never credentials),
scrubbed panic lines, push transport status — slog to stderr, Info level.
`-debug-trace` / `NIMNA_RELAY_DEBUG_TRACE` raises the level to Debug and
adds per-connection tracing keyed by opaque sequence numbers —
**never in production**.

Push configuration (all default-empty; nothing set = push-less mode):
`-push-sink` / `NIMNA_RELAY_PUSH_SINK` selects the TEST-ONLY HTTP sink
that stands in for the push platforms during done-checks. The real
APNs/FCM credential slots are named now and consumed in Session 6:
`NIMNA_RELAY_APNS_KEY_FILE`, `NIMNA_RELAY_APNS_KEY_ID`,
`NIMNA_RELAY_APNS_TEAM_ID`, `NIMNA_RELAY_APNS_TOPIC`,
`NIMNA_RELAY_FCM_SA_FILE`. Credentials are deployment configuration —
env / mounted file paths only, never repository content (spec §4).

`logscrub_test.go` is the CI log-scrub assertion (note §20): it builds
THIS binary, runs it in production config with windows shortened via
config, drives identifier-bearing traffic through both planes and every
limit (two phases — the day cap needs its own config), captures all
process output plus a metrics scrape, and asserts zero occurrences of
every known identifier in hex/base64/raw form, zero client addresses,
and no identifier-shaped strings. It runs under the plain
`go test ./...` CI step.

Its import graph contains no protocol crypto — the relay never derives
topics. CI-asserted (anchored form):
`go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto$\|^golang.org/x/crypto/'`
must be 0.
