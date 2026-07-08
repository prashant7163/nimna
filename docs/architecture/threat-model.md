# Nimna threat-model coverage (Session 18 adversarial pass)

**Status:** binding coverage record for the S18 done-check — *"every §9 row
has a passing test OR a documented accepted limitation."* Produced by the
S18 adversarial pass (2026-07-08, branch `session-18-adversarial`). Maps
every spec **§9** adversary row and every plan-**§18** "new row" to the
concrete test that exercises it, or to an explicitly documented accepted
limitation with its PUBLISH_READY device-QA pointer.

Sources of truth: `docs/nimna-protocol-spec-v0.2.1.md` §9 (threat table),
`nimna-build-plan-v3-sessions.md` §18, and the S18 intake **HOST-MAX**
decision (`DECISIONS.md`, 2026-07-08): the loop runs the maximal host +
emulator pass; the four genuinely hardware-bound rungs are documented
accepted limitations carried into `PUBLISH_READY.md` §2 device-QA
hand-steps, not S18 blockers.

Test-name convention below: `path :: test name`. All test paths are
relative to the repo root. Dart tests under `application/mobile/`, Go tests
under `application/relay/` and the isolated oracle module
`docs/test-vectors/oracle/`.

---

## What S18 added (net-new this session)

| Area | Stack | Test(s) |
|---|---|---|
| §5.4 outer-frame parser fuzz | Go | `application/relay/internal/wire/fuzz_test.go :: FuzzParse` (no crash under extended `go test -fuzz`; see QA done-check evidence) |
| KNOCK payload parser fuzz | Go | `application/relay/internal/wire/fuzz_test.go :: FuzzParseKnockPayload` (no crash under extended `go test -fuzz`; see QA done-check evidence) |
| Independent Noise oracle (flynn/noise, test-only) | Go (isolated module) | `docs/test-vectors/oracle/pairing_test.go :: TestOracleXXpsk2BothRoles`, `:: TestOracleCommitmentM0`, `:: TestOraclePairingTransport`; `session_test.go :: TestOracleKKBothRoles`, `:: TestOracleSessionTransport` |
| Safety-phrase MISMATCH (divergent-key detector) | Dart | `test/noise/safety_phrase_mismatch_test.dart :: MITM who owns the code still forks the safety phrase (§3.1.4 divergent-key detector)` |
| Single-attempt fail-closed §3.1.6 | Dart | `test/pairing/join_controller_test.dart :: §3.1.6 single fail-closed attempt: a wrong code burns the pairing — exactly one handshake, no retry oracle for a later valid M2` |
| Forward secrecy §7.3 | Dart | `test/noise/forward_secrecy_test.dart :: captured frames do not decrypt from the long-term statics alone (§7.3)` |
| Codec fuzz (inner + outer) | Dart | `test/protocol/codec_fuzz_test.dart :: outer-frame decode: only OuterFrameError, and accepted ⇒ byte-identical round trip`, `:: inner-envelope decode: only InnerEnvelopeError, and accepted ⇒ byte-identical round trip` (seed `0x0DDF00D`, 20k iters each) |
| Oversized outer-frame rejection | Dart | `test/protocol/outer_frame_test.dart :: an over-MaxFrame frame is rejected with OuterFrameError (mirrors the relay ErrOversize)`, `:: a frame at exactly MaxFrame (128 KiB) decodes` |
| Screenshot-notice non-suppressibility | Dart | `test/session/session_controller_test.dart :: screenshot notice cannot be silenced while live: unconditional CONTROL 0x03, no suppression toggle (§18-E honesty)` |
| XMP + ICC strip | Dart | `test/media/image_processor_test.dart :: XMP packet is stripped by the real processor (§18-G, S11 NIT)`, `:: ICC colour profile is stripped by the real processor (§18-G, §5.1)`, `:: precondition: fixtures actually carry XMP and an ICC profile` |

**Findings the pass caught and closed (production fixes, not deferrals):**
- **ICC colour-profile leak** — `image_processor.dart` stripped EXIF/GPS/XMP
  but re-emitted the source ICC profile (identifying data survived the
  pipeline), violating the §5.1 metadata-strip guarantee. Fixed
  (`image.iccProfile = null`); the FINDING test flipped to a positive strip
  assertion. This is the S11 XMP/ICC NIT, discharged.
- **Dart outer-frame had no upper bound** — Go rejects >128 KiB
  (`ErrOversize`); Dart accepted oversize, a hostile/compelled-relay
  memory-DoS vector (§9 relay-operator row). Fixed (`outerMaxFrame = 128
  KiB` decode bound, architect-ruled a spec-conformance fix, not a
  frozen-codec change). The `dart:io` socket-buffer residual is documented
  as an accepted limitation (see below).

---

## §9 adversary rows

| # | Adversary | Protection (spec) | Coverage | Disposition |
|---|---|---|---|---|
| 9.1 | Relay operator (incl. compelled) | Ciphertext + routing metadata only; nothing stored | `application/relay/cmd/relay/logscrub_test.go`, `logscrub_tls_test.go` (real-binary log capture, no identifier ever emitted); `internal/ident/ident_test.go` (unloggable wrapper types redact on serialize); relay never parses inner envelopes (§5.4 outer only) — `internal/wire/wire_test.go` + `FuzzParse`; `application/mobile/test/session/session_controller_test.dart` (SESSION_DATA forwarded verbatim, relay sees ciphertext) | **TEST** |
| 9.2 | Relay recovers code from topic ID (offline brute force) | Argon2id (t=3, m=64 MiB) + daily date salt | `application/relay/cmd/testclient/derive_test.go` + `application/mobile/test/protocol/rendezvous_test.dart` (production-cost Argon2id derivation, vector-locked); the ~thousand-server-years *magnitude* is an analytic claim, stated in-doc | **TEST** (construction) **+ DOC** (magnitude) |
| 9.3 | Network observer | TLS to relay + E2E within; sees only that a device talked to the relay | `application/relay/internal/server/tls_test.go` (TLS 1.3 enforced); the "sees a device talked to the relay" residual is an acknowledged v1 property | **TEST** (TLS) **+ DOC** (acknowledged residual) |
| 9.4 | Pairing-time MITM | Requires the code (psk); one attempt fail-closed; commitment prologue; phrase caught at ~1-in-2.1B | `application/mobile/test/noise/xxpsk2_pairing_test.dart` (code-less MITM fails closed at M2; lying M0 commitment caught); `safety_phrase_mismatch_test.dart` (code-holding MITM still forks the phrase → different words); `test/pairing/join_controller_test.dart` (single fail-closed §3.1.6, PSK burned, no retry oracle); **independent oracle** `docs/test-vectors/oracle/pairing_test.go` (flynn/noise agrees byte-for-byte on XXpsk2 + commitment) | **TEST** (strong; incl. independent oracle) |
| 9.5 | Relay-plane replay/forgery (KNOCK/ACCEPT/TEARDOWN) | Not cryptographically protected — stated honestly; ride inside TLS; consequence bounded to nuisance; rate limits cap | `application/relay/internal/wire/fuzz_test.go :: FuzzParseKnockPayload` + `internal/wire/knock_test.go` (malformed frames rejected); `internal/limits/ratetable_test.go` (nuisance bounded by §4 limits); a forged accepted knock yields a bridge on which the impostor cannot complete KK — `application/mobile/test/noise/session_kk_test.dart` + `noise_transport_test.dart` (KK fail-closed, nothing decrypts) | **TEST** (bounding) **+ DOC** (honest "not cryptographically protected" statement) |
| 9.6 | Peer's device seized | Out of scope for protocol; app lock, expiry, panic wipe | `application/mobile/test/lock/lock_controller_test.dart`, `test/wipe/wipe_service_test.dart`, per-message expiry in `test/session/session_controller_test.dart` | **TEST** (app-level mitigations) **+ DOC** (protocol out-of-scope, honest) |
| 9.7 | Your own device seized | App lock, encrypted-at-rest, panic wipe, no cloud backups; past sessions undecryptable (forward secrecy §7.3) | `application/mobile/test/storage/storage_service_test.dart` (raw-byte no-plaintext-marker scan with canary self-test); `test/wipe/wipe_service_test.dart` (interrupted wipe → survivors undecryptable under any future MK); **`test/noise/forward_secrecy_test.dart`** (captured frames don't decrypt from the long-term statics alone) | **TEST** (host-max) **+ LIMITATION** (real seized-device cold-boot disk forensics + real `isExcludedFromBackup` read-back → device-QA) |
| 9.8 | Counterpart captures content (screenshot / 2nd camera) | Screenshot: detect-and-notify, honor-system, disclosed; second camera: undetectable, disclosed | `application/mobile/test/session/session_controller_test.dart` (CONTROL 0x03 unconditional while live, **no suppression toggle** — the honesty invariant); `test/screenshot/screenshot_widgets_test.dart` (system-line rendering) | **TEST** (suppression-honesty, host) **+ LIMITATION** (real OS screenshot keystroke on iOS17/Android14+ → device-QA) **+ DOC** (2nd-camera undetectable, honest) |
| 9.9 | Metadata correlation (IP/timing/sizes) | Acknowledged v1 limitation; document honestly | Acknowledged in spec §9 and on the /security page (S19) | **DOC** (accepted v1 limitation) |

## Plan-§18 "new rows"

| Row | Coverage | Disposition |
|---|---|---|
| Replay | `application/mobile/test/noise/noise_transport_test.dart` (nonce `direction‖counter` strict-increment, counter-gap + AAD-tamper fail-closed, per-message rekey); `forward_secrecy_test.dart` | **TEST** |
| MITM | See §9.4 (incl. the independent flynn/noise oracle) | **TEST** |
| Malformed frames + fuzzing — **relay** | `application/relay/internal/wire/fuzz_test.go :: FuzzParse` + `:: FuzzParseKnockPayload` (Go native fuzzing; no crash / no bug under extended `go test -fuzz`, CI runs the seed corpus) | **TEST** (net-new) |
| Malformed frames + fuzzing — **app** | `application/mobile/test/protocol/codec_fuzz_test.dart` (seeded random/structured-random inner-envelope + outer-frame; only typed errors, accepted ⇒ byte-identical round-trip) | **TEST** (net-new) |
| Storage/backup inspection | `application/mobile/test/storage/storage_service_test.dart` (raw `readAsBytesSync` marker scan, canary self-test); `test/privacy/diag_marker_audit_test.dart` | **TEST** (host raw-file scan) **+ LIMITATION** (real `isExcludedFromBackup` read-back on a physical device → device-QA; the host `integration_test/app_boot_test.dart` could not build headless — see note) |
| Screenshot-notice suppression honesty | `application/mobile/test/session/session_controller_test.dart` (structural: no `suppress` param; behavioral: 3 live screenshots → peer receives all 3, no dedup/silencing) | **TEST** (net-new) |
| Push-bombing vs rate limits | `application/relay/internal/limits/ratetable_test.go` (boundary-exact at spec values: knock collapse 10s, push 1/60s + **6/hr** + **20/24h** per CRID, rendezvous 6/min/IP), wired in `internal/server/limits_test.go`, CI-captured in `cmd/relay/logscrub_test.go` | **TEST** (best-covered row) |
| EXIF-strip verification | `application/mobile/test/media/image_processor_test.dart` (EXIF + GPS + **XMP** + **ICC** all stripped through the real `package:image` pipeline; ICC leak found & fixed this session) | **TEST** (strengthened; Finding B closed) **+ LIMITATION** (real-camera capture EXIF → device-QA) |
| Wipe forensics | `application/mobile/test/wipe/wipe_service_test.dart` (key-destruction-first ordering; interrupted-wipe survivors undecryptable; raw-file marker scan) | **TEST** (host-max) **+ LIMITATION** (seized-device cold-boot disk forensics → device-QA) |

---

## Accepted limitations — hardware-bound (→ PUBLISH_READY §2 device-QA)

Per the HOST-MAX intake decision, these four rungs require a physical
handset the loop cannot attach. Each is a documented device-QA hand-step,
not a coverage gap — the host-level evidence above proves the *code* is
correct; the device-QA run confirms the *platform* behaves as assumed.

1. **Real-camera EXIF capture** — photograph with a real camera (GPS/lens
   EXIF present), send, confirm the received/exported image carries none.
   (Host proof: `image_processor_test.dart` strips EXIF/GPS/XMP/ICC from
   crafted fixtures.)
2. **OS screenshot keystroke** — trigger a real OS screenshot on iOS 17 and
   Android 14+, confirm the CONTROL 0x03 notice reaches the peer's thread.
   (Host proof: the non-suppressibility + round-trip tests.)
3. **Push delivery to a locked physical device** — knock a
   backgrounded/locked real phone, confirm the content-free "New activity"
   nudge arrives via live APNs/FCM. (Host proof: `content_free_push_test`,
   `push_service_test`, byte-constant relay body.)
4. **Cold-boot disk forensics + backup exclusion read-back** — pull the
   raw app container from a seized device / inspect a device backup,
   confirm no plaintext and `isExcludedFromBackup==true`. (Host proof: raw
   `readAsBytesSync` marker scans; `allowBackup=false` + `dataExtractionRules`
   in the manifests.)

**Environmental note (not a product bug):** the host
`integration_test/app_boot_test.dart` (simulator-half backup read-back)
could not be built headless — the iOS build fails compiling the transitive
`flutter_secure_storage_windows` against the repo's pinned `win32: 5.15.0`
override. This is a pre-existing build-graph incompatibility unrelated to
any S18 change and does not affect the host `flutter test` suite. Tracked
as a PUBLISH_READY build-graph item; the backup read-back rides device-QA
regardless.

## Accepted limitations — analytic / acknowledged (DOC only)

- **Metadata correlation** (§9.9) — IP/timing/size correlation by a network
  observer; acknowledged v1 limitation (future: federation, transport
  overlays).
- **Second camera** (§9.8) — capturing the screen with a second device is
  undetectable; disclosed honestly. Trust in the counterpart is an
  acknowledged part of the model.
- **Relay-plane frame forgery inside TLS** (§9.5) — KNOCK/ACCEPT/TEARDOWN
  are not cryptographically authenticated; only the relay itself (which can
  equally drop traffic) can forge/replay them, and the consequence is
  bounded to nuisance capped by §4 rate limits. Stated honestly.
- **Argon2id brute-force magnitude** (§9.2) — the ~thousand-server-years
  cost of a 2^45 code sweep is an analytic claim about the construction,
  not a runtime-testable event; the construction itself is vector-locked.

---

## Independence note — the flynn/noise oracle

The hand-implemented from-spec Noise engine (Dart `lib/src/noise/` + the Go
vector generator) is byte-locked to the committed vectors, which both
stacks already pass. S18 adds an **independent** implementation
(`github.com/flynn/noise`, the reference Go Noise library) that agrees with
those committed vectors — XXpsk2 (both roles, incl. the M0 commitment
prologue recomputed with an independent SHA-256) and Noise_KK (both roles).
Where flynn/noise cannot mirror a Nimna-specific deviation (the
`direction‖counter` transport nonce and per-message rekey are not standard
Noise), the oracle re-wraps the transport with `x/crypto` directly and
asserts byte-equality vs the committed frames; the AEAD core is `x/crypto`
on both sides by design (no second ChaCha worth trusting over the audited
one). See `docs/architecture/s18-noise-oracle-design.md`.

**Isolation (test-only, never a runtime dependency):** the oracle is a
separate Go module `nimna.app/test-vectors/oracle` with its own
`go.mod`/`go.sum`, outside the AGPL-published relay tree. Three CI layers
prove flynn/noise never enters the relay binary's dependency graph:
a manifest tripwire (`! grep flynn/noise application/relay/go.sum`), a
semantic graph proof (`go list -deps ./...` on the relay → 0 flynn/noise),
and the generator staying flynn-free — mirroring the existing x/crypto
exclusion guard.
