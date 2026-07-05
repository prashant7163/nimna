import 'dart:ffi';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';
import 'package:sodium/sodium.ffi.dart';

/// Authentication failure (or malformed input) while opening an at-rest
/// ciphertext. Deliberately carries no data beyond its type.
class AeadAuthError extends Error {
  @override
  String toString() => 'AeadAuthError';
}

/// ChaCha20-Poly1305-IETF (96-bit nonce, RFC 8439) — the S2-locked AEAD —
/// applied to at-rest records (app-architecture.md §2).
///
/// The `sodium` package's high-level API exposes only the *original*
/// construction (64-bit nonce) and XChaCha20; both are outside the locked
/// suite. This class is therefore thin pointer glue over libsodium's own
/// `crypto_aead_chacha20poly1305_ietf_*` functions, reached through the
/// package's public FFI wrapper (`package:sodium/sodium.ffi.dart`). No
/// cryptography is implemented here — libsodium computes everything; this
/// file only moves bytes in and out of sodium-allocated (guarded, zeroed on
/// free) native memory. Correctness is locked to the RFC 8439 §2.8.2 test
/// vector in test/crypto/at_rest_aead_test.dart.
class AtRestAead {
  AtRestAead(this._sodium) : _ffi = const LibSodiumFFI() {
    // Defensive: assert the runtime library agrees on the IETF constants.
    assert(_ffi.crypto_aead_chacha20poly1305_ietf_keybytes() == keyBytes);
    assert(_ffi.crypto_aead_chacha20poly1305_ietf_npubbytes() == nonceBytes);
    assert(_ffi.crypto_aead_chacha20poly1305_ietf_abytes() == macBytes);
  }

  static const int keyBytes = 32;
  static const int nonceBytes = 12;
  static const int macBytes = 16;

  final Sodium _sodium;
  final LibSodiumFFI _ffi;

  /// The underlying libsodium instance (for SecureKey allocation).
  Sodium get sodium => _sodium;

  /// Fresh random bytes (libsodium `randombytes`).
  Uint8List randomBytes(int length) => _sodium.randombytes.buf(length);

  /// Fresh random 12-byte nonce (libsodium `randombytes`).
  Uint8List newNonce() => _sodium.randombytes.buf(nonceBytes);

  /// Fresh random key material of [length] bytes held in native memory.
  SecureKey newKey({int length = keyBytes}) => _sodium.secureRandom(length);

  /// Encrypts [plaintext] under [key]/[nonce] binding [additionalData];
  /// returns `ciphertext ‖ tag(16)`.
  Uint8List encrypt({
    required SecureKey key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List additionalData,
  }) {
    _checkKeyAndNonce(key, nonce);
    SodiumPointer<UnsignedChar>? dataPtr;
    SodiumPointer<UnsignedChar>? noncePtr;
    SodiumPointer<UnsignedChar>? adPtr;
    try {
      dataPtr = SodiumPointer.alloc(_ffi, count: plaintext.length + macBytes)
        ..fill(plaintext);
      noncePtr = nonce.toSodiumPointer(
        _ffi,
        memoryProtection: MemoryProtection.readOnly,
      );
      adPtr = additionalData.toSodiumPointer(
        _ffi,
        memoryProtection: MemoryProtection.readOnly,
      );

      final result = _withKeyPointer(
        key,
        (keyPtr) => _ffi.crypto_aead_chacha20poly1305_ietf_encrypt(
          dataPtr!.ptr,
          nullptr,
          dataPtr.ptr,
          plaintext.length,
          adPtr!.ptr,
          adPtr.count,
          nullptr,
          noncePtr!.ptr,
          keyPtr.ptr,
        ),
      );
      if (result != 0) {
        throw AeadAuthError();
      }
      return Uint8List.fromList(dataPtr.asListView<Uint8List>());
    } finally {
      dataPtr?.dispose();
      noncePtr?.dispose();
      adPtr?.dispose();
    }
  }

  /// Opens `ciphertext ‖ tag(16)`; throws [AeadAuthError] if authentication
  /// fails (wrong key, wrong nonce, wrong AD, or tampered bytes).
  Uint8List decrypt({
    required SecureKey key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List additionalData,
  }) {
    _checkKeyAndNonce(key, nonce);
    if (ciphertext.length < macBytes) {
      throw AeadAuthError();
    }
    SodiumPointer<UnsignedChar>? dataPtr;
    SodiumPointer<UnsignedChar>? noncePtr;
    SodiumPointer<UnsignedChar>? adPtr;
    try {
      dataPtr = ciphertext.toSodiumPointer(_ffi);
      noncePtr = nonce.toSodiumPointer(
        _ffi,
        memoryProtection: MemoryProtection.readOnly,
      );
      adPtr = additionalData.toSodiumPointer(
        _ffi,
        memoryProtection: MemoryProtection.readOnly,
      );

      final result = _withKeyPointer(
        key,
        (keyPtr) => _ffi.crypto_aead_chacha20poly1305_ietf_decrypt(
          dataPtr!.ptr,
          nullptr,
          nullptr,
          dataPtr.ptr,
          dataPtr.count,
          adPtr!.ptr,
          adPtr.count,
          noncePtr!.ptr,
          keyPtr.ptr,
        ),
      );
      if (result != 0) {
        throw AeadAuthError();
      }
      final view = dataPtr.asListView<Uint8List>();
      return Uint8List.fromList(
        Uint8List.sublistView(view, 0, ciphertext.length - macBytes),
      );
    } finally {
      dataPtr?.dispose();
      noncePtr?.dispose();
      adPtr?.dispose();
    }
  }

  void _checkKeyAndNonce(SecureKey key, Uint8List nonce) {
    if (key.length != keyBytes) {
      throw ArgumentError.value(key.length, 'key', 'must be $keyBytes bytes');
    }
    if (nonce.length != nonceBytes) {
      throw ArgumentError.value(
        nonce.length,
        'nonce',
        'must be $nonceBytes bytes',
      );
    }
  }

  /// Runs [body] with the key material copied into sodium-guarded native
  /// memory (read-only), zeroed and freed afterwards.
  int _withKeyPointer(
    SecureKey key,
    int Function(SodiumPointer<UnsignedChar> keyPtr) body,
  ) {
    return key.runUnlockedSync((keyData) {
      SodiumPointer<UnsignedChar>? keyPtr;
      try {
        keyPtr = keyData.toSodiumPointer(
          _ffi,
          memoryProtection: MemoryProtection.readOnly,
        );
        return body(keyPtr);
      } finally {
        keyPtr?.dispose();
      }
    });
  }
}
