import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/protocol/pairing_code.dart';

/// All four join methods (spec §3.1 step 3) canonicalize to the SAME bytes.
/// Manual entry and paste feed [PairingCode.canonicalize] directly; live
/// scan and upload feed [PairingCode.fromScannedPayload] (which strips the
/// `nimna:` QR prefix, spec §3.1.1). Every representation of one code
/// converges.
void main() {
  const canonical = 'KR7FM2XQ4';

  PairingCode expectCode(PairingCode? code) {
    expect(code, isNotNull);
    expect(code!.canonical, canonical);
    return code;
  }

  test('manual entry — lowercase, no hyphens', () {
    expectCode(PairingCode.canonicalize('kr7fm2xq4'));
  });

  test('manual entry — with Crockford ambiguous glyphs (I→1, O→0, L→1)', () {
    // A 9-char code typed with look-alikes; Crockford decode folds them.
    expect(PairingCode.canonicalize('ilo-234-567')?.canonical, '110234567');
  });

  test('paste — display form with hyphens, mixed case', () {
    expectCode(PairingCode.canonicalize('Kr7-fM2-Xq4'));
  });

  test('paste — with surrounding whitespace/newlines', () {
    expectCode(PairingCode.canonicalize('  KR7-FM2-XQ4\n'));
  });

  test('scan — full QR payload with prefix and hyphens', () {
    expectCode(PairingCode.fromScannedPayload('nimna:KR7-FM2-XQ4'));
  });

  test('scan — prefix, no hyphens', () {
    expectCode(PairingCode.fromScannedPayload('nimna:KR7FM2XQ4'));
  });

  test('scan/upload — payload without the prefix (scanners accept both)', () {
    expectCode(PairingCode.fromScannedPayload('KR7-FM2-XQ4'));
  });

  test('scan — case-insensitive prefix', () {
    expectCode(PairingCode.fromScannedPayload('NIMNA:kr7fm2xq4'));
  });

  test('all four representations converge to identical canonical bytes', () {
    final forms = <PairingCode?>[
      PairingCode.canonicalize('kr7fm2xq4'), // manual
      PairingCode.canonicalize('KR7-FM2-XQ4'), // paste
      PairingCode.fromScannedPayload('nimna:KR7-FM2-XQ4'), // scan
      PairingCode.fromScannedPayload('KR7FM2XQ4'), // upload (no prefix)
    ];
    for (final f in forms) {
      expect(f?.canonicalBytes, forms.first?.canonicalBytes);
    }
  });

  test('a foreign / unreadable QR yields no code (no error state, F3.2)', () {
    expect(PairingCode.fromScannedPayload('https://example.com'), isNull);
    expect(PairingCode.fromScannedPayload('nimna:TOO-SHORT'), isNull);
    expect(PairingCode.fromScannedPayload('nimna:has U invalid'), isNull);
  });
}
