import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The S10 directory-decomposition fence (the G4-gating done-check clause;
/// same source-scan class as test/pairing/single_call_site_test.dart). It
/// mechanically PASS/FAILs the `lib/src/session` split so that G4 (S11 ∥ S12)
/// is safe — the two lanes cannot grow a shared mutable surface:
///
///   model/       IMMUTABLE seam types — a leaf: imports neither connection/
///                nor chat/, and no Flutter widget library.
///   connection/  the protocol lane — imports NO Flutter and NO chat/ (owns
///                the transport/keys/counters/message store).
///   chat/        the widget lane — may import model/ + connection/'s public
///                interface, but must NOT hold/mutate a NoiseTransport / key /
///                counter / message store.
void main() {
  String strip(String source) => source.replaceAll(RegExp(r'//[^\n]*'), '');

  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  const modelDir = 'lib/src/session/model';
  const connectionDir = 'lib/src/session/connection';
  const chatDir = 'lib/src/session/chat';

  test('model/ is a leaf: no connection/, chat/, or Flutter widget import', () {
    for (final file in dartFilesUnder(modelDir)) {
      final code = strip(file.readAsStringSync());
      expect(
        code.contains("session/connection/") ||
            code.contains("'../connection/") ||
            code.contains("session/chat/") ||
            code.contains("'../chat/"),
        isFalse,
        reason: '${file.path}: model/ must not import connection/ or chat/',
      );
      expect(
        code.contains('package:flutter/material.dart') ||
            code.contains('package:flutter/widgets.dart') ||
            code.contains('package:flutter/cupertino.dart'),
        isFalse,
        reason: '${file.path}: model/ is Flutter-free (immutable seam types)',
      );
    }
  });

  test('connection/ imports no Flutter and no chat/', () {
    for (final file in dartFilesUnder(connectionDir)) {
      final code = strip(file.readAsStringSync());
      expect(
        code.contains('package:flutter/'),
        isFalse,
        reason:
            '${file.path}: the connection lane must not import ANY Flutter '
            'library (no widget/foundation coupling)',
      );
      expect(
        code.contains("session/chat/") || code.contains("'../chat/"),
        isFalse,
        reason: '${file.path}: connection/ must not import chat/',
      );
    }
  });

  test('chat/ holds no transport / key / counter / message store', () {
    // The chat lane renders immutable view models and reports gestures; it
    // must never touch protocol state. Any of these identifiers appearing in a
    // chat/ file is a shared-mutable-surface leak.
    const banned = [
      'NoiseTransport',
      'SessionTransport',
      'SecureKey',
      'MessageRepository',
      'MessageStore',
      'ChannelRepository',
      'AtRestAead',
      'NoiseHandshakeState',
      'SessionInitiatorHandshake',
      'SessionResponderHandshake',
    ];
    for (final file in dartFilesUnder(chatDir)) {
      final code = strip(file.readAsStringSync());
      for (final needle in banned) {
        expect(
          code.contains(needle),
          isFalse,
          reason:
              '${file.path}: chat/ must not reference $needle — the connection '
              'lane owns all transport/key/counter/store state (import fence)',
        );
      }
      // chat/ may import the connection lane's public interface, but never
      // reaches into the noise/transport/storage trees directly.
      expect(
        code.contains("src/noise/") ||
            code.contains("src/transport/") ||
            code.contains("src/storage/"),
        isFalse,
        reason:
            '${file.path}: chat/ must not import the noise/transport/storage '
            'trees directly',
      );
    }
  });
}
