import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-scan pins for the S8 structural invariants (same class as the S7
/// string-scan tests; reviewer remains the authority):
///
/// 1. **G2 single entry (intake §4):** `startCreateLine` — the only way to
///    begin code creation — is called from exactly ONE site outside its
///    defining file. S17 wires the paywall gate by editing exactly
///    create_line_entry.dart; this test guarantees no second ungated door
///    ever appears.
/// 2. **share_plus fence (intake §7):** the dependency is invoked from the
///    single call-site module `lib/src/pairing/initiator/share.dart`.
/// 3. **qr fence:** the encoder is invoked only from `qr_matrix.dart`
///    (whose output is pinned by the committed fixture).
void main() {
  List<File> dartFilesUnderLib() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('lib/l10n/'))
      .toList();

  String stripComments(String source) =>
      source.replaceAll(RegExp(r'//[^\n]*'), '');

  test('startCreateLine has exactly one call site outside its file', () {
    const definingFile = 'lib/src/pairing/initiator/create_line_entry.dart';
    final callSites = <String>[];
    for (final file in dartFilesUnderLib()) {
      if (file.path == definingFile) {
        continue;
      }
      final code = stripComments(file.readAsStringSync());
      for (final match in RegExp(r'startCreateLine\s*\(').allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        callSites.add('${file.path}:$line');
      }
    }
    expect(
      callSites,
      hasLength(1),
      reason:
          'startCreateLine must have exactly ONE call site (the F4 create '
          'action) — S17 gates creation at create_line_entry.dart alone. '
          'Found: $callSites',
    );
    expect(callSites.single, startsWith('lib/src/ui/screens/'));
  });

  test('share_plus is imported only by the fenced call sites', () {
    // S8: the pairing-code share. S11: the media export (the one deliberate
    // quarantine exit — decrypt-to-temp → share → cleanup, spec §5.1). S16: the
    // diagnostics export (structurally content-free enum-names + ints, shared
    // in-memory via ShareParams(text:) — no temp file; architect Concern 2).
    const allowed = {
      'lib/src/pairing/initiator/share.dart',
      'lib/src/media/pipeline/media_export.dart',
      'lib/src/ui/screens/settings/diagnostics_screen.dart',
    };
    final offenders = <String>[];
    for (final file in dartFilesUnderLib()) {
      if (allowed.contains(file.path)) {
        continue;
      }
      final code = stripComments(file.readAsStringSync());
      if (code.contains('package:share_plus')) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'share_plus is fenced to $allowed (S8 code-share + S11 media-export '
          'scoped sign-offs)',
    );
  });

  test('the qr encoder is imported only by qr_matrix.dart', () {
    const matrixModule = 'lib/src/pairing/initiator/qr_matrix.dart';
    final offenders = <String>[];
    for (final file in dartFilesUnderLib()) {
      if (file.path == matrixModule) {
        continue;
      }
      final code = stripComments(file.readAsStringSync());
      if (code.contains('package:qr/')) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'the qr encoder is fenced to $matrixModule (fixture-pinned)',
    );
  });

  test(
    'crypto_scalarmult (sumo X25519) lives ONLY in lib/src/noise/dh.dart',
    () {
      // The Noise DH is a new sumo FFI use of a signed-off primitive
      // (SESSION-9 intake flag); it is fenced to the single Noise-DH module so
      // the scalarmult surface never sprawls. Same crypto-sprawl-guard
      // discipline as the crypto_pwhash fence
      // (test/lock/pin_verifier_test.dart).
      const allowed = 'lib/src/noise/dh.dart';
      final offenders = <String>[];
      for (final file in dartFilesUnderLib()) {
        if (file.path == allowed) {
          continue;
        }
        final code = stripComments(file.readAsStringSync());
        if (code.contains('scalarmult')) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'crypto_scalarmult is fenced to $allowed (SESSION-9: the sole '
            'X25519/Noise-DH site; keep the sumo scalarmult surface here)',
      );
    },
  );

  test('the §5.5–§5.8 inner-envelope codec is confined to its two modules '
      '(S10 checkpoint)', () {
    // S10 OPENS the fence the S8/S9 sessions reserved: the inner envelope
    // (§5.5: TEXT/ACK/CONTROL/HANGUP/MEDIA_CHUNK/REACTION) and the
    // reaction/reply codecs (§5.8) are now implemented — but the CLASS
    // DEFINITIONS live ONLY in inner_envelope.dart + reaction_body.dart.
    // No second implementation may sprawl elsewhere in the protocol tree
    // (same crypto/framing-sprawl discipline as the scalarmult fence
    // above). Usage from the future session layer (lib/src/session, Phase
    // B) is expected and unfenced — this pins the codec's single home.
    const sanctioned = {
      'lib/src/protocol/inner_envelope.dart',
      'lib/src/protocol/reaction_body.dart',
    };
    final defRe = RegExp(
      r'class\s+(InnerEnvelope|ReactionBody|AckBody|ControlBody|'
      r'ManifestBody|ChunkBody)\b',
    );
    final offenders = <String>[];
    for (final file
        in Directory('lib/src/protocol')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      if (sanctioned.contains(file.path)) {
        continue;
      }
      final code = stripComments(file.readAsStringSync());
      if (defRe.hasMatch(code)) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'the §5.5–§5.8 inner-envelope codec is defined only in '
          'inner_envelope.dart + reaction_body.dart (S10 checkpoint home); '
          'found a second definition in: $offenders',
    );
  });
}
