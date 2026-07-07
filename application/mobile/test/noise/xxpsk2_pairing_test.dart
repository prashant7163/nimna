import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/noise/handshake_state.dart';
import 'package:nimna/src/noise/xxpsk2.dart';
import 'package:nimna/src/protocol/channel_identity.dart';
import 'package:nimna/src/protocol/commitment.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:nimna/src/protocol/token_payload.dart';

import '../helpers/test_env.dart';

/// End-to-end pairing over the two role drivers with FRESH keys, plus the
/// adversarial rejections the fail-closed discipline (§3.1.6) requires: a
/// code-less MITM (wrong psk), a tampered M4, and a lying commitment (M0
/// disagreeing with the joiner's real keys — the explicit §3.1.3 check).
void main() {
  final wordlist = File(
    '../../docs/test-vectors/wordlist-en-v1.txt',
  ).readAsLinesSync().where((l) => l.isNotEmpty).toList();

  Uint8List outerHeader(Uint8List topic) => Uint8List.sublistView(
    OuterFrame(type: FrameType.pairData, routingId: topic).encode(),
    0,
    outerHeaderBytes,
  );

  test('two devices pair end-to-end; identical CRID + safety phrase', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final psk = sodium.secureRandom(32);
    final jStatic = generateNoiseKeyPair(sodium);
    final cStatic = generateNoiseKeyPair(sodium);
    final topic = aead.randomBytes(16);
    addTearDown(() {
      psk.dispose();
      jStatic.dispose();
      cStatic.dispose();
    });

    final joinerToken = TokenPayload.present(
      platform: PushPlatform.fcm,
      token: Uint8List.fromList(utf8Bytes('fcm-token')),
    );

    final joiner = NoiseJoinerHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: jStatic,
      psk: psk,
      tokenPayload: joinerToken,
    );
    final creator = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: cStatic,
      psk: psk,
      tokenPayload: const TokenPayload.absent(),
    );
    addTearDown(() {
      joiner.dispose();
      creator.dispose();
    });

    final m1 = joiner.writeM1();
    creator.readM1(m1);
    final m2 = creator.writeM2();
    joiner.readM2(m2);
    final m3 = joiner.writeM3();
    creator.readM3(m3);
    final m4 = creator.writeM4(outerHeader(topic));
    joiner.completeWithM4(m4, outerHeader(topic));

    final jMat = joiner.finalizeChannel();
    final cMat = creator.finalizeChannel();
    addTearDown(() {
      jMat.disposeSecret();
      cMat.disposeSecret();
    });

    // Identity agrees on both ends.
    expect(bytesToHex(jMat.crid), bytesToHex(cMat.crid));
    expect(bytesToHex(jMat.peerStaticPublic), bytesToHex(cStatic.publicKey));
    expect(bytesToHex(cMat.peerStaticPublic), bytesToHex(jStatic.publicKey));

    // The peer's token crossed the wire E2E (§3.2.1): the creator learns the
    // joiner's push token; the joiner sees the creator's "absent".
    expect(cMat.peerToken.isPresent, isTrue);
    expect(cMat.peerToken.platform, PushPlatform.fcm);
    expect(jMat.peerToken.isPresent, isFalse);

    // The safety phrases match (the closing ritual, §3.1.4).
    final jWords = safetyPhraseWords(
      ss: jMat.ss,
      aPublic: jStatic.publicKey,
      bPublic: jMat.peerStaticPublic,
      wordlist: wordlist,
    );
    final cWords = safetyPhraseWords(
      ss: cMat.ss,
      aPublic: cStatic.publicKey,
      bPublic: cMat.peerStaticPublic,
      wordlist: wordlist,
    );
    expect(jWords, cWords);
    expect(jWords, hasLength(3));
  });

  test('code-less MITM (wrong psk) fails closed at M2', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final jStatic = generateNoiseKeyPair(sodium);
    final cStatic = generateNoiseKeyPair(sodium);
    addTearDown(() {
      jStatic.dispose();
      cStatic.dispose();
    });

    // The two sides hold DIFFERENT psks — the relay/MITM never learned the
    // code, so its psk is wrong (§3.1.3).
    final joiner = NoiseJoinerHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: jStatic,
      psk: sodium.secureRandom(32),
      tokenPayload: const TokenPayload.absent(),
    );
    final creator = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: cStatic,
      psk: sodium.secureRandom(32),
      tokenPayload: const TokenPayload.absent(),
    );
    addTearDown(() {
      joiner.dispose();
      creator.dispose();
    });

    final m1 = joiner.writeM1();
    creator.readM1(m1); // pre-psk material only — succeeds by design.
    final m2 = creator.writeM2();
    // The joiner's correct-vs-wrong psk mismatch surfaces on the M2 payload.
    expect(() => joiner.readM2(m2), throwsA(isA<PairingHandshakeError>()));
  });

  test('tampered M4 is rejected (joiner never finalizes)', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final psk = sodium.secureRandom(32);
    final jStatic = generateNoiseKeyPair(sodium);
    final cStatic = generateNoiseKeyPair(sodium);
    final topic = aead.randomBytes(16);
    addTearDown(() {
      psk.dispose();
      jStatic.dispose();
      cStatic.dispose();
    });

    final joiner = NoiseJoinerHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: jStatic,
      psk: psk,
      tokenPayload: const TokenPayload.absent(),
    );
    final creator = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: cStatic,
      psk: psk,
      tokenPayload: const TokenPayload.absent(),
    );
    addTearDown(() {
      joiner.dispose();
      creator.dispose();
    });

    creator.readM1(joiner.writeM1());
    joiner.readM2(creator.writeM2());
    creator.readM3(joiner.writeM3());
    final m4 = creator.writeM4(outerHeader(topic));
    final tampered = Uint8List.fromList(m4)..[0] ^= 0xFF;
    expect(
      () => joiner.completeWithM4(tampered, outerHeader(topic)),
      throwsA(isA<PairingHandshakeError>()),
    );
  });

  test('lying M0 commitment is caught by the creator at M3', () async {
    final sodium = await testSodium();
    final aead = AtRestAead(sodium);
    final psk = sodium.secureRandom(32);
    final jStatic = generateNoiseKeyPair(sodium);
    final jEph = generateNoiseKeyPair(sodium);
    final cStatic = generateNoiseKeyPair(sodium);
    final bogus = generateNoiseKeyPair(sodium);
    addTearDown(() {
      psk.dispose();
      jStatic.dispose();
      jEph.dispose();
      cStatic.dispose();
      bogus.dispose();
    });

    // A malicious joiner commits M0 over BOGUS keys but runs the handshake
    // with its real keys. Both sides use bogusM0 as the prologue, so every
    // AEAD stays in sync — only the creator's explicit recomputation of the
    // commitment from the real keys (§3.1.3) can catch it.
    final bogusM0 = commitmentM0(
      joinerEphemeralPublic: bogus.publicKey,
      joinerStaticPublic: bogus.publicKey,
    );
    final malicious = NoiseHandshakeState(
      sodium: sodium,
      aead: aead,
      role: NoiseRole.initiator,
      protocolName: pairingProtocolName,
      prologue: bogusM0,
      staticKeyPair: jStatic,
      psk: psk,
      ephemeral: jEph,
    );
    addTearDown(malicious.dispose);

    final m1body = malicious.writeMessage(const [NoiseToken.e], Uint8List(0));
    final m1 = Uint8List.fromList([...bogusM0, ...m1body]);

    final creator = NoiseResponderHandshake(
      sodium: sodium,
      aead: aead,
      staticKeyPair: cStatic,
      psk: psk,
      tokenPayload: const TokenPayload.absent(),
    );
    addTearDown(creator.dispose);

    creator.readM1(m1); // AEAD passes (prologue agrees).
    final m2 = creator.writeM2();
    malicious.readMessage(const [
      NoiseToken.e,
      NoiseToken.ee,
      NoiseToken.s,
      NoiseToken.es,
      NoiseToken.psk,
    ], m2);
    final m3 = malicious.writeMessage(const [
      NoiseToken.s,
      NoiseToken.se,
    ], const TokenPayload.absent().encode());
    // AEAD would pass, but the commitment recomputed from the real keys
    // disagrees with bogusM0 → fail-closed.
    expect(() => creator.readM3(m3), throwsA(isA<PairingHandshakeError>()));
  });
}

List<int> utf8Bytes(String s) => s.codeUnits;
