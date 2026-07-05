# App architecture note — Sessions 7–17

**Author:** tech-architect · **Date:** 2026-07-05 (Session 7 / Phase-2
intake; amended 2026-07-05 at the S7 implementation review — ACKed
deviations folded in where they land; later session intakes append, never
rewrite) ·
**Binding for:** `application/mobile/` implementation, Sessions 7–17.
**Sources:** spec `docs/nimna-protocol-spec-v0.2.1.md` (§3.1.4, §3.1.5,
§5.1, §6, §6.1, §7, §10 — §6/§6.1/§7 verified byte-identical to v0.2 at
the S7 review; the v0.2.1 additions have zero S7 storage/crypto surface),
`docs/crypto-evaluation.md` §11.2, DECISIONS.md S1/S2
entries + the i18n scope entry (2026-07-04), the work-loop LOGGING &
OBSERVABILITY DOCTRINE and DEPENDENCY DISCIPLINE,
`designs/handoff/flutter-notes.md` (binding UI notes),
`designs/system/tokens.json` v1.1.0, `designs/brand/voice-and-microcopy.md`.
All decisions here are CODE decisions unless marked otherwise. Package
health facts verified against pub.dev on 2026-07-05.

---

## 1. Dependencies (S7 set — architect sign-off per dep)

Runtime (all version-pinned in pubspec with caret on the verified version;
`flutter pub get` resolution is committed via pubspec.lock):

- **`sodium` ^4.0.2 — sign-off GIVEN (extends the S2 sign-off to at-rest
  use).** libsodium FFI; S7 uses `randombytes` (master/record key + nonce
  generation), `crypto_aead_chacha20poly1305_ietf` (the locked AEAD, §2),
  and `SecureKey` (native-memory key storage with explicit zeroing — the
  panic-wipe substrate). **As-shipped fact (ACKed at S7 review):** the
  package's *high-level Dart API* exposes only the original-nonce
  ChaCha20-Poly1305 and XChaCha20 — neither is the locked IETF
  construction — so the IETF AEAD is reached through the package's public
  FFI wrapper (`package:sodium/sodium.ffi.dart`) with marshalling-only
  pointer glue in `lib/src/crypto/at_rest_aead.dart` (~150 lines;
  adjudication in §2). S7 needs only standard-variant APIs; the S2 note's
  sumo verification (scalarmult/pwhash) still lands with S8/S9 protocol
  work. **Day-one spike required:** confirm `flutter test` on the CI
  runner builds/loads the libsodium native asset (v4 uses Dart build
  hooks, stable since Dart 3.10; we pin 3.12). If host tests can't load
  it, the fallback is installing libsodium on the runner and using the
  binding's manual-load path — never a Dart reimplementation.
- **`crypto` ^3.0.7 (dart.dev) — sign-off GIVEN (S2).** SHA-256 /
  HMAC-SHA-256. The in-repo HKDF-SHA-256 composition (RFC 5869, ~10
  lines) planned for S9 is pulled forward to S7 — key derivation (§3)
  needs it. It lands vector-locked in S7: RFC 5869 Appendix A vectors +
  RFC 4231 HMAC vectors, byte-cross-checked against the Go stdlib values
  already committed in `docs/test-vectors/`.
- **`sqflite` ^2.4.3 (tekartik) — sign-off GIVEN** (persistence-touching).
  SQLite via the platform's own library; the boring community standard
  (5.5k likes, ~2.5M downloads/30d, actively maintained). It stores only
  ciphertext blobs and integers (§4) — no crypto inside the dependency.
  Rejected: **drift** (codegen + build_runner dev-tree for typed queries
  we cannot use over ciphertext), **isar/hive** (custom storage formats,
  heavier or maintenance-uncertain), **sembast** (would still need our
  AEAD, less boring than SQLite for message volume),
  **sqflite_sqlcipher/SQLCipher** (§2 — crypto-lock violation and a
  second native crypto stack).
- **`flutter_secure_storage` ^10.3.1 — sign-off GIVEN, scoped:** used for
  exactly ONE item — the wrapped 32-byte master key (§3). iOS backend =
  Keychain with pinned accessibility `first_unlock_this_device`
  (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly); Android backend =
  Android-Keystore-resident wrap keys (RSA-OAEP + AES-GCM in v10) over an
  app-private blob. 4.5k likes, ~3.2M downloads/30d. Rejected: hand-written
  Keychain/Keystore platform channels (~150 lines we'd own, rediscovering
  vendor Keystore quirks the package has already absorbed; the package is
  the more-audited path). The general-purpose API surface is fenced by
  code review: one call site, in `src/storage/keys/`.
- **`path_provider` ^2.1.6 (flutter.dev) — sign-off GIVEN.** Directory
  resolution only.
- **`path` (dart.dev)** — path joins; already transitive via sqflite,
  imported directly. Sign-off GIVEN.
- **`flutter_localizations` (SDK) + `intl: any`** (version dictated by the
  SDK pin, per Flutter guidance) + `gen_l10n` via `l10n.yaml`. Sign-off
  GIVEN (SDK-owned).
- **`cupertino_icons` — REMOVED** from pubspec (skeleton residue; iconography
  is CustomPainter per the design system).

Dev-only: `flutter_test`, `integration_test` (both SDK), `flutter_lints`
(existing), and **`sqflite_common_ffi` ^2.3.7 (resolves 2.4.2, tekartik —
sign-off GIVEN at S7 review, DEV-ONLY):** host-side SQLite so the DB
marker-absence scans and restart-persistence tests run under plain
`flutter test`/CI; `dev_dependencies` never enter the app binary
(pubspec.lock records it as `direct dev` — reviewer keeps it there). No
codegen packages.

**Explicitly NOT in S7** (each waits for its session's intake +
sign-off): qr_flutter, mobile_scanner, image/file pickers,
flutter_image_compress, share_plus (S8/S9/S11), local_auth (S13),
platform push integration (S15 — note ahead: `firebase_messaging` named
in flutter-notes is **not pre-approved**; the S15 intake evaluates it
against the no-telemetry doctrine and the content-free contract, and
Android has no FCM-less alternative to weigh it against — expect a
tightly-scoped sign-off decision then). **No Firebase anything at S7.**
**google_fonts REJECTED permanently** (§8.5).

## 2. At-rest encryption — inside the crypto lock (adjudication)

**Decision: all Nimna-authored at-rest encryption uses the S2-locked
primitives and nothing else** — ChaCha20-Poly1305 **IETF** (96-bit nonce,
RFC 8439) via libsodium for record/file AEAD, HKDF-SHA-256 for key
derivation, libsodium `randombytes` for keys/nonces. No USER question is
needed because no deviation is taken.

- **SQLCipher REJECTED:** its cryptography (AES-256-CBC + HMAC page
  encryption) is outside the locked suite — adopting it would be a USER
  exception to an explicitly locked decision, for which the only payoff
  is SQL-visible plaintext columns we don't want anyway (§4). It would
  also add a second native crypto stack beside libsodium. Not escalated:
  the in-lock design is superior on its own merits, not merely compliant.
- **XChaCha20 / secretbox / secretstream REJECTED:** libsodium's natural
  file APIs (`crypto_secretstream_xchacha20poly1305`, `crypto_secretbox`)
  are XChaCha20/XSalsa20 constructions — **not** the locked IETF AEAD.
  Convenient, but a silent deviation; we do not take it. Large blobs are
  bounded at 5 MB by spec §5.1, so single-shot IETF AEAD is sufficient
  (§5) and no streaming construction is needed.
- **Adjudication (S7 review, verified in code): reaching the IETF AEAD via
  the `sodium` package's public FFI wrapper is NOT hand-rolled crypto.**
  The binding's high-level API omits the IETF variant, so
  `lib/src/crypto/at_rest_aead.dart` calls
  `crypto_aead_chacha20poly1305_ietf_encrypt/decrypt` directly through
  `package:sodium/sodium.ffi.dart` — audited libsodium computes every
  cryptographic byte; the Dart file is pointer marshalling in
  sodium-guarded native memory only, with zero crypto arithmetic.
  Correctness is locked by the RFC 8439 §2.8.2 vector test plus wrong-key/
  wrong-nonce/wrong-AD/tamper/truncation negatives
  (`test/crypto/at_rest_aead_test.dart`). Fence: this file is the ONLY
  FFI-level crypto surface in the app — any future primitive access goes
  through it or gets its own adjudication here; reviewer audits the fence
  each session. (The in-file constant assertions are debug-only `assert`s
  — defensive; the vector test is the guarantee.) Alternatives rejected:
  the high-level original-nonce/XChaCha APIs (lock violation), a second
  crypto dependency exposing IETF (needless surface), waiting on upstream
  (blocks S7).
- **Record format (normative):** stored value = `nonce(12) ‖ ct`, where
  `ct = ChaCha20-Poly1305-IETF(key = k_rec, nonce, ad, plaintext)`.
  `ad = "nimna/app/ad/v1" ‖ store_id(1) ‖ schema_ver(1) ‖ record_id(16)`
  — every ciphertext is bound to its store, schema epoch, and row;
  cross-row/cross-store ciphertext transplants fail authentication.
  Store ids: 0x01 channels · 0x02 messages · 0x03 media-index ·
  0x04 media-blob · 0x05 diag · 0x06 meta.
- **Nonce discipline (two independent belts):** (1) record keys are
  unique per record by derivation (§3), so a nonce can never repeat
  across records even in principle; (2) every *write* additionally draws
  a fresh random 12-byte nonce, covering rewrites of the same record.
  Rewrite counts per record are tiny (settings updates, delivery-state
  changes), so random 96-bit nonces under a per-record key are far below
  any collision bound.
- **Label namespace:** all app-storage HKDF info strings live under
  `nimna/app/…` — structurally disjoint from the protocol's
  `nimna/topic|psk|phrase|crid/…` namespace. App-storage derivations can
  never collide with protocol derivations.
- **Honesty note (memory):** SecureKey zeroing covers *key material*.
  Decrypted content in Dart heap (message text in widgets) is GC-managed
  and not zeroizable — the same accepted class as every mobile messenger.
  The audited at-rest claim is precisely: nothing readable on disk
  without the keystore-held key.

## 3. Key hierarchy, keystore integration, wipe & lock perimeter

```
platform keystore (iOS Keychain / Android Keystore)
  └─ MK  master key, 32 random bytes, generated at first launch
       ├─ k_channels = HKDF(MK, info="nimna/app/store/v1/channels")
       ├─ k_media_ix = HKDF(MK, info="nimna/app/store/v1/media-index")
       ├─ k_diag     = HKDF(MK, info="nimna/app/store/v1/diag")
       ├─ k_meta     = HKDF(MK, info="nimna/app/store/v1/meta")
       └─ (messages & media blobs key off each channel's CDK, below)
channel record (ciphertext) contains
  └─ CDK  channel data key, 32 random bytes, minted at channel creation
       └─ k_rec = HKDF(CDK, info="nimna/app/rec/v1" ‖ record_id)   # msgs+media
channel-store / index / diag / meta records:
       k_rec = HKDF(k_store, info="nimna/app/rec/v1" ‖ record_id)
```

(HKDF salt = empty throughout, RFC 5869 default — matches protocol
convention; all labels ASCII, no terminators; record_id = 16 random bytes.)

- **iOS:** MK lives in the Keychain via flutter_secure_storage with
  accessibility **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`**,
  pinned in code. `ThisDeviceOnly` is load-bearing: non-migratable, never
  in iCloud Keychain or device backups. `AfterFirstUnlock` (vs
  `WhenUnlocked`) is the standard messenger choice; the delta only
  matters to an attacker already executing code inside our sandbox on a
  powered-on locked device, and it removes a whole class of S15
  reconnect-on-tap foot-guns. Recorded here so it is contestable; judged
  CODE (a parameter within spec §6's "platform keystore" rail, set to the
  industry-standard value — not a posture change).
- **Android:** MK is wrapped by Android-Keystore-resident keys
  (flutter_secure_storage v10 default: RSA-OAEP + AES-GCM) and the
  wrapped blob stored app-private. The wrap keys are non-exportable; a
  backed-up or exfiltrated blob is useless off-device.
- **Adjudication — the platform wrap is not a lock violation:** spec §6
  *mandates* "encrypted at rest using platform keystore (iOS
  Keychain/Secure Enclave, Android Keystore)". The AES/RSA the platform
  uses *inside* its keystore is platform key-protection mechanics, not a
  Nimna cryptography choice; the S2 lock governs crypto we choose or
  implement. Data encryption is 100% locked-suite (§2); the keystore
  wraps exactly one 32-byte key. Reviewers: sighting AES-GCM/RSA in
  flutter_secure_storage internals is expected and adjudicated here.
- **App-lock perimeter (structural now, UI at S13):** a single
  `KeyService` owns MK and every derived key, all in `SecureKey` native
  memory. States: **sealed** (no key material in memory) ⇄ **open**.
  All repositories obtain keys only through KeyService; a sealed
  KeyService throws `StorageSealedError` — the storage layer structurally
  cannot decrypt while locked. S7 ships: `open()` loads from the keystore
  unconditionally; `seal()` zeroizes everything; a root-level `LockGate`
  widget *replaces the entire Navigator subtree* when sealed (zero-leak
  rule, DECISIONS 2026-07-03 — never a route stacked above content).
  S13 drops PIN/biometric in front of `open()` and wires
  lifecycle-pause→`seal()`; nothing else moves.
- **Panic wipe semantics (spec §6; S13 implements, S7's schema makes it
  true):** *key destruction first, deletion second.*
  **Full wipe:** delete the keystore MK entry → zeroize in-memory keys →
  delete the store root recursively (DB + WAL/SHM sidecars + media +
  diag) → recreate empty. Once step 1 lands, everything on disk is
  undecryptable ciphertext even if deletion is interrupted.
  **Per-channel wipe:** delete the channel row — the only copy of that
  channel's CDK dies with it — then delete its message/media rows and
  files. Load-bearing property: message/media ciphertext keys derive from
  the CDK, so any SQLite free-page or flash-remnant ciphertext is dead
  the moment the CDK row is gone; deletion completeness is best-effort
  hygiene (`PRAGMA secure_delete=ON`, WAL checkpoint TRUNCATE after bulk
  deletes), not the security boundary. Beneath our layer, Android 10+
  mandatory file-based encryption and iOS Data Protection bound what
  forensics can see at all — stated honestly, not relied upon.

## 4. Store schemas (SQLite, one DB `nimna.db` at an explicit path)

The DB lives under a single app-support store root
`<ApplicationSupport>/nimna-store/` (never sqflite's default path, never
Documents, never Caches/tmp — purgeable and Files-app-visible
respectively). One root = one iOS exclusion point (§7) + one wipe point.
`PRAGMA secure_delete=ON`; WAL mode; wipe deletes sidecars.

**Plaintext-column budget (normative — nothing else is ever plaintext):**
random local surrogate ids, integer ordering counters, `purge_at`, and
inherent blob sizes. **No CRID, public key, label, timestamp, or token
ever appears as a plaintext column** — channel lookup by CRID happens in
an in-memory index built at unlock (channel counts are dozens;
decrypt-all-at-open is trivial). Surrogates are random 16-byte values
minted locally, correlatable to nothing.

```
channels   id BLOB16 PK · sort INTEGER · ct BLOB
           ct ⊃ own static keypair, peer static pubkey, CRID, label,
                per-channel settings (push opt-in, default expiry,
                peer device-token §3.2.1), CDK, created_at
messages   id BLOB16 PK · channel_id BLOB16 · seq INTEGER ·
           purge_at INTEGER NULL · ct BLOB
           ct ⊃ direction, inner-envelope fields (msg_id, timestamp,
                type, body/text), delivery state (waiting/sent/delivered),
                expiry_s, read_at
media_ix   id BLOB16 PK · channel_id BLOB16 · purge_at INTEGER NULL · ct BLOB
           ct ⊃ manifest msg linkage, mime, byte length, content_hash,
                blob file id
meta       k TEXT PK · v BLOB          (schema_version plaintext int; any
                                        other value an encrypted record)
```

- **Ordering:** per-channel monotonic `seq` (local counter, kept in the
  channel record), never wall-clock — timestamps stay inside ciphertext.
- **`purge_at` (stated leak, accepted):** disappearing enforcement (read
  time + expiry_s, S10/S11) needs to find due rows without decrypting
  all history. A nullable plaintext epoch reveals, to an attacker already
  holding the DB file, that *some* message expires at time T — nothing
  else. Alternative (no column) makes expiry a full-history decrypt sweep;
  rejected. Sizes/counts are likewise visible and were already disclosed
  metadata classes on the wire (spec §1.6).
- **v0.2.1 reply/reaction anticipation — adjudicated at S7 review:
  interior fields, never columns.** Spec v0.2.1's `reply_to` (§5.5
  flags-bit-2) and reactions (§5.8) are absorbed by the schema AS SHIPPED
  with zero S7 code change and zero migration cost: `reply_to` is one
  more inner-envelope field inside the message record's encrypted
  interior (which §4 already defines as holding "inner-envelope fields"
  and which is versioned), and reactions land at S10 with their reference
  linkage inside ciphertext — recommended shape: fold reactions into the
  referent record's interior, making dies-with-referent and
  inherit-expiry automatic (§2's rewrite nonce discipline already covers
  the extra writes); fallback if S10 finds interior-fold wanting: an
  adjunct table of encrypted interiors whose only plaintext columns are
  the §4 budget (surrogate id, channel_id, mirrored `purge_at`). **A
  plaintext `reply_to` column or plaintext `ref_msg_id` reactions table
  is REJECTED:** it would write the conversation's reply/reaction graph
  to disk in plaintext — a new leak class outside the pinned budget,
  purchased for nothing, because reply/reaction resolution only ever
  happens on already-decrypted in-memory channel history (unlike
  `purge_at`, no sweep needs it without decryption). The coordination
  flag's "cheaper now than a migration" rationale predates the
  destructive-reset stance below, which makes pre-launch schema changes
  free regardless. The plaintext-column budget stands unchanged; this
  adjudication is binding on the S10 intake.
- **Static keypairs:** the channel's own X25519 private key lives inside
  the channel record ciphertext and is loaded into `SecureKey` when in
  use. (S8+ may hold it as a libsodium-managed key end-to-end; the store
  format doesn't change.)
- **Schema versioning stance (pre-launch):** `schema_version` in `meta`
  + `schema_ver` byte in every record's AD. Until first store release:
  **version mismatch = destructive reset** (log `schemaReset` diag event,
  wipe store root, recreate) — dev devices only, no migration code to
  review or trust. Migration machinery starts at the launch schema
  (v1 = what S19 ships). Rejected: speculative migration framework for an
  app with zero installed users.

## 5. Media store (spec §5.1, §6)

- Blobs are **files, not DB rows**: `<root>/media/<hex(id)>` where id =
  the media_ix record_id. 5 MB spec cap ⇒ single-shot IETF AEAD per file
  (`nonce ‖ ct`, key = `HKDF(CDK, "nimna/app/rec/v1" ‖ id)`, ad per §2
  with store_id 0x04). No streaming construction needed or permitted
  (§2). Rejected: blobs in SQLite (page churn, WAL bloat, slower wipe).
- Never the gallery, never Documents, never tmp: decrypt-to-memory for
  display; export (S11) is a deliberate act through the share sheet, and
  decrypt-to-temp-file for export cleans up immediately after handoff.
- Wipe: per-channel wipe deletes `media_ix` rows by `channel_id` and
  their files; CDK destruction is the guarantee (§3).

## 6. Diagnostic log — encrypted ring buffer, structurally content-free

Dart equivalent of the relay's unloggable types: **the log API accepts no
strings.**

- **API (the whole public surface):**
  `Diag.log(DiagEvent event, {DiagCode code = DiagCode.none, List<int> args = const []})`.
  `DiagEvent` and `DiagCode` are closed enums in one reviewed file;
  adding a member is a review event. There is no String/Object parameter
  anywhere, no interpolation point, no exception-message pathway —
  platform/OS exceptions are mapped to `DiagCode` members via an explicit
  lookup (default `DiagCode.unknown`); `e.toString()` never enters the
  package. Free-text logging is not inconvenient — it is unrepresentable.
- **Record encoding (fixed):**
  `ver(1) ‖ event(2) ‖ code(2) ‖ ts_ms(8) ‖ argc(1) ‖ argc × int64` —
  integers only, big-endian, no varlen fields.
- **Storage:** `<root>/diag/YYYYMMDD.nlog` (UTC day files), append-only;
  each record stored as `len(4) ‖ nonce(12) ‖ ct` with
  `k_day = HKDF(k_diag, "nimna/app/diag/day/v1" ‖ date)`, random nonce,
  `ad = "nimna/app/ad/v1" ‖ 0x05 ‖ schema_ver ‖ date-bytes-padded`.
  Diag reuses the §2 AEAD/HKDF from `src/crypto` (see §8.1's amended
  layering — no duplicated crypto code). **Ring = prune files older than
  7 days** at open and on day rollover (doctrine's "~7 days" pinned at
  exactly 7).
- **Perimeter & wipe:** k_diag derives from MK — sealed app cannot write
  or read the log. While sealed, events go to a bounded in-memory queue
  (256 entries, drop-oldest — the only loggable events while sealed are
  lock-screen lifecycle anyway), flushed at open. Full panic wipe
  destroys MK and deletes `<root>/diag/` with the store root. "Share
  diagnostics" (S16) decrypts and renders human-readable *at export
  time*, as a deliberate user act; nothing ever auto-uploads.
- **Test enforcement (three layers):** (1) a source-scan test over
  `src/diag/`'s public API asserting no String-typed parameters exist;
  (2) a round-trip audit: exercise every event, decrypt the whole log,
  assert every decoded record's event/code is within the enums and the
  encoding contains nothing outside the fixed schema; (3) the **planted-
  marker audit** (mirror of the relay logscrub test): integration test
  drives flows with known sensitive markers (a fake code string, fake
  token bytes, key hex), then asserts the markers appear neither in the
  decrypted log dump nor anywhere in the raw on-disk log bytes.

## 7. Cloud-backup exclusion — mechanics + what S7 proves

**Android:** `android:allowBackup="false"` on `<application>` (kills
auto-backup and legacy transport everywhere) **plus** explicit
`android:dataExtractionRules` (API 31+) whose XML excludes the app's
files/database/sharedpref domains from **both** `cloud-backup` and
`device-transfer` — belt and braces, intent visible in the manifest even
if tooling defaults shift. flutter_secure_storage's blob rides the same
exclusion; its Keystore wrap keys are non-exportable regardless.

**iOS:** `isExcludedFromBackup = true` (URLResourceValues) set on the
store root `nimna-store/` at creation and **re-asserted every launch**
(the attribute is metadata that restores/migrations can drop). Implemented
via a ~20-line hand-written platform channel (`app.nimna/storage`) — no
dependency exists for a resource-value write; this is platform glue, not
crypto. The Keychain item is independently backup-proof via
`ThisDeviceOnly` (§3).

**S7 proof standard** (deep forensic inspection is S18's plan row — S7
proves the mechanisms are present and behaving):

1. **Manifest facts (Android):** build the APK, dump the merged manifest
   (`aapt2 dump xmltree`, script in `temp/`), assert
   `allowBackup=false` + `dataExtractionRules` present and pointing at
   the committed XML; assert the XML excludes all domains in both rules.
2. **Behavioral (Android, API 35 emulator):** `adb shell bmgr backupnow
   app.nimna` reports the package not eligible / backup not performed;
   captured as QA evidence. (`adb backup` is a no-op at modern API levels
   — bmgr is the honest probe.)
3. **Attribute assertion (iOS):** integration test reads back
   `isExcludedFromBackup == true` on the store root — run on simulator
   and on the real device; plus the re-assert path (clear the flag,
   relaunch, read true again). *Real-device half DEFERRED to S18's
   backup-forensics row (USER, 2026-07-05 10:30 +0200 — device-trust
   blockage at S7 QA; simulator run + independent `xattr` read-back stand
   as the S7 proof; see DECISIONS.md). The S18 forensic pass executes it
   together with item 5.*
4. **Keychain class:** the accessibility constant is pinned in code and
   unit-asserted; item attributes read back where the API allows.
5. **Logged deferral:** actual backup-archive inspection (Finder local
   backup of a real device; forensic diff) = S18, stated in PROGRESS at
   S7 wrap.

## 8. App skeleton

**8.1 Layering** (dependency arrows point down only; `diag` importable by
all layers above it and imports only `crypto` — amended at S7 review:
diag encrypts with the same §2 AEAD/HKDF rather than duplicating it, so
`crypto` sits below `diag` and **must stay diag-free** (crypto code
throws, never logs — the cycle is forbidden structurally)):

```
lib/main.dart
lib/src/app/      MaterialApp, theme wiring, LockGate, AppScope (DI),
                  route table, page-transition theme
lib/src/ui/       screens + widgets (S7: placeholder shell; S8+ real)
lib/src/domain/   services & models (channel, message), app state
lib/src/storage/  keys/ (KeyService, keystore glue), db/, media/, backup/
lib/src/crypto/   sodium init, RFC 5869 HKDF, at-rest AEAD helpers;
                  S8/S9 Noise engine lands here
lib/src/diag/     event/code enums, encoder, ring store
lib/l10n/         ARBs + gen_l10n output
```

Protocol/storage/crypto code is locale-independent by definition (i18n
decision 2026-07-04) — nothing below `ui/` may touch locale.

**8.2 State management — zero-dependency.** `ChangeNotifier`/
`ValueNotifier` services exposed through one `AppScope` InheritedWidget
(constructor-injected singletons), consumed via `ListenableBuilder`. The
app is a dozen shallow screens over a handful of services; that is what
the Flutter SDK's own primitives are for. Rejected: `provider` (thin, but
a dependency for sugar), `riverpod`/`bloc` (machinery and idioms
disproportionate to the surface), `get_it` (service-locator hides the
graph). Revisit only on demonstrated pain, as its own decision.

**8.3 Navigation — imperative Navigator 1.0**, named routes via
`onGenerateRoute`. v1 has no URL/deep-link surface (push-tap is an
app-launch event handled at startup, not a route URL — S15). `LockGate`
sits *above* the Navigator and swaps the whole subtree when sealed
(§3). Global `PageTransitionsTheme` = fade + 8px drift, 320 ms decelerate
per flutter-notes; honors `MediaQuery.disableAnimations`. Rejected:
`go_router` (a routing dependency for routes that don't branch).

**8.4 Tokens → theme.** Hand-written `NimnaTokens
ThemeExtension` (one file) synced with `designs/system/tokens.json`
v1.1.0; two `ThemeData` (dark/light) from the same map;
`themeMode: ThemeMode.system`; semantic names only — no `Color(0xFF…)`
literals outside the tokens file (reviewer-enforced). **Drift guard:** a
unit test reads `../../designs/system/tokens.json` (monorepo-relative —
the app tree is closed-source and never split) and asserts every color/
size constant in the Dart file matches; tokens can't silently diverge
from design.

**8.5 Fonts — VENDORED.** Schibsted Grotesk (400/500/600) + Spline Sans
Mono (500) committed under `assets/fonts/` with their OFL license texts;
declared in pubspec. **As-shipped (ACKed at S7 review):** upstream
google/fonts distributes these families as variable-weight TTFs, so one
`…-wght.ttf` per family is vendored and the three weights are selected
via `FontVariation('wght', …)` in the tokens file — pinned by the tokens
drift test; weight-bearing styles must set `fontVariations`, not
`fontWeight` alone (reviewer-checked). **`google_fonts` REJECTED** — its
default is a runtime fetch from Google servers: a phone-home in a product
whose safety features "have nowhere to call." Even bundled-only mode is a
dependency for what a pubspec stanza does. This supersedes the
`google_fonts` line in flutter-notes §Theme (that same document's Asset
Wiring section already says "vendor for reproducible builds" — the
doctrine decides the contradiction; noted as design-note drift, not a
design change).

**8.6 i18n (from the first widget).** `flutter_localizations` +
`gen_l10n` (`l10n.yaml`; template `lib/l10n/app_en.arb`);
`supportedLocales` = EN, DE, FR, ES, IT from S7 so locale plumbing is
real and testable. **Non-EN ARBs until S16 contain only `@@locale`** —
gen_l10n falls back to the template (EN) at runtime and lists every
missing message in `untranslated-messages-file`, which becomes S16's
work-queue and S16-CI's zero-remaining assertion. Rejected: EN-copied
ARBs (masks translation state; S16 can't distinguish "translated" from
"copied"), machine-translation placeholders (violates the
crafted-translation USER decision). Zero hardcoded user-facing strings:
reviewer-enforced (primary) + a CI grep heuristic over `lib/` for string
literals inside `Text(`-class constructors (safety net, reviewer remains
the authority).

**8.7 S7 visible surface.** LockGate (passthrough) → one placeholder
shell: the channel-list scaffold rendering **voice-guide string 4
verbatim** ("No lines yet. / Create a Nimna code, or enter one you've
been given.") from the EN ARB — canonical copy, zero invention, and it
gives i18n/theme wiring something real to prove. Its two actions are
present but disabled/stub (they are S8/S9 flows). Nothing else
user-visible ships in S7. Real screens implement `designs/` verbatim from
S8 on.

## 9. Minimum OS floors — RECOMMENDATION (flagged USER)

Judged **USER**: the floor sets the addressable market (scope/money) and
the uniformity of a spec §5.3 capability — not an engineering-internal
knob. Recommendation, with reasoning, for the orchestrator's question
list:

- **iOS 17.0** (current pbxproj default: 13.0). SensitiveContentAnalysis
  (spec §5.3, S14) requires iOS 17 — a 17 floor makes the recipient-side
  check uniform on iOS instead of silently absent on older devices;
  iOS 17 runs on iPhone XS (2018) and later, so a 2026 launch sheds only
  9-year-old hardware; one less availability-gated code path and QA
  matrix row.
- **Android minSdk 29 / Android 10** (Flutter 3.44.2 default: 24).
  Android 10 is where file-based encryption beneath our at-rest layer is
  mandatory for shipping devices and scoped storage is default — both
  directly load-bearing for §6-class promises; BiometricPrompt (S13) is
  solid from 28. 2019 floor ≈ 97%+ of 2026 active devices.
- Fallback if USER prefers wider reach: iOS 16 / minSdk 26 works — S14's
  iOS check then needs an availability gate and the §5.3 story gains a
  per-device asterisk; nothing in S7–S13 breaks.

The floor lands in S7 so every later session tests against the real
matrix. **As landed (verified at S7 review):** iOS 17.0 in
`project.pbxproj` `IPHONEOS_DEPLOYMENT_TARGET` across all three build
configurations — there is no Podfile to carry it (Flutter 3.44 manages
iOS plugins via Swift Package Manager; this note's original
"pbxproj/Podfile" wording is corrected) — and `minSdk = 29` in
`android/app/build.gradle.kts`.

## 10. S7 testing architecture (maps 1:1 to the done-check)

- **Unit:** at-rest AEAD round-trip + negative tests (wrong key, wrong
  AD store_id/record_id/schema_ver each fail); HKDF vs RFC 5869 A.1–A.3
  + RFC 4231 vectors + cross-check against committed Go-generated
  values; nonce freshness across rewrites (statistical: N writes, N
  distinct nonces); diag encoder round-trip + closed-vocabulary
  assertion; ring pruning with injectable clock (8th day file dies);
  KeyService seal/open lifecycle (sealed ⇒ `StorageSealedError`
  everywhere); schema-version mismatch ⇒ destructive reset path.
- **Widget:** app boots to the shell in all five locales (string 4
  renders from ARB; DE/FR/ES/IT fall back to EN pre-S16); dark + light
  themes expose `NimnaTokens`; LockGate swaps the subtree when sealed
  (no channel-list widget in the tree while locked).
- **Integration (emulator + simulator; real iPhone for §7.3):**
  *encrypted-at-rest:* write channel/message/media records containing a
  known marker string → scan `nimna.db`, WAL, and media files as raw
  bytes → marker absent; decrypt through the API → marker present.
  *Restart persistence:* full app kill and relaunch → records decrypt
  intact (the done-check's "persists encrypted records across restart").
  *Backup exclusion:* the §7 ladder (manifest dump script, bmgr run,
  isExcludedFromBackup read-back incl. re-assert path).
  *Diag audit:* the §6 planted-marker test.
  *Wipe seam:* full-wipe primitive (keystore delete + root delete)
  leaves a fresh empty store on next open — the S13 UI will call exactly
  this.
- **CI (existing mobile job):** all of the above except
  device-attached integration tests; `dart format` / `flutter analyze` /
  `flutter test` stay green; tokens-drift test and l10n generation run in
  CI. Device-attached evidence (bmgr, real-iPhone attribute read) is
  captured by QA in the done-check run and logged in PROGRESS.md.

## 11. Open items carried forward

- **S8/S9:** sodium sumo-variant verification (scalarmult/pwhash), Noise
  engine in `src/crypto/` against committed vectors, channel-creation
  writes through this store.
- **S10:** reply_to + reactions storage per the §4 adjudication (encrypted
  interiors, never plaintext reference columns; interior-fold recommended,
  budget-conforming adjunct table as fallback).
- **S13:** PIN/biometric in front of `KeyService.open()`; wipe UI over
  the §3 wipe primitives; `local_auth` sign-off at that intake.
- **S15:** push dependency evaluation (see §1 fence); keychain
  accessibility interaction re-checked against the real reconnect flow.
- **S16:** DE/FR/ES/IT ARB fill; untranslated-file zero assertion.
- **S18:** forensic backup inspection + wipe forensics (this note's §7.5
  deferral).
