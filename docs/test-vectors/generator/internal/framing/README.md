# internal/framing/

Exact wire layouts of spec v0.2 §5.4–§5.7, hand-specified (no
serialization library, all integers big-endian):

- `framing.go` — 18-byte outer frame (ver ‖ frame_type ‖ routing_id) and
  all frame_type constants; inner envelope encode/decode with structural
  validation (type/flag rules, expiry offset shift, ACK/CONTROL/HANGUP
  body rules); MEDIA_CHUNK manifest + chunk bodies and transfer
  reassembly incl. content_hash verification (§5.1); token_payload in
  both the E2E form (§5.7) and the prefix-less relay-plane KNOCK form
  (§5.4).
- `framing_test.go` — fixed-seed round-trip property test (2000 random
  valid envelopes), offset assertions, rejection matrix, token forms,
  reassembly rules.
