import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/hkdf.dart';
import 'package:crypto/crypto.dart';

import '../helpers/test_env.dart';

/// HKDF-SHA-256 locked to RFC 5869 Appendix A vectors, the underlying HMAC
/// locked to RFC 4231 vectors, and the composition byte-cross-checked
/// against the Go-generated values committed in docs/test-vectors/
/// (app-architecture.md §1).
void main() {
  group('RFC 5869 Appendix A (SHA-256)', () {
    test('A.1 basic', () {
      final okm = hkdfSha256(
        ikm: hexToBytes('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'),
        salt: hexToBytes('000102030405060708090a0b0c'),
        info: hexToBytes('f0f1f2f3f4f5f6f7f8f9'),
        length: 42,
      );
      expect(
        bytesToHex(okm),
        '3cb25f25faacd57a90434f64d0362f2a'
        '2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });

    test('A.2 longer inputs/outputs', () {
      final ikm = hexToBytes(
        '000102030405060708090a0b0c0d0e0f'
        '101112131415161718191a1b1c1d1e1f'
        '202122232425262728292a2b2c2d2e2f'
        '303132333435363738393a3b3c3d3e3f'
        '404142434445464748494a4b4c4d4e4f',
      );
      final salt = hexToBytes(
        '606162636465666768696a6b6c6d6e6f'
        '707172737475767778797a7b7c7d7e7f'
        '808182838485868788898a8b8c8d8e8f'
        '909192939495969798999a9b9c9d9e9f'
        'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf',
      );
      final info = hexToBytes(
        'b0b1b2b3b4b5b6b7b8b9babbbcbdbebf'
        'c0c1c2c3c4c5c6c7c8c9cacbcccdcecf'
        'd0d1d2d3d4d5d6d7d8d9dadbdcdddedf'
        'e0e1e2e3e4e5e6e7e8e9eaebecedeeef'
        'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff',
      );
      final okm = hkdfSha256(ikm: ikm, salt: salt, info: info, length: 82);
      expect(
        bytesToHex(okm),
        'b11e398dc80327a1c8e7f78c596a4934'
        '4f012eda2d4efad8a050cc4c19afa97c'
        '59045a99cac7827271cb41c65e590e09'
        'da3275600c2f09b8367793a9aca3db71'
        'cc30c58179ec3e87c14c01d5c1f3434f'
        '1d87',
      );
    });

    test('A.3 zero-length salt and info', () {
      final okm = hkdfSha256(
        ikm: hexToBytes('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'),
        info: const [],
        length: 42,
      );
      expect(
        bytesToHex(okm),
        '8da4e775a563c18f715f802a063c5a31'
        'b8a11f5c5ee1879ec3454e5f3c738d2d'
        '9d201395faa4b61a96c8',
      );
    });
  });

  group('RFC 4231 (HMAC-SHA-256 underlying primitive)', () {
    String hmacHex(List<int> key, List<int> data) =>
        bytesToHex(Hmac(sha256, key).convert(data).bytes);

    test('case 1', () {
      expect(
        hmacHex(hexToBytes('0b' * 20), ascii.encode('Hi There')),
        'b0344c61d8db38535ca8afceaf0bf12b'
        '881dc200c9833da726e9376c2e32cff7',
      );
    });

    test('case 2', () {
      expect(
        hmacHex(
          ascii.encode('Jefe'),
          ascii.encode('what do ya want for nothing?'),
        ),
        '5bdcc146bf60754e6a042426089575c7'
        '5a003f089d2739839dec58b964ec3843',
      );
    });

    test('case 3', () {
      expect(
        hmacHex(hexToBytes('aa' * 20), hexToBytes('dd' * 50)),
        '773ea91e36800e46854db8ebd09181a7'
        '2959098b3ef8c122d9635514ced565fe',
      );
    });

    test('case 4', () {
      expect(
        hmacHex(
          hexToBytes('0102030405060708090a0b0c0d0e0f10111213141516171819'),
          hexToBytes('cd' * 50),
        ),
        '82558a389a443c0ea4cc819899f2083a'
        '85f0faa3e578f8077a2e3ff46729665b',
      );
    });
  });

  group('cross-check vs committed Go-generated vectors', () {
    test('topic/psk derivations from topic-derivation.json', () {
      final file = File('../../docs/test-vectors/topic-derivation.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'monorepo-relative test vectors must exist',
      );
      final doc = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final hkdfParams = doc['hkdf'] as Map<String, dynamic>;
      final topicInfo = ascii.encode(hkdfParams['topic_info'] as String);
      final pskInfo = ascii.encode(hkdfParams['psk_info'] as String);
      final cases = doc['cases'] as List<dynamic>;

      var checked = 0;
      for (final c in cases.cast<Map<String, dynamic>>()) {
        if (c['valid'] != true) {
          continue;
        }
        for (final paramSet in ['production', 'reduced_test_only']) {
          final expected = c[paramSet] as Map<String, dynamic>;
          final seed = hexToBytes(expected['seed'] as String);
          expect(
            bytesToHex(hkdfSha256(ikm: seed, info: topicInfo, length: 16)),
            expected['topic'],
            reason: '$paramSet topic for case ${c['name']}',
          );
          expect(
            bytesToHex(hkdfSha256(ikm: seed, info: pskInfo, length: 32)),
            expected['psk'],
            reason: '$paramSet psk for case ${c['name']}',
          );
          checked++;
        }
      }
      expect(checked, greaterThan(0));
    });
  });
}
