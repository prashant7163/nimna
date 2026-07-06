/// Nimna code format, generation, canonicalization & QR payload —
/// spec §3.1.1, fixed permanently (spec §4). Pure and locale-independent:
/// the code renders identically in every locale; nothing here may touch
/// locale, I/O, or Flutter.
library;

import 'dart:typed_data';

/// The 32-character Crockford Base32 alphabet (no I, L, O, U) —
/// spec §3.1.1, byte-identical to the vectors' `crockford_alphabet`.
const String crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Code length in canonical characters (spec §4: fixed permanently).
const int pairingCodeLength = 9;

/// The `nimna:` QR payload prefix (lowercase, spec §3.1.1).
const String qrPayloadPrefix = 'nimna:';

/// A syntactically valid Nimna code held in canonical form: exactly 9
/// uppercase Crockford Base32 characters, no hyphens — the only form ever
/// hashed (spec §3.1.1).
class PairingCode {
  const PairingCode._(this.canonical);

  /// Canonical form: 9 ASCII characters of [crockfordAlphabet].
  final String canonical;

  /// Generates a fresh code: 9 characters sampled uniformly at random from
  /// the alphabet. [uniform] must return a uniformly distributed integer in
  /// `[0, upperBound)` — production injects libsodium's
  /// `randombytes_uniform`, which is bias-free by construction (no modulo
  /// over a byte stream).
  factory PairingCode.generate(int Function(int upperBound) uniform) {
    final chars = StringBuffer();
    for (var i = 0; i < pairingCodeLength; i++) {
      final index = uniform(crockfordAlphabet.length);
      if (index < 0 || index >= crockfordAlphabet.length) {
        throw ArgumentError.value(index, 'uniform', 'sampler out of range');
      }
      chars.write(crockfordAlphabet[index]);
    }
    return PairingCode._(chars.toString());
  }

  /// Canonicalizes [input] per spec §3.1.1 (identical for all four join
  /// methods): strip whitespace (exactly ASCII space, tab, CR, LF) and
  /// hyphens; fold to uppercase; map `I → 1`, `L → 1`, `O → 0` (Crockford
  /// decode rules). `U` is not in the alphabet and is invalid — rejected,
  /// never mapped. Anything that does not canonicalize to exactly 9
  /// alphabet characters returns null (client-side error; nothing is sent).
  static PairingCode? canonicalize(String input) {
    final out = StringBuffer();
    for (final unit in input.codeUnits) {
      switch (unit) {
        case 0x20 || 0x09 || 0x0D || 0x0A || 0x2D: // space tab CR LF hyphen
          continue;
      }
      var c = String.fromCharCode(unit).toUpperCase();
      switch (c) {
        case 'I' || 'L':
          c = '1';
        case 'O':
          c = '0';
      }
      if (c.length != 1 || !crockfordAlphabet.contains(c)) {
        return null;
      }
      out.write(c);
      if (out.length > pairingCodeLength) {
        return null;
      }
    }
    if (out.length != pairingCodeLength) {
      return null;
    }
    return PairingCode._(out.toString());
  }

  /// Rebuilds a code from stored canonical bytes (the at-rest record);
  /// throws on anything that is not already canonical.
  factory PairingCode.fromCanonicalBytes(Uint8List bytes) {
    final code = canonicalize(String.fromCharCodes(bytes));
    if (code == null || code.canonical != String.fromCharCodes(bytes)) {
      throw ArgumentError('not canonical code bytes');
    }
    return code;
  }

  /// The canonical 9 ASCII bytes — the only form ever hashed (§3.1.2).
  Uint8List get canonicalBytes => Uint8List.fromList(canonical.codeUnits);

  /// Display form `XXX-XXX-XXX` — the grouping is part of the format
  /// (spec §4); mono face everywhere; identical in every locale.
  String get display =>
      '${canonical.substring(0, 3)}-'
      '${canonical.substring(3, 6)}-'
      '${canonical.substring(6, 9)}';

  /// QR payload: the ASCII string `nimna:XXX-XXX-XXX` — canonical
  /// characters, display hyphenation, lowercase prefix, nothing else
  /// (spec §3.1.1: no expiry hint, no version, no metadata).
  String get qrPayload => '$qrPayloadPrefix$display';

  @override
  bool operator ==(Object other) =>
      other is PairingCode && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;

  /// Deliberately NOT the code: a code must never reach a log or an
  /// exception message through an implicit toString.
  @override
  String toString() => 'PairingCode(redacted)';
}
