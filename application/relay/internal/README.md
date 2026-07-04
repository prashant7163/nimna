# relay/internal/

Implementation packages of the relay — see the
[relay README](../README.md) for the layout and commands. Internal to
module `nimna.app/relay`; nothing here is importable from outside.

- [`wire/`](wire/README.md) — 18-byte outer frame + §5.4 frame-type enum
  + KNOCK payload parse/build; the module's only protocol-parsing surface
- [`ident/`](ident/README.md) — unloggable identifier wrapper types
  (Topic, CRID, RemoteAddr, DeviceToken); per-IP key canonicalization
  (IPv4 exact, IPv6 /64)
- [`rendezvous/`](rendezvous/README.md) — topic registry + bridging state
  machine (waiting → bridged → dead, 24 h cap, no tombstones)
- [`channel/`](channel/README.md) — CRID registry: registrations, pending
  knocks (60 s), knock → accept → bridged sessions
- [`push/`](push/README.md) — stateless push forwarding: content-free by
  construction, bounded dispatcher, config-gated test sink
- [`limits/`](limits/README.md) — token bucket, per-IP rendezvous window,
  bounded per-CRID rate table, limit listener (per-IP cap + liveness)
- [`metrics/`](metrics/README.md) — identifier-free counters +
  hand-rolled Prometheus text exposition
- [`server/`](server/README.md) — WebSocket accept loop, connection
  lifecycle, frame router, limit wiring, ops listener, panic scrub
