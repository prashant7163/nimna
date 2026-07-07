/// Noise `HandshakeState` — token processing over a [NoiseSymmetricState]
/// (Noise spec rev 34, §5.3), implemented from the specification. Carries
/// the local/remote statics and ephemerals and drives `WriteMessage` /
/// `ReadMessage` for the message patterns the pairing driver hands it.
///
/// PSK-pattern rule (Noise §9.2): in psk patterns every `e` token
/// additionally calls `MixKey(e.public_key)`. That rule is
/// [mixKeyOnEphemeral] — `true` for `XXpsk2` (pairing, §3.1.3), `false` for
/// `KK` (sessions, §3.3.1). The engine is otherwise pattern-agnostic: KK
/// carries its two static public keys as pre-messages ([preMessagePublicKeys]
/// mixed into `h`, initiator's first) and its peer static is known from
/// pairing ([remoteStaticPublic]), so no `s` token ever crosses a KK frame.
/// Pure and locale-independent (all crypto is the S2-locked suite via
/// [NoiseSymmetricState] and [x25519]).
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
  /// initialization (Noise §5.3). For pairing this is `M0` (§3.1.3); for KK
  /// it is zero-length (§3.3.1). [preMessagePublicKeys] are then mixed into
  /// `h` in order (Noise pre-message rule): empty for XXpsk2, the two static
  /// public keys (initiator's first) for KK. A pre-set [e] (test injection or
  /// a joiner that pre-committed its ephemeral in `M0`) is reused by the first
  /// `e` token instead of a fresh generation. [remoteStaticPublic] pre-sets
  /// the peer static known since pairing (KK); XXpsk2 leaves it null and
  /// learns it from an `s` token. [psk] is the code-derived pre-shared key
  /// (§3.1.2); null for KK. [mixKeyOnEphemeral] applies the psk-pattern `e`
  /// rule (§9.2) — true for XXpsk2, false for KK.
  NoiseHandshakeState({
    required this._sodium,
    required AtRestAead aead,
    required this.role,
    required String protocolName,
    required Uint8List prologue,
    required this._staticKeyPair,
    this._psk,
    NoiseKeyPair? ephemeral,
    Uint8List? remoteStaticPublic,
    List<Uint8List> preMessagePublicKeys = const [],
    this.mixKeyOnEphemeral = true,
  }) : _e = ephemeral,
       _rs = remoteStaticPublic == null
           ? null
           : Uint8List.fromList(remoteStaticPublic),
       symm = NoiseSymmetricState.initialize(aead, protocolName) {
    symm.mixHash(prologue);
    for (final pub in preMessagePublicKeys) {
      symm.mixHash(pub);
    }
  }

  final SodiumSumo _sodium;
  final NoiseRole role;
  final NoiseSymmetricState symm;

  /// psk-pattern `e`/MixKey rule (Noise §9.2): true for XXpsk2, false for KK.
  final bool mixKeyOnEphemeral;

  final NoiseKeyPair _staticKeyPair;
  NoiseKeyPair? _e;
  final SecureKey? _psk;
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
          if (mixKeyOnEphemeral) {
            symm.mixKey(ePub); // psk-pattern rule (§9.2); XXpsk2 only.
          }
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
          if (mixKeyOnEphemeral) {
            symm.mixKey(re); // psk-pattern rule (§9.2); XXpsk2 only.
          }
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
    final psk = _psk;
    if (psk == null) {
      throw StateError('psk token in a pattern with no psk');
    }
    psk.runUnlockedSync((bytes) {
      symm.mixKeyAndHash(Uint8List.fromList(bytes));
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
