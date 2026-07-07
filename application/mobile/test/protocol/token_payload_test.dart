import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/token_payload.dart';

import '../helpers/test_env.dart';

/// §5.7 token_payload codec — byte-locked to the `token_payload.encoded`
/// fields of docs/test-vectors/pairing-handshake.json, plus round-trip and
/// malformation coverage.
void main() {
  final vectors =
      jsonDecode(
            File(
              '../../docs/test-vectors/pairing-handshake.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  group('committed vectors', () {
    for (final t in (vectors['transcripts'] as List).cast<Map>()) {
      for (final side in ['creator', 'joiner']) {
        final tp = (t[side] as Map)['token_payload'] as Map;
        test('${t['name']} · $side (${tp['form']})', () {
          final encoded = hexToBytes(tp['encoded'] as String);
          final decoded = TokenPayload.decode(encoded);
          expect(decoded.isPresent, tp['form'] == 'present');
          // Re-encode round-trips to the same bytes.
          expect(bytesToHex(decoded.encode()), tp['encoded']);
          if (decoded.isPresent) {
            expect(bytesToHex(decoded.token!), tp['token']);
          }
        });
      }
    }
  });

  test('absent form is the single byte 0x00', () {
    expect(const TokenPayload.absent().encode(), Uint8List.fromList([0x00]));
    expect(TokenPayload.decode(Uint8List.fromList([0x00])).isPresent, isFalse);
  });

  test('present form round-trips APNs and FCM tokens', () {
    for (final platform in PushPlatform.values) {
      final token = Uint8List.fromList(utf8.encode('device-token-xyz'));
      final tp = TokenPayload.present(platform: platform, token: token);
      final round = TokenPayload.decode(tp.encode());
      expect(round.platform, platform);
      expect(round.token, token);
    }
  });

  group('malformation is rejected (structural failure)', () {
    final bad = <String, Uint8List>{
      'empty': Uint8List(0),
      'absent with trailing byte': Uint8List.fromList([0x00, 0x01]),
      'unknown leading byte': Uint8List.fromList([0x02]),
      'present truncated header': Uint8List.fromList([0x01, 0x01, 0x00]),
      'present unknown platform': Uint8List.fromList([0x01, 0x09, 0x00, 0x00]),
      'present length disagrees': Uint8List.fromList([
        0x01,
        0x01,
        0x00,
        0x02,
        0xAA,
      ]),
    };
    bad.forEach((name, bytes) {
      test(name, () {
        expect(
          () => TokenPayload.decode(bytes),
          throwsA(isA<TokenPayloadError>()),
        );
      });
    });
  });
}
