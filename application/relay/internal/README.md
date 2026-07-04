# relay/internal/

Implementation packages of the relay — see the
[relay README](../README.md) for the layout and commands. Internal to
module `nimna.app/relay`; nothing here is importable from outside.

- [`wire/`](wire/README.md) — 18-byte outer frame + §5.4 frame-type enum;
  the module's only protocol-parsing surface
- [`ident/`](ident/README.md) — unloggable identifier wrapper types
  (Topic, CRID, RemoteAddr, DeviceToken)
- [`rendezvous/`](rendezvous/README.md) — topic registry + bridging state
  machine (waiting → bridged → dead, 24 h cap, no tombstones)
- [`server/`](server/README.md) — WebSocket accept loop, connection
  lifecycle, frame router, single-writer discipline

Reserved seams (do not create early): `channel/` and `push/` land in
Session 4; `metrics/` and `limits/` in Session 5 (architecture note §2).
