import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/noise/handshake_state.dart';
import 'package:nimna/src/noise/session_kk.dart';
import 'package:nimna/src/protocol/inner_envelope.dart';
import 'package:nimna/src/protocol/outer_frame.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';

/// Noise_KK session handshake (§3.3.1): the from-spec engine byte-locked to
/// docs/test-vectors/session-handshake.json (S1/S2 bytes, per-step ck + h,
/// Split), plus the driver round-trip (matching, working transport keys) and
/// the fail-closed rejections (tampered S1/S2, wrong static key).
void main() {
  final vectors =
      jsonDecode(
            File(
              '../../docs/test-vectors/session-handshake.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final transcripts = (vectors['transcripts'] as List)
      .cast<Map<String, dynamic>>();

  NoiseKeyPair kpFromPriv(SodiumSumo sodium, String privHex) {
    final sk = SecureKey.fromList(sodium, hexToBytes(privHex));
    final pub = sodium.crypto.scalarmult.base(n: sk);
    return NoiseKeyPair(publicKey: pub, secretKey: sk);
  }

  Uint8List outerHeader(Uint8List crid) => Uint8List.sublistView(
    OuterFrame(type: FrameType.sessionData, routingId: crid).encode(),
    0,
    outerHeaderBytes,
  );

  test('protocol name is the spec KK suite', () {
    expect(sessionProtocolName, 'Noise_KK_25519_ChaChaPoly_SHA256');
  });

  for (final t in transcripts) {
    group('transcript ${t['name']}', () {
      test('KK S1/S2 + Split lock byte-for-byte', () async {
        final sodium = await testSodium();
        final aead = AtRestAead(sodium);
        final initiator = t['initiator'] as Map<String, dynamic>;
        final responder = t['responder'] as Map<String, dynamic>;

        final iStatic = kpFromPriv(sodium, initiator['static_priv'] as String);
        final iEph = kpFromPriv(sodium, initiator['ephemeral_priv'] as String);
        final rStatic = kpFromPriv(sodium, responder['static_priv'] as String);
        final rEph = kpFromPriv(sodium, responder['ephemeral_priv'] as String);
        addTearDown(() {
          iStatic.dispose();
          iEph.dispose();
          rStatic.dispose();
          rEph.dispose();
        });
        expect(bytesToHex(iStatic.publicKey), initiator['static_pub']);
        expect(bytesToHex(rStatic.publicKey), responder['static_pub']);

        final pre = [iStatic.publicKey, rStatic.publicKey];
        final ihs = NoiseHandshakeState(
          sodium: sodium,
          aead: aead,
          role: NoiseRole.initiator,
          protocolName: sessionProtocolName,
          prologue: Uint8List(0),
          staticKeyPair: iStatic,
          ephemeral: iEph,
          remoteStaticPublic: rStatic.publicKey,
          preMessagePublicKeys: pre,
          mixKeyOnEphemeral: false,
        );
        final rhs = NoiseHandshakeState(
          sodium: sodium,
          aead: aead,
          role: NoiseRole.responder,
          protocolName: sessionProtocolName,
          prologue: Uint8List(0),
          staticKeyPair: rStatic,
          ephemeral: rEph,
          remoteStaticPublic: iStatic.publicKey,
          preMessagePublicKeys: pre,
          mixKeyOnEphemeral: false,
        );
        addTearDown(() {
          ihs.dispose();
          rhs.dispose();
        });

        // InitializeSymmetric + pre-message MixHash.
        for (final hs in [ihs, rhs]) {
          expect(bytesToHex(hs.symm.chainingKey), t['chaining_key_initial']);
          expect(
            bytesToHex(hs.symm.handshakeHash),
            t['handshake_hash_after_pre_messages'],
          );
        }

        final messages = (t['messages'] as List).cast<Map<String, dynamic>>();
        void expectStep(NoiseHandshakeState hs, Map<String, dynamic> m) {
          expect(bytesToHex(hs.symm.chainingKey), m['chaining_key_after']);
          expect(bytesToHex(hs.symm.handshakeHash), m['handshake_hash_after']);
        }

        // S1: initiator writes [e, es, ss] over an empty payload → 48 bytes.
        final s1 = ihs.writeMessage(const [
          NoiseToken.e,
          NoiseToken.es,
          NoiseToken.ss,
        ], Uint8List(0));
        expect(s1.length, 48);
        expect(bytesToHex(s1), messages[0]['session_data_payload']);
        expectStep(ihs, messages[0]);
        expect(
          rhs.readMessage(const [
            NoiseToken.e,
            NoiseToken.es,
            NoiseToken.ss,
          ], s1),
          isEmpty,
        );
        expectStep(rhs, messages[0]);

        // S2: responder writes [e, ee, se] over an empty payload → 48 bytes.
        final s2 = rhs.writeMessage(const [
          NoiseToken.e,
          NoiseToken.ee,
          NoiseToken.se,
        ], Uint8List(0));
        expect(s2.length, 48);
        expect(bytesToHex(s2), messages[1]['session_data_payload']);
        expectStep(rhs, messages[1]);
        expect(
          ihs.readMessage(const [
            NoiseToken.e,
            NoiseToken.ee,
            NoiseToken.se,
          ], s2),
          isEmpty,
        );
        expectStep(ihs, messages[1]);

        // Split → (k_ir, k_ri), identical on both ends.
        final split = t['split'] as Map<String, dynamic>;
        final (ikir, ikri) = ihs.split();
        final (rkir, rkri) = rhs.split();
        expect(bytesToHex(ikir), split['k_ir']);
        expect(bytesToHex(ikri), split['k_ri']);
        expect(bytesToHex(rkir), split['k_ir']);
        expect(bytesToHex(rkri), split['k_ri']);
      });

      test(
        'driver derives working transports that decrypt the vector frames',
        () async {
          final sodium = await testSodium();
          final aead = AtRestAead(sodium);
          final initiator = t['initiator'] as Map<String, dynamic>;
          final responder = t['responder'] as Map<String, dynamic>;
          final crid = hexToBytes(t['crid'] as String);

          final iStatic = kpFromPriv(
            sodium,
            initiator['static_priv'] as String,
          );
          final rStatic = kpFromPriv(
            sodium,
            responder['static_priv'] as String,
          );
          addTearDown(() {
            iStatic.dispose();
            rStatic.dispose();
          });

          final knocker = SessionInitiatorHandshake(
            sodium: sodium,
            aead: aead,
            staticKeyPair: iStatic,
            peerStaticPublic: rStatic.publicKey,
            ephemeral: kpFromPriv(
              sodium,
              initiator['ephemeral_priv'] as String,
            ),
          );
          final accepter = SessionResponderHandshake(
            sodium: sodium,
            aead: aead,
            staticKeyPair: rStatic,
            peerStaticPublic: iStatic.publicKey,
            ephemeral: kpFromPriv(
              sodium,
              responder['ephemeral_priv'] as String,
            ),
          );

          final s1 = knocker.writeS1();
          accepter.readS1(s1);
          final s2 = accepter.writeS2();
          final iTx = knocker.completeWithS2(s2);
          final rTx = accepter.deriveTransport();
          addTearDown(() {
            iTx.destroy();
            rTx.destroy();
          });

          // Feed the committed transport frames through the receiving side and
          // check the recovered inner envelopes. Frames are ordered per
          // direction, exercising the counter + per-message rekey.
          final frames = (t['transport_frames'] as List)
              .cast<Map<String, dynamic>>();
          for (final f in frames) {
            final ad = hexToBytes(f['ad_outer_header'] as String);
            expect(bytesToHex(ad), bytesToHex(outerHeader(crid)));
            final ct = hexToBytes(f['session_data_payload'] as String);
            final initToResp = f['direction'] == 'initiator->responder';
            final rx = initToResp ? rTx.receive : iTx.receive;
            expect(rx.counter, f['counter']);
            final pt = rx.open(outerHeader: ad, ciphertext: ct);
            final expected =
                (f['inner_envelope_plaintext'] as Map)['encoded'] as String;
            expect(bytesToHex(pt), expected);
            // The recovered plaintext is a well-formed inner envelope.
            expect(
              bytesToHex(InnerEnvelope.decode(pt).encode()),
              expected.toLowerCase(),
            );
          }
        },
      );
    });
  }

  group('driver (fresh keys)', () {
    Future<void> runRoundTrip(SodiumSumo sodium) async {
      final aead = AtRestAead(sodium);
      final iStatic = generateNoiseKeyPair(sodium);
      final rStatic = generateNoiseKeyPair(sodium);
      final crid = aead.randomBytes(16);
      Uint8List header() => Uint8List.sublistView(
        OuterFrame(type: FrameType.sessionData, routingId: crid).encode(),
        0,
        outerHeaderBytes,
      );

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

      final s1 = knocker.writeS1();
      expect(s1.length, 48);
      accepter.readS1(s1);
      final s2 = accepter.writeS2();
      expect(s2.length, 48);
      final iTx = knocker.completeWithS2(s2);
      final rTx = accepter.deriveTransport();
      addTearDown(() {
        iStatic.dispose();
        rStatic.dispose();
        iTx.destroy();
        rTx.destroy();
      });

      // Several messages each way: counters advance, per-message rekey holds.
      for (var i = 0; i < 3; i++) {
        final msg = Uint8List.fromList(utf8.encode('knocker $i'));
        final ct = iTx.send.seal(outerHeader: header(), plaintext: msg);
        expect(rTx.receive.open(outerHeader: header(), ciphertext: ct), msg);

        final reply = Uint8List.fromList(utf8.encode('accepter $i'));
        final ct2 = rTx.send.seal(outerHeader: header(), plaintext: reply);
        expect(iTx.receive.open(outerHeader: header(), ciphertext: ct2), reply);
      }
      expect(iTx.send.counter, 3);
      expect(rTx.receive.counter, 3);
    }

    test('a full handshake yields matching, working transport keys', () async {
      await runRoundTrip(await testSodium());
    });

    test('tampered S1 fails closed at the accepter', () async {
      final sodium = await testSodium();
      final aead = AtRestAead(sodium);
      final iStatic = generateNoiseKeyPair(sodium);
      final rStatic = generateNoiseKeyPair(sodium);
      addTearDown(() {
        iStatic.dispose();
        rStatic.dispose();
      });
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
      final s1 = Uint8List.fromList(knocker.writeS1())..[40] ^= 0xFF;
      expect(() => accepter.readS1(s1), throwsA(isA<SessionHandshakeError>()));
    });

    test('tampered S2 fails closed at the knocker', () async {
      final sodium = await testSodium();
      final aead = AtRestAead(sodium);
      final iStatic = generateNoiseKeyPair(sodium);
      final rStatic = generateNoiseKeyPair(sodium);
      addTearDown(() {
        iStatic.dispose();
        rStatic.dispose();
      });
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
      final s2 = Uint8List.fromList(accepter.writeS2())..[10] ^= 0xFF;
      expect(
        () => knocker.completeWithS2(s2),
        throwsA(isA<SessionHandshakeError>()),
      );
    });

    test('a wrong peer static key fails closed', () async {
      final sodium = await testSodium();
      final aead = AtRestAead(sodium);
      final iStatic = generateNoiseKeyPair(sodium);
      final rStatic = generateNoiseKeyPair(sodium);
      final bogus = generateNoiseKeyPair(sodium);
      addTearDown(() {
        iStatic.dispose();
        rStatic.dispose();
        bogus.dispose();
      });
      final knocker = SessionInitiatorHandshake(
        sodium: sodium,
        aead: aead,
        staticKeyPair: iStatic,
        peerStaticPublic: rStatic.publicKey,
      );
      // The accepter believes the peer static is `bogus`, not the real
      // initiator — its pre-message hash and ss/es DHs diverge, so S1 fails
      // to authenticate (§3.3.1 fail-closed).
      final accepter = SessionResponderHandshake(
        sodium: sodium,
        aead: aead,
        staticKeyPair: rStatic,
        peerStaticPublic: bogus.publicKey,
      );
      expect(
        () => accepter.readS1(knocker.writeS1()),
        throwsA(isA<SessionHandshakeError>()),
      );
    });
  });
}
