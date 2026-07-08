import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/noise/noise_transport.dart';
import 'package:nimna/src/noise/session_kk.dart';
import 'package:nimna/src/protocol/outer_frame.dart';

import '../helpers/test_env.dart';

/// §7.3 / §9.7 forward secrecy — "your own device seized": a captured session
/// transcript stays undecryptable even given BOTH sides' long-term static
/// keys, because Noise_KK mixes fresh ephemerals (`ee/es/se`) into the
/// transport keys and those ephemerals are wiped after the handshake (plus
/// the per-message REKEY throws the chain forward, §5.6).
///
/// This drives the REAL from-spec KK drivers to completion, captures the real
/// transport ciphertexts, and then hands an adversary the two static
/// privates. The only transport-derivation path the code exposes REQUIRES a
/// live handshake with ephemerals — a statics-only adversary can at best run a
/// FRESH handshake (fresh ephemerals ⇒ different keys), which fails to open
/// the captured frames. The suite had no forward-secrecy assertion before.
void main() {
  Uint8List header(Uint8List crid) => Uint8List.sublistView(
    OuterFrame(type: FrameType.sessionData, routingId: crid).encode(),
    0,
    outerHeaderBytes,
  );

  test('captured frames do not decrypt from the long-term statics alone '
      '(§7.3)', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);

    // The two devices' long-term channel statics — the ONLY secrets a later
    // seizure of both handsets yields (ephemerals are gone).
    final iStatic = generateNoiseKeyPair(sodium);
    final rStatic = generateNoiseKeyPair(sodium);
    final crid = aead.randomBytes(16);
    addTearDown(() {
      iStatic.dispose();
      rStatic.dispose();
    });

    // ---- the real live session -----------------------------------------
    final knocker = SessionInitiatorHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: iStatic,
      peerStaticPublic: rStatic.publicKey,
    );
    final accepter = SessionResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: rStatic,
      peerStaticPublic: iStatic.publicKey,
    );
    accepter.readS1(knocker.writeS1());
    final iTx = knocker.completeWithS2(accepter.writeS2());
    final rTx = accepter.deriveTransport();
    addTearDown(() {
      iTx.destroy();
      rTx.destroy();
    });

    // Capture a few initiator→responder frames off the wire (what an observer
    // with a recorder would keep). Prove each is genuine ciphertext by opening
    // it with the LEGITIMATE receiver exactly once.
    final captured = <Uint8List>[];
    final plaintexts = <Uint8List>[];
    for (var i = 0; i < 3; i++) {
      final pt = Uint8List.fromList(utf8.encode('secret line $i'));
      final ct = iTx.send.seal(outerHeader: header(crid), plaintext: pt);
      captured.add(Uint8List.fromList(ct));
      plaintexts.add(pt);
      // Legit peer opens it (advances rTx.receive counter + rekey).
      expect(rTx.receive.open(outerHeader: header(crid), ciphertext: ct), pt);
    }

    // ---- the adversary: holds BOTH static privates, ephemerals gone -----
    // The best a statics-only adversary can do is run a fresh KK handshake
    // with the seized statics; fresh ephemerals ⇒ a different `k_ir`. It is
    // set up as the responder (holds rStatic, knows iStatic) to receive the
    // captured initiator→responder direction.
    final advInit = SessionInitiatorHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: iStatic,
      peerStaticPublic: rStatic.publicKey,
    );
    final advResp = SessionResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: rStatic,
      peerStaticPublic: iStatic.publicKey,
    );
    advResp.readS1(advInit.writeS1());
    final advInitTx = advInit.completeWithS2(advResp.writeS2());
    final advRespTx = advResp.deriveTransport();
    addTearDown(() {
      advInitTx.destroy();
      advRespTx.destroy();
    });

    // The reconstructed receive key sits at counter 0, exactly matching the
    // first captured frame's nonce/counter/AD — so the ONLY difference is the
    // ephemeral-derived key. It fails closed: the statics did not, and cannot,
    // recover the past ephemeral transport.
    expect(advRespTx.receive.counter, 0);
    expect(
      () => advRespTx.receive.open(
        outerHeader: header(crid),
        ciphertext: captured.first,
      ),
      throwsA(isA<TransportError>()),
      reason: 'statics + fresh handshake must not open a past frame',
    );
    // The fatal open destroyed the direction key (fail-closed, §3.3.1).
    expect(advRespTx.receive.isLive, isFalse);

    // Sanity: the captured bytes really were the live session's ciphertext
    // (not empty/garbage) — they are 16 bytes longer than plaintext (the
    // Poly1305 tag) and distinct per message.
    for (var i = 0; i < captured.length; i++) {
      expect(captured[i].length, plaintexts[i].length + 16);
    }
    expect(captured[0], isNot(captured[1]));
  });
}
