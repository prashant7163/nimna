import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/noise/dh.dart';
import 'package:nimna/src/noise/handshake_state.dart';
import 'package:nimna/src/noise/xxpsk2.dart';
import 'package:nimna/src/protocol/channel_identity.dart';
import 'package:nimna/src/protocol/commitment.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/test_env.dart';

/// Byte-lock of the from-spec Noise_XXpsk2 engine against the committed
/// transcripts in docs/test-vectors/pairing-handshake.json: every key,
/// every message byte, per-step chaining key + handshake hash, the Split
/// keys, M4 PAIR_CONFIRM, and the derived CRID + safety phrase. This drives
/// the real symmetric_state / handshake_state / cipher_state code through
/// the exact §3.1.3 message pattern in lockstep for both roles.
void main() {
  final vectors =
      jsonDecode(
            File(
              '../../docs/test-vectors/pairing-handshake.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final transcripts = (vectors['transcripts'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final wordlist = File(
    '../../docs/test-vectors/wordlist-en-v1.txt',
  ).readAsLinesSync().where((l) => l.isNotEmpty).toList();

  NoiseKeyPair kpFromPriv(SodiumSumo sodium, String privHex) {
    final sk = SecureKey.fromList(sodium, hexToBytes(privHex));
    final pub = sodium.crypto.scalarmult.base(n: sk);
    return NoiseKeyPair(publicKey: pub, secretKey: sk);
  }

  test('wordlist pins to 1296 words', () => expect(wordlist.length, 1296));

  for (final t in transcripts) {
    group('transcript ${t['name']}', () {
      test('full XXpsk2 transcript locks byte-for-byte', () async {
        final sodium = await testSodium();
        final aead = AtRestAead(sodium);
        final rv = t['rendezvous'] as Map<String, dynamic>;
        final psk = SecureKey.fromList(sodium, hexToBytes(rv['psk'] as String));
        addTearDown(psk.dispose);

        final creator = t['creator'] as Map<String, dynamic>;
        final joiner = t['joiner'] as Map<String, dynamic>;

        final jStatic = kpFromPriv(sodium, joiner['static_priv'] as String);
        final jEph = kpFromPriv(sodium, joiner['ephemeral_priv'] as String);
        final cStatic = kpFromPriv(sodium, creator['static_priv'] as String);
        final cEph = kpFromPriv(sodium, creator['ephemeral_priv'] as String);
        addTearDown(() {
          jStatic.dispose();
          jEph.dispose();
          cStatic.dispose();
          cEph.dispose();
        });

        // Keys derive to the committed public keys.
        expect(bytesToHex(jStatic.publicKey), joiner['static_pub']);
        expect(bytesToHex(jEph.publicKey), joiner['ephemeral_pub']);
        expect(bytesToHex(cStatic.publicKey), creator['static_pub']);
        expect(bytesToHex(cEph.publicKey), creator['ephemeral_pub']);

        // M0 commitment prologue.
        final m0 = commitmentM0(
          joinerEphemeralPublic: jEph.publicKey,
          joinerStaticPublic: jStatic.publicKey,
        );
        expect(bytesToHex(m0), (t['commitment'] as Map)['m0']);
        expect(bytesToHex(m0), t['prologue']);

        final jhs = NoiseHandshakeState(
          sodium: sodium,
          aead: aead,
          role: NoiseRole.initiator,
          protocolName: pairingProtocolName,
          prologue: m0,
          staticKeyPair: jStatic,
          psk: psk,
          ephemeral: jEph,
        );
        final chs = NoiseHandshakeState(
          sodium: sodium,
          aead: aead,
          role: NoiseRole.responder,
          protocolName: pairingProtocolName,
          prologue: m0,
          staticKeyPair: cStatic,
          psk: psk,
          ephemeral: cEph,
        );
        addTearDown(() {
          jhs.dispose();
          chs.dispose();
        });

        // InitializeSymmetric + MixHash(prologue).
        for (final hs in [jhs, chs]) {
          expect(bytesToHex(hs.symm.chainingKey), t['chaining_key_initial']);
          expect(
            bytesToHex(hs.symm.handshakeHash),
            t['handshake_hash_after_prologue'],
          );
        }

        final messages = (t['messages'] as List).cast<Map<String, dynamic>>();
        void expectStep(NoiseHandshakeState hs, Map<String, dynamic> m) {
          expect(bytesToHex(hs.symm.chainingKey), m['chaining_key_after']);
          expect(bytesToHex(hs.symm.handshakeHash), m['handshake_hash_after']);
        }

        // M1: joiner writes [e]; the M1 frame is M0 ‖ body.
        final m1body = jhs.writeMessage(const [NoiseToken.e], Uint8List(0));
        expect(
          bytesToHex([...m0, ...m1body]),
          messages[0]['pair_data_payload'],
        );
        expectStep(jhs, messages[0]);
        final cReadM1 = chs.readMessage(const [NoiseToken.e], m1body);
        expect(cReadM1, isEmpty);
        expectStep(chs, messages[0]);

        // M2: creator writes [e, ee, s, es, psk] carrying token_payload_A.
        final tokenA = hexToBytes(
          ((creator['token_payload'] as Map)['encoded']) as String,
        );
        final m2 = chs.writeMessage(const [
          NoiseToken.e,
          NoiseToken.ee,
          NoiseToken.s,
          NoiseToken.es,
          NoiseToken.psk,
        ], tokenA);
        expect(bytesToHex(m2), messages[1]['pair_data_payload']);
        expectStep(chs, messages[1]);
        final jReadM2 = jhs.readMessage(const [
          NoiseToken.e,
          NoiseToken.ee,
          NoiseToken.s,
          NoiseToken.es,
          NoiseToken.psk,
        ], m2);
        expect(bytesToHex(jReadM2), messages[1]['payload_plaintext']);
        expect(bytesToHex(jhs.remoteStatic!), creator['static_pub']);
        expectStep(jhs, messages[1]);

        // M3: joiner writes [s, se] carrying token_payload_B.
        final tokenB = hexToBytes(
          ((joiner['token_payload'] as Map)['encoded']) as String,
        );
        final m3 = jhs.writeMessage(const [
          NoiseToken.s,
          NoiseToken.se,
        ], tokenB);
        expect(bytesToHex(m3), messages[2]['pair_data_payload']);
        expectStep(jhs, messages[2]);
        final cReadM3 = chs.readMessage(const [
          NoiseToken.s,
          NoiseToken.se,
        ], m3);
        expect(bytesToHex(cReadM3), messages[2]['payload_plaintext']);
        expect(bytesToHex(chs.remoteStatic!), joiner['static_pub']);
        expectStep(chs, messages[2]);

        // Commitment check the creator performs on M3.
        final recomputed = commitmentM0(
          joinerEphemeralPublic: chs.remoteEphemeral!,
          joinerStaticPublic: chs.remoteStatic!,
        );
        expect(bytesToHex(recomputed), (t['commitment'] as Map)['m0']);

        // Split.
        final split = t['split'] as Map<String, dynamic>;
        final (jkir, jkri) = jhs.split();
        final (ckir, ckri) = chs.split();
        expect(bytesToHex(jkir), split['k_ir']);
        expect(bytesToHex(jkri), split['k_ri']);
        expect(bytesToHex(ckir), split['k_ir']);
        expect(bytesToHex(ckri), split['k_ri']);

        // M4 PAIR_CONFIRM: creator encrypts empty under k_ri.
        final m4v = t['m4_pair_confirm'] as Map<String, dynamic>;
        final outerHeader = hexToBytes(m4v['ad_outer_header'] as String);
        final ckriKey = SecureKey.fromList(sodium, ckri);
        final m4 = aead.encrypt(
          key: ckriKey,
          nonce: pairConfirmNonce(),
          plaintext: Uint8List(0),
          additionalData: outerHeader,
        );
        ckriKey.dispose();
        expect(bytesToHex(m4), m4v['pair_data_payload']);
        expect(bytesToHex(pairConfirmNonce()), m4v['nonce']);
        // Joiner verifies M4 (no throw).
        final jkriKey = SecureKey.fromList(sodium, jkri);
        aead.decrypt(
          key: jkriKey,
          nonce: pairConfirmNonce(),
          ciphertext: m4,
          additionalData: outerHeader,
        );
        jkriKey.dispose();

        // Channel identity: ss, salt2, CRID, safety phrase.
        final channel = t['channel'] as Map<String, dynamic>;
        final ss = x25519(
          sodium: sodium,
          scalar: jStatic.secretKey,
          point: cStatic.publicKey,
        );
        expect(bytesToHex(ss), channel['ss']);
        final salt2 = channelSalt2(
          aPublic: cStatic.publicKey,
          bPublic: jStatic.publicKey,
        );
        expect(bytesToHex(salt2), channel['salt2']);
        expect(bytesToHex(deriveCrid(ss: ss, salt2: salt2)), channel['crid']);
        final pbytes = safetyPhraseBytes(ss: ss, salt2: salt2);
        expect(bytesToHex(pbytes), channel['phrase_bytes']);
        expect(
          phraseIndices(pbytes),
          (channel['phrase_indices'] as List).cast<int>(),
        );
        expect(
          safetyPhraseWords(
            ss: ss,
            aPublic: cStatic.publicKey,
            bPublic: jStatic.publicKey,
            wordlist: wordlist,
          ),
          (channel['phrase_words'] as List).cast<String>(),
        );
      });
    });
  }
}
