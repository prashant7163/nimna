# internal/server/

WebSocket accept loop, connection lifecycle, and frame router
(architecture note §3, §5, §5.1, §§9–12):

- `server.go` — accept endpoint (`github.com/coder/websocket`), config
  (listen address, topic TTL, pending-knock TTL — spec defaults — and the
  optional push Sender; nil = push-less), frame-size limit enforced with a
  bare silent close (the library limiter would explain a RELAY policy
  decision, outside the §5.1 carve-out, so it is disabled), graceful
  shutdown on context cancel, lifecycle-only slog (started/stopped/config
  — never a topic, CRID, IP, or token; net/http's internal error logger
  is discarded because its fallback writes raw client IPs to stderr). The
  full §5.4 router: both planes handled; only relay-emitted go-signals
  (0x10–0x12) echoed back are unhandled and dropped. Serve runs both
  registry janitors and the push dispatcher worker.
- `conn.go` — per connection: one read goroutine + one writer goroutine
  draining a bounded channel (cap 32; a full buffer closes the peer — the
  relay never queues); sync.Once teardown unwinds BOTH planes'
  registrations (topics die whole with no signal — §5.4 defines none; a
  CRID bridge survivor gets the relay TEARDOWN, disconnection being an
  implicit TEARDOWN) and closes via bare `CloseNow`. Silence doctrine per
  §5.1: relay code never sends a close frame carrying reason text or a
  Nimna-state-dependent status; the only close frames with text are the
  WebSocket library's own RFC 6455 transport-compliance closes (1002), a
  fixed function of the sender's malformed transport input, carrying no
  Nimna identifier or state. Rendezvous-plane handlers (REGISTER_TOPIC,
  PAIR_DATA) live here.
- `channel.go` — channel-plane handlers: REGISTER_CRID (silent, with
  deliver-on-register of an unexpired pending KNOCK_FWD), KNOCK (the one
  parsed payload — malformed closes, state-independent; forward set gets
  freshly built empty KNOCK_FWDs, so the token strip is structural; empty
  forward set + token = exactly one push dispatch), ACCEPT
  (first-ACCEPT-wins, SESSION_BRIDGED to both), TEARDOWN (notify the
  other member only; registrations survive), SESSION_DATA (verbatim
  between bridge members). Every state-dependent rejection is a silent
  drop. Keepalive needs no code: the library auto-pongs during Read
  (note §12).
- `server_test.go` — Session 3 end-to-end over real WebSockets: bridge to
  both ends, verbatim PAIR_DATA both ways, topic death on disconnect,
  silent fresh re-registration, third-registrant silence,
  malformed-Nimna-frame closes asserting NO close status was sent,
  unhandled-type drops, full unwind, shutdown — plus the §5.1 covering
  test: raw-TCP probes (RSV bits set, unknown opcode) asserting the
  library's 1002 close carries the known generic text, no identifier
  bytes, and byte-identical output against an empty relay and one holding
  registered and bridged topics (state-independence).
- `channel_test.go` — Session 4 wire-level rows of the note §10 edge
  table (`TestRowNN…`), the keepalive ping mid-session check, and the
  done-check mirror `TestChannelPlaneEndToEnd`: pair → disconnect → the
  four knock scenarios against a real `push.HTTPSink` — exactly ONE
  content-free POST for the offline+token knock, zero for online knocks —
  asserting the relay's memory is empty afterwards (topic entries, CRID
  entries, pending count all zero).
