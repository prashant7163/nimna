# nimna — relay (Go)

The Nimna relay: a **stateless** WebSocket router that bridges exactly two
live device connections and never stores anything. Implements spec §3–§4 of
[`docs/nimna-protocol-spec-v0.2.md`](../../docs/nimna-protocol-spec-v0.2.md);
§5 data-plane traffic is opaque payload — routed verbatim, never parsed.

**Status:** Session 3 — connections & rendezvous. The relay accepts
WebSocket connections, registers rendezvous topics (silently, §3.1.6),
bridges a topic's first two distinct registrants (`TOPIC_BRIDGED` to both
ends), forwards `PAIR_DATA` verbatim between them, and kills the topic
when either end disconnects or its 24 h registration cap fires — no
tombstones, no explanations. Knock/sessions/push forwarding land in
Session 4; hardening/rate limits/observability in Session 5; deploy and
the public AGPL-3.0 release in Session 6.

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
- `internal/wire/` — 18-byte outer frame + §5.4 frame-type enum
- `internal/ident/` — unloggable identifier wrapper types
- `internal/rendezvous/` — topic registry + bridging state machine
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
                           #   -listen / NIMNA_RELAY_LISTEN to override)
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

## Dependencies

Stdlib-first; every addition justified, pinned, and architect-signed-off
(crypto/network deps always). Current, per the S3 sign-off:

- `github.com/coder/websocket` v1.8.15 — WebSocket transport (zero
  transitive deps, ISC, context-first API on `net/http`)
- `golang.org/x/crypto` v0.53.0 — **test client only** (`argon2`);
  `cmd/relay`'s import graph stays x/crypto-free, checked per session with
  `go list -deps ./cmd/relay | grep -c '^golang.org/x/crypto'` → 0 and
  CI-asserted from Session 5
