import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/at_rest_aead.dart';
import 'lock_config_store.dart';

/// The PIN gate's Argon2id verifier (SESSION-13 intake §2 — gate-not-key).
///
/// THIS IS THE ONLY FILE THAT TOUCHES `crypto_pwhash`. The PIN is an
/// interactive gate in front of `KeyService.open()`, never key material:
///
/// - Enrollment: `salt = randombytes(16)`,
///   `verifier = Argon2id(v1.3, t=3, m=64 MiB, p=1, out=32)(pin, salt)` —
///   the spec §7 locked slow-KDF with its locked parameters, verbatim,
///   computed by libsodium (`crypto_pwhash`, ALG_ARGON2ID13; libsodium's
///   Argon2id is fixed at p=1). Reached through the package's high-level
///   sumo API — no FFI glue was needed (intake §2 day-one spike outcome).
/// - Verify: recompute, compare constant-time via the fence's
///   `sodium_memcmp` wrapper ([AtRestAead.constantTimeEquals]).
///
/// The derived bytes are structurally unusable as a key: the public API
/// returns only `Future<void>` / `Future<bool>`; derived material never
/// leaves this file and is zeroized after use (SecureKey dispose + explicit
/// fills). A structural test asserts the no-byte-returning-API property
/// (test/lock/pin_verifier_test.dart).
class PinVerifier {
  PinVerifier({
    required this._sodium,
    required this._aead,
    required this._store,
    this._opsLimit = specOpsLimit,
    this._memLimit = specMemLimitBytes,
  });

  /// Spec §7 locked parameters — Argon2id v1.3, t=3, m=64 MiB, p=1.
  /// Pinned here and unit-asserted; constructor overrides exist ONLY for
  /// the reduced-cost test lane (production code never passes them).
  static const int specOpsLimit = 3;
  static const int specMemLimitBytes = 64 * 1024 * 1024;

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final LockConfigStore _store;
  final int _opsLimit;
  final int _memLimit;

  static final RegExp _pinShape = RegExp(r'^[0-9]{4,8}$');

  /// Derives a fresh salt+verifier for [pin] and persists the lock config
  /// (PIN enabled). [pin] must be 4–8 digits (design-settled).
  Future<void> enroll({
    required String pin,
    required bool biometricEnabled,
  }) async {
    _checkPin(pin);
    final salt = _sodium.randombytes.buf(LockConfig.saltBytes);
    final derived = _derive(pin, salt);
    try {
      final verifier = derived.runUnlockedSync(Uint8List.fromList);
      await _store.write(
        LockConfig(
          pinEnabled: true,
          biometricEnabled: biometricEnabled,
          pinLength: pin.length,
          salt: salt,
          verifier: verifier,
        ),
      );
      verifier.fillRange(0, verifier.length, 0);
    } finally {
      derived.dispose();
    }
  }

  /// Recomputes the verifier for [pin] against the stored config and
  /// compares constant-time. False when no PIN is enrolled. Each call
  /// costs one Argon2id evaluation by construction.
  Future<bool> verify(String pin) async {
    if (!_pinShape.hasMatch(pin)) {
      return false;
    }
    final config = await _store.read();
    if (config == null || !config.pinEnabled) {
      return false;
    }
    final derived = _derive(pin, config.salt);
    try {
      return derived.runUnlockedSync(
        (bytes) => _aead.constantTimeEquals(bytes, config.verifier),
      );
    } finally {
      derived.dispose();
    }
  }

  void _checkPin(String pin) {
    if (!_pinShape.hasMatch(pin)) {
      throw ArgumentError('PIN must be 4-8 digits');
    }
  }

  /// Argon2id via libsodium; output lives in SecureKey native memory and
  /// never leaves this file.
  SecureKey _derive(String pin, Uint8List salt) {
    final password = Int8List.fromList(pin.codeUnits);
    try {
      return _sodium.crypto.pwhash(
        outLen: LockConfig.verifierBytes,
        password: password,
        salt: salt,
        opsLimit: _opsLimit,
        memLimit: _memLimit,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
    } finally {
      password.fillRange(0, password.length, 0);
    }
  }
}
