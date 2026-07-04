# nimna — relay (Go)

The Nimna relay: a **stateless** WebSocket router that bridges exactly two
live device connections and never stores anything. Implements spec §3–§4 of
[`docs/nimna-protocol-spec-v0.1.1.md`](../../docs/nimna-protocol-spec-v0.1.1.md);
§5 traffic is opaque payload — routed verbatim, never parsed.

**Status:** Session 1 scaffold — builds and tests, no protocol behavior yet.
Rendezvous/bridging arrive in Session 3; knock/sessions/push forwarding in
Session 4; hardening/rate limits/observability in Session 5; deploy and the
public AGPL-3.0 release in Session 6.

## Invariants (non-negotiable)

- **Zero storage:** the complete at-rest inventory is routing tables in
  memory, TLS certificates, and push credentials as deployment config
  (spec §4). Any persistence beyond that is a USER decision by definition.
- **Push credentials are config slots** (env / mounted files), never
  repository content.
- **Metrics, not logs:** production instrument is aggregate in-memory
  counters with no CRIDs/IPs/device-tokens/code-hashes in any label.
  Identifier types are unloggable wrapper types (redact on serialization,
  CI-asserted from Session 5).
- License will be **AGPL-3.0** (LICENSE lands with the public-release
  readiness work in Session 6).

## Layout

- `cmd/relay/` — main package (single static binary)
- `go.mod` — module `nimna.app/relay` (vanity path; nothing imports the
  relay, so it need not resolve)

## Commands

```sh
go build ./...        # build everything
go test ./...         # run tests
go vet ./...          # static checks
gofmt -l .            # formatting (must print nothing)
go run ./cmd/relay    # run the scaffold binary
```

Dependencies: stdlib-first. Every module addition is justified, pinned, and
reviewed; crypto/network-touching additions need tech-architect sign-off.
