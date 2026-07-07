/// Noise `CipherState` — the keyed AEAD half of a handshake (Noise spec
/// rev 34, §5.1), implemented from the specification (NO Noise library —
/// crypto lock, DECISIONS 2026-07-04 13:44 Q2).
///
/// The cipher itself is the S2-locked ChaCha20-Poly1305-IETF, reached
/// through the vetted [AtRestAead] FFI glue (libsodium computes every
/// cryptographic byte). This file only tracks the key + nonce counter and
/// encodes the Noise handshake nonce. Pure and locale-independent.
library;

import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../crypto/at_rest_aead.dart';

/// Encodes a Noise handshake nonce: 32 bits of zeros ‖ 64-bit LITTLE-endian
/// counter (Noise spec §5.1 / §11.4 for the 25519_ChaChaPoly suite; the
/// committed vectors confirm "4 zero bytes ‖ little-endian counter"). This
/// is the handshake encoding only; post-Split transport uses the Nimna
/// nonce of spec §5.6 (S10).
Uint8List noiseHandshakeNonce(int counter) {
  final nonce = Uint8List(AtRestAead.nonceBytes);
  ByteData.sublistView(nonce).setUint64(4, counter, Endian.little);
  return nonce;
}

/// One direction's keyed cipher during a handshake. Holds the 32-byte key
/// in native ([SecureKey]) memory and the strictly-incrementing counter.
class NoiseCipherState {
  NoiseCipherState(this._aead);

  final AtRestAead _aead;
  SecureKey? _k;
  int _n = 0;

  /// Whether a key has been installed (Noise `has_key`).
  bool get hasKey => _k != null;

  /// Installs a fresh 32-byte key and resets the counter to 0 (Noise
  /// `InitializeKey`). Takes a COPY into native memory; the caller still
  /// owns and should zeroize [key].
  void initializeKey(Uint8List key) {
    _k?.dispose();
    _k = SecureKey.fromList(_aead.sodium, key);
    _n = 0;
  }

  /// `EncryptWithAd` — with no key, returns the plaintext unchanged (Noise
  /// §5.1); otherwise ChaCha20-Poly1305 over the current nonce, then the
  /// counter advances by one.
  Uint8List encryptWithAd(Uint8List ad, Uint8List plaintext) {
    final k = _k;
    if (k == null) {
      return Uint8List.fromList(plaintext);
    }
    final ct = _aead.encrypt(
      key: k,
      nonce: noiseHandshakeNonce(_n),
      plaintext: plaintext,
      additionalData: ad,
    );
    _n++;
    return ct;
  }

  /// `DecryptWithAd` — the inverse. Throws [AeadAuthError] (from
  /// [AtRestAead]) on any authentication failure, which the driver treats
  /// as a fail-closed handshake failure (§3.1.6).
  Uint8List decryptWithAd(Uint8List ad, Uint8List ciphertext) {
    final k = _k;
    if (k == null) {
      return Uint8List.fromList(ciphertext);
    }
    final pt = _aead.decrypt(
      key: k,
      nonce: noiseHandshakeNonce(_n),
      ciphertext: ciphertext,
      additionalData: ad,
    );
    _n++;
    return pt;
  }

  /// Zeroizes and frees the key.
  void dispose() {
    _k?.dispose();
    _k = null;
  }
}
