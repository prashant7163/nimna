import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/pairing_code.dart';

/// §3.1.1 code format — vector-locked to
/// docs/test-vectors/topic-derivation.json (canonicalization cases) plus
/// generation properties (uniform sampler by construction — no modulo
/// bias: one uniform(32) draw per character).
void main() {
  final vectors =
      jsonDecode(
            File(
              '../../docs/test-vectors/topic-derivation.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('alphabet matches the committed vectors byte for byte', () {
    expect(crockfordAlphabet, vectors['crockford_alphabet']);
    expect(crockfordAlphabet.length, 32);
  });

  group('canonicalization (every committed case)', () {
    for (final caseJson in vectors['cases'] as List<dynamic>) {
      final c = caseJson as Map<String, dynamic>;
      test(c['name'], () {
        final code = PairingCode.canonicalize(c['input'] as String);
        if (c['valid'] as bool) {
          expect(code, isNotNull);
          expect(code!.canonical, c['canonical']);
        } else {
          expect(code, isNull, reason: c['reject_reason'] as String?);
        }
      });
    }
  });

  test('rejects empty, whitespace-only, and unicode lookalike input', () {
    expect(PairingCode.canonicalize(''), isNull);
    expect(PairingCode.canonicalize(' \t\r\n---'), isNull);
    // Cyrillic А is not ASCII 'A'; no mapping may exist.
    expect(PairingCode.canonicalize('АQ2-M4K-9XV'), isNull);
  });

  test('display grouping and QR payload (spec-fixed forms)', () {
    final code = PairingCode.canonicalize('7Q2M4K9XV')!;
    expect(code.display, '7Q2-M4K-9XV');
    expect(code.qrPayload, 'nimna:7Q2-M4K-9XV');
    expect(code.canonicalBytes, ascii.encode('7Q2M4K9XV'));
    // All four §3.1 input forms converge on the same bytes.
    expect(PairingCode.canonicalize(code.display), code);
    expect(
      PairingCode.canonicalize(code.qrPayload.substring('nimna:'.length)),
      code,
    );
  });

  test('generation: 9 draws of uniform(32) mapped through the alphabet', () {
    final draws = <int>[];
    var next = 0;
    final code = PairingCode.generate((upperBound) {
      expect(upperBound, 32);
      draws.add(next);
      return next++ % 32;
    });
    expect(draws.length, pairingCodeLength);
    expect(code.canonical, '012345678');
    expect(code.display, '012-345-678');
  });

  test('generation covers the full alphabet, rejects rogue samplers', () {
    for (var v = 0; v < 32; v++) {
      final code = PairingCode.generate((_) => v);
      expect(code.canonical, crockfordAlphabet[v] * 9);
      // Every generated code is its own canonical form.
      expect(PairingCode.canonicalize(code.canonical), code);
    }
    expect(() => PairingCode.generate((_) => 32), throwsArgumentError);
    expect(() => PairingCode.generate((_) => -1), throwsArgumentError);
  });

  test('toString never leaks the code', () {
    final code = PairingCode.canonicalize('7Q2M4K9XV')!;
    expect(code.toString().contains('7Q2'), isFalse);
  });
}
