# docs/architecture/

Tech-architect architecture notes — binding technical shape for the
implementation sessions. Decisions recorded here are CODE decisions
(logged in `DECISIONS.md` by the orchestrator); anything protocol-visible
still defers to `docs/nimna-protocol-spec-v0.2.1.md`.

- [`app-architecture.md`](app-architecture.md) — Sessions 7–17 app
  (Flutter) shape, S7 intake: at-rest encryption inside the S2 crypto
  lock (record-level ChaCha20-Poly1305-IETF, SQLCipher/XChaCha rejected),
  key hierarchy (platform keystore → master key → store/channel-data/
  record keys), panic-wipe semantics + app-lock perimeter seam, store
  schemas with a pinned plaintext-column budget, dependency sign-offs
  (sqflite, flutter_secure_storage, path_provider; google_fonts
  rejected — fonts vendored), cloud-backup exclusion mechanics + the S7
  proof standard, content-free diagnostic-log design, skeleton layering /
  zero-dep state management / i18n wiring, and the min-OS-floor
  recommendation (flagged USER).
- [`relay-architecture.md`](relay-architecture.md) — Sessions 3–6 relay
  shape: WebSocket dependency sign-off (`coder/websocket` v1.8.15),
  package layout, concurrency model, unloggable identifier types, S3
  scope fence + topic lifecycle, CLI test-client shape, and where the
  outer-frame invalid-case tests live. Session 4 addendum (§§9–13):
  channel-plane edge semantics (CRID registry, knock/accept/bridge,
  pending-knock hold), stateless push forwarding design (`push.Sender`,
  content-free payload constants, config slots; real APNs/FCM transports
  deferred to S6, stdlib-only), keepalive stance, and the S4 test-client
  + done-check verification path.
