import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/noise/xxpsk2.dart';
import 'package:nimna/src/protocol/channel_identity.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/protocol/token_payload.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';

/// §9.4 / §18-B adversarial: the safety phrase (§3.1.4) as a MITM DETECTOR.
///
/// A pairing-time MITM who learned the code (psk) can complete a handshake on
/// each leg, but it must substitute its OWN static key toward each victim, so
/// each victim's channel secret `ss` and peer-static-public differ from the
/// honest end-to-end values. The out-of-band 3-word comparison (§3.1.4)
/// therefore shows DIFFERENT phrases on the two devices — the "~1 in 2.1B"
/// divergent-key detector. The suite previously only asserted phrase
/// AGREEMENT (honest path); this drives the real from-spec engine into a real
/// two-leg MITM and asserts DIVERGENCE.
void main() {
  final wordlist = File(
    '../../docs/test-vectors/wordlist-en-v1.txt',
  ).readAsLinesSync().where((l) => l.isNotEmpty).toList();

  Uint8List outerHeader(Uint8List topic) => Uint8List.sublistView(
    OuterFrame(type: FrameType.pairData, routingId: topic).encode(),
    0,
    outerHeaderBytes,
  );

  test('MITM who owns the code still forks the safety phrase (§3.1.4 '
      'divergent-key detector)', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);

    // The victims' fresh channel statics.
    final jStatic = generateNoiseKeyPair(sodium); // real joiner
    final cStatic = generateNoiseKeyPair(sodium); // real creator
    // The MITM substitutes a distinct static toward each victim.
    final mTowardJoiner = generateNoiseKeyPair(sodium);
    final mTowardCreator = generateNoiseKeyPair(sodium);
    // The MITM learned the code, so it holds the correct psk on both legs.
    // One shared psk value, handed to each engine as its own SecureKey (each
    // engine disposes the key it is given).
    final pskBytes = aead.randomBytes(32);
    SecureKey sharedPsk() => SecureKey.fromList(sodium, pskBytes);
    final topic = aead.randomBytes(16);
    addTearDown(() {
      jStatic.dispose();
      cStatic.dispose();
      mTowardJoiner.dispose();
      mTowardCreator.dispose();
      pskBytes.fillRange(0, pskBytes.length, 0);
    });

    // ---- Leg A: real joiner J  <->  MITM-as-responder --------------------
    final joiner = NoiseJoinerHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: jStatic,
      psk: sharedPsk(),
      tokenPayload: const TokenPayload.absent(),
    );
    final mitmResponder = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: mTowardJoiner,
      psk: sharedPsk(),
      tokenPayload: const TokenPayload.absent(),
    );
    addTearDown(() {
      joiner.dispose();
      mitmResponder.dispose();
    });
    mitmResponder.readM1(joiner.writeM1());
    joiner.readM2(mitmResponder.writeM2());
    mitmResponder.readM3(joiner.writeM3());
    final legAHeader = outerHeader(topic);
    joiner.completeWithM4(mitmResponder.writeM4(legAHeader), legAHeader);
    final jMat = joiner.finalizeChannel();
    addTearDown(jMat.disposeSecret);

    // ---- Leg B: MITM-as-joiner  <->  real creator C ---------------------
    final mitmJoiner = NoiseJoinerHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: mTowardCreator,
      psk: sharedPsk(),
      tokenPayload: const TokenPayload.absent(),
    );
    final creator = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: cStatic,
      psk: sharedPsk(),
      tokenPayload: const TokenPayload.absent(),
    );
    addTearDown(() {
      mitmJoiner.dispose();
      creator.dispose();
    });
    creator.readM1(mitmJoiner.writeM1());
    mitmJoiner.readM2(creator.writeM2());
    creator.readM3(mitmJoiner.writeM3());
    final legBHeader = outerHeader(topic);
    mitmJoiner.completeWithM4(creator.writeM4(legBHeader), legBHeader);
    final cMat = creator.finalizeChannel();
    addTearDown(cMat.disposeSecret);

    // Each victim really does see the MITM's substituted static, not the
    // peer's — the precondition for the detector to matter.
    expect(
      bytesToHex(jMat.peerStaticPublic),
      bytesToHex(mTowardJoiner.publicKey),
    );
    expect(
      bytesToHex(cMat.peerStaticPublic),
      bytesToHex(mTowardCreator.publicKey),
    );
    // The channel secrets diverge (the underlying ~1-in-2.1B forked key).
    expect(bytesToHex(jMat.ss), isNot(bytesToHex(cMat.ss)));

    // The two devices compute DIFFERENT 3-word phrases → the humans catch it.
    final joinerPhrase = safetyPhraseWords(
      ss: jMat.ss,
      aPublic: jStatic.publicKey,
      bPublic: jMat.peerStaticPublic,
      wordlist: wordlist,
    );
    final creatorPhrase = safetyPhraseWords(
      ss: cMat.ss,
      aPublic: cStatic.publicKey,
      bPublic: cMat.peerStaticPublic,
      wordlist: wordlist,
    );
    expect(joinerPhrase, hasLength(3));
    expect(creatorPhrase, hasLength(3));
    expect(
      joinerPhrase,
      isNot(creatorPhrase),
      reason: 'a MITM forces divergent phrases the §3.1.4 ritual exposes',
    );
  });
}
