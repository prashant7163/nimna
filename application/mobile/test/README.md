# test/

Host-side suite — all of it runs under plain `flutter test` (real
libsodium via the sodium package's build hooks; real SQLite via
`sqflite_common_ffi`, dev-only; platform keystore and paths faked through
the bootstrap seams).

```
helpers/test_env.dart      shared harness: TestDevice (stable store root +
                           keystore across simulated relaunches), raw-byte
                           marker scanner, hex utilities
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
storage/
  key_service_test.dart    MK mint/load, seal ⇒ StorageSealedError, key
                           destruction, Keychain-accessibility pin
  storage_service_test.dart  THE done-check core: restart persistence,
                             raw-byte marker absence over db/WAL/media/diag,
                             schema-mismatch destructive reset, full-wipe
                             and per-channel-wipe seams
privacy/
  diag_marker_audit_test.dart  planted-marker audit (relay-logscrub
                               mirror): fake code/label/body/token/key-hex
                               driven through real flows → absent from the
                               decrypted dump AND the raw log bytes
ui/
  tokens_drift_test.dart   reads ../../designs/system/tokens.json and
                           asserts every constant in nimna_tokens.dart
  shell_test.dart          boots in all five locales (EN fallback pre-S16),
                           both themes expose NimnaTokens, LockGate swaps
                           the whole subtree while sealed
  no_hardcoded_strings_test.dart  grep safety net for Text('...') literals
```

Device-attached coverage lives in `../integration_test/` (see its README);
the Android merged-manifest backup facts are checked by the git-ignored
`temp/verify-android-backup-flags.sh` against a built APK.
