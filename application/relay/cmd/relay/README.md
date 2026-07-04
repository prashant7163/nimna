# cmd/relay/

The relay's main package — the single binary (`go run ./cmd/relay`;
`go build ./cmd/relay` drops `relay` in the module root, git-ignored;
plain `go build ./...` only compiles, writing nothing). Thin wiring of
`internal/server`: flags/env for every spec §4 limit (each flag's default
seeds from its `NIMNA_RELAY_*` env var; flag wins; spec numbers are
spec-verbatim defaults — the full table lives in the
[relay README](../../README.md)), TLS and push-credential config with
boot-fatal validity rules (below), the ops listener (`-metrics-listen`,
default `127.0.0.1:9441`, `GET /metrics` + `GET /healthz`, empty
disables), graceful shutdown on SIGINT/SIGTERM. No logic lives here.

Operational logging (note §19): lifecycle, a fixed-shape boot config
summary (limit values and listener addresses — never credentials),
scrubbed panic lines, push transport status — slog to stderr, Info level.
`-debug-trace` / `NIMNA_RELAY_DEBUG_TRACE` raises the level to Debug and
adds per-connection tracing keyed by opaque sequence numbers —
**never in production**.

TLS (note §§24–25): `-tls-cert`/`-tls-key` (env `NIMNA_RELAY_TLS_CERT`/
`TLS_KEY`) take the PEM chain/key paths, both-or-neither — one alone is
boot-fatal; both empty = the first-class plain listener. TLS 1.3 floor,
`http/1.1`-only ALPN, and an in-process mtime-checked certificate
hot-reload (renewal never restarts the relay). The boot summary logs
`tls=on|off` and the configured paths — never file contents.

Push configuration (all default-empty; nothing set = push-less mode):
`-push-sink` / `NIMNA_RELAY_PUSH_SINK` selects the TEST-ONLY HTTP sink
that stands in for the push platforms during done-checks — boot-fatal
combined with any real credential. The real APNs/FCM transports consume
the pinned slots (each also a flag): `NIMNA_RELAY_APNS_KEY_FILE`,
`NIMNA_RELAY_APNS_KEY_ID`, `NIMNA_RELAY_APNS_TEAM_ID`,
`NIMNA_RELAY_APNS_TOPIC` (all four together or none — a partial quad is
boot-fatal, naming the missing slot names only, never values) and
`NIMNA_RELAY_FCM_SA_FILE`; credential files must parse at boot.
Credentials are deployment configuration — env / mounted file paths
only, never repository content (spec §4); `deploy/relay.env.example`
ships every slot empty. The boot summary's `push_mode` is the fixed
enumeration `push-less|sink|apns|fcm|apns+fcm`.

The version (`var version`, default `dev`) is stamped by
`deploy/build.sh` via `-ldflags "-X main.version=…"` and surfaces in the
boot log, `-version`, and the `/healthz` body.

`logscrub_test.go` is the CI log-scrub assertion (note §20): it builds
THIS binary, runs it in production config with windows shortened via
config, drives identifier-bearing traffic through both planes and every
limit (two phases — the day cap needs its own config), captures all
process output plus a metrics scrape, and asserts zero occurrences of
every known identifier in hex/base64/raw form, zero client addresses,
and no identifier-shaped strings. `logscrub_tls_test.go` extends it per
note §25: the binary booted WITH TLS (runtime-generated certificate
under boring temp names — the cert paths are logged by design and must
carry no identifier-shaped bytes), real flows over `wss://`, and
deliberately failed handshakes (plain HTTP at the TLS port, a 1.2-only
ClientHello, an untrusting client), asserting that handshake errors —
which embed remote addresses — never reach the output. Both run under
the plain `go test ./...` CI step.

Its import graph contains no protocol crypto — the relay never derives
topics. CI-asserted (anchored form):
`go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto$\|^golang.org/x/crypto/'`
must be 0.
