import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/keys/master_key_store.dart';

/// The lock configuration blob (SESSION-13 intake §3) — fixed-length, no
/// strings:
///
/// ```
/// ver(1) ‖ flags(1: bit0 pinEnabled, bit1 biometricEnabled) ‖
/// pin_len(1) ‖ salt(16) ‖ verifier(32)
/// ```
///
/// `pin_len` (CODE, S13): screen 12 renders one dot per enrolled PIN digit
/// (its mock shows a 4-dot row for a 4-digit PIN) and auto-submits at full
/// length — the sealed surface therefore needs the enrolled length before
/// any MK-derived key exists. It lives INSIDE this keystore-wrapped blob:
/// zero new plaintext-at-rest, still fixed-length, still string-free. This
/// extends the intake §3 field list by one byte; flagged in
/// progress/SESSION-13.md for the architect at merge.
class LockConfig {
  LockConfig({
    required this.pinEnabled,
    required this.biometricEnabled,
    required this.pinLength,
    required this.salt,
    required this.verifier,
  }) {
    if (salt.length != saltBytes) {
      throw ArgumentError.value(salt.length, 'salt', 'must be $saltBytes');
    }
    if (verifier.length != verifierBytes) {
      throw ArgumentError.value(
        verifier.length,
        'verifier',
        'must be $verifierBytes',
      );
    }
    if (pinLength < pinLengthMin || pinLength > pinLengthMax) {
      throw ArgumentError.value(pinLength, 'pinLength', 'must be 4–8');
    }
  }

  static const int version = 1;
  static const int saltBytes = 16;
  static const int verifierBytes = 32;
  static const int encodedLength = 3 + saltBytes + verifierBytes;

  /// PIN length bounds — design-settled (wireframes README / F8.2: the pad
  /// accepts 4–8 digits).
  static const int pinLengthMin = 4;
  static const int pinLengthMax = 8;

  final bool pinEnabled;
  final bool biometricEnabled;
  final int pinLength;
  final Uint8List salt;
  final Uint8List verifier;

  LockConfig copyWith({bool? biometricEnabled}) => LockConfig(
    pinEnabled: pinEnabled,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    pinLength: pinLength,
    salt: salt,
    verifier: verifier,
  );

  Uint8List encode() {
    final out = Uint8List(encodedLength);
    out[0] = version;
    out[1] = (pinEnabled ? 0x01 : 0x00) | (biometricEnabled ? 0x02 : 0x00);
    out[2] = pinLength;
    out.setRange(3, 3 + saltBytes, salt);
    out.setRange(3 + saltBytes, encodedLength, verifier);
    return out;
  }

  /// Decodes a stored blob; returns null for anything unexpected (wrong
  /// length/version/bounds). An undecodable blob is treated as absent —
  /// the same fail-to-fresh class as keystore loss (spec §6.1): the blob
  /// sits inside the platform keystore wrap, so corruption is a platform
  /// fault, never attacker-writable content.
  static LockConfig? decode(Uint8List bytes) {
    if (bytes.length != encodedLength || bytes[0] != version) {
      return null;
    }
    final flags = bytes[1];
    final pinLength = bytes[2];
    if (flags & ~0x03 != 0 ||
        pinLength < pinLengthMin ||
        pinLength > pinLengthMax) {
      return null;
    }
    return LockConfig(
      pinEnabled: flags & 0x01 != 0,
      biometricEnabled: flags & 0x02 != 0,
      pinLength: pinLength,
      salt: Uint8List.sublistView(bytes, 3, 3 + saltBytes),
      verifier: Uint8List.sublistView(bytes, 3 + saltBytes),
    );
  }
}

/// Persistence seam for the lock-config blob. Absence = lock disabled
/// (the S7 upgrade path is automatic).
abstract interface class LockConfigStore {
  Future<LockConfig?> read();

  Future<void> write(LockConfig config);

  /// Full panic wipe also deletes this item — a wiped phone equals a fresh
  /// install, including "App lock: Off" (SESSION-13 intake §6).
  Future<void> delete();
}

/// The SECOND (and last) flutter_secure_storage call site in the app —
/// scope amendment on record (SESSION-13 intake §3: "two call sites, both
/// enumerated"; the first is `src/storage/keys/master_key_store.dart`).
/// The gate must be evaluable while sealed, so this cannot live in the
/// encrypted store. Same pinned iOS accessibility class as the MK item
/// (`first_unlock_this_device`, ThisDeviceOnly — never backed up), same
/// Android Keystore wrap.
class SecureStorageLockConfigStore implements LockConfigStore {
  SecureStorageLockConfigStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: SecureStorageMasterKeyStore.pinnedIosAccessibility,
        ),
        aOptions: AndroidOptions(),
      );

  static const String _key = 'nimna/lock/v1';

  final FlutterSecureStorage _storage;

  @override
  Future<LockConfig?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) {
      return null;
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(value);
    } on FormatException {
      return null;
    }
    return LockConfig.decode(bytes);
  }

  @override
  Future<void> write(LockConfig config) =>
      _storage.write(key: _key, value: base64.encode(config.encode()));

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
