# internal/server/

WebSocket accept loop, connection lifecycle, frame router, and the
Session 5 limit/observability wiring (architecture note §3, §5, §5.1,
§§9–12, §§14–22):

- `server.go` — accept endpoint (`github.com/coder/websocket`), the full
  runtime Config (spec-default TTLs and every §14 limit knob; zero values
  mean defaults), frame-size limit enforced with a bare silent close (the
  library limiter would explain a RELAY policy decision, outside the §5.1
  carve-out, so it is disabled), graceful shutdown on context cancel (NO
  drain — pending knocks and queued pushes are the dies-with-process
  class, §22). Serve wraps the raw listener in the `internal/limits`
  limit listener (per-IP cap, liveness; S6 ordering: TCP → limit listener
  → TLS → HTTP), stashes the tracked conn in the request context (one
  canonical IP key; idle-close attribution), runs all janitors and the
  push worker under the recover-and-scrub discipline, and serves the ops
  listener (`GET /metrics`, everything else 404) that dies with the same
  context. Panic scrub (§19): every long-lived goroutine recovers, logs
  site + panic Go TYPE only (never the value, never a stack at production
  level), counts `panics_total{site}`, and restarts (janitors, worker) or
  unwinds (connection goroutines). Operational slog is lifecycle-only;
  net/http's internal error logger is discarded (its fallback writes raw
  client IPs). `-debug-trace` gates per-connection tracing keyed by an
  opaque process-local sequence number.
- `conn.go` — per connection: one read goroutine + one writer goroutine
  draining a bounded channel (cap 32; a full buffer closes the peer — the
  relay never queues); the read loop charges one token per WebSocket
  message BEFORE parse and sleeps out any bucket wait (§16: backpressure,
  never an error). sync.Once teardown takes a close-class for metrics
  attribution only (structural/oversize/idle/read_error/write_error/
  send_overflow/shutdown — on the wire every teardown is identical),
  unwinds BOTH planes' registrations, and closes via bare `CloseNow`.
  Rendezvous-plane handlers live here: REGISTER_TOPIC behind the per-IP
  rendezvous window and the per-conn registration cap (both silent
  drops — registration has no ack), PAIR_DATA verbatim.
- `channel.go` — channel-plane handlers: REGISTER_CRID (silent, cap-gated,
  deliver-on-register), KNOCK (structural payload parse FIRST — its close
  must stay a pure function of the bytes — then the per-CRID collapse
  window, dropped silently before any state change; then registry
  validation; push dispatch gated by the per-CRID caps, which suppress
  only the dispatch, never the knock), ACCEPT (first-ACCEPT-wins),
  TEARDOWN (notify other member only), SESSION_DATA (verbatim). Every
  state-dependent rejection — including every shared-state limit — is a
  silent drop: an observable outcome would let one end probe the other's
  activity (§16).
- `server_test.go` — Session 3 end-to-end (bridge, verbatim PAIR_DATA,
  topic death, no tombstones, malformed-frame closes with NO close
  status, unwind, shutdown) + the §5.1 transport-compliance covering test
  (1002 closes byte-identical against empty and loaded relays).
- `channel_test.go` — Session 4 wire-level rows of the note §10 edge
  table (`TestRowNN…`), keepalive ping, and the done-check mirror
  `TestChannelPlaneEndToEnd` (relay memory empty after; exactly one
  content-free POST per eligible knock). Tests that fire repeated knocks
  shrink the S5 windows via config — the limits have their own tests.
- `limits_test.go` — Session 5: the §16 empty-vs-loaded per-IP-cap
  covering test (zero-byte refusal in both worlds), frame-rate pacing
  (all frames delivered, paced, no errors), configured max-frame
  boundary, rendezvous throttle (behavioral: throttled registration takes
  no state), registration caps on both planes (deliver-on-register does
  not fire for a dropped register), knock collapse and push floor at the
  wire, liveness through Serve (pings keep alive; silence reaps; idle
  close class), panic recover-and-scrub (site + `%T` only, identifier
  panic value never rendered, connection unwound), janitor restart, and
  the ops listener surface incl. §22 shutdown.
