# internal/server/

WebSocket accept loop, connection lifecycle, and frame router
(architecture note §3, §5, §5.1):

- `server.go` — accept endpoint (`github.com/coder/websocket`), config
  (listen address, topic TTL — spec defaults), frame-size limit enforced
  with a bare silent close (the library limiter would explain a RELAY
  policy decision, outside the §5.1 carve-out, so it is disabled),
  graceful shutdown on context cancel, lifecycle-only slog
  (started/stopped/config — never a topic, CRID, IP, or token; net/http's
  internal error logger is discarded because its fallback writes raw
  client IPs to stderr).
- `conn.go` — per connection: one read goroutine + one writer goroutine
  draining a bounded channel (cap 32; a full buffer closes the peer — the
  relay never queues); sync.Once teardown unwinds every topic registration
  and closes via bare `CloseNow`. Silence doctrine per §5.1: relay code
  never sends a close frame carrying reason text or a
  Nimna-state-dependent status; the only close frames with text are the
  WebSocket library's own RFC 6455 transport-compliance closes (1002),
  a fixed function of the sender's malformed transport input, carrying no
  Nimna identifier or state. Router: REGISTER_TOPIC and PAIR_DATA in
  Session 3; valid-but-unhandled types silently dropped; structurally
  malformed traffic closes the connection. Session 4 registers
  channel-plane handlers on the same map.
- `server_test.go` — end-to-end over real WebSockets: bridge to both
  ends, verbatim PAIR_DATA both ways, topic death on disconnect, silent
  fresh re-registration, third-registrant silence, malformed-Nimna-frame
  closes asserting NO close status was sent, unhandled-type drops, full
  unwind, shutdown — plus the §5.1 covering test: raw-TCP probes (RSV
  bits set, unknown opcode) asserting the library's 1002 close carries
  the known generic text, no identifier bytes, and byte-identical output
  against an empty relay and one holding registered and bridged topics
  (state-independence).
