# test/

Host-side suite — all of it runs under plain `flutter test` (real
libsodium via the sodium package's build hooks; real SQLite via
`sqflite_common_ffi`, dev-only; platform keystore and paths faked through
the bootstrap seams).

```
helpers/test_env.dart      shared harness: TestDevice (stable store root +
                           keystore across simulated relaunches), raw-byte
                           marker scanner, hex utilities
helpers/fake_relay.dart    in-memory RelayConnector/RelayConnection fakes
                           (recorded sends, test-side deliver/drop,
                           fail-next-attempts)
helpers/fake_entitlement.dart  scriptable EntitlementSource fake (S17):
                           status/price/restore/purchase permutations, call
                           counts (permanence: zero-query assertion)
fixtures/                  committed expected values (see its README):
                           the independently-decoder-verified QR matrix
crypto/
  hkdf_test.dart           RFC 5869 A.1–A.3 + RFC 4231 HMAC vectors +
                           byte-cross-check vs the committed Go-generated
                           values in docs/test-vectors/
  at_rest_aead_test.dart   RFC 8439 §2.8.2 vector (locks the IETF
                           construction) + negative auth tests
  record_cipher_test.dart  record format, AD binding (store/schema/row),
                           nonce freshness across rewrites, per-record keys
diag/
  diag_encoder_test.dart   fixed-layout round-trips, closed-vocabulary
                           rejection, wire-id regression pins
  diag_ring_test.dart      7-day ring pruning (injectable clock), sealed
                           queue (256, drop-oldest), ciphertext-on-disk
  diag_api_surface_test.dart  source scan: no String/Object/dynamic in the
                              public diag API — free text unrepresentable
protocol/ (S8, vector-locked to ../../docs/test-vectors/)
  pairing_code_test.dart   §3.1.1: every committed canonicalization case
                           (valid + reject), display/QR-payload forms,
                           uniform-sampler generation, redacted toString
  rendezvous_test.dart     §3.1.2: salts + seed/topic/psk under the
                           reduced-cost set (fast default) AND the
                           production-cost set (tagged `production-cost`,
                           runs by default, CI-selectable — the Go -short
                           mirror); Argon2id/HKDF constants pinned
  outer_frame_test.dart    §5.4: all 11 committed outer-frame cases,
                           full enum coverage assertion, strict rejects
pairing/ (S8)
  initiator_controller_test.dart  the state machine over the fake relay:
                           create/register/persist, offline edge (no
                           phantom codes), bridged hold + opaque PAIR_DATA
                           buffering (no fabricated replies), backoff
                           re-register (no retry storm), TTL expiry live +
                           on-resume, original-creation-date resume topic,
                           cancel silence, bridged-drop fail-closed,
                           background grace, diag events-only
  pending_pairing_test.dart  encrypted record round-trip incl. keypair,
                           raw-disk absence of code/key bytes, remove =
                           real erase (row deleted)
  qr_matrix_test.dart      committed expected-matrix fixture (independent
                           decoder verified) + determinism
  single_call_site_test.dart  source pins: startCreateLine G2 single call
                           site, share_plus fence, qr-encoder fence, S10
                           inner-envelope fence
storage/
  key_service_test.dart    MK mint/load, seal ⇒ StorageSealedError, key
                           destruction, Keychain-accessibility pin
  meta_records_test.dart   encrypted meta values (S8): round-trip/rewrite/
                           delete, ciphertext-on-disk + restart, AD
                           transplant rejection, sealed perimeter
  storage_service_test.dart  THE done-check core: restart persistence,
                             raw-byte marker absence over db/WAL/media/diag,
                             schema-mismatch destructive reset, full-wipe
                             and per-channel-wipe seams
privacy/
  diag_marker_audit_test.dart  planted-marker audit (relay-logscrub
                               mirror): fake code/label/body/token/key-hex
                               driven through real flows → absent from the
                               decrypted dump AND the raw log bytes
lock/                      S13 app lock
  pin_verifier_test.dart   Argon2id round-trip (reduced-cost lane), spec §7
                           param pins, tagged `production-cost` lane
                           (dart_test.yaml), structural fence scans (no
                           byte-returning API; pwhash only here;
                           constant-time compare in use)
  lock_controller_test.dart  lock-enabled cold start reads the keystore
                             ZERO times before a successful verify
                             (recording keystore), wrong PIN stays sealed,
                             escalating-delay schedule + pad disarm/rearm,
                             biometric verdict == correct PIN, turn-off
                             requires the current PIN
wipe/                      S13 panic wipe
  wipe_service_test.dart   planted-marker full-wipe audit (zero residual
                           bytes; lock config dies too; fresh-install diag
                           shape), destruction-ORDER probe (keystore entry
                           dies while files still exist), interrupted-wipe
                           (post-step-1 ciphertext undecryptable under any
                           future MK), per-channel wipe + pre-wipe hook
ui/
  tokens_drift_test.dart   reads ../../designs/system/tokens.json and
                           asserts every constant in nimna_tokens.dart
  shell_test.dart          boots in all five locales (EN fallback pre-S16),
                           both themes expose NimnaTokens, LockGate swaps
                           the whole subtree while sealed
  pairing_flow_test.dart   F2 widget slices (S8): F2.1/F2.2+F2.4/F2.8
                           canonical strings in all five locales, QR + code
                           simultaneous, TTL sheet presets, offline edge,
                           copy toast, F2.3 sheet caption (string 13),
                           back-confirm vocabulary, 320 px narrow-frame
                           survival (wide test font = length stress)
  no_hardcoded_strings_test.dart  grep safety net for Text('...') literals
  lock_gate_test.dart      S13: seal on `hidden` (zero content widgets on
                           the sealed surface), `inactive` never seals,
                           PIN-pad unlock restores the tree, biometric
                           auto-prompt (ARB reason string)
  wipe_sheet_test.dart     S13 hold semantics: release at 99% ⇒ no call +
                           track reset; completion ⇒ exactly one call +
                           sheet closes; 1.5 s / 2.5 s durations pinned;
                           sheet strings from the ARB in five locales
  settings_flow_test.dart  S13 F8 flows: root rows (five locales), PIN
                           choose→confirm enroll + mismatch restart,
                           biometric recommended-on, turn-off gated by the
                           current PIN, wipe row raises the string-8 sheet
billing/ (S17)
  billing_service_test.dart  gate bool mapping (active only; unresolved
                           fail-closed), price pass-through / null, restore
                           + purchase re-grant, cancelled = calm
  billing_fences_test.dart   in_app_purchase fenced to store_entitlement_
                           source; session/storage path never references
                           billing (permanence is structural)
  paywall_gate_test.dart   F9 gate: unentitled intercepts to the paywall,
                           entitled goes straight to create; buy/restore
                           re-grant + toast + continue; dismiss = calm
                           return; offline = reconnect state (no CTA);
                           existing state never consults billing
```

Device-attached coverage lives in `../integration_test/` (see its README);
the Android merged-manifest backup facts are checked by the git-ignored
`temp/verify-android-backup-flags.sh` against a built APK.
