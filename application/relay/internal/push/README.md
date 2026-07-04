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
  non-2xx), dropped (queue overflow OR a dispatch for a platform with no
  configured transport — `ErrNoTransport`, unlogged; the enumeration does
  not grow, §27) — the caps' refusals are counted by
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
- `router.go` — `Router` (implements `Sender`): routes the platform byte
  0x01 → the APNs sender, 0x02 → the FCM sender; either may be nil (a
  one-platform deployment is legal per §3.2.1), and a dispatch for a
  missing platform is the `ErrNoTransport` silent drop. `cmd/relay`
  wires a Router whenever any real credential is configured; the sink
  and real credentials are mutually boot-fatal.
- `apns.go` — the real APNs transport (note §27): HTTP/2 POST
  `{base}/3/device/<hex(token)>` (stdlib negotiates h2; the KNOCK token
  is the raw 32-byte device token, hex-encoded here — the token bytes
  contract) with the §11 constant headers (`apns-push-type: alert`,
  `apns-priority: 10`, `apns-expiration: now+60s`, `apns-topic` from
  config) and constant body; ES256 provider JWT assembled as fixed
  base64url/JSON over a stdlib `crypto/ecdsa` signature (composition,
  not hand-rolled crypto), cached and lazily re-signed at 40 min age
  inline on the one worker. The .p8 (PKCS#8 P-256) must parse at boot.
  Responses drained and discarded, never parsed or logged; non-2xx →
  `StatusError` (a 410 on a stale token IS spec §3.2.1's "a push
  silently fails").
- `fcm.go` — the real FCM v1 transport (note §27): OAuth2 JWT-bearer
  grant (RS256 over stdlib `crypto/rsa`) against the SA file's
  `token_uri`, access token cached to expiry − 5 min, refreshed lazily
  inline; then POST `{base}/v1/projects/<project>/messages:send` with
  the §11 constant message plus exactly ONE per-dispatch field —
  `message.token` (the registration token's ASCII bytes), built by
  `json.Marshal` of a fixed struct. The service-account JSON
  (client_email, private_key, token_uri, project_id) must parse at
  boot. Base URLs are constructor params (test injection — no flags);
  the JWT/token caches are in-memory derivatives of the credential
  config: recomputable, user-free, dead with the process.
- `push_test.go` — exactly one Send per enqueue, overflow drops without
  blocking, per-send deadline, worker lifecycle; outcome counting
  (sent/failed/dropped) through the public exposition; the fixed-field
  failure line (platform + status only, status 0 for non-HTTP errors,
  never token bytes or the error's own text); sink assertions: POST per
  call, pinned constant bodies byte-identical across calls, token only in
  the addressing header, `StatusError` on non-2xx.
- `apns_test.go` / `fcm_test.go` / `router_test.go` — mock platform
  servers as in-package `httptest` TLS servers (h2 for APNs, asserted via
  `ProtoMajor == 2`); keys GENERATED AT TEST RUNTIME (`ecdsa.GenerateKey`,
  `rsa.GenerateKey`, serialized to .p8/SA-JSON shapes in `t.TempDir()` —
  no key-shaped file is ever committed); JWT signatures verified against
  the public keys with exact header/claim sets; exact request shapes and
  byte-identical bodies across sends (modulo FCM's one addressing field);
  cache/re-sign windows under injectable clocks; boot-fatal constructor
  cases; router platform dispatch and the unconfigured-platform drop
  (counted `dropped`, no log line).
