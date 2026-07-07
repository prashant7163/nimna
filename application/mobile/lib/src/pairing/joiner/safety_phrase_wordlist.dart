/// Loads the pinned safety-phrase wordlist (EFF short wordlist 2.0, 1296
/// words) bundled as a read-only asset. The wordlist is **protocol output,
/// not UI copy**: one global list, rendered identically in every locale
/// (spec §3.1.4, i18n decision 2026-07-04) — so it is an asset, never an ARB
/// string. Its canonical SHA-256 is normative (`phrase-words.json`); the
/// loader verifies it at load time and fails closed on any drift.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// The pinned wordlist and its normative digest (spec §3.1.4;
/// docs/test-vectors/phrase-words.json).
class SafetyPhraseWordlist {
  SafetyPhraseWordlist._(this.words);

  static const String assetPath = 'assets/wordlist/wordlist-en-v1.txt';

  /// Normative SHA-256 of the committed wordlist file (phrase-words.json).
  static const String pinnedSha256 =
      '7aa57a4d3ecf6581729992bad9575bacdebf7c28378af2aec6a50f11aec326f5';

  static const int wordCount = 1296;

  /// The 1296 words in index order.
  final List<String> words;

  static SafetyPhraseWordlist? _cached;

  /// Loads (and caches) the wordlist, asserting its SHA-256 matches the
  /// pinned value. Tests may pass a substitute [bundle].
  static Future<SafetyPhraseWordlist> load({AssetBundle? bundle}) async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final data = await (bundle ?? rootBundle).load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = sha256.convert(bytes).toString();
    if (digest != pinnedSha256) {
      throw StateError('safety-phrase wordlist failed integrity check');
    }
    final words = const LineSplitter()
        .convert(utf8.decode(bytes))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (words.length != wordCount) {
      throw StateError('safety-phrase wordlist must hold $wordCount words');
    }
    return _cached = SafetyPhraseWordlist._(words);
  }

  /// Test-only reset of the process cache.
  static void resetForTest() => _cached = null;
}
