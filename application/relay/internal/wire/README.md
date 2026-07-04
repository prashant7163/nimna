# internal/wire/

The Nimna outer frame, byte-exact per spec v0.2 §5.4 — THE ONLY
protocol-parsing surface in the relay module:

- `wire.go` — 18-byte header `[ver 0x01][frame_type][routing_id:16]`
  parse/encode; the complete frame-type enum (relay-plane 0x01–0x05,
  go-signals 0x10–0x12, data-plane 0x20–0x21 — defined in full even though
  Session 3 handles only three); constants (`HeaderLen` 18, `Version`
  0x01, `MaxFrame` 128 KiB). Validation errors are fixed-text sentinels
  carrying zero frame bytes.
- `wire_test.go` — table-driven invalid cases (the Session 2 deferral:
  empty/short frame, bad version, unknown type, oversize) plus boundary
  semantics (all-zero routing_id is routable; exactly-MaxFrame accepted),
  and conformance tests over the committed `outer_frames` vectors in
  `docs/test-vectors/framing.json` (read-only; never regenerated here).
