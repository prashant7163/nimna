import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/diag/diag_events.dart';
import 'package:nimna/src/diag/diag_record.dart';

/// The fixed binary encoding: integers only, big-endian, closed vocabulary.
void main() {
  test('round-trips every event with every code', () {
    for (final event in DiagEvent.values) {
      for (final code in DiagCode.values) {
        final record = DiagRecord(
          event: event,
          code: code,
          timestampMs: 1751700000123,
          args: const [0, 1, -1, 1 << 40],
        );
        final decoded = DiagCodec.decode(DiagCodec.encode(record));
        expect(decoded.event, event);
        expect(decoded.code, code);
        expect(decoded.timestampMs, record.timestampMs);
        expect(decoded.args, record.args);
      }
    }
  });

  test('record length is exactly header + 8×argc — no varlen fields', () {
    for (final argc in [0, 1, 5]) {
      final bytes = DiagCodec.encode(
        DiagRecord(
          event: DiagEvent.appLaunch,
          code: DiagCode.none,
          timestampMs: 0,
          args: List.filled(argc, 7),
        ),
      );
      expect(bytes.length, DiagCodec.headerBytes + 8 * argc);
    }
  });

  test('unknown event id is rejected (closed vocabulary)', () {
    final bytes = DiagCodec.encode(
      const DiagRecord(
        event: DiagEvent.appLaunch,
        code: DiagCode.none,
        timestampMs: 0,
        args: [],
      ),
    );
    final data = ByteData.sublistView(bytes)..setUint16(1, 0xFFFF);
    expect(
      () => DiagCodec.decode(data.buffer.asUint8List()),
      throwsA(isA<DiagDecodeError>()),
    );
  });

  test('unknown code id is rejected (closed vocabulary)', () {
    final bytes = DiagCodec.encode(
      const DiagRecord(
        event: DiagEvent.appLaunch,
        code: DiagCode.none,
        timestampMs: 0,
        args: [],
      ),
    );
    final data = ByteData.sublistView(bytes)..setUint16(3, 0xFFFF);
    expect(
      () => DiagCodec.decode(data.buffer.asUint8List()),
      throwsA(isA<DiagDecodeError>()),
    );
  });

  test('wrong version byte is rejected', () {
    final bytes = DiagCodec.encode(
      const DiagRecord(
        event: DiagEvent.appLaunch,
        code: DiagCode.none,
        timestampMs: 0,
        args: [],
      ),
    );
    bytes[0] = 99;
    expect(() => DiagCodec.decode(bytes), throwsA(isA<DiagDecodeError>()));
  });

  test('length mismatch is rejected', () {
    final bytes = DiagCodec.encode(
      const DiagRecord(
        event: DiagEvent.appLaunch,
        code: DiagCode.none,
        timestampMs: 0,
        args: [1],
      ),
    );
    expect(
      () => DiagCodec.decode(Uint8List.sublistView(bytes, 0, bytes.length - 1)),
      throwsA(isA<DiagDecodeError>()),
    );
  });

  test('wire ids are stable and append-only (regression pin)', () {
    // Renumbering breaks decodability of existing logs; this test pins the
    // published ids. Extend it when (and only when) members are appended.
    expect(DiagEvent.appLaunch.id, 1);
    expect(DiagEvent.masterKeyGenerated.id, 2);
    expect(DiagEvent.storeCreated.id, 3);
    expect(DiagEvent.storeOpened.id, 4);
    expect(DiagEvent.storeSealed.id, 5);
    expect(DiagEvent.schemaReset.id, 6);
    expect(DiagEvent.channelWiped.id, 7);
    expect(DiagEvent.backupExclusionAsserted.id, 8);
    expect(DiagEvent.backupExclusionFailed.id, 9);
    expect(DiagEvent.storageError.id, 10);
    expect(DiagCode.none.id, 0);
    expect(DiagCode.unknown.id, 1);
    expect(DiagCode.keystoreUnavailable.id, 2);
    expect(DiagCode.dbOpenFailed.id, 3);
    expect(DiagCode.recordCorrupt.id, 4);
    expect(DiagCode.ioError.id, 5);
    expect(DiagCode.platformChannelUnavailable.id, 6);
    expect(DiagCode.schemaMismatch.id, 7);
  });
}
