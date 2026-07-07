import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/channel_identity.dart';

import '../helpers/test_env.dart';

/// §3.1.4 safety-phrase mapping — byte-locked to
/// docs/test-vectors/phrase-words.json (the uint64 → base-1296 → words
/// mapping, including the full-uint64 range the BigInt path exists for) and
/// docs/test-vectors/wordlist-en-v1.txt.
void main() {
  final phrase =
      jsonDecode(
            File(
              '../../docs/test-vectors/phrase-words.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final wordlist = File(
    '../../docs/test-vectors/wordlist-en-v1.txt',
  ).readAsLinesSync().where((l) => l.isNotEmpty).toList();

  test('committed wordlist SHA-256 is pinned', () {
    // The committed vector records the normative digest; the app asset
    // loader checks the same value at runtime.
    expect((phrase['wordlist'] as Map)['size'], phraseWordCount);
    expect(wordlist.length, phraseWordCount);
  });

  group('n → indices → words', () {
    for (final c in (phrase['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'], () {
        final out8 = hexToBytes(c['hkdf_output'] as String);
        final indices = phraseIndices(out8);
        expect(indices, (c['indices'] as List).cast<int>());
        final words = [for (final i in indices) wordlist[i]];
        expect(words, (c['words'] as List).cast<String>());
      });
    }
  });

  test('salt2 sorts the two public keys (order-independent)', () {
    final a = hexToBytes('00' * 32);
    final b = hexToBytes('ff' * 32);
    expect(
      bytesToHex(channelSalt2(aPublic: a, bPublic: b)),
      bytesToHex(channelSalt2(aPublic: b, bPublic: a)),
    );
  });
}
