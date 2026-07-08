/// Diagnostics export (architect Concern 2 / F8 settings) — the ONE deliberate
/// act that moves the local diagnostic log OUT of Nimna, through the OS share
/// sheet, on a single user tap. Nothing auto-uploads; the app makes no network
/// call here.
///
/// The rendered text is STRUCTURALLY content-free: a [DiagRecord] is closed
/// enums + int64s (event/code names are developer constants, never user text;
/// the §6 layer-1 source-scan asserts the whole diag public API is String-free,
/// and the layer-3 planted-marker audit asserts no sensitive markers reach the
/// bytes). This renderer therefore CANNOT emit content, keys, codes, tokens, or
/// peer identifiers — it prints enum names, decimal integers, and UTC
/// timestamps only. `args` are rendered as plain decimal integers (never
/// hex/ascii-reinterpreted) so the rendering introduces no decode ambiguity.
///
/// Only the PURE render lives here (its sole parameter is `List<DiagRecord>`,
/// no text-capable param — the diag_api_surface scan of `lib/src/diag/` stays
/// green). The `share_plus` sink is the diagnostics SCREEN
/// (`diagnostics_screen.dart`), the third sanctioned call site fenced in
/// test/pairing/single_call_site_test.dart; it hands the rendered text
/// in-memory via `ShareParams(text:)`, so NO plaintext file ever touches the
/// filesystem (unlike media, which must attach a file).
library;

import 'diag_record.dart';

abstract final class DiagExport {
  /// Renders the retained log as a human-readable, structurally content-free
  /// dump: one line per record — `ISO-8601-UTC  event  code  args` — with a
  /// short header. Pure and locale-independent (enum names + integers only;
  /// `args` as plain decimal ints, never hex/ascii-reinterpreted).
  static String render(List<DiagRecord> records) {
    final buffer = StringBuffer()
      ..writeln('nimna diagnostics')
      ..writeln('records: ${records.length}')
      ..writeln('event codes and times only — no message content')
      ..writeln('---');
    for (final r in records) {
      final ts = DateTime.fromMillisecondsSinceEpoch(
        r.timestampMs,
        isUtc: true,
      ).toIso8601String();
      buffer.writeln(
        '$ts\t${r.event.name}\t${r.code.name}\t${r.args.join(',')}',
      );
    }
    return buffer.toString();
  }
}
