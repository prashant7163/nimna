# nimna — relay (Go)

The Nimna relay: a **stateless** WebSocket router that bridges exactly two
live device connections and never stores anything. Implements spec §3–§4 of
[`docs/nimna-protocol-spec-v0.2.md`](../../docs/nimna-protocol-spec-v0.2.md);
§5 data-plane traffic is opaque payload — routed verbatim, never parsed.

**Status:** Session 5 — hardening, rate limits & observability. On top of
the Session 3 rendezvous plane and Session 4 channel plane, the relay now
enforces every spec §4 limit as config with spec-verbatim defaults
(per-IP connection cap with zero-byte accept refusal, read-paced
per-connection frame rate, max frame size, per-IP rendezvous throttle,
per-conn registration caps, knock collapse 1/10 s/CRID, push caps
1/60 s + 6/hr + 20/day/CRID), reaps dead connections via a liveness
listener (90 s idle deadline; WS pings count structurally), serves
identifier-free Prometheus metrics on a separate ops listener, recovers
and scrubs panics (site + type only), and ships `cmd/soak` for load/abuse
verification. CI now asserts the log-scrub property against the real
binary and the x/crypto-free relay import graph. TLS, real APNs/FCM
transports, `/healthz`, deploy, and the public AGPL-3.0 release are
Session 6.

## Invariants (non-negotiable)

- **Zero storage:** the complete at-rest inventory is routing tables in
  memory, TLS certificates, and push credentials as deployment config
  (spec §4). The S5 rate/push counters are spec §4's own named transient
  class: in-memory, user-anonymous, reset on restart. Any persistence
  beyond that is a USER decision by definition.
- **Push credentials are config slots** (env / mounted files), never
  repository content.
- **Metrics, not logs:** production instrument is aggregate in-memory
  counters with no CRIDs/IPs/device-tokens/code-hashes in any label —
  label values are compile-time enumerations, so no identifier can become
  a label by construction. Identifiers are unloggable wrapper types
  (`internal/ident`) that redact on every serialization surface,
  CI-asserted by a real-binary log-scrub test. Operational logging is
  lifecycle-only: started/stopped/config, scrubbed panic lines (site +
  panic type only), push transport status (platform + HTTP status only).
  `-debug-trace` (never in production) adds per-connection tracing keyed
  by opaque sequence numbers.
- **Silence doctrine** (scoped to the Nimna layer, where it is absolute —
  architecture note §5.1, §16): relay code never sends a close frame
  carrying reason text or a Nimna-state-dependent status. Malformed Nimna
  frames close the connection with nothing said; valid-but-unhandled
  frames and every state-dependent rejection are silently dropped. Every
  rate-limit outcome is byte-identical silence, a bare close, or a
  zero-byte refusal at the TCP accept boundary; limits keyed on shared
  per-CRID state are indistinguishable-silent so one end can never probe
  the other's activity. The only close frames with text are the WebSocket
  library's own RFC 6455 transport-compliance closes (1002), a fixed
  function of the sender's malformed transport bytes — state-independent
  and identifier-free, test-asserted.
- License will be **AGPL-3.0** (LICENSE lands with the public-release
  readiness work in Session 6).

## Layout

- `cmd/relay/` — the relay binary: thin wiring, flags/env, signals
- `cmd/testclient/` — CLI test client for the S3/S4 done-checks (real
  §3.1.2 code→topic derivation; the only x/crypto consumer)
- `cmd/soak/` — soak & abuse driver: churn, full flows, limit probes,
  metrics sampling, flat-memory verdict (Session 5 done-check tool)
- `internal/wire/` — 18-byte outer frame + §5.4 frame-type enum + KNOCK
  payload parse/build
- `internal/ident/` — unloggable identifier wrapper types; per-IP keys
  canonicalized here (IPv4 exact, IPv6 /64)
- `internal/rendezvous/` — topic registry + bridging state machine
- `internal/channel/` — CRID registry: registrations, pending knocks,
  knock → accept → bridged sessions
- `internal/push/` — stateless push forwarding (content-free by
  construction; config-gated test sink; real transports in S6)
- `internal/limits/` — token bucket, rendezvous window, per-CRID rate
  table, limit listener (per-IP cap + liveness)
- `internal/metrics/` — identifier-free counters + hand-rolled Prometheus
  text exposition
- `internal/server/` — accept loop, connection lifecycle, frame router,
  limit wiring, ops listener, panic scrub
- `go.mod` — module `nimna.app/relay` (vanity path; nothing imports the
  relay, so it need not resolve)

## Commands

```sh
go build ./...             # compile everything (writes no binaries)
go test ./...              # run tests (-short skips production-cost Argon2id;
                           #   includes the real-binary log-scrub assertion)
go vet ./...               # static checks
gofmt -l .                 # formatting (must print nothing)
go run ./cmd/relay         # run the relay (default 127.0.0.1:9440)
go build ./cmd/relay       # drop the `relay` binary here (git-ignored);
go build ./cmd/testclient  #   same for `testclient` and ./cmd/soak
```

### Relay configuration (flag · env `NIMNA_RELAY_*` · default)

Every limit is a flag whose default seeds from the matching env var; the
flag wins. Spec-named numbers are spec-verbatim defaults.

| Flag | Env | Default |
|---|---|---|
| `-listen` | `LISTEN` | `127.0.0.1:9440` |
| `-metrics-listen` | `METRICS_LISTEN` | `127.0.0.1:9441` (empty disables) |
| `-push-sink` | `PUSH_SINK` | empty (push-less; test-only sink) |
| `-max-conns-per-ip` | `MAX_CONNS_PER_IP` | 64 (IPv4 exact, IPv6 /64) |
| `-frame-rate` / `-frame-burst` | `FRAME_RATE` / `FRAME_BURST` | 50 /s · 100 |
| `-max-frame` | `MAX_FRAME` | 131072 (spec 128 KiB; raising past the wire constant is a protocol change, not config) |
| `-rendezvous-per-min` | `RENDEZVOUS_PER_MIN` | 6 |
| `-max-regs-per-conn` | `MAX_REGS_PER_CONN` | 256 per plane |
| `-knock-interval` | `KNOCK_INTERVAL` | 10s (spec) |
| `-push-min-interval` | `PUSH_MIN_INTERVAL` | 60s (spec) |
| `-push-per-hour` / `-push-per-day` | `PUSH_PER_HOUR` / `PUSH_PER_DAY` | 6 · 20 (spec) |
| `-push-hour-window` / `-push-day-window` | `PUSH_HOUR_WINDOW` / `PUSH_DAY_WINDOW` | 1h · 24h (test/soak acceleration knobs; defaults stay spec) |
| `-idle-timeout` | `IDLE_TIMEOUT` | 90s (three missed 30 s client pings) |
| `-debug-trace` | `DEBUG_TRACE` | off — **never in production** |

The per-CRID rate-table hard cap (65,536 entries) is a pinned constant,
not a knob.

### Metrics

`GET http://127.0.0.1:9441/metrics` (Prometheus text 0.0.4; everything
else on that port 404s). Prefix `nimna_relay_`; all label values are
compile-time enumerations — see `internal/metrics/README.md` for the
pinned inventory. Operator-local by default: remote scraping is the
operator's tunnel/firewall decision.

### Rendezvous demo (two clients through the live relay)

```sh
go run ./cmd/relay                                          # terminal 1
go run ./cmd/testclient --role create --code 7Q2-M4K-9XV    # terminal 2
go run ./cmd/testclient --role join   --code 7Q2-M4K-9XV    # terminal 3
```

Both clients print the derivation, the bridge, and the verbatim PAIR_DATA
exchange, then exit 0. The relay logs nothing but its own lifecycle.

### Knock/session demo (channel plane)

```sh
go run ./cmd/relay                                          # terminal 1
go run ./cmd/testclient --role answer --code 7Q2-M4K-9XV    # terminal 2
go run ./cmd/testclient --role knock  --code 7Q2-M4K-9XV    # terminal 3
```

The knocker registers a CRID (test-only derivation from the code — NOT
§3.1.5; `--crid <32 hex>` overrides), knocks, chats over `SESSION_DATA`
after `SESSION_BRIDGED`, checks the keepalive pong, and tears down; the
answerer accepts (a knock pending at the relay reaches it even if it
connects up to 60 s late) and exits on the relay `TEARDOWN`. Add
`--token <hex> --platform apns|fcm` to the knocker and run the relay with
`-push-sink <url>` to watch the offline-knock push path: the sink
receives exactly one content-free POST per eligible knock, and zero when
the peer is online.

### Soak & abuse (Session 5 done-check)

See `cmd/soak/README.md`. Accelerated example:

```sh
go run ./cmd/relay -push-sink http://127.0.0.1:9470 \
    -push-day-window 90s -push-hour-window 60s              # terminal 1
go run ./cmd/soak -duration 10m -drain 60s -abuse \
    -sink-listen 127.0.0.1:9470                             # terminal 2
```

## Dependencies

Stdlib-first; every addition justified, pinned, and architect-signed-off
(crypto/network deps always). Session 5 adds **zero** new dependencies
(note §23): limits, metrics, liveness, and soak are stdlib plus the
existing pin. Current, per the S3 sign-off:

- `github.com/coder/websocket` v1.8.15 — WebSocket transport (zero
  transitive deps, ISC, context-first API on `net/http`)
- `golang.org/x/crypto` v0.53.0 — **test client only** (`argon2`);
  `cmd/relay`'s import graph stays x/crypto-free, CI-asserted with the
  anchored check
  `go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto$\|^golang.org/x/crypto/'` → 0
