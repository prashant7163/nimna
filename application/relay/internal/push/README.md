# internal/push/

Stateless push forwarding (spec §3.2.1; architecture note §11, §19): peer
offline + token present = exactly ONE content-free outbound call, then the
token is discarded. Never a token registry.

- `push.go` — `Sender`: one method, taking context, platform byte
  (straight from the KNOCK payload), and `ident.DeviceToken` — and NO
  content parameter; content-freeness is structural. The platform bodies
  are compile-time constants pinned in note §11 (a single localization
  key, `NEW_ACTIVITY`; no channel, sender, count, or timestamp),
  byte-identical across all pushes except addressing — that constancy is
  the auditable claim. `Dispatcher`: bounded queue (cap 32) drained by one
  worker with a 10 s per-attempt timeout; enqueue never blocks. Outcomes
  are metered (`pushes_total{outcome}`): sent, failed (transport error or
  non-2xx), dropped (queue overflow) — the caps' refusals are counted by
  the caller in `internal/server`. A failed attempt logs ONE fixed-field
  Warn line carrying platform and HTTP status only (`StatusError` is the
  sole error detail that can reach a log — no token, no CRID, no URL, no
  error rendering; note §19). On the wire everything stays silent — push
  is best-effort by spec. `HTTPSink`: the config-gated test sink
  (`-push-sink` / `NIMNA_RELAY_PUSH_SINK`) that stands in for the
  platform — POSTs the constant body with `Nimna-Push-Platform` and
  `Nimna-Push-Token` headers (the platform legitimately receives the
  token); non-2xx responses surface as `StatusError`. With nothing
  configured the relay runs push-less.
- `push_test.go` — exactly one Send per enqueue, overflow drops without
  blocking, per-send deadline, worker lifecycle; outcome counting
  (sent/failed/dropped) through the public exposition; the fixed-field
  failure line (platform + status only, status 0 for non-HTTP errors,
  never token bytes or the error's own text); sink assertions: POST per
  call, pinned constant bodies byte-identical across calls, token only in
  the addressing header, `StatusError` on non-2xx.

Real APNs/FCM transports are Session 6 (deploy) work behind the same
`Sender` interface — stdlib-only per the note §11 pin (HTTP/2 + ES256 JWT
for APNs, OAuth2 RS256 grant for FCM); credential config slots are named
in `cmd/relay` and stay empty until then.
