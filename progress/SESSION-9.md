# SESSION 9 — Pairing: joiner side & handshake (G2, ∥ S17)

Worktree `session-9-pairing-joiner`, branched off main. Sole protocol-envelope
session in flight; codec freezes at S10. Append here during the session; the
orchestrator folds into canonical TASKS/PROGRESS/DECISIONS at merge.

## Intake (architect, 2026-07-07 12:24 +0200)

**Owns:** `lib/src/noise` (from-spec XXpsk2 engine, NO Noise library — settled
S2), `lib/src/pairing/joiner` (sibling to `initiator/`, sharing only pure
`protocol/`+`transport/`+`noise/`), pairing-plane slices in `lib/src/protocol`
(M0–M4 payloads, CRID §3.1.5, safety-phrase §3.1.4, token_payload §5.7).
**Implements NO §5.5–§5.8 inner-envelope codec — that is S10's, keep the
checkpoint clean.** Owes no new vectors (locks against already-committed
`docs/test-vectors/pairing-handshake.json` / `phrase-words.json` /
`cacophony-*.json`).

**Handshake needs ZERO new crypto/network deps** — composed from already-signed-off
`sodium` sumo (`crypto_scalarmult` DH, `crypto_aead_chacha20poly1305_ietf_*`),
`package:crypto` SHA-256, in-repo `lib/src/crypto/hkdf.dart`. XXpsk2 pattern
`→e · ←e,ee,s,es,psk · →s,se`; M0 commitment `SHA-256("nimna/commit/v1"‖eB_pub‖sB_pub)`
as prologue; code-psk mix at psk2; M4 PAIR_CONFIRM (ChaCha20-Poly1305, §5.6);
fail-closed wipe on any failure (§3.1.6). Joiner = Noise initiator (sends M1 on
`TOPIC_BRIDGED`); two Argon2id derivations (today, then yesterday) per §3.1.2,
on-main-isolate per S8 precedent.

**Four join methods** funnel through `PairingCode.canonicalize` (built): manual
XXX-XXX-XXX auto-advancing field; paste (`Clipboard`, no dep); live QR scan; upload
image **or PDF**. Safety-phrase screen (F3.4) two buttons only, **no skip**
(settled). Self-join guard consumes DS surface: canonicalized input vs
`PendingPairingStore.readAll()` (own OUTSTANDING codes only) → `pairing_selfJoinOwnCode`
(canonical, warning-toned, shake-free). Silence doctrine: every non-bridging
outcome → the one generic F3.6/F3.7 string after the joiner's own no-answer timeout.

## Decisions carried in

- **USER 2026-07-07 12:24 — phrase mismatch = LOCAL-ONLY discard.** "They don't
  match" silently discards the just-finalized channel on the declining device; no
  peer wire signal (protocol destroys pairing state + kills topic at M4). **Persist
  the channel only AFTER "They match"** so a decline leaves nothing to un-persist.
  **Reconcile F3.4 copy** — design's "the confirming side is told 'They said the
  words didn't match.'" overreaches the protocol; reword to drop the peer-notification
  claim (flag to PM/design-sync).
- **CODE — TTL-vs-handshake-window boundary:** TTL is a pre-bridge registration gate
  only. Cancel the TTL/no-answer timer at `TOPIC_BRIDGED`; from bridge onward the only
  terminal states are handshake success (valid M4) or handshake/bridge failure
  (§3.1.6 fail-closed discard). Do NOT abort a progressing handshake on a mid-flight
  TTL crossing. Coordinate the initiator side: cancel `CreateLineController._expiryTimer`
  on entry to `bridged` (fold into the write-seam edit below).
- **CODE — post-unlock pending-pairing resume hook (`// TODO(S9)`):** extract the
  boot-time `pending_pairings` read into a one-shot `loadPendingPairing(...)`; run it at
  boot when `storage.isOpen` (lock-disabled, unchanged) AND on the first sealed→unsealed
  `LockController` transition via a one-shot listener attached in `bootstrap.dart` (body
  gated on `storage.isOpen`). Idempotency latch — fire exactly once (guard against a
  stale re-adopt of a consumed one-shot entry). Confine the edit to `bootstrap.dart`;
  fallback = an additive `onFirstUnlock` callback on `LockController` only if no
  observable transition exists.

## Dependency proposals (pending pin-time no-telemetry audit — HARD gate)

- `mobile_scanner` — live QR scan + still-image decode (`analyzeImage`). Pin the
  **bundled MLKit** variant (avoid `play-services-mlkit-*` telemetry surface); prove
  zero network + zero analytics in the tree. Escalate to USER only if the bundled
  variant is unavailable / a phone-home is unavoidable. Fence: ONE module
  `join_entry/qr_source.dart`; camera-permission copy = F3.2 canonical.
- `file_picker` — OS picker, image or PDF (`FileType.custom`). CODE + health check. ONE call site.
- `pdfrx` (or `pdfx`) — rasterize PDF page 1 → image → `analyzeImage`. CODE + health check. ONE call site.
- PDF support is spec-mandated (§3.1 step 3 method iv); rasterizer choice is CODE.

## Cross-lane / risks

- **[TOP] Write-seam on `initiator_controller.dart`:** the creator's responder engine
  needs a send path (S8 left `_conn.send` private). Add a minimal
  `attachResponder(...)` / send-callback+frame-stream seam; responder logic lives in
  `lib/src/noise`. Edits an initiator-tree file — but S17's gate is in
  `create_line_entry.dart`, NOT `initiator_controller.dart`, so G2 file-disjointness
  HOLDS. Fold the TTL-timer-cancel-at-bridge change into this same edit.
- **Codec checkpoint:** `lib/src/protocol` additions are pairing-plane ONLY; no
  §5.5–§5.8 codec (S10's) — review-enforceable.
- **S15 edge:** E2E-carry `token_payload` in M2/M3 (present when push enabled, `0x00`
  absent otherwise) + store peer token at finalization, even though S9 ships push-off,
  so S15 has nothing to retrofit.
- **`crypto_pwhash` fence** already sanctions two sites; joiner reuses `deriveRendezvous`
  → no new pwhash site. Sumo `crypto_scalarmult` for Noise DH = new FFI use of a
  signed-off primitive; keep inside `lib/src/noise`, flag for reviewer attention.
- **ARB:** namespace `pairing_*`; `pairing_selfJoinOwnCode` is DS-delivered canonical —
  do not re-author. Fold at merge.

## Done-check (from plan)

Two devices pair end-to-end via each join method; MITM test vector rejected; phrase
screen matches design-loop artifacts.

---

## Implementation (mobile dev, 2026-07-07)

Full suite **252 tests green** (all lanes incl. `production-cost`),
`flutter analyze` clean, `dart format` clean. Handshake byte-locked to the
committed vectors on first run.

### What was built

**1. `lib/src/noise/` — from-spec XXpsk2 engine (NO Noise library).**
`cipher_state.dart` (CipherState + handshake nonce), `symmetric_state.dart`
(ck/h/cipher; MixKey/MixHash/MixKeyAndHash/Enc/DecAndHash/Split over the
in-repo RFC 5869 HKDF), `dh.dart` (X25519 — the SOLE `crypto_scalarmult`
site, fenced here), `handshake_state.dart` (token processor with the PSK
`e`-MixKey rule, §9.2), `xxpsk2.dart` (the two role drivers: joiner
initiator + creator responder, M0 prologue, code-psk, M4 PAIR_CONFIRM §5.6,
fail-closed wipe §3.1.6, `PairingChannelMaterial` at finalization).
Byte-locked to `pairing-handshake.json`: every key, message byte, per-step
ck+h, Split key, M4, CRID, phrase — both transcripts, both roles.

**2. `lib/src/protocol/` pairing-plane slices ONLY.** `commitment.dart`
(M0 §3.1.3), `token_payload.dart` (§5.7 codec), `channel_identity.dart`
(CRID §3.1.5 + safety phrase §3.1.4 from `ss` + salt2; uint64→base-1296 via
BigInt so the full-uint64 vector case is exact). `ss` is computed once in
`lib/src/noise` (scalarmult stays there) and passed in as bytes, keeping
these pure. **No §5.5–§5.8 inner-envelope codec** (codec checkpoint held).

**3. `lib/src/pairing/joiner/`.** `join_controller.dart` (F3 state machine:
entry → joining → verify → naming → done; mismatch on decline; joiner =
Noise initiator; two Argon2id derivations today→yesterday, both registered
up front on the main isolate; self-join guard reads the pending store; the
one generic no-answer response after the joiner's own timeout). Persists the
channel **only after "They match"**; **"They don't match" = LOCAL-ONLY
silent discard** (no peer wire signal — the relay connection is already
closed at handshake completion; nothing persisted, nothing to un-persist).
`joiner_service.dart` (DI bundle), `safety_phrase_wordlist.dart` (loads the
pinned EFF wordlist asset, SHA-256-verified fail-closed), and the two fenced
join-method sources `join_entry/qr_source.dart` (mobile_scanner) +
`join_entry/upload_source.dart` (file_picker + pdfrx). All four methods
funnel through `PairingCode.canonicalize` / `.fromScannedPayload` (§3.1.1).
Peer device-token stored at finalization (§3.2.1) so S15 needs no retrofit.

**4. Write-seam on `initiator_controller.dart` (the ONLY initiator-tree file
edited).** Added an opt-in `attachResponder(onComplete, onFailed)` seam: the
from-spec responder engine (in `lib/src/noise`) drives M2/M4 over the bridge;
the TTL timer is cancelled at the bridge (TTL is a pre-bridge gate only —
`checkExpiryNow` now expires in `waiting` only). **Absent an attached
responder, behavior is exactly S8's** (buffer PAIR_DATA, fabricate nothing),
so every S8 test passes unchanged. `create_line_entry.dart` NOT touched.

**5. Post-unlock pending-pairing resume hook (`bootstrap.dart` only).**
Extracted the boot `pending_pairings` read into a one-shot `loadPendingPairing`
with an idempotency latch; runs at boot when `storage.isOpen` AND on the
first sealed→unsealed `LockController` transition (one-shot listener; the
`locked` getter + unlock notification are the observable transition, so no
`onFirstUnlock` fallback was needed).

**6. UI (F3).** `join_line_flow.dart` (host + entry/handshake/verify/name/
mismatch screens), `join_scan_screen.dart` (F3.2), `code_field.dart`
(segmented XXX-XXX-XXX auto-advancing field). All copy is canonical ARB
(`pairing_*`, 30 new EN keys folded; DE/FR/ES/IT ride the S16 pass + the
untranslated tracker). Channel-list "Enter a code" wired to `startJoinLine`
(never paywalled).

### Dependencies — pin-time no-telemetry audit: **PASS**

`flutter pub deps` + grep found **zero** firebase/analytics/crashlytics/
telemetry/beacon in the tree. `mobile_scanner` 7.2.0 defaults to the
**bundled on-device MLKit** (`com.google.mlkit:barcode-scanning`; we do NOT
set `useUnbundled`) — not the play-services variant. `pdfrx`'s transitive
`http` serves only its remote-URL loading API, which Nimna never invokes (we
rasterize a locally-picked file). Added: `mobile_scanner: 7.2.0`,
`file_picker: 11.0.2`, `pdfrx: 2.4.4`, each fenced to ONE module. Dep note
folded into `docs/architecture/app-architecture.md §1`.

- **`dependency_overrides: win32: ^5.14.0` (CODE, flagged):** file_picker
  11's Windows COM picker needs win32 5.x symbols that win32 6.x drops, while
  share_plus ^13.2 declares ^6.0.1. Nimna ships iOS/Android only (win32 never
  compiled/linked), but `flutter test` compiles every plugin's desktop impl
  on the host, so both must at least COMPILE — the 5.x line satisfies
  file_picker and share_plus compiles against it. Touches no crypto/network
  dep. Revisit when the two realign on win32 6.x.

### New tests (all green)

`test/noise/handshake_vectors_test.dart` (full XXpsk2 byte-lock, both
transcripts), `xxpsk2_pairing_test.dart` (end-to-end pairing + **MITM
(wrong-psk) / tampered-M4 / lying-commitment** rejections),
`test/protocol/token_payload_test.dart` (§5.7 vectors + round-trip +
malformation), `channel_identity_test.dart` (phrase-words mapping incl. the
BigInt path), `test/pairing/join_methods_test.dart` (the four methods
converge), `join_controller_test.dart` (the F3 machine driven against a REAL
responder engine: handshake → matching phrase → persisted channel + stored
peer token; self-join; no-answer; fail-closed spent; local-only mismatch
discard; offline), `test/app/bootstrap_resume_test.dart` (both resume-hook
paths + idempotency). The S8 `single_call_site` codec fence was widened to
allow §5.7 `TokenPayload` while still forbidding the §5.5–§5.8 inner
envelope; `shell_test` updated ("Enter a code" now live).

### Codec checkpoint: **HELD.** `lib/src/protocol` gained only pairing-plane
slices (M0, §5.7 token_payload, CRID, safety phrase). No §5.5–§5.8 inner
envelope, no nonce/key transport discipline, no reaction/reply codec. The
fence test enforces it.

### FLAGS

- **[DESIGN-SYNC — do NOT edit designs/ myself] F3.4 edge copy overreach.**
  The wireframe's F3.4 edge annotation claims "the confirming side is told
  'They said the words didn't match. This pairing was thrown away.'" The app
  renders **no peer-notification string** (USER 2026-07-07: mismatch is a
  local-only discard, no peer wire signal). The declining device shows the
  canonical F2.9-equivalent local copy ("The words didn't match." / "…thrown
  away — nothing was kept."), which is doctrine-clean. **Reword the F3.4 edge
  annotation to drop the peer-notification claim.** Secondary nuance flagged
  for the same sync: F2.9's "Make a new code and share it somewhere safer"
  CTA is creator-oriented; the joiner's mismatch screen uses the canonical
  **"Go back"** verb instead (the joiner joins, it does not create codes).

- **[REVIEWER/QA] Creator-side finalization is out of S9 scope.** The write-
  seam lets the creator's responder complete the handshake and hold
  `PairingChannelMaterial`, but the creator's F2.6 safety-phrase / F2.7 name
  / channel-persist UI is NOT built here (a later session). End-to-end pairing
  is proven at the engine + joiner-controller level; the creator controller
  reaches handshake completion holding material (not persisted).

- **[QA — device pass] Native join-method glue** (`qr_source.dart` camera +
  `analyzeImage`, `upload_source.dart` file_picker + pdfrx raster) cannot run
  under `flutter test`; the canonicalization it feeds IS unit-tested, but the
  camera/picker/PDF-raster paths and the win32-override desktop-compile need a
  real-device / built-app QA pass. Join-flow **widget** tests were not added
  (the controller logic is exhaustively covered; the UI is thin) — a
  reasonable follow-up if the reviewer wants widget-level coverage of F3.

- **[MERGE FOLD] ARB:** 30 `pairing_*` EN keys added to `lib/l10n/app_en.arb`;
  namespaced, canonical. `pairing_selfJoinOwnCode` reused verbatim from the DS
  handoff (not re-authored). Two new diag events (`pairingFinalized`,
  `pairingHandshakeFailed`) appended to the closed vocabulary.
