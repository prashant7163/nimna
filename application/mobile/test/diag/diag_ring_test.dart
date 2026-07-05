import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/crypto/at_rest_aead.dart';
import 'package:nimna/src/diag/diag.dart';
import 'package:nimna/src/diag/diag_events.dart';

import '../helpers/test_env.dart';

/// Ring behavior (exactly 7 UTC day files), sealed-queue behavior, and the
/// encrypted on-disk format (raw bytes decode to nothing).
void main() {
  late AtRestAead aead;
  late Directory dir;
  late DateTime now;

  DateTime clock() => now;

  Diag newDiag() => Diag(aead: aead, clock: clock);

  setUpAll(() async {
    aead = await testAead();
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nimna-diag-');
    now = DateTime.utc(2026, 7, 1, 12);
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  List<String> dayFiles() =>
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();

  test('day rollover prunes: the 8th day file dies', () {
    final diag = newDiag();
    diag.attach(diagKey: aead.newKey(), dir: dir);

    for (var day = 0; day < 9; day++) {
      now = DateTime.utc(2026, 7, 1 + day, 12);
      diag.log(DiagEvent.appLaunch);
    }

    // Days 20260701..20260709 written; only the last 7 survive.
    expect(dayFiles(), [
      '20260703.nlog',
      '20260704.nlog',
      '20260705.nlog',
      '20260706.nlog',
      '20260707.nlog',
      '20260708.nlog',
      '20260709.nlog',
    ]);
    diag.detach();
  });

  test('attach prunes stale files from a previous run', () {
    final first = newDiag()..attach(diagKey: aead.newKey(), dir: dir);
    first.log(DiagEvent.appLaunch);
    first.detach();
    expect(dayFiles(), ['20260701.nlog']);

    now = DateTime.utc(2026, 7, 20);
    final second = newDiag()..attach(diagKey: aead.newKey(), dir: dir);
    expect(dayFiles(), isEmpty);
    second.detach();
  });

  test('sealed queue buffers (256 cap, drop-oldest) and flushes at attach', () {
    final diag = newDiag();
    // 300 sealed events; only the newest 256 survive.
    for (var i = 0; i < 300; i++) {
      diag.log(DiagEvent.appLaunch, args: [i]);
    }
    final key = aead.newKey();
    diag.attach(diagKey: key, dir: dir);

    final records = diag.readAll();
    expect(records.length, 256);
    expect(records.first.args, [44]); // 300 - 256 = 44 dropped
    expect(records.last.args, [299]);
    diag.detach();
  });

  test('readAll round-trips events and codes within the closed enums', () {
    final diag = newDiag()..attach(diagKey: aead.newKey(), dir: dir);
    for (final event in DiagEvent.values) {
      diag.log(event, code: DiagCode.ioError, args: [event.id]);
    }
    final records = diag.readAll();
    expect(records.length, DiagEvent.values.length);
    for (final r in records) {
      expect(DiagEvent.values, contains(r.event));
      expect(DiagCode.values, contains(r.code));
      expect(r.args, [r.event.id]);
    }
    diag.detach();
  });

  test('on-disk bytes are ciphertext: a fresh key cannot read them', () {
    final diag = newDiag()..attach(diagKey: aead.newKey(), dir: dir);
    diag.log(DiagEvent.storeOpened);
    diag.detach();

    final other = newDiag()..attach(diagKey: aead.newKey(), dir: dir);
    expect(() => other.readAll(), throwsA(isA<AeadAuthError>()));
    other.detach();
  });

  test('reset drops the sealed queue — no trace survives a full wipe', () {
    final diag = newDiag();
    diag.log(DiagEvent.storeSealed);
    diag.reset();
    diag.attach(diagKey: aead.newKey(), dir: dir);
    expect(diag.readAll(), isEmpty);
    diag.detach();
  });

  test('log while detached never touches the filesystem', () {
    final diag = newDiag();
    diag.log(DiagEvent.appLaunch);
    expect(dir.listSync(), isEmpty);
  });
}
