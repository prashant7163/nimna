# nimna — relay (Go)

The Nimna relay: a **stateless** WebSocket router that bridges exactly two
live device connections and never stores anything. Implements spec §3–§4 of
[`docs/nimna-protocol-spec-v0.2.md`](../../docs/nimna-protocol-spec-v0.2.md);
§5 data-plane traffic is opaque payload — routed verbatim, never parsed.

**Status:** Session 4 — channels, knock, sessions, push forwarding. On
top of the Session 3 rendezvous plane (silent topic registration,
`TOPIC_BRIDGED`, verbatim `PAIR_DATA`, 24 h cap, no tombstones), the relay
now serves the full channel plane: `REGISTER_CRID`, `KNOCK` (pending held
exactly 60 s, silently expiring; delivered live to online registrants or
on-register to late ones), first-`ACCEPT`-wins bridging
(`SESSION_BRIDGED` to both), verbatim `SESSION_DATA`, `TEARDOWN` both
ways (disconnection is an implicit TEARDOWN), and stateless push
forwarding — peer offline + token = exactly one content-free platform
call, token discarded, never stored. Real APNs/FCM transports, rate
limits, and observability are Sessions 5–6; deploy and the public
AGPL-3.0 release are Session 6.

## Invariants (non-negotiable)

- **Zero storage:** the complete at-rest inventory is routing tables in
  memory, TLS certificates, and push credentials as deployment config
  (spec §4). Any persistence beyond that is a USER decision by definition.
- **Push credentials are config slots** (env / mounted files), never
  repository content.
- **Metrics, not logs:** production instrument is aggregate in-memory
  counters with no CRIDs/IPs/device-tokens/code-hashes in any label.
  Identifiers are unloggable wrapper types (`internal/ident`) that redact
  on every serialization surface (CI-asserted from Session 5). Operational
  logging is lifecycle-only: started/stopped/config.
- **Silence doctrine** (scoped to the Nimna layer, where it is absolute —
  architecture note §5.1): relay code never sends a close frame carrying
  reason text or a Nimna-state-dependent status. Malformed Nimna frames
  close the connection with nothing said; valid-but-unhandled frames are
  silently dropped. The only close frames with text are the WebSocket
  library's own RFC 6455 transport-compliance closes (1002), a fixed
  function of the sender's malformed transport bytes — state-independent
  and identifier-free, test-asserted.
- License will be **AGPL-3.0** (LICENSE lands with the public-release
  readiness work in Session 6).

## Layout

- `cmd/relay/` — the relay binary: thin wiring, flags/env, signals
- `cmd/testclient/` — CLI test client for the S3/S4 done-checks (real
  §3.1.2 code→topic derivation; the only x/crypto consumer)
- `internal/wire/` — 18-byte outer frame + §5.4 frame-type enum + KNOCK
  payload parse/build
- `internal/ident/` — unloggable identifier wrapper types
- `internal/rendezvous/` — topic registry + bridging state machine
- `internal/channel/` — CRID registry: registrations, pending knocks,
  knock → accept → bridged sessions
- `internal/push/` — stateless push forwarding (content-free by
  construction; config-gated test sink; real transports in S6)
- `internal/server/` — accept loop, connection lifecycle, frame router
- `go.mod` — module `nimna.app/relay` (vanity path; nothing imports the
  relay, so it need not resolve)

## Commands

```sh
go build ./...             # compile everything (writes no binaries)
go test ./...              # run tests (-short skips production-cost Argon2id)
go vet ./...               # static checks
gofmt -l .                 # formatting (must print nothing)
go run ./cmd/relay         # run the relay (default 127.0.0.1:9440;
                           #   -listen / NIMNA_RELAY_LISTEN to override;
                           #   -push-sink / NIMNA_RELAY_PUSH_SINK for the
                           #   test-only push sink — empty = push-less)
go build ./cmd/relay       # drop the `relay` binary here (git-ignored);
go build ./cmd/testclient  #   same for `testclient`
```

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

## Dependencies

Stdlib-first; every addition justified, pinned, and architect-signed-off
(crypto/network deps always). Current, per the S3 sign-off:

- `github.com/coder/websocket` v1.8.15 — WebSocket transport (zero
  transitive deps, ISC, context-first API on `net/http`)
- `golang.org/x/crypto` v0.53.0 — **test client only** (`argon2`);
  `cmd/relay`'s import graph stays x/crypto-free, checked per session with
  `go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto'` → 0 and
  CI-asserted from Session 5
