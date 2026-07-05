import 'dart:typed_data';

import 'diag_events.dart';

/// Thrown when stored diagnostic bytes do not decode to the closed
/// vocabulary and fixed layout. Carries no data beyond its type.
class DiagDecodeError extends Error {
  @override
  String toString() => 'DiagDecodeError';
}

/// One decoded diagnostic record.
class DiagRecord {
  const DiagRecord({
    required this.event,
    required this.code,
    required this.timestampMs,
    required this.args,
  });

  final DiagEvent event;
  final DiagCode code;
  final int timestampMs;
  final List<int> args;
}

/// Fixed binary encoding (app-architecture.md §6 — normative):
/// `ver(1) ‖ event(2) ‖ code(2) ‖ ts_ms(8) ‖ argc(1) ‖ argc × int64`,
/// integers only, big-endian, no variable-length fields. There is no
/// pathway for text in this layout.
abstract final class DiagCodec {
  static const int version = 1;
  static const int headerBytes = 1 + 2 + 2 + 8 + 1;
  static const int maxArgs = 255;

  static Uint8List encode(DiagRecord record) {
    if (record.args.length > maxArgs) {
      throw ArgumentError.value(record.args.length, 'args', 'at most $maxArgs');
    }
    final out = ByteData(headerBytes + 8 * record.args.length);
    var offset = 0;
    out.setUint8(offset, version);
    offset += 1;
    out.setUint16(offset, record.event.id);
    offset += 2;
    out.setUint16(offset, record.code.id);
    offset += 2;
    out.setUint64(offset, record.timestampMs);
    offset += 8;
    out.setUint8(offset, record.args.length);
    offset += 1;
    for (final arg in record.args) {
      out.setInt64(offset, arg);
      offset += 8;
    }
    return out.buffer.asUint8List();
  }

  /// Decodes one record; throws [DiagDecodeError] on any deviation from the
  /// fixed layout or on ids outside the closed enums.
  static DiagRecord decode(Uint8List bytes) {
    if (bytes.length < headerBytes) {
      throw DiagDecodeError();
    }
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    final ver = data.getUint8(offset);
    offset += 1;
    if (ver != version) {
      throw DiagDecodeError();
    }
    final event = DiagEvent.byId[data.getUint16(offset)];
    offset += 2;
    final code = DiagCode.byId[data.getUint16(offset)];
    offset += 2;
    if (event == null || code == null) {
      throw DiagDecodeError();
    }
    final tsMs = data.getUint64(offset);
    offset += 8;
    final argc = data.getUint8(offset);
    offset += 1;
    if (bytes.length != headerBytes + 8 * argc) {
      throw DiagDecodeError();
    }
    final args = List<int>.generate(argc, (i) => data.getInt64(offset + 8 * i));
    return DiagRecord(event: event, code: code, timestampMs: tsMs, args: args);
  }
}
