/// Noise_KK session-handshake role drivers (spec §3.3.1) — the knocker
/// (Noise initiator) and accepter (Noise responder) engines that exchange
/// S1/S2 on a fresh bridge and Split into the per-direction transport keys.
/// Composed ONLY from already-signed-off primitives via [NoiseHandshakeState]
/// (X25519 + ChaCha20-Poly1305-IETF + SHA-256 + in-repo HKDF); NO Noise
/// library (crypto lock).
///
/// KK reuses the S9 XXpsk2 engine unchanged except for the two psk-vs-KK
/// parameters it now exposes: `mixKeyOnEphemeral = false` (no psk-pattern `e`
/// rule) and the KK pre-messages/known-peer-static (both static public keys
/// mixed into `h`, initiator's first; the peer static known since pairing, so
/// no `s` token crosses a KK frame). Prologue is zero-length; payloads are
/// zero-length; S1/S2 are 48 bytes each (`epub(32) ‖ tag-over-empty(16)`).
///
/// Byte-locked to `docs/test-vectors/session-handshake.json`. Fail-closed:
/// any AEAD failure or short buffer throws [SessionHandshakeError] and the
/// driver wipes all handshake state (§3.3.1). Pure and locale-independent.
library;

import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/at_rest_aead.dart';
import 'dh.dart';
import 'handshake_state.dart';
import 'noise_transport.dart';

/// The session Noise protocol name (spec §3.3.1, §7).
const String sessionProtocolName = 'Noise_KK_25519_ChaChaPoly_SHA256';

/// Raised on any session-handshake failure — the fail-closed outcome class
/// (§3.3.1). Carries no bytes by design.
class SessionHandshakeError extends Error {
  @override
  String toString() => 'SessionHandshakeError';
}

/// The pair of transport channels a finished handshake yields for one role:
/// [send] and [receive], each a keyed [NoiseTransport] on its correct
/// direction (§5.6). The knocker sends on `k_ir`/receives on `k_ri`; the
/// accepter is the mirror.
class SessionTransport {
  SessionTransport({required this.send, required this.receive});

  final NoiseTransport send;
  final NoiseTransport receive;

  /// Destroys both direction keys (session teardown / panic wipe).
  void destroy() {
    send.destroy();
    receive.destroy();
  }
}

/// KK pre-messages MixHash order: initiator static public key first, then
/// responder static (Noise pre-message rules, §3.3.1). Identical on both
/// roles, so the two ends' handshake hashes agree.
List<Uint8List> _kkPreMessages({
  required Uint8List initiatorStaticPublic,
  required Uint8List responderStaticPublic,
}) => [initiatorStaticPublic, responderStaticPublic];

SessionTransport _buildTransport({
  required AtRestAead aead,
  required NoiseRole role,
  required Uint8List kIr,
  required Uint8List kRi,
}) {
  try {
    final ir = NoiseTransport(
      aead: aead,
      key: kIr,
      direction: TransportDirection.initiatorToResponder,
    );
    final ri = NoiseTransport(
      aead: aead,
      key: kRi,
      direction: TransportDirection.responderToInitiator,
    );
    return role == NoiseRole.initiator
        ? SessionTransport(send: ir, receive: ri)
        : SessionTransport(send: ri, receive: ir);
  } finally {
    kIr.fillRange(0, kIr.length, 0);
    kRi.fillRange(0, kRi.length, 0);
  }
}

/// The KNOCKER side (Noise initiator, spec §3.3.1): writes S1 `→ e, es, ss`,
/// reads S2 `← e, ee, se`, and Splits into the transport keys. Owns its
/// ephemeral; the caller owns [staticKeyPair].
class SessionInitiatorHandshake {
  SessionInitiatorHandshake({
    required this._sodium,
    required this._aead,
    required NoiseKeyPair staticKeyPair,
    required Uint8List peerStaticPublic,
    this._ephemeral,
  }) : _static = staticKeyPair,
       _peerStatic = Uint8List.fromList(peerStaticPublic);

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final NoiseKeyPair _static;
  final Uint8List _peerStatic;

  NoiseKeyPair? _ephemeral;
  NoiseHandshakeState? _hs;

  /// Builds the KK handshake state and writes S1 = `e ‖ tag-over-empty`
  /// (48 bytes, spec §3.3.1).
  Uint8List writeS1() {
    _hs = NoiseHandshakeState(
      sodium: _sodium,
      aead: _aead,
      role: NoiseRole.initiator,
      protocolName: sessionProtocolName,
      prologue: Uint8List(0),
      staticKeyPair: _static,
      ephemeral: _ephemeral,
      remoteStaticPublic: _peerStatic,
      preMessagePublicKeys: _kkPreMessages(
        initiatorStaticPublic: _static.publicKey,
        responderStaticPublic: _peerStatic,
      ),
      mixKeyOnEphemeral: false,
    );
    try {
      return _hs!.writeMessage(const [
        NoiseToken.e,
        NoiseToken.es,
        NoiseToken.ss,
      ], Uint8List(0));
    } catch (_) {
      dispose();
      throw SessionHandshakeError();
    }
  }

  /// Reads S2 (spec §3.3.1) and Splits into `(k_ir, k_ri)`, returning the
  /// knocker's [SessionTransport]. A malformed or unauthenticated S2 is a
  /// fail-closed protocol error.
  SessionTransport completeWithS2(Uint8List s2) {
    final hs = _hs;
    if (hs == null) {
      throw SessionHandshakeError();
    }
    try {
      hs.readMessage(const [NoiseToken.e, NoiseToken.ee, NoiseToken.se], s2);
      final (kIr, kRi) = hs.split();
      return _buildTransport(
        aead: _aead,
        role: NoiseRole.initiator,
        kIr: kIr,
        kRi: kRi,
      );
    } catch (_) {
      dispose();
      throw SessionHandshakeError();
    } finally {
      dispose();
    }
  }

  /// Fail-closed wipe of the handshake state and ephemeral (§3.3.1). The
  /// static keypair is owned by the caller. Idempotent.
  void dispose() {
    _hs?.dispose();
    _hs = null;
    _ephemeral?.dispose();
    _ephemeral = null;
  }
}

/// The ACCEPTER side (Noise responder, spec §3.3.1): reads S1 `→ e, es, ss`,
/// writes S2 `← e, ee, se`, and Splits into the transport keys. Owns its
/// ephemeral; the caller owns [staticKeyPair].
class SessionResponderHandshake {
  SessionResponderHandshake({
    required this._sodium,
    required this._aead,
    required NoiseKeyPair staticKeyPair,
    required Uint8List peerStaticPublic,
    this._ephemeral,
  }) : _static = staticKeyPair,
       _peerStatic = Uint8List.fromList(peerStaticPublic);

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final NoiseKeyPair _static;
  final Uint8List _peerStatic;

  NoiseKeyPair? _ephemeral;
  NoiseHandshakeState? _hs;

  /// Builds the KK handshake state and reads S1 (spec §3.3.1). A malformed or
  /// unauthenticated S1 is a fail-closed protocol error.
  void readS1(Uint8List s1) {
    _hs = NoiseHandshakeState(
      sodium: _sodium,
      aead: _aead,
      role: NoiseRole.responder,
      protocolName: sessionProtocolName,
      prologue: Uint8List(0),
      staticKeyPair: _static,
      ephemeral: _ephemeral,
      remoteStaticPublic: _peerStatic,
      preMessagePublicKeys: _kkPreMessages(
        initiatorStaticPublic: _peerStatic,
        responderStaticPublic: _static.publicKey,
      ),
      mixKeyOnEphemeral: false,
    );
    try {
      _hs!.readMessage(const [NoiseToken.e, NoiseToken.es, NoiseToken.ss], s1);
    } catch (_) {
      dispose();
      throw SessionHandshakeError();
    }
  }

  /// Writes S2 = `e ‖ tag-over-empty` (48 bytes, spec §3.3.1).
  Uint8List writeS2() {
    final hs = _hs;
    if (hs == null) {
      throw SessionHandshakeError();
    }
    try {
      return hs.writeMessage(const [
        NoiseToken.e,
        NoiseToken.ee,
        NoiseToken.se,
      ], Uint8List(0));
    } catch (_) {
      dispose();
      throw SessionHandshakeError();
    }
  }

  /// Splits into `(k_ir, k_ri)` and returns the accepter's
  /// [SessionTransport]. Only valid after [writeS2].
  SessionTransport deriveTransport() {
    final hs = _hs;
    if (hs == null) {
      throw SessionHandshakeError();
    }
    try {
      final (kIr, kRi) = hs.split();
      return _buildTransport(
        aead: _aead,
        role: NoiseRole.responder,
        kIr: kIr,
        kRi: kRi,
      );
    } catch (_) {
      throw SessionHandshakeError();
    } finally {
      dispose();
    }
  }

  /// Fail-closed wipe of the handshake state and ephemeral (§3.3.1).
  /// Idempotent.
  void dispose() {
    _hs?.dispose();
    _hs = null;
    _ephemeral?.dispose();
    _ephemeral = null;
  }
}
