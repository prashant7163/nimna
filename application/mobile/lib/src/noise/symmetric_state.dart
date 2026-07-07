/// Noise `SymmetricState` — the chaining key + handshake hash + cipher of a
/// handshake (Noise spec rev 34, §5.2), implemented from the specification.
///
/// SHA-256 is `package:crypto` (S2 suite); the Noise HKDF (2- and 3-output
/// forms and Split) is the in-repo RFC 5869 [hkdfSha256] with the chaining
/// key as the extract salt and empty `info` — Noise's `HKDF(ck, ikm, n)`
/// is exactly RFC 5869 extract-then-expand, so the vector-locked
/// composition is reused byte-for-byte. Pure and locale-independent.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../crypto/at_rest_aead.dart';
import '../crypto/hkdf.dart';
import 'cipher_state.dart';

/// The `SHA256` hash length (Noise `HASHLEN`).
const int _hashLen = 32;

/// Holds `ck`, `h`, and the [NoiseCipherState]. `ck`/`h` are transient
/// key-adjacent material held in Dart buffers and zeroized on [dispose]
/// (consistent with [hkdfSha256] returning a `Uint8List`); the whole state
/// is wiped fail-closed by the driver on any failure or on finalization.
class NoiseSymmetricState {
  NoiseSymmetricState._(this._ck, this._h, this.cipher);

  /// `InitializeSymmetric(protocol_name)` (Noise §5.2): if the name fits in
  /// `HASHLEN`, `h` is the name zero-padded; otherwise `h = HASH(name)`.
  /// `ck = h`; the cipher starts empty.
  factory NoiseSymmetricState.initialize(AtRestAead aead, String protocolName) {
    final name = ascii.encode(protocolName);
    final Uint8List h;
    if (name.length <= _hashLen) {
      h = Uint8List(_hashLen)..setAll(0, name);
    } else {
      h = Uint8List.fromList(sha256.convert(name).bytes);
    }
    final ck = Uint8List.fromList(h);
    return NoiseSymmetricState._(ck, h, NoiseCipherState(aead));
  }

  Uint8List _ck;
  Uint8List _h;

  /// The keyed AEAD half (exposed so drivers can read `has_key` for
  /// length-prefix decisions).
  final NoiseCipherState cipher;

  /// The current chaining key (a COPY — for the test oracle only).
  Uint8List get chainingKey => Uint8List.fromList(_ck);

  /// The current handshake hash (a COPY — this is the AEAD `ad` and the
  /// test-oracle checkpoint).
  Uint8List get handshakeHash => Uint8List.fromList(_h);

  /// `MixKey(ikm)` (Noise §5.2): `(ck, temp_k) = HKDF(ck, ikm, 2)`, then the
  /// cipher is re-keyed with `temp_k`.
  void mixKey(Uint8List ikm) {
    final out = hkdfSha256(ikm: ikm, salt: _ck, info: const [], length: 64);
    _replaceCk(out, 0);
    final tempK = Uint8List.sublistView(out, 32, 64);
    cipher.initializeKey(tempK);
    out.fillRange(0, out.length, 0);
  }

  /// `MixHash(data)` (Noise §5.2): `h = HASH(h ‖ data)`.
  void mixHash(Uint8List data) {
    final next = sha256.convert(<int>[..._h, ...data]).bytes;
    _h = Uint8List.fromList(next);
  }

  /// `MixKeyAndHash(ikm)` (Noise §5.2, for the `psk` token):
  /// `(ck, temp_h, temp_k) = HKDF(ck, ikm, 3)`, `MixHash(temp_h)`, re-key
  /// with `temp_k`.
  void mixKeyAndHash(Uint8List ikm) {
    final out = hkdfSha256(ikm: ikm, salt: _ck, info: const [], length: 96);
    _replaceCk(out, 0);
    mixHash(Uint8List.fromList(Uint8List.sublistView(out, 32, 64)));
    cipher.initializeKey(Uint8List.sublistView(out, 64, 96));
    out.fillRange(0, out.length, 0);
  }

  /// `EncryptAndHash(plaintext)` (Noise §5.2).
  Uint8List encryptAndHash(Uint8List plaintext) {
    final ct = cipher.encryptWithAd(_h, plaintext);
    mixHash(ct);
    return ct;
  }

  /// `DecryptAndHash(ciphertext)` (Noise §5.2). Throws on AEAD failure.
  Uint8List decryptAndHash(Uint8List ciphertext) {
    final pt = cipher.decryptWithAd(_h, ciphertext);
    mixHash(ciphertext);
    return pt;
  }

  /// `Split()` (Noise §5.2): `(temp_k1, temp_k2) = HKDF(ck, empty, 2)`.
  /// Returns `(k1, k2)` — for XXpsk2, `k1` is initiator→responder and `k2`
  /// is responder→initiator (§3.1.3, confirmed by the committed vectors).
  /// The caller owns the returned buffers.
  (Uint8List, Uint8List) split() {
    final out = hkdfSha256(
      ikm: const [],
      salt: _ck,
      info: const [],
      length: 64,
    );
    final k1 = Uint8List.fromList(Uint8List.sublistView(out, 0, 32));
    final k2 = Uint8List.fromList(Uint8List.sublistView(out, 32, 64));
    out.fillRange(0, out.length, 0);
    return (k1, k2);
  }

  void _replaceCk(Uint8List source, int offset) {
    _ck.fillRange(0, _ck.length, 0);
    _ck = Uint8List.fromList(
      Uint8List.sublistView(source, offset, offset + 32),
    );
  }

  /// Zeroizes `ck`, `h`, and the cipher key.
  void dispose() {
    _ck.fillRange(0, _ck.length, 0);
    _h.fillRange(0, _h.length, 0);
    cipher.dispose();
  }
}
