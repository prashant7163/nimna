/// CRID (§3.1.5) and the safety phrase (§3.1.4) — both derived from the
/// channel's shared secret `ss = X25519(own static priv, peer static pub)`
/// and `salt2`, vector-locked to `docs/test-vectors/pairing-handshake.json`
/// (`channel.*`) and `docs/test-vectors/phrase-words.json`.
///
/// Pure and locale-independent: this module takes `ss` as bytes (the DH is
/// computed once, in `lib/src/noise` — the sole scalarmult site) and does
/// only HKDF-SHA-256 (the in-repo RFC 5869 composition) and integer mapping.
/// The safety phrase is **protocol output, not UI copy**: one global
/// wordlist, rendered identically in every locale (spec §3.1.4, i18n
/// decision 2026-07-04). Pairing-plane surface only — no §5.5–§5.8 codec.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../crypto/hkdf.dart';

/// HKDF info label for the CRID (spec §3.1.5).
const String cridLabel = 'nimna/crid/v1';

/// HKDF info label for the safety phrase (spec §3.1.4).
const String phraseLabel = 'nimna/phrase/v1';

/// CRID length in bytes (spec §3.1.5).
const int cridBytes = 16;

/// Safety-phrase HKDF output length in bytes (spec §3.1.4).
const int phraseOutBytes = 8;

/// Wordlist size — the base of the three phrase digits (spec §3.1.4).
const int phraseWordCount = 1296;

/// `salt2 = SHA-256( min(A_pub, B_pub) ‖ max(A_pub, B_pub) )` in lexicographic
/// byte order (spec §3.1.4) — identical on both ends because it sorts the two
/// public keys.
Uint8List channelSalt2({
  required Uint8List aPublic,
  required Uint8List bPublic,
}) {
  final aFirst = _lexLessOrEqual(aPublic, bPublic);
  final lo = aFirst ? aPublic : bPublic;
  final hi = aFirst ? bPublic : aPublic;
  return Uint8List.fromList(sha256.convert(<int>[...lo, ...hi]).bytes);
}

/// `CRID = HKDF-SHA-256(ikm = ss, salt = salt2, info = "nimna/crid/v1")[0:16]`
/// (spec §3.1.5).
Uint8List deriveCrid({required Uint8List ss, required Uint8List salt2}) =>
    hkdfSha256(
      ikm: ss,
      salt: salt2,
      info: ascii.encode(cridLabel),
      length: cridBytes,
    );

/// The 8-byte safety-phrase HKDF output (spec §3.1.4).
Uint8List safetyPhraseBytes({
  required Uint8List ss,
  required Uint8List salt2,
}) => hkdfSha256(
  ikm: ss,
  salt: salt2,
  info: ascii.encode(phraseLabel),
  length: phraseOutBytes,
);

/// Maps the 8 phrase bytes to three wordlist indices (spec §3.1.4):
/// `n = uint64 big-endian`; `word0 = (n ÷ 1296²) mod 1296`,
/// `word1 = (n ÷ 1296) mod 1296`, `word2 = n mod 1296` — most-significant
/// digit first. BigInt because `n` spans the full unsigned 64-bit range
/// (the max-uint64 vector case exceeds Dart's signed-int max).
List<int> phraseIndices(Uint8List out8) {
  if (out8.length != phraseOutBytes) {
    throw ArgumentError('phrase output must be $phraseOutBytes bytes');
  }
  var n = BigInt.zero;
  for (final byte in out8) {
    n = (n << 8) | BigInt.from(byte);
  }
  final base = BigInt.from(phraseWordCount);
  final word2 = (n % base).toInt();
  final word1 = ((n ~/ base) % base).toInt();
  final word0 = ((n ~/ (base * base)) % base).toInt();
  return [word0, word1, word2];
}

/// The three safety-phrase words, in derivation order, rendered from
/// [wordlist] (the pinned global list; spec §3.1.4). Lowercase by wordlist
/// construction; identical in every locale.
List<String> safetyPhraseWords({
  required Uint8List ss,
  required Uint8List aPublic,
  required Uint8List bPublic,
  required List<String> wordlist,
}) {
  if (wordlist.length != phraseWordCount) {
    throw ArgumentError('wordlist must hold $phraseWordCount words');
  }
  final salt2 = channelSalt2(aPublic: aPublic, bPublic: bPublic);
  final out = safetyPhraseBytes(ss: ss, salt2: salt2);
  try {
    return [for (final i in phraseIndices(out)) wordlist[i]];
  } finally {
    out.fillRange(0, out.length, 0);
  }
}

bool _lexLessOrEqual(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) {
      return a[i] < b[i];
    }
  }
  return a.length <= b.length;
}
