# nimna — relay

The Nimna relay: a **stateless** WebSocket router that bridges exactly two
live device connections and never stores anything. It routes ciphertext
between two phones; it cannot read it, and it keeps nothing.

**Status:** Session 6 — deploy & open-source release readiness. On top of
the S3 rendezvous plane, S4 channel/knock/push plane, and S5 limits &
observability, the relay now serves TLS 1.3 on the public listener (with
in-process certificate hot-reload), answers `GET /healthz` on the ops
listener, ships real APNs/FCM push transports (stdlib-only, mock-verified;
live-platform verification is a later session), and carries its complete
deployment kit (`deploy/`) and public-release scaffolding (LICENSE,
CONTRIBUTING, vendored spec and test vectors, its own CI workflow) inside
this tree.

## The zero-storage claim — and how to audit it

The relay's **complete at-rest inventory** is: routing tables in memory,
the TLS certificate pair, and push credentials supplied as deployment
configuration. Nothing about any user is at rest, ever (spec §4). Don't
take the claim — check it:

- **Spec §4's inventory** — `docs/nimna-protocol-spec-v0.2.md` (vendored
  byte-identical in this tree) names every table the relay may hold; all
  are in-memory, die with their connection or window, and reset on
  restart. `grep` the tree: there is no database driver, no file write on
  any request path, no queue.
- **Unloggable identifiers** — `internal/ident` wraps every identifier
  class (topics, CRIDs, remote addresses, device tokens) in types whose
  every serialization surface (`String`, `Format`, `MarshalText/JSON`,
  `slog`) redacts to a fixed tag. Raw bytes exit only via the greppable
  `WireBytes()`; audit its call sites — they are the wire encoder and the
  push platform call, nothing else.
- **The real-binary log-scrub test** — `cmd/relay/logscrub_test.go` (and
  its TLS twin `logscrub_tls_test.go`) builds this repo's actual binary,
  runs it in production config, drives known-byte identifiers through
  every flow and every limit — over `ws://` and `wss://`, including
  deliberately failed TLS handshakes — and asserts zero occurrences of
  any identifier in any encoding across all process output. It runs in
  plain `go test ./...`, i.e. in CI on every change.
- **The anchored x/crypto CI step** — the relay never derives topics, so
  protocol crypto must never enter its import graph:
  `go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto$\|^golang.org/x/crypto/'`
  must print 0. It is a named, visible step in `.github/workflows/ci.yml`.
  (The *module* carries `golang.org/x/crypto` solely for
  `cmd/testclient`'s Argon2id derivation — a hands-on audit tool; the
  invariant is `cmd/relay`'s import graph.)
- **Silence-doctrine tests** — the relay never explains itself on the
  wire: state-dependent rejections are byte-identical silence, structural
  malformation is a bare close, and TLS handshake failures are
  covering-tested to be byte-identical against an empty relay and a
  loaded one (`internal/server/tls_test.go`, `internal/server/*_test.go`).
- **Push content-freeness** — `push.Sender`'s call surface has no content
  parameter; the platform bodies are compile-time constants,
  byte-identical across all pushes except addressing
  (`internal/push`, mock-platform tests verify the exact bytes and the
  ES256/RS256 JWTs against runtime-generated public keys).
- **The deployment story** — `deploy/` ships the hardened systemd unit
  (`ProtectSystem=strict` with **no writable paths**: zero-at-rest as a
  sandbox property), a reproducible-best-effort build script, and the
  runbook. What runs in production is buildable and checkable from this
  tree.

## Quickstart

Requires Go (version pinned in `go.mod`). The module path
`nimna.app/relay` is a vanity identity; `go install` support (go-import
meta tags on nimna.app) arrives with the public launch — until then,
clone and build (no meta tags needed):

```sh
go build ./...             # compile everything
go test ./...              # full suite incl. the log-scrub assertion
go run ./cmd/relay         # plain listener on 127.0.0.1:9440 (dev mode)
```

With TLS (production shape — any PEM pair; the deploy kit wires certbot):

```sh
go run ./cmd/relay -listen :8443 -tls-cert fullchain.pem -tls-key privkey.pem
```

TLS is 1.3-only, `http/1.1`-only (the port speaks
WebSocket-upgrade-or-nothing), and the certificate pair hot-reloads
in-process when the cert file's mtime moves (~60 s) — renewal never
restarts the relay. Plain mode (no TLS flags) is first-class for dev and
tunnel/LB-terminated deployments; one TLS flag without the other refuses
to boot.

## Configuration reference (flag · env `NIMNA_RELAY_*` · default)

Every knob is a flag whose default seeds from the matching env var; the
flag wins. Spec-named numbers are spec-verbatim defaults.

| Flag | Env | Default |
|---|---|---|
| `-listen` | `LISTEN` | `127.0.0.1:9440` |
| `-tls-cert` | `TLS_CERT` | empty (with `-tls-key`: both or neither) |
| `-tls-key` | `TLS_KEY` | empty |
| `-metrics-listen` | `METRICS_LISTEN` | `127.0.0.1:9441` — `/metrics` + `/healthz`; empty disables |
| `-apns-key-file` | `APNS_KEY_FILE` | empty (.p8 path; the four APNs slots are all-or-nothing) |
| `-apns-key-id` | `APNS_KEY_ID` | empty |
| `-apns-team-id` | `APNS_TEAM_ID` | empty |
| `-apns-topic` | `APNS_TOPIC` | empty (app bundle id) |
| `-fcm-sa-file` | `FCM_SA_FILE` | empty (service-account JSON path) |
| `-push-sink` | `PUSH_SINK` | empty — test-only sink; boot-fatal beside real credentials |
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
| `-version` | — | print the stamped version and exit |

Config validity is loud: half a TLS pair, a partial APNs quad, an
unparseable credential file, or `-push-sink` beside a real credential are
all boot-fatal. The per-CRID rate-table hard cap (65,536 entries) is a
pinned constant, not a knob.

### Push token bytes (client contract)

The KNOCK frame's token field carries the **platform-native token
verbatim** (spec §5.4's opaque bytes): for APNs, the raw 32-byte binary
device token — the relay hex-encodes it into the request path; for FCM,
the registration token's ASCII bytes — inserted as the one
`message.token` JSON string. The push bodies are constants; addressing is
the URL path (APNs) or that single field (FCM), and nothing else ever
varies.

## Invariants (non-negotiable)

- **Zero storage:** the complete at-rest inventory is routing tables in
  memory, TLS certificates, and push credentials as deployment config
  (spec §4). Rate/push counters are spec §4's own named transient class:
  in-memory, user-anonymous, reset on restart. Any persistence beyond
  that is a product-owner decision by definition — i.e., it does not
  happen in a code change.
- **Push credentials are config slots** (env / mounted files), never
  repository content; `.gitignore` guards every secret file shape.
- **Metrics, not logs:** the production instrument is aggregate in-memory
  counters with no CRIDs/IPs/device-tokens/code-hashes in any label —
  label values are compile-time enumerations, so no identifier can become
  a label by construction. Identifiers are unloggable wrapper types
  (`internal/ident`), CI-asserted by the real-binary log-scrub test.
  Operational logging is lifecycle-only: started/stopped/config, scrubbed
  panic lines (site + panic type only), push transport status (platform +
  HTTP status only), TLS events (config paths and cert expiry only —
  per-handshake errors are never logged). `-debug-trace` (never in
  production) adds per-connection tracing keyed by opaque sequence
  numbers.
- **Silence doctrine** (scoped to the Nimna layer, where it is absolute):
  relay code never sends a close frame carrying reason text or a
  Nimna-state-dependent status. Malformed Nimna frames close the
  connection with nothing said; valid-but-unhandled frames and every
  state-dependent rejection are silently dropped. Every rate-limit
  outcome is byte-identical silence, a bare close, or a zero-byte refusal
  at the TCP accept boundary. The only transport-layer signals with
  content are the WebSocket library's RFC 6455 compliance closes and
  stdlib TLS alerts — both a fixed function of the sender's own malformed
  transport bytes, state-independent and identifier-free, test-asserted.
- **License: AGPL-3.0** (`LICENSE`) — the Signal-server/SimpleX
  precedent: anyone operating a modified relay as a service must publish
  their modifications, protecting users' expectations of anything called
  a Nimna relay. The protocol spec is published alongside (vendored in
  `docs/`); the app is separate and closed.

Copyright (C) 2026 The Nimna Authors. This program is free software:
you can redistribute it and/or modify it under the terms of the GNU
Affero General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any
later version. See `LICENSE` for the full text; it comes with ABSOLUTELY
NO WARRANTY.

Contributions: see `CONTRIBUTING.md` (small fixes welcome; DCO sign-off;
protocol behavior is spec-governed and not changeable by PR).

## Layout

- `cmd/relay/` — the relay binary: thin wiring, flags/env, signals; home
  of the real-binary log-scrub assertions
- `cmd/testclient/` — CLI audit/test client (real §3.1.2 code→topic
  derivation; `ws://` and `wss://` with `-tls-ca`; the module's only
  x/crypto consumer)
- `cmd/soak/` — soak & abuse driver: churn, full flows, limit probes,
  metrics sampling, flat-memory verdict
- `internal/wire/` — 18-byte outer frame + §5.4 frame-type enum + KNOCK
  payload parse/build (vendored conformance vectors in `testdata/`)
- `internal/ident/` — unloggable identifier wrapper types; per-IP keys
  canonicalized here (IPv4 exact, IPv6 /64)
- `internal/rendezvous/` — topic registry + bridging state machine
- `internal/channel/` — CRID registry: registrations, pending knocks,
  knock → accept → bridged sessions
- `internal/push/` — content-free push: bounded dispatcher, platform
  router, real APNs (HTTP/2 + ES256 JWT) and FCM v1 (OAuth2 RS256 grant)
  transports, config-gated test sink
- `internal/limits/` — token bucket, rendezvous window, per-CRID rate
  table, limit listener (per-IP cap + liveness)
- `internal/metrics/` — identifier-free counters + hand-rolled Prometheus
  text exposition
- `internal/server/` — accept loop, TLS wiring + cert reloader, frame
  router, limit wiring, ops listener (`/metrics`, `/healthz`), panic scrub
- `deploy/` — systemd unit, env example, build script, certbot hook,
  runbook
- `docs/` — vendored byte-identical protocol spec
- `go.mod` — module `nimna.app/relay` (vanity path; nothing imports the
  relay, so it need not resolve to build)

## Ops surface

`GET http://127.0.0.1:9441/healthz` → `ok nimna-relay <version>` (200 is
"alive and serving" — a stateless relay has no deeper health; the
listener is operator-local only). `GET .../metrics` → Prometheus text
0.0.4, prefix `nimna_relay_`, all label values compile-time enumerations —
see `internal/metrics/README.md` for the pinned inventory. Everything
else on that port 404s. Remote scraping is the operator's tunnel/firewall
decision — never expose the port.

## Demos

### Rendezvous (two clients through the live relay)

```sh
go run ./cmd/relay                                          # terminal 1
go run ./cmd/testclient --role create --code 7Q2-M4K-9XV    # terminal 2
go run ./cmd/testclient --role join   --code 7Q2-M4K-9XV    # terminal 3
```

Both clients print the derivation, the bridge, and the verbatim PAIR_DATA
exchange, then exit 0. The relay logs nothing but its own lifecycle.
Against a TLS relay, add `--relay wss://host:port` (and `-tls-ca ca.pem`
for a local/QA CA — there is deliberately no verify-off switch).

### Knock/session (channel plane)

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

### Soak & abuse

See `cmd/soak/README.md`. Accelerated example:

```sh
go run ./cmd/relay -push-sink http://127.0.0.1:9470 \
    -push-day-window 90s -push-hour-window 60s              # terminal 1
go run ./cmd/soak -duration 10m -drain 60s -abuse \
    -sink-listen 127.0.0.1:9470                             # terminal 2
```

## Dependencies

Stdlib-first; every addition justified and pinned. Session 6 adds
**zero** new dependencies: TLS is `crypto/tls`, the push JWTs are fixed
encoding over `crypto/ecdsa`/`crypto/rsa` signatures (composition, not
hand-rolled crypto — test-verified against the public keys), and ACME is
certbot's job, not the binary's. Current:

- `github.com/coder/websocket` v1.8.15 — WebSocket transport (zero
  transitive deps, ISC, context-first API on `net/http`)
- `golang.org/x/crypto` v0.53.0 — **test client only** (`argon2`);
  `cmd/relay`'s import graph stays x/crypto-free, CI-asserted with the
  anchored check
  `go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto$\|^golang.org/x/crypto/'` → 0
