import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence seam for the single platform-keystore item Nimna owns:
/// the wrapped 32-byte master key (app-architecture.md §1/§3).
abstract interface class MasterKeyStore {
  /// Returns the stored master key bytes, or null on first launch / after
  /// a full wipe.
  Future<Uint8List?> read();

  Future<void> write(Uint8List key);

  /// Panic-wipe step 1: once this returns, everything on disk is
  /// undecryptable ciphertext.
  Future<void> delete();
}

/// The ONE flutter_secure_storage call site in the app (fenced by review —
/// app-architecture.md §1). Stores exactly one item.
///
/// iOS: Keychain with accessibility pinned to
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — `ThisDeviceOnly` is
/// load-bearing (non-migratable, never in iCloud Keychain or backups).
/// Android: Android-Keystore-resident wrap keys (RSA-OAEP + AES-GCM) over an
/// app-private blob; the wrap keys are non-exportable. Sighting AES-GCM/RSA
/// inside this dependency is platform key-protection mechanics, adjudicated
/// in app-architecture.md §3 — not a crypto-lock violation.
class SecureStorageMasterKeyStore implements MasterKeyStore {
  SecureStorageMasterKeyStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: pinnedIosAccessibility),
        aOptions: AndroidOptions(),
      );

  /// Pinned in code and unit-asserted (test/storage/key_service_test.dart).
  static const KeychainAccessibility pinnedIosAccessibility =
      KeychainAccessibility.first_unlock_this_device;

  static const String _key = 'nimna.mk.v1';

  final FlutterSecureStorage _storage;

  /// Exposed for the accessibility-pin unit assertion only.
  FlutterSecureStorage get storage => _storage;

  // Honesty note (review N6): the MK transits the Dart heap as a base64
  // String here — Strings are immutable and unzeroizable, and this is
  // inherent to flutter_secure_storage's String-only API. Same accepted
  // class as the §2 heap-content note; the at-rest claim is unaffected.
  @override
  Future<Uint8List?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) {
      return null;
    }
    return base64.decode(value);
  }

  @override
  Future<void> write(Uint8List key) =>
      _storage.write(key: _key, value: base64.encode(key));

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
