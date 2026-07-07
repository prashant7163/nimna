/// XXpsk2 pairing-handshake role drivers (spec §3.1.3) — the joiner (Noise
/// initiator) and creator (Noise responder) engines that produce M1–M4 and
/// the finalized channel material. Composed ONLY from already-signed-off
/// primitives via [NoiseHandshakeState] (X25519 + ChaCha20-Poly1305-IETF +
/// SHA-256 + in-repo HKDF); NO Noise library (crypto lock).
///
/// Byte-locked to `docs/test-vectors/pairing-handshake.json`. Fail-closed:
/// any AEAD failure, short buffer, malformed token_payload, or commitment
/// mismatch throws and the driver wipes all handshake state (§3.1.6). Pure
/// and locale-independent.
library;

import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/at_rest_aead.dart';
import '../protocol/channel_identity.dart';
import '../protocol/commitment.dart';
import '../protocol/token_payload.dart';
import 'dh.dart';
import 'handshake_state.dart';

/// The pairing Noise protocol name (spec §3.1.3, §7).
const String pairingProtocolName = 'Noise_XXpsk2_25519_ChaChaPoly_SHA256';

/// The M4 PAIR_CONFIRM nonce (spec §5.6): direction constant
/// `0x00000001` (responder→initiator) ‖ 64-bit counter `0`.
Uint8List pairConfirmNonce() {
  final nonce = Uint8List(AtRestAead.nonceBytes);
  nonce[3] = 0x01;
  return nonce;
}

/// Raised on any pairing-handshake failure — the single fail-closed outcome
/// class (§3.1.6). Carries no bytes by design.
class PairingHandshakeError extends Error {
  @override
  String toString() => 'PairingHandshakeError';
}

/// Finalized channel material handed to the controller after a valid
/// handshake. [ss] is sensitive (the static-static shared secret) and is
/// held only long enough to derive the safety phrase; the caller MUST
/// [disposeSecret] it. Nothing extra is persisted — CRID and phrase are
/// re-derivable from the statics (spec §3.1.4/§3.1.5/§6).
class PairingChannelMaterial {
  PairingChannelMaterial({
    required this.peerStaticPublic,
    required this.crid,
    required this.ss,
    required this.peerToken,
  });

  final Uint8List peerStaticPublic;
  final Uint8List crid;

  /// `ss = X25519(own static priv, peer static pub)` — transient.
  final Uint8List ss;

  /// The peer's decrypted device-token payload (§5.7); "absent" when the
  /// peer has push off. Stored encrypted at finalization (§3.2.1) so S15
  /// needs no retrofit.
  final TokenPayload peerToken;

  void disposeSecret() => ss.fillRange(0, ss.length, 0);
}

Uint8List _deriveSs({
  required SodiumSumo sodium,
  required SecureKey ownStaticPrivate,
  required Uint8List peerStaticPublic,
}) => x25519(sodium: sodium, scalar: ownStaticPrivate, point: peerStaticPublic);

Uint8List _confirmM4({
  required AtRestAead aead,
  required Uint8List kRi,
  required Uint8List outerHeader,
}) {
  final key = SecureKey.fromList(aead.sodium, kRi);
  try {
    return aead.encrypt(
      key: key,
      nonce: pairConfirmNonce(),
      plaintext: Uint8List(0),
      additionalData: outerHeader,
    );
  } finally {
    key.dispose();
  }
}

void _verifyM4({
  required AtRestAead aead,
  required Uint8List kRi,
  required Uint8List m4,
  required Uint8List outerHeader,
}) {
  final key = SecureKey.fromList(aead.sodium, kRi);
  try {
    aead.decrypt(
      key: key,
      nonce: pairConfirmNonce(),
      ciphertext: m4,
      additionalData: outerHeader,
    );
  } on AeadAuthError {
    throw PairingHandshakeError();
  } finally {
    key.dispose();
  }
}

/// The JOINER side (Noise initiator, spec §3.1.3): sends M1, receives M2,
/// sends M3, and finalizes on a valid M4. Owns its ephemeral; the caller
/// owns [staticKeyPair] and [psk].
class NoiseJoinerHandshake {
  NoiseJoinerHandshake({
    required this._sodium,
    required this._aead,
    required NoiseKeyPair staticKeyPair,
    required this._psk,
    required this._tokenPayload,
    this._ephemeral,
  }) : _static = staticKeyPair;

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final NoiseKeyPair _static;
  final SecureKey _psk;
  final TokenPayload _tokenPayload;

  NoiseKeyPair? _ephemeral;
  NoiseHandshakeState? _hs;
  Uint8List? _kRi;
  TokenPayload? _creatorToken;
  bool _done = false;

  /// Generates the joiner ephemeral (unless injected), computes the M0
  /// commitment, and writes M1 = `M0 ‖ e ‖ tag` (spec §3.1.3).
  Uint8List writeM1() {
    _ephemeral ??= generateNoiseKeyPair(_sodium);
    final m0 = commitmentM0(
      joinerEphemeralPublic: _ephemeral!.publicKey,
      joinerStaticPublic: _static.publicKey,
    );
    _hs = NoiseHandshakeState(
      sodium: _sodium,
      aead: _aead,
      role: NoiseRole.initiator,
      protocolName: pairingProtocolName,
      prologue: m0,
      staticKeyPair: _static,
      psk: _psk,
      ephemeral: _ephemeral,
    );
    try {
      final body = _hs!.writeMessage(const [NoiseToken.e], Uint8List(0));
      return Uint8List.fromList([...m0, ...body]);
    } catch (_) {
      dispose();
      throw PairingHandshakeError();
    }
  }

  /// Reads M2 (spec §3.1.3), recovering the creator's static public key and
  /// device-token payload.
  void readM2(Uint8List m2) {
    final hs = _hs;
    if (hs == null) {
      throw PairingHandshakeError();
    }
    try {
      final payload = hs.readMessage(const [
        NoiseToken.e,
        NoiseToken.ee,
        NoiseToken.s,
        NoiseToken.es,
        NoiseToken.psk,
      ], m2);
      _creatorToken = TokenPayload.decode(payload);
    } catch (_) {
      dispose();
      throw PairingHandshakeError();
    }
  }

  /// Writes M3 (spec §3.1.3), carrying the joiner's own device-token.
  Uint8List writeM3() {
    final hs = _hs;
    if (hs == null) {
      throw PairingHandshakeError();
    }
    try {
      return hs.writeMessage(const [
        NoiseToken.s,
        NoiseToken.se,
      ], _tokenPayload.encode());
    } catch (_) {
      dispose();
      throw PairingHandshakeError();
    }
  }

  /// Splits the handshake and verifies M4 PAIR_CONFIRM (spec §3.1.3/§5.6).
  /// A valid M4 is the sole finalization signal for the joiner — without it
  /// everything is discarded (no half-open channels).
  void completeWithM4(Uint8List m4, Uint8List outerHeader) {
    final hs = _hs;
    if (hs == null) {
      throw PairingHandshakeError();
    }
    Uint8List? kIr;
    try {
      final (a, b) = hs.split();
      kIr = a;
      _kRi = b;
      _verifyM4(aead: _aead, kRi: _kRi!, m4: m4, outerHeader: outerHeader);
      _done = true;
    } catch (e) {
      dispose();
      if (e is PairingHandshakeError) {
        rethrow;
      }
      throw PairingHandshakeError();
    } finally {
      kIr?.fillRange(0, kIr.length, 0);
    }
  }

  /// Derives the finalized channel material (spec §3.1.4/§3.1.5). Only valid
  /// after [completeWithM4].
  PairingChannelMaterial finalizeChannel() {
    if (!_done || _creatorToken == null) {
      throw PairingHandshakeError();
    }
    final peerStatic = _hs!.remoteStatic!;
    final ss = _deriveSs(
      sodium: _sodium,
      ownStaticPrivate: _static.secretKey,
      peerStaticPublic: peerStatic,
    );
    final salt2 = channelSalt2(aPublic: _static.publicKey, bPublic: peerStatic);
    final crid = deriveCrid(ss: ss, salt2: salt2);
    return PairingChannelMaterial(
      peerStaticPublic: peerStatic,
      crid: crid,
      ss: ss,
      peerToken: _creatorToken!,
    );
  }

  /// Fail-closed wipe of all handshake state (§3.1.6). The static keypair
  /// and psk are owned by the caller.
  void dispose() {
    _hs?.dispose();
    _hs = null;
    _kRi?.fillRange(0, _kRi!.length, 0);
    _kRi = null;
    _ephemeral?.dispose();
    _ephemeral = null;
  }
}

/// The CREATOR side (Noise responder, spec §3.1.3): receives M1, sends M2,
/// receives M3 (verifying the M0 commitment), and sends M4. Owns its
/// ephemeral; the caller owns [staticKeyPair] and [psk].
class NoiseResponderHandshake {
  NoiseResponderHandshake({
    required this._sodium,
    required this._aead,
    required NoiseKeyPair staticKeyPair,
    required this._psk,
    required this._tokenPayload,
    this._ephemeral,
  }) : _static = staticKeyPair;

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final NoiseKeyPair _static;
  final SecureKey _psk;
  final TokenPayload _tokenPayload;

  NoiseKeyPair? _ephemeral;
  NoiseHandshakeState? _hs;
  Uint8List? _m0;
  Uint8List? _kRi;
  TokenPayload? _joinerToken;
  bool _done = false;

  /// Reads M1 = `M0 ‖ e ‖ tag` (spec §3.1.3): extracts M0 as the prologue,
  /// then reads the joiner's ephemeral.
  void readM1(Uint8List m1) {
    if (m1.length < 32) {
      throw PairingHandshakeError();
    }
    final m0 = Uint8List.fromList(Uint8List.sublistView(m1, 0, 32));
    _m0 = m0;
    _hs = NoiseHandshakeState(
      sodium: _sodium,
      aead: _aead,
      role: NoiseRole.responder,
      protocolName: pairingProtocolName,
      prologue: m0,
      staticKeyPair: _static,
      psk: _psk,
      ephemeral: _ephemeral,
    );
    try {
      _hs!.readMessage(const [
        NoiseToken.e,
      ], Uint8List.fromList(Uint8List.sublistView(m1, 32, m1.length)));
    } catch (_) {
      dispose();
      throw PairingHandshakeError();
    }
  }

  /// Writes M2 (spec §3.1.3), carrying the creator's own device-token.
  Uint8List writeM2() {
    final hs = _hs;
    if (hs == null) {
      throw PairingHandshakeError();
    }
    try {
      return hs.writeMessage(const [
        NoiseToken.e,
        NoiseToken.ee,
        NoiseToken.s,
        NoiseToken.es,
        NoiseToken.psk,
      ], _tokenPayload.encode());
    } catch (_) {
      dispose();
      throw PairingHandshakeError();
    }
  }

  /// Reads M3 (spec §3.1.3), recovering the joiner's static and token, then
  /// verifies `M0 == SHA-256("nimna/commit/v1" ‖ eB_pub ‖ sB_pub)`. A
  /// mismatch is a fail-closed handshake failure (§3.1.6).
  void readM3(Uint8List m3) {
    final hs = _hs;
    if (hs == null) {
      throw PairingHandshakeError();
    }
    try {
      final payload = hs.readMessage(const [NoiseToken.s, NoiseToken.se], m3);
      _joinerToken = TokenPayload.decode(payload);
      final expected = commitmentM0(
        joinerEphemeralPublic: hs.remoteEphemeral!,
        joinerStaticPublic: hs.remoteStatic!,
      );
      if (!_aead.constantTimeEquals(expected, _m0!)) {
        throw PairingHandshakeError();
      }
    } catch (e) {
      dispose();
      if (e is PairingHandshakeError) {
        rethrow;
      }
      throw PairingHandshakeError();
    }
  }

  /// Splits and writes M4 PAIR_CONFIRM (spec §3.1.3/§5.6) over [outerHeader]
  /// (the M4 outer-frame header, the AEAD `ad`).
  Uint8List writeM4(Uint8List outerHeader) {
    final hs = _hs;
    if (hs == null || _joinerToken == null) {
      throw PairingHandshakeError();
    }
    Uint8List? kIr;
    try {
      final (a, b) = hs.split();
      kIr = a;
      _kRi = b;
      final m4 = _confirmM4(aead: _aead, kRi: _kRi!, outerHeader: outerHeader);
      _done = true;
      return m4;
    } catch (_) {
      dispose();
      throw PairingHandshakeError();
    } finally {
      kIr?.fillRange(0, kIr.length, 0);
    }
  }

  /// Derives the finalized channel material (spec §3.1.4/§3.1.5). Only valid
  /// after [writeM4].
  PairingChannelMaterial finalizeChannel() {
    if (!_done || _joinerToken == null) {
      throw PairingHandshakeError();
    }
    final peerStatic = _hs!.remoteStatic!;
    final ss = _deriveSs(
      sodium: _sodium,
      ownStaticPrivate: _static.secretKey,
      peerStaticPublic: peerStatic,
    );
    final salt2 = channelSalt2(aPublic: _static.publicKey, bPublic: peerStatic);
    final crid = deriveCrid(ss: ss, salt2: salt2);
    return PairingChannelMaterial(
      peerStaticPublic: peerStatic,
      crid: crid,
      ss: ss,
      peerToken: _joinerToken!,
    );
  }

  /// Fail-closed wipe of all handshake state (§3.1.6).
  void dispose() {
    _hs?.dispose();
    _hs = null;
    _kRi?.fillRange(0, _kRi!.length, 0);
    _kRi = null;
    _ephemeral?.dispose();
    _ephemeral = null;
  }
}
