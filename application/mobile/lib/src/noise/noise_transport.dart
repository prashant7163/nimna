/// Nimna post-Split transport discipline (spec §3.3.1, §5.6) — NOT the
/// generic Noise transport. One [NoiseTransport] drives one direction of a
/// live session:
///
///   - nonce = `direction(4, BE) ‖ counter(8, BE)` (initiator→responder
///     `0x00000000`, responder→initiator `0x00000001`); counter from 0,
///     strict increment, never reset; `2^64-1` forbidden (§5.6);
///   - AEAD `ad` = the 18-byte outer frame header (§5.4), binding every
///     ciphertext to its channel and position;
///   - per-message REKEY after EVERY seal/open (Noise §11.3): the old key is
///     zeroized immediately (per-message forward secrecy, §3.3.1);
///   - receiver enforcement is fail-closed — any AEAD failure destroys the
///     key and raises [TransportError], which the session layer acts on
///     (destroy all session keys + TEARDOWN, §3.3.1).
///
/// Keys live in [SecureKey] native memory. All crypto is the S2-locked
/// ChaCha20-Poly1305-IETF via [AtRestAead]/libsodium; this file only tracks
/// the key + counter and encodes the Nimna nonce. Pure of Flutter,
/// locale-independent.
library;

import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../crypto/at_rest_aead.dart';

/// Per-direction 32-bit big-endian nonce prefix (spec §5.6).
enum TransportDirection {
  /// initiator→responder: `0x00000000`.
  initiatorToResponder(0x00000000),

  /// responder→initiator: `0x00000001`.
  responderToInitiator(0x00000001);

  const TransportDirection(this.constant);

  /// The spec-fixed 32-bit direction constant.
  final int constant;
}

/// The reserved counter value `2^64-1` — its nonce collides with the REKEY
/// nonce, so it must never be used (spec §3.3.1). In Dart's two's-complement
/// 64-bit int this is `-1` (`0xFFFFFFFFFFFFFFFF`).
const int forbiddenCounter = -1;

/// A §3.3.1 transport protocol error — an AEAD failure or the forbidden
/// counter. Fail-closed: the direction key is destroyed before this throws;
/// the session layer must destroy the other direction and TEARDOWN. Carries
/// no bytes by design.
class TransportError extends Error {
  @override
  String toString() => 'TransportError';
}

/// Encodes a Nimna transport nonce: `direction(4, BE) ‖ counter(8, BE)`
/// (spec §5.6). The REKEY nonce is `transportNonce(0, forbiddenCounter)`.
Uint8List transportNonce(int direction, int counter) {
  final nonce = Uint8List(AtRestAead.nonceBytes);
  final bd = ByteData.sublistView(nonce);
  bd.setUint32(0, direction);
  bd.setUint64(4, counter);
  return nonce;
}

/// One direction of a live session's transport channel (spec §3.3.1, §5.6).
class NoiseTransport {
  /// Starts a direction with its post-Split key and [direction]. Takes a COPY
  /// of [key] into native memory; the caller still owns and should zeroize
  /// its [key] buffer.
  NoiseTransport({
    required AtRestAead aead,
    required Uint8List key,
    required this.direction,
  }) : _aead = aead,
       _key = SecureKey.fromList(aead.sodium, key);

  final AtRestAead _aead;

  /// The fixed direction constant for this channel (spec §5.6).
  final TransportDirection direction;

  SecureKey? _key;
  int _counter = 0;

  /// The next expected/used counter for this direction (test oracle).
  int get counter => _counter;

  /// Whether a key is still installed (false after [destroy] / a fatal open).
  bool get isLive => _key != null;

  /// Seals one frame: AEAD-encrypts [plaintext] under the current key/counter
  /// binding [outerHeader] (§5.4), then REKEYs and advances the counter.
  /// Returns `ciphertext ‖ tag(16)` — the `SESSION_DATA` payload (§5.4).
  Uint8List seal({
    required Uint8List outerHeader,
    required Uint8List plaintext,
  }) {
    final key = _requireLiveKey();
    _guardCounter();
    final ct = _aead.encrypt(
      key: key,
      nonce: transportNonce(direction.constant, _counter),
      plaintext: plaintext,
      additionalData: outerHeader,
    );
    _rekey();
    _counter++;
    return ct;
  }

  /// Opens one frame: AEAD-decrypts [ciphertext] under the current
  /// key/counter binding [outerHeader], then REKEYs and advances the counter.
  /// Any AEAD failure is fatal (§3.3.1): the key is destroyed and
  /// [TransportError] is thrown. A counter gap/repeat/regression manifests
  /// here as an AEAD failure — the receiver only ever tries its own next
  /// expected counter, so a reordered or replayed frame simply fails closed.
  Uint8List open({
    required Uint8List outerHeader,
    required Uint8List ciphertext,
  }) {
    final key = _requireLiveKey();
    _guardCounter();
    final Uint8List pt;
    try {
      pt = _aead.decrypt(
        key: key,
        nonce: transportNonce(direction.constant, _counter),
        ciphertext: ciphertext,
        additionalData: outerHeader,
      );
    } on AeadAuthError {
      destroy();
      throw TransportError();
    }
    _rekey();
    _counter++;
    return pt;
  }

  /// REKEY (Noise §11.3): `k ← first 32 bytes of Encrypt(k, nonce = 0…0 ‖
  /// 0xFF…FF, ad = empty, pt = 32 zero bytes)`. The old key is zeroized
  /// immediately (§3.3.1).
  void _rekey() {
    final zeros = Uint8List(32);
    final ct = _aead.encrypt(
      key: _key!,
      nonce: transportNonce(0, forbiddenCounter),
      plaintext: zeros,
      additionalData: Uint8List(0),
    );
    try {
      final next = Uint8List.fromList(Uint8List.sublistView(ct, 0, 32));
      _key!.dispose();
      _key = SecureKey.fromList(_aead.sodium, next);
      next.fillRange(0, next.length, 0);
    } finally {
      ct.fillRange(0, ct.length, 0);
    }
  }

  SecureKey _requireLiveKey() {
    final key = _key;
    if (key == null) {
      throw TransportError();
    }
    return key;
  }

  void _guardCounter() {
    if (_counter == forbiddenCounter) {
      destroy();
      throw TransportError();
    }
  }

  /// Zeroizes and frees this direction's key (session teardown / panic wipe).
  /// Idempotent.
  void destroy() {
    _key?.dispose();
    _key = null;
  }
}
