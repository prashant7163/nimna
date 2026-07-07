import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/pairing/initiator/qr_matrix.dart';
import 'package:nimna/src/protocol/pairing_code.dart';

/// The committed expected-matrix test (S8 intake §7 sign-off condition):
/// the encoder must reproduce, bit for bit, the fixture matrix that was
/// verified once with an independent decoder (Apple Vision — see
/// test/fixtures/README.md). The QR carries the payload and NOTHING else
/// (spec §3.1.1: no expiry hint, no version, no metadata).
void main() {
  test('module matrix for nimna:KR7-FM2-XQ4 matches the verified fixture', () {
    final expected = File(
      'test/fixtures/qr_nimna_kr7-fm2-xq4_ecM.txt',
    ).readAsLinesSync().where((l) => l.isNotEmpty).toList();

    final code = PairingCode.canonicalize('KR7-FM2-XQ4')!;
    expect(code.qrPayload, 'nimna:KR7-FM2-XQ4');
    final matrix = QrMatrix.forCode(code);

    expect(matrix.moduleCount, expected.length);
    final actual = [
      for (var y = 0; y < matrix.moduleCount; y++)
        [
          for (var x = 0; x < matrix.moduleCount; x++)
            matrix.isDark(x, y) ? '#' : '.',
        ].join(),
    ];
    expect(actual, expected);
  });

  test('matrix is deterministic and square for every code shape', () {
    for (final canonical in ['000000000', 'ZZZZZZZZZ', '7Q2M4K9XV']) {
      final code = PairingCode.canonicalize(canonical)!;
      final a = QrMatrix.forCode(code);
      final b = QrMatrix.forCode(code);
      expect(a.moduleCount, b.moduleCount);
      for (var y = 0; y < a.moduleCount; y++) {
        for (var x = 0; x < a.moduleCount; x++) {
          expect(a.isDark(x, y), b.isDark(x, y));
        }
      }
    }
  });
}
