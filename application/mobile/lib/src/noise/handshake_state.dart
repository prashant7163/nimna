/// Noise `HandshakeState` — token processing over a [NoiseSymmetricState]
/// (Noise spec rev 34, §5.3), implemented from the specification. Carries
/// the local/remote statics and ephemerals and drives `WriteMessage` /
/// `ReadMessage` for the message patterns the pairing driver hands it.
///
/// PSK-pattern rule (Noise §9.2): every `e` token additionally calls
/// `MixKey(e.public_key)`. This engine only ever runs `XXpsk2`, so the PSK
/// rule is always active. Pure and locale-independent (all crypto is the
/// S2-locked suite via [NoiseSymmetricState] and [x25519]).
library;

import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/at_rest_aead.dart';
import 'dh.dart';
import 'symmetric_state.dart';

/// The two Noise roles.
enum NoiseRole { initiator, responder }

/// The Noise message tokens this engine understands.
enum NoiseToken { e, s, ee, es, se, ss, psk }

/// 32-byte X25519 public-key length (also the ephemeral wire length).
const int _dhLen = 32;

class NoiseHandshakeState {
  /// [prologue] is mixed into `h` immediately after protocol-name
  /// initialization (Noise §5.3). For pairing this is `M0` (§3.1.3). A
  /// pre-set [e] (test injection or a joiner that pre-committed its
  /// ephemeral in `M0`) is reused by the first `e` token instead of a fresh
  /// generation. [psk] is the code-derived pre-shared key (§3.1.2).
  NoiseHandshakeState({
    required this._sodium,
    required AtRestAead aead,
    required this.role,
    required String protocolName,
    required Uint8List prologue,
    required this._staticKeyPair,
    required this._psk,
    NoiseKeyPair? ephemeral,
  }) : _e = ephemeral,
       symm = NoiseSymmetricState.initialize(aead, protocolName) {
    symm.mixHash(prologue);
  }

  final SodiumSumo _sodium;
  final NoiseRole role;
  final NoiseSymmetricState symm;

  final NoiseKeyPair _staticKeyPair;
  NoiseKeyPair? _e;
  final SecureKey _psk;
  Uint8List? _rs;
  Uint8List? _re;

  /// The decrypted remote static public key (available after the message
  /// carrying the peer's `s` token has been read).
  Uint8List? get remoteStatic => _rs == null ? null : Uint8List.fromList(_rs!);

  /// The remote ephemeral public key (available after the peer's `e` token).
  Uint8List? get remoteEphemeral =>
      _re == null ? null : Uint8List.fromList(_re!);

  /// The local ephemeral public key (after it has been generated/set).
  Uint8List? get localEphemeral =>
      _e == null ? null : Uint8List.fromList(_e!.publicKey);

  /// `WriteMessage(payload)` for the given token sequence (Noise §5.3).
  Uint8List writeMessage(List<NoiseToken> tokens, Uint8List payload) {
    final buffer = BytesBuilder(copy: false);
    for (final token in tokens) {
      switch (token) {
        case NoiseToken.e:
          _e ??= generateNoiseKeyPair(_sodium);
          final ePub = _e!.publicKey;
          buffer.add(ePub);
          symm.mixHash(ePub);
          symm.mixKey(ePub); // PSK-pattern rule (§9.2).
        case NoiseToken.s:
          buffer.add(symm.encryptAndHash(_staticKeyPair.publicKey));
        case NoiseToken.ee:
        case NoiseToken.es:
        case NoiseToken.se:
        case NoiseToken.ss:
          _mixDh(token);
        case NoiseToken.psk:
          _mixPsk();
      }
    }
    buffer.add(symm.encryptAndHash(payload));
    return buffer.toBytes();
  }

  /// `ReadMessage(message)` for the given token sequence (Noise §5.3).
  /// Throws on any AEAD failure or a short buffer (a structural handshake
  /// failure — fail-closed, §3.1.6).
  Uint8List readMessage(List<NoiseToken> tokens, Uint8List message) {
    var offset = 0;
    Uint8List take(int n) {
      if (offset + n > message.length) {
        throw ArgumentError('short Noise message');
      }
      final slice = Uint8List.sublistView(message, offset, offset + n);
      offset += n;
      return Uint8List.fromList(slice);
    }

    for (final token in tokens) {
      switch (token) {
        case NoiseToken.e:
          final re = take(_dhLen);
          _re = re;
          symm.mixHash(re);
          symm.mixKey(re); // PSK-pattern rule (§9.2).
        case NoiseToken.s:
          final len = symm.cipher.hasKey
              ? _dhLen + AtRestAead.macBytes
              : _dhLen;
          _rs = symm.decryptAndHash(take(len));
        case NoiseToken.ee:
        case NoiseToken.es:
        case NoiseToken.se:
        case NoiseToken.ss:
          _mixDh(token);
        case NoiseToken.psk:
          _mixPsk();
      }
    }
    final rest = Uint8List.fromList(
      Uint8List.sublistView(message, offset, message.length),
    );
    return symm.decryptAndHash(rest);
  }

  /// `Split()` (Noise §5.2) — returns `(k_ir, k_ri)` (§3.1.3).
  (Uint8List, Uint8List) split() => symm.split();

  void _mixDh(NoiseToken token) {
    final SecureKey scalar;
    final Uint8List point;
    switch (token) {
      case NoiseToken.ee:
        scalar = _e!.secretKey;
        point = _re!;
      case NoiseToken.es:
        if (role == NoiseRole.initiator) {
          scalar = _e!.secretKey;
          point = _rs!;
        } else {
          scalar = _staticKeyPair.secretKey;
          point = _re!;
        }
      case NoiseToken.se:
        if (role == NoiseRole.initiator) {
          scalar = _staticKeyPair.secretKey;
          point = _re!;
        } else {
          scalar = _e!.secretKey;
          point = _rs!;
        }
      case NoiseToken.ss:
        scalar = _staticKeyPair.secretKey;
        point = _rs!;
      case NoiseToken.e:
      case NoiseToken.s:
      case NoiseToken.psk:
        throw StateError('not a DH token');
    }
    final shared = x25519(sodium: _sodium, scalar: scalar, point: point);
    try {
      symm.mixKey(shared);
    } finally {
      shared.fillRange(0, shared.length, 0);
    }
  }

  void _mixPsk() {
    _psk.runUnlockedSync((psk) {
      symm.mixKeyAndHash(Uint8List.fromList(psk));
    });
  }

  /// Wipes the symmetric state and the ephemeral (the static and psk are
  /// owned by the driver, which disposes them). Idempotent.
  void dispose() {
    symm.dispose();
    _e?.dispose();
    _e = null;
  }
}
