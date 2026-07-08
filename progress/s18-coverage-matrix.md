# S18 Adversarial Pass — Coverage Matrix (intake, not test-writing)

Owner: senior-qa. Produced 2026-07-08 at S18 intake. Maps existing test
coverage (66 Dart `_test.dart` + 22 Go `_test.go`, plus the device-attached
`integration_test/app_boot_test.dart`) against **spec §9 threat-model rows**
and **plan-§18 "new rows"**, so a Go dev and a Flutter dev can each pick up
their column and know exactly what to build.

Done-check contract (plan §18): *every §9 row has a passing test OR a
documented accepted limitation.* HOST-MAX intake decision (DECISIONS.md
2026-07-08): four rungs are hardware-bound accepted limitations carried into
PUBLISH_READY device-QA, not S18 blockers.

Legend — **Disposition**: `TEST` = host-level test/fuzz/scan to add in S18 ·
`CONSOLIDATE` = already well-covered; S18 adds one adversarial consolidating
assertion, no rework · `LIMITATION` = hardware-bound accepted limitation,
names the PUBLISH_READY device-QA step · `DOC` = honest-disclosure row, no
host test possible beyond what exists.

References are `file :: exact test/group name`. Dart paths under
`application/mobile/`, Go under `application/relay/`.

---

## Part A — Spec §9 threat-model rows (lines 1003–1013)

### §9.1 — Relay operator (incl. compelled): ciphertext + routing only, nothing stored; can't MITM pairing; can't forge graceful HANGUP; can't decrypt
- **Already covered by:**
  - Ciphertext-opaque forwarding: `internal/server/limits_test.go :: TestPerIPCapCoveringEmptyVsLoaded` (refusal is a pure function of live-conn count, "no Nimna registry state"); byte-verbatim payload forwarding throughout `server/server_test.go` + `channel_test.go`.
  - Nothing logged: `cmd/relay/logscrub_test.go :: TestLogScrub` + `logscrub_tls_test.go :: TestLogScrubTLS` (real binary, every plane + every limit, asserts zero identifiers/addresses/PEM in captured stdout+stderr+metrics).
  - Can't MITM pairing / can't forge HANGUP: cross-refs §9.4 (MITM) and §3.3.1 kill — `session_controller_test.dart :: a tampered transport frame kills the session (§3.3.1)`, `:: a HANGUP ends BOTH sides as "ended"`. A relay-injected HANGUP has no valid transport MAC.
- **GAP S18 must fill:** No explicit **statelessness / no-persistence** assertion — registry state is shown *unwound* on teardown (`server/limits_test.go :: TestLivenessAtServer`) but nothing asserts the relay writes nothing to disk. Add a consolidating assertion: run full flows, assert the process opens/writes no on-disk store (at-rest inventory = memory tables + TLS certs + push config only, per CLAUDE.md). Also add a consolidating **relay-forged-HANGUP-rejected** cross-stack assertion (relay injects a plausible HANGUP frame → receiver's Noise transport rejects it; no graceful-end forged).
- **Stack:** Go (+ one Dart cross-stack assertion). **Disposition:** CONSOLIDATE.

### §9.2 — Relay recovers code from topic ID (offline brute force): Argon2id t=3/m=64MiB + date salt
- **Already covered by:**
  - `internal/rendezvous/registry_test.go` derivation + `cmd/testclient/derive_test.go :: TestTopicSalt` (date-salt lock), `:: TestDerivationProduction` (production t=3/m=64MiB constants, not `-short`-skipped).
  - Dart side: `protocol/rendezvous_test.dart :: Argon2id constants match the committed protocol constants`, production-cost lane group; `protocol/pairing_code_test.dart` (topic-derivation vectors).
- **GAP S18 must fill:** Coverage is **correctness/vector-lock only** — it proves the derivation matches the vectors and runs at production cost, but there is **no assertion of the cost itself** (the ~thousand-server-years claim) and no daily-salt-rotation-defeats-precompute assertion. Add: a documented cost-parameter assertion (constants pinned to §3.1.2) + a test that two different `creation_date_utc` values yield disjoint salts (precomputed tables die daily). The brute-force *magnitude* is a doc claim, not host-testable → note in threat-model doc.
- **Stack:** Go + Dart + doc. **Disposition:** CONSOLIDATE (+ DOC for the magnitude claim).

### §9.3 — Network observer: TLS to relay + E2E within; sees only "talked to Nimna relay"
- **Already covered by:** `cmd/relay/logscrub_tls_test.go :: TestLogScrubTLS` (real TLS boot, wss://, self-signed P-256, failed-handshake IPs never logged). E2E inner layer covered by the whole Noise suite.
- **GAP S18 must fill:** None host-testable beyond TLS-present + E2E-present, both covered. The IP/timing/sizes residue is §9.9 below.
- **Stack:** doc. **Disposition:** DOC (acknowledged; the substantive residue is §9.9).

### §9.4 — Pairing-time MITM: needs code (psk); wrong code = one fail-closed attempt; can't grind safety phrase (commitment prologue); caught by phrase comparison (~1 in 2.1B)
- **Already covered by:**
  - MITM without code rejected: `noise/xxpsk2_pairing_test.dart :: code-less MITM (wrong psk) fails closed at M2`.
  - Commitment anti-grind: `noise/xxpsk2_pairing_test.dart :: lying M0 commitment is caught by the creator at M3` (adversarial); `noise/handshake_vectors_test.dart` recomputes commitment (honest-path lock).
  - Tamper: `:: tampered M4 is rejected`; transport `noise/noise_transport_test.dart :: a tampered ciphertext fails closed`, `:: wrong outer-header (ad) fails closed`.
  - Safety-phrase *agreement*: `xxpsk2_pairing_test.dart :: two devices pair end-to-end; identical CRID + safety phrase`.
- **GAP S18 must fill (TWO real gaps):**
  1. **No safety-phrase MISMATCH test.** Only agreement is asserted. Add a divergent-key/MITM scenario asserting the two computed 3-word phrases **differ** (the §3.1.4 out-of-band comparison working as an attack detector — the "~1 in 2.1B" defense).
  2. **No single-attempt / fail-closed §3.1.6 retry-limit test.** The wrong-PSK *cryptographic* abort is covered (M2 throws), but nothing asserts a wrong code gets **exactly one attempt** and the rendezvous/PSK is then burned (no second grind). Add a test at the pairing-controller level asserting one-shot / no-retry.
- **Stack:** Dart. **Disposition:** TEST.

### §9.5 — Relay-plane replay/forgery (KNOCK, ACCEPT, TEARDOWN): not crypto-protected (honest); bounded to nuisance; forged knock → bridge where impostor can't complete KK; rate limits cap
- **Already covered by:**
  - Malformed KNOCK closes: `internal/server/channel_test.go :: TestRow07MalformedKnockPayloadCloses` (registered + unregistered).
  - Forged-knock nuisance bounded: `channel_test.go :: TestRow05KnockFromUnregisteredSilentDrop`, `:: TestRow22KnockerDeathDeletesPendingLateAcceptSilent`, `:: TestRow20TeardownNotifiesOtherOnlyRegsSurvive`, `:: TestRow21DisconnectIsImplicitTeardown`, `:: TestRow23SimultaneousTeardown`.
  - Impostor can't complete KK on the bridge: `noise/session_kk_test.dart :: a wrong peer static key fails closed`.
  - Rate limits cap the nuisance: see §18-F below.
- **GAP S18 must fill:** No explicit **replay** test — the state-machine rows cover forgery/late-accept/teardown, but none *re-sends a previously valid frame* and asserts bounded consequence. Add a consolidating replay assertion: replay a captured KNOCK/ACCEPT/TEARDOWN and assert (a) it cannot forge decryptable content, (b) a forged-accepted bridge dies at the KK handshake, (c) rate limits absorb repeated replays. The "not cryptographically protected — stated honestly" framing goes in the threat-model doc.
- **Stack:** Go (+ doc). **Disposition:** CONSOLIDATE (+ DOC for the honest "unprotected inside TLS" statement).

### §9.6 — Peer's device seized: out of scope for protocol; mitigated by app lock, expiry, panic wipe
- **Already covered by:** app-lock `lock/lock_controller_test.dart`, `lock/pin_verifier_test.dart`, `ui/lock_gate_test.dart`; expiry `session_controller_test.dart :: a disappearing message mirrors purge_at...`; wipe `wipe/wipe_service_test.dart` (see §18-H).
- **GAP S18 must fill:** None new — this row is "out of scope for protocol," and the mitigations are each covered. Cross-refs §9.7 / §18-D / §18-H. The cold-boot forensics on a *physically seized, powered-off* handset is a hardware rung.
- **Stack:** doc. **Disposition:** LIMITATION — PUBLISH_READY device-QA step: *cold-boot disk forensics on a seized handset* (one of the 4 HOST-MAX hardware-bound rungs). Host proof of the encrypted-at-rest + wipe residue is §18-D/H.

### §9.7 — Your own device seized: app lock, encrypted-at-rest, panic wipe, no cloud backups; past sessions undecryptable even with statics (forward secrecy §7.3)
- **Already covered by:**
  - Encrypted-at-rest + wrong-key failure: `crypto/at_rest_aead_test.dart :: wrong key fails authentication` (+ tampered/truncated/wrong-nonce/wrong-AD suite); `storage/meta_records_test.dart :: ciphertext transplanted onto another key fails authentication`.
  - No plaintext on disk: `storage/storage_service_test.dart :: no plaintext marker or key material in any on-disk byte` (see §18-D).
  - No cloud backups: Keychain pin `storage/key_service_test.dart :: iOS keychain accessibility is pinned to first_unlock_this_device`; filesystem exclusion read-back `integration_test/app_boot_test.dart` (simulator + real-device).
  - Interrupted-wipe residue undecryptable: `wipe/wipe_service_test.dart :: interrupted wipe after step 1: every surviving ciphertext is undecryptable`.
- **GAP S18 must fill (real gap):** **No forward-secrecy assertion.** Nothing in either stack proves the §7.3 claim that a *past* session transcript stays undecryptable given the long-term static keys (fresh `ee` per KK handshake). Add a test: capture a completed session's transport frames, hand a fresh engine the static privates, assert the past frames **do not** decrypt (past-session non-recovery). Filesystem backup-exclusion `com_apple_backup_excludeItem` read-back exists only in the device-attached integration test — see disposition.
- **Stack:** Dart (forward-secrecy TEST). **Disposition:** TEST (forward secrecy) + LIMITATION (real-iPhone `isExcludedFromBackup` read-back = the S7 §7.3 rung deferred here, DECISIONS.md 2026-07-05 10:30; **run `integration_test/app_boot_test.dart` on the iOS simulator in S18 for the host-max half; real-iPhone attribute read-back = PUBLISH_READY device-QA step**).

### §9.8 — Counterpart captures content (screenshot detect-and-notify honor system; second camera undetectable, disclosed)
- **Already covered by:** screenshot notice must reach peer while live: `session/session_controller_test.dart :: screenshot round trip: CONTROL 0x03 → peer system line, own recorded`; no-op when not live: `:: screenshot notice is a no-op when the line is not live`; UI `screenshot/screenshot_widgets_test.dart`. See §18-E for suppression-honesty gap.
- **GAP S18 must fill:** The suppression-honesty gap is §18-E. Second-camera is undetectable-by-design → doc.
- **Stack:** Dart (see §18-E) + doc. **Disposition:** see §18-E. Second camera = DOC. The **OS screenshot keystroke event** on a physical device is a hardware rung → LIMITATION (PUBLISH_READY device-QA: real-device screenshot fires the OS API on iOS 17 / Android 14+).

### §9.9 — Metadata correlation (IP / timing / sizes): acknowledged v1 limitation; document honestly
- **Already covered by:** honest disclosure; sizes-are-disclosed-metadata is spec §1.6/§8. TLS present (§9.3).
- **GAP S18 must fill:** None testable — this is an accepted limitation by spec (no traffic padding/length hiding in v1, §8 non-goals). Must appear explicitly in the S18 threat-model doc.
- **Stack:** doc. **Disposition:** DOC (accepted limitation).

---

## Part B — Plan-§18 "new rows" (line 160)

### §18-A — Replay
Covered under §9.5 above. **Disposition:** CONSOLIDATE (Go) + DOC. Gap: explicit replay of a captured KNOCK/ACCEPT/TEARDOWN asserting bounded nuisance + dead bridge at KK.

### §18-B — MITM
Covered under §9.4 above. Genuinely well-covered at the crypto layer (S9). **Disposition:** TEST — the two real gaps are the **safety-phrase mismatch** test and the **single-attempt fail-closed §3.1.6** test (see §9.4). Everything else = CONSOLIDATE.

### §18-C — Malformed frames + fuzzing (relay AND app)
- **Already covered by (enumerated negatives, thorough but deterministic):**
  - Go outer frame: `internal/wire/wire_test.go :: TestParseInvalid` (short/empty/bad-version/unknown-type/**oversize**→ErrOversize), `:: TestParseValidBounds` (max-frame boundary).
  - Go KNOCK: `internal/wire/knock_test.go :: TestParseKnockPayloadInvalid` (bad length-prefix, LE/BE, over/under-run).
  - Go at the wire: `internal/server/server_test.go :: TestMalformedFrameCloses` (+ `:: TestTransportComplianceCloses` for WS rsv/opcode).
  - Dart outer frame: `protocol/outer_frame_test.dart :: strict rejects` group (short header, wrong version, unknown type, 16-byte routing-id).
  - Dart inner envelope: `protocol/inner_envelope_test.dart :: structural errors (each throws InnerEnvelopeError)` group (ver, undefined type, reserved flags, flag-on-wrong-type, truncations, bad body lengths, invalid UTF-8, reaction structural set) + `:: vector conformance` (valid:false → throws).
  - Dart token payload: `protocol/token_payload_test.dart :: malformation is rejected` group.
  - Dart transport kill: `session/session_controller_test.dart :: a tampered transport frame kills the session`, `:: an inbound TEXT with a non-UTF-8 body kills the session`.
- **GAP S18 must fill (real gaps — the plan explicitly asks for "fuzzing"):**
  1. **No native Go fuzz target anywhere** (`grep "func Fuzz" application/relay` → NONE). Add `FuzzParse` on the §5.4 outer-frame parser (`internal/wire`) and `FuzzParseKnockPayload` on the KNOCK parser — seed from `testdata/framing.json`, assert no panic on arbitrary bytes.
  2. **No Dart property/random-bytes fuzz** of the inner-envelope (§5.5–5.8) or outer-frame decoder. Coverage is entirely hand-enumerated. Add a seeded random-bytes harness asserting decode either returns a valid structure or throws the typed codec error — never crashes/hangs/allocates unbounded.
  3. **Dart outer-frame parser has no oversized/upper-bound rejection test** (Go has `oversize`→ErrOversize; Dart only tests the *lower* bound). Add a max-length/oversized-frame Dart rejection case.
- **Stack:** Go (2 fuzz targets) + Dart (fuzz harness + oversized case). **Disposition:** TEST.

### §18-D — Storage / backup inspection
- **Already covered by (genuine raw-byte forensic scans — verified `readAsBytesSync` over real files, not API round-trips):**
  - `storage/storage_service_test.dart :: no plaintext marker or key material in any on-disk byte` (scans DB + WAL/SHM + media blobs + diag for plaintext markers + MK/CDK/ownPriv as both hex and raw bytes; includes a canary self-test proving the scanner catches a real leak).
  - `storage/meta_records_test.dart :: value is ciphertext on disk and survives restart`.
  - `privacy/diag_marker_audit_test.dart :: diag log contains no content, keys, codes, or tokens` (raw scan + decoded-enum scan).
  - `diag/diag_export_test.dart :: render is enum-names + decimal ints + ISO timestamps only`.
  - Keychain non-migratable pin: `storage/key_service_test.dart :: iOS keychain accessibility is pinned to first_unlock_this_device`.
- **GAP S18 must fill:** The unit suite proves no-plaintext-on-disk strongly. The **filesystem `com_apple_backup_excludeItem` / `isExcludedFromBackup` read-back is NOT in the unit suite** — only in `integration_test/app_boot_test.dart` (device/simulator-attached). S18 host-max step: **run the integration test on the iOS simulator** to close the host half. Consider one consolidating scan that unifies the S13 storage-forensic assertions into the S18 adversarial doc. No net-new unit test strictly required for no-plaintext (already strong).
- **Stack:** Dart (run integration_test on simulator) + doc. **Disposition:** CONSOLIDATE + LIMITATION (real-iPhone attribute read-back = PUBLISH_READY, same rung as §9.7).

### §18-E — Screenshot-notice suppression honesty
- **Already covered by:** positive obligation — `session/session_controller_test.dart :: screenshot round trip: CONTROL 0x03 → peer system line` (peer receives exactly one notice, `own==false`, over the real wire); correctly-suppressed-only-when-not-live `:: screenshot notice is a no-op when the line is not live`.
- **GAP S18 must fill (real gap — this is the "suppression HONESTY" ask):** No test proves the notice **cannot be silently suppressed while live** — there is no assertion that emission-to-peer is unconditional with no user/config toggle to disable it. Add a test that drives a screenshot on a live line under every relevant setting/state and asserts the CONTROL 0x03 always emits (a hostile/misconfigured sender cannot screenshot silently). Note: the Android <14 detection-floor gap (DECISIONS.md 2026-07-08 S14) is a *disclosed* limitation, not a suppression bug — verify the onboarding caveat copy honesty as part of this row.
- **Stack:** Dart. **Disposition:** TEST + LIMITATION (the **OS screenshot keystroke on a physical device** = PUBLISH_READY device-QA; Android <14 no-notice is disclosed, verify copy).

### §18-F — Push-bombing vs rate limits (at exact configured values)
- **Already covered by (boundary-exact, fake-clock, at spec-default values):**
  - Knock collapse **1 per 10s/CRID**: `internal/limits/ratetable_test.go :: TestKnockCollapseBoundary` (9.999s collapsed, exactly 10.000s allowed); wire `internal/server/limits_test.go :: TestKnockCollapseAtWire`.
  - Push min-interval **1 per 60s/CRID**: `ratetable_test.go :: TestPushMinIntervalBoundary`; wire `:: TestPushMinIntervalAtWire`.
  - Push **6/hour/CRID**: `ratetable_test.go :: TestPushHourCap` (7th denied, rolls at exactly 1h).
  - Push **20/day (24h)/CRID**: `ratetable_test.go :: TestPushDayCap` (21st denied, rolls at exactly 24h). (Plan text says "20-day"; actual spec = 20 per 24h.)
  - Per-IP frame window **6/min**: `internal/limits/ipwindow_test.go :: TestIPWindowLimit` + `:: TestIPWindowBoundary`.
  - Per-IP conn cap, rate-table hard cap (fail-open knock / fail-closed push): `internal/limits/listener_test.go :: TestPerIPCapZeroBytes`, `ratetable_test.go :: TestRateTableCap`.
  - Every limit trips under CI capture: `cmd/relay/logscrub_test.go :: TestLogScrub` (Phase A+B).
- **GAP S18 must fill:** Essentially none on the relay — this is the best-covered row, at exact boundary values. S18 adds one consolidating **push-bomb burst** assertion (rapid-fire knocks from one CRID → assert relay throttles at the exact 6/hr + 20/day caps and the client is never wedged). Client-side: verify the app surfaces no crash under a push burst.
- **Stack:** Go (consolidate). **Disposition:** CONSOLIDATE + LIMITATION (**push *delivery* to a locked physical device** = PUBLISH_READY device-QA, absorbs S6 DEFERRAL-2 / S15 live-APNs-FCM deferral, DECISIONS.md 2026-07-08 S15 intake).

### §18-G — EXIF-strip verification
- **Already covered by:** `media/image_processor_test.dart :: processing strips ALL EXIF (GPS/make/time) and keeps pixels` (real `package:image` pipeline, not mocked; asserts `exif.isEmpty`, `Make==null`, **`gpsLatitude==null`**) with a genuine precondition `:: precondition: the fixture actually carries EXIF`; `:: original-quality path also strips EXIF`. Fence: `media/media_fences_test.dart :: package:image is imported only by image_processor.dart`.
- **GAP S18 must fill (real gap — the S11 NIT):** **XMP and ICC are NOT asserted stripped.** `grep -ri "xmp\|iccprofile" lib test` → NONE. `exif.isEmpty` only covers the EXIF IFD; the test name "strips ALL" overstates it. Add: feed an image carrying an **XMP packet + ICC profile** through the real processor and assert both are gone (or documented if the `image` package re-emits a default sRGB ICC — then assert no *original* profile survives). GPS/EXIF are covered; XMP/ICC are the concrete missing assertions.
- **Stack:** Dart. **Disposition:** TEST + LIMITATION (**real-camera EXIF capture on a physical phone** = PUBLISH_READY device-QA; host proof uses a synthetic-metadata fixture).

### §18-H — Wipe forensics
- **Already covered by (genuine raw-byte residue scans):**
  - `wipe/wipe_service_test.dart :: full wipe: keystore + lock config destroyed, zero residual markers, reopened fresh-install state` (recursive raw-byte scan after fullWipe; re-minted MK≠old; no `channelWiped` tell-event → fresh-install-indistinguishable).
  - `:: destruction ORDER: keystore entry dies before any file deletion`.
  - `:: interrupted wipe after step 1: every surviving ciphertext is undecryptable` (raw rows fail `cipher.open` with AeadAuthError under a fresh MK).
  - `:: per-channel wipe: pre-wipe hook fires first, only that channel dies` (raw scan confirms A's markers gone, B readable).
  - `storage/storage_service_test.dart :: full wipe: fresh empty store, new master key, no trace`, `:: AeadAuthError on open → SILENT fresh-install-reset`.
- **GAP S18 must fill:** Strongly covered at host level — the full-wipe scan runs over a *recreated empty* tree, while the per-channel and interrupted-wipe scans prove marker-absence when files *do* survive. S18 adds one consolidating adversarial residue-scan doc entry unifying these. No net-new host test strictly required.
- **Stack:** Dart (consolidate) + doc. **Disposition:** CONSOLIDATE + LIMITATION (**cold-boot disk forensics on a seized handset** = PUBLISH_READY device-QA, same rung as §9.6).

### §18-I (USER scope addition, DECISIONS.md 2026-07-05 02:20) — Noise-engine test oracle (flynn/noise class), test-only
- **Already covered by:** Byte-for-byte vector locks of the hand-rolled engines: `noise/handshake_vectors_test.dart` (XXpsk2), `noise/session_kk_test.dart :: KK S1/S2 + Split lock byte-for-byte`, plus the Go engine's own vector conformance. `grep -ri "flynn/noise\|oracle" application` → NONE (only spec-doc prose mentions "test oracle").
- **GAP S18 must fill (real gap — not yet built):** No independent cross-implementation oracle exists. Build a **test-only** Go harness that runs an established Go Noise library (flynn/noise class) as an oracle for the XXpsk2 + KK transcripts, cross-checking the hand-rolled Go engine's messages/keys. flynn/noise is a **test-only** dependency — never in the runtime tree (CLAUDE.md crypto bar; DECISIONS.md 2026-07-05). The Dart engine is validated transitively (it is already byte-locked to the same committed vectors the Go engine and oracle agree on).
- **Stack:** Go (test-only). **Disposition:** TEST.

---

## Summary — what each column owner builds in S18

**Go dev (TEST):**
1. `FuzzParse` native fuzz target — §5.4 outer-frame parser (`internal/wire`), seeded from `testdata/framing.json`. (§18-C)
2. `FuzzParseKnockPayload` native fuzz target — KNOCK parser. (§18-C)
3. flynn/noise **test-only** oracle harness cross-verifying the Go XXpsk2 + KK engines. (§18-I)

**Go dev (CONSOLIDATE — one assertion each, no rework):**
4. Relay statelessness / no-disk-persistence + relay-forged-HANGUP-rejected. (§9.1)
5. Argon2id daily-salt-disjoint + cost-constant pin. (§9.2)
6. Replay of KNOCK/ACCEPT/TEARDOWN → bounded nuisance + dead bridge. (§9.5/§18-A)
7. Push-bomb burst throttled at exact 6/hr + 20/day caps, client not wedged. (§18-F)

**Flutter dev (TEST):**
1. Safety-phrase **mismatch** (divergent-key MITM → phrases differ). (§9.4/§18-B)
2. Single-attempt / fail-closed **§3.1.6** (wrong code = one attempt, PSK burned). (§9.4/§18-B)
3. **Forward-secrecy** (§7.3): past session frames don't decrypt given the statics. (§9.7)
4. Dart property/random-bytes **fuzz** harness for inner-envelope + outer-frame codecs. (§18-C)
5. Dart outer-frame **oversized/upper-bound** rejection case. (§18-C)
6. Screenshot-notice **non-suppressibility** while live (no toggle silences it). (§18-E)
7. **XMP + ICC** strip assertion through the real image pipeline (S11 NIT). (§18-G)

**Flutter dev (CONSOLIDATE / run):**
8. Run `integration_test/app_boot_test.dart` on the iOS simulator (backup-exclusion host half). (§18-D/§9.7)
9. Consolidating wipe-residue + storage-forensic doc entries. (§18-D/§18-H)

**Doc (threat-model doc):** §9.3 network observer, §9.9 metadata correlation, §9.5 "unprotected inside TLS" honesty, §9.2 brute-force magnitude claim, second-camera undetectability (§9.8).

**LIMITATION — PUBLISH_READY device-QA hand-steps (the 4 HOST-MAX hardware-bound rungs, DECISIONS.md 2026-07-08 S18 intake):**
- Real-camera EXIF capture on a physical phone (§18-G host proof uses synthetic fixture).
- OS screenshot keystroke event on iOS 17 / Android 14+ device (§18-E/§9.8).
- Push delivery to a locked physical device — live APNs/FCM (§18-F/§9.8; absorbs S6/S15 deferral).
- Cold-boot disk forensics on a seized handset + real-iPhone `isExcludedFromBackup` read-back (§9.6/§9.7/§18-D/§18-H).

**USER-level decisions surfaced:** none beyond the already-settled HOST-MAX call (DECISIONS.md 2026-07-08 S18 intake). No done-check clause is softened; the four hardware rungs are documented accepted limitations per that decision, not S18 blockers.
