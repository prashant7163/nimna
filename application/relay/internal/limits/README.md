# internal/limits/

Rate limits, per-IP caps, and the liveness/limit listener (spec §4;
architecture note §§14–17). Every table here is spec §4's own named
"rate/push counters" transient class — in-memory, user-anonymous, reset
on restart. Maps key on `internal/ident` wrapper types only; this package
sends no frames and writes no logs — callers apply note §16's silence
adjudication (silent drops, bare closes, zero-byte refusals).

- `bucket.go` — hand-rolled per-connection token bucket (no `x/time/rate`
  dep for a fmt-sized loop): one token per WebSocket message, charged
  before parse; `Reserve()` returns the wait and the read loop sleeps it
  out — backpressure, never an error (§16).
- `ipwindow.go` — per-IP fixed 60 s window counting REGISTER_TOPIC frames
  only (the brute-force surface; CRIDs are 128-bit and exempt). Default
  6/min: three code entries a minute, a joiner costing two registrations.
- `ratetable.go` — the ONE per-CRID rate table (knock collapse 10 s, push
  60 s floor + 6/hour + 20/day — spec-verbatim defaults; hour/day windows
  configurable only as test/soak acceleration). Deliberately NOT on the
  channel registry's entries: those die with their last connection and
  could not honor 20/day across reconnect churn. Bounded: idle entries
  evicted past the longest configured window (24 h at spec defaults) by a
  60 s janitor; hard cap 65,536 (pinned constant, ~4 MB worst case). At
  cap: fail-OPEN on the forward, fail-CLOSED on the push — filling the
  table must never mint pushes at the platform.
- `listener.go` — the limit listener (§17), the single home for
  transport-boundary enforcement wrapping the raw TCP listener (S6
  ordering: raw TCP → limit listener → TLS → HTTP). Per-IP accounting on
  the canonical key (IPv4 exact, IPv6 /64): an at-cap connect is closed
  in accept with ZERO bytes written. Liveness: each conn's `Read` bumps a
  last-inbound-byte clock — WS pings are inbound bytes, so pings count
  structurally — and a janitor (30 s tick at the 90 s default, tick =
  deadline/3 for accelerated configs) closes conns idle past the
  deadline; reap lands between deadline and 4/3 × deadline. TCP keepalive
  stays on with Go defaults as the OS-level write-path backstop.
- `*_test.go` — boundary-exact on injectable fake clocks (collapse alive
  at 9.999 s / dead at 10 s; push floor at 59.999 s / 60 s; hour/day
  window rolls to the millisecond; eviction at horizon vs horizon+ε; cap
  fail-open/fail-closed), plus real-TCP listener tests: zero-byte
  over-cap refusal with under-cap conns undisturbed, liveness reap vs
  inbound-byte survival, and the janitor-tick derivation.
