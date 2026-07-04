# internal/wire/

The Nimna outer frame, byte-exact per spec v0.2 §5.4 — THE ONLY
protocol-parsing surface in the relay module:

- `wire.go` — 18-byte header `[ver 0x01][frame_type][routing_id:16]`
  parse/encode; the complete frame-type enum (relay-plane 0x01–0x05,
  go-signals 0x10–0x12, data-plane 0x20–0x21); constants (`HeaderLen` 18,
  `Version` 0x01, `MaxFrame` 128 KiB). Validation errors are fixed-text
  sentinels carrying zero frame bytes.
- `knock.go` — KNOCK payload parse/build (the one relay-plane payload the
  relay must parse, §5.4/§5.7): empty (no push) or
  `platform (1: 0x01 APNs / 0x02 FCM) ‖ token_len (2, BE) ‖ token` — no
  presence byte on the relay plane; anything else is `ErrKnockPayload`,
  structurally malformed traffic (the caller closes the connection). The
  parsed token aliases the input; the server wraps it in
  `ident.DeviceToken` immediately at the parse boundary.
- `wire_test.go` — table-driven invalid cases (the Session 2 deferral:
  empty/short frame, bad version, unknown type, oversize) plus boundary
  semantics (all-zero routing_id is routable; exactly-MaxFrame accepted),
  and conformance tests over the committed `outer_frames` vectors in
  `docs/test-vectors/framing.json` (read-only; never regenerated here).
- `knock_test.go` — table-driven KNOCK payload invalid cases (truncated
  forms, zero/lying token_len, bad platform bytes, endianness probe),
  valid boundaries (1-byte and max-uint16 tokens, big-endian length
  pinned), encode/parse round trip, and conformance against the committed
  KNOCK vectors in `framing.json`.
