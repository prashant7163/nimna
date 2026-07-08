import 'package:flutter_test/flutter_test.dart';
import 'package:nimna/src/diag/diag_events.dart';
import 'package:nimna/src/diag/diag_export.dart';
import 'package:nimna/src/diag/diag_record.dart';

/// The diagnostics export renderer (architect Concern 2) is structurally
/// content-free: enum NAMES + decimal integers + UTC timestamps only. It
/// CANNOT emit content, keys, codes, tokens, or peer identifiers — a
/// [DiagRecord] carries none. Empty is handled gracefully.
void main() {
  test('render is enum-names + decimal ints + ISO timestamps only', () {
    final records = [
      DiagRecord(
        event: DiagEvent.appLaunch,
        code: DiagCode.none,
        timestampMs: DateTime.utc(2026, 7, 8, 9, 41).millisecondsSinceEpoch,
        args: const [],
      ),
      DiagRecord(
        event: DiagEvent.storageError,
        code: DiagCode.relayUnreachable,
        timestampMs: DateTime.utc(2026, 7, 8, 9, 42).millisecondsSinceEpoch,
        args: const [3, 500],
      ),
    ];

    final out = DiagExport.render(records);

    // Developer constants (enum names) appear; integers render as decimals.
    expect(out, contains('appLaunch'));
    expect(out, contains('storageError'));
    expect(out, contains('relayUnreachable'));
    expect(out, contains('3,500'));
    // ISO-8601 UTC timestamp (locale-independent).
    expect(out, contains('2026-07-08T09:41:00.000Z'));
    expect(out, contains('records: 2'));

    // No decode ambiguity: args are plain decimals, never hex/ascii.
    expect(out, isNot(contains('0x')));
  });

  test('empty log renders a header only (graceful)', () {
    final out = DiagExport.render(const []);
    expect(out, contains('records: 0'));
  });
}
