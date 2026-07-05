import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import '../crypto/at_rest_aead.dart';
import '../crypto/hkdf.dart';
import '../crypto/record_cipher.dart';
import 'diag_events.dart';
import 'diag_record.dart';

/// The local diagnostic log — an encrypted, ring-buffered (exactly 7 UTC
/// day files), structurally content-free event log (app-architecture.md §6).
///
/// PUBLIC LOGGING SURFACE: [log] only — enums and integers. No String or
/// Object parameter exists anywhere on this class's public API (enforced by
/// test/diag/diag_api_surface_test.dart), so free text is unrepresentable.
///
/// Perimeter: the day keys derive from `k_diag` (itself derived from the
/// master key), so a sealed app can neither write nor read the log. While
/// sealed, records queue in a bounded in-memory buffer (256, drop-oldest)
/// and flush at [attach]. A full panic wipe destroys the master key, deletes
/// the diag directory with the store root, and calls [reset] — leaving no
/// trace that a log (or a wipe) ever existed.
class Diag {
  Diag({required this._aead, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const int retainedDays = 7;
  static const int maxQueuedRecords = 256;
  static final Uint8List _dayLabel = ascii.encode('nimna/app/diag/day/v1');

  final AtRestAead _aead;
  final DateTime Function() _clock;

  SecureKey? _diagKey;
  Directory? _dir;
  final Queue<DiagRecord> _sealedQueue = Queue<DiagRecord>();

  bool get attached => _diagKey != null;

  /// Records an event. Safe to call in any state, from any layer.
  void log(
    DiagEvent event, {
    DiagCode code = DiagCode.none,
    List<int> args = const [],
  }) {
    final record = DiagRecord(
      event: event,
      code: code,
      timestampMs: _clock().toUtc().millisecondsSinceEpoch,
      args: args,
    );
    if (!attached) {
      if (_sealedQueue.length >= maxQueuedRecords) {
        _sealedQueue.removeFirst();
      }
      _sealedQueue.add(record);
      return;
    }
    _append(record);
  }

  /// Opens the log perimeter: takes ownership of [diagKey] (`k_diag`),
  /// ensures [dir] exists, prunes the ring, and flushes the sealed queue.
  ///
  /// Never throws on filesystem trouble (review S2): a failing diagnostic
  /// log must never break boot — appends simply drop until the disk
  /// recovers.
  void attach({required SecureKey diagKey, required Directory dir}) {
    _diagKey?.dispose();
    _diagKey = diagKey;
    _dir = dir;
    try {
      dir.createSync(recursive: true);
    } on FileSystemException {
      // Stay attached; _append drops records it cannot write.
    }
    prune();
    while (_sealedQueue.isNotEmpty) {
      _append(_sealedQueue.removeFirst());
    }
  }

  /// Closes the perimeter and zeroizes the key. Queued-but-unflushed
  /// records are retained in memory for the next [attach].
  void detach() {
    _diagKey?.dispose();
    _diagKey = null;
    _dir = null;
  }

  /// Full-wipe hook: detaches AND drops the sealed queue, so nothing —
  /// including the wipe itself — survives into a fresh store.
  void reset() {
    detach();
    _sealedQueue.clear();
  }

  /// Deletes day files older than [retainedDays] (keeps today plus the six
  /// preceding UTC days). Runs at attach and on day rollover. Filesystem
  /// failures are swallowed (review S2); pruning retries on the next
  /// rollover/attach.
  void prune() {
    try {
      final dir = _dir;
      if (dir == null || !dir.existsSync()) {
        return;
      }
      final today = _utcDayNumber(_clock().toUtc());
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.nlog')) {
          continue;
        }
        final day = _parseDayFileName(entity.uri.pathSegments.last);
        if (day == null || today - day > retainedDays - 1) {
          try {
            entity.deleteSync();
          } on FileSystemException {
            // Skip this file; retried next prune.
          }
        }
      }
    } on FileSystemException {
      // Listing failed; retried next prune.
    }
  }

  /// Decrypts and decodes the whole retained log, oldest file first.
  /// Test/export surface (S16 "share diagnostics" renders from this).
  List<DiagRecord> readAll() {
    final dir = _dir;
    final key = _diagKey;
    if (dir == null || key == null) {
      throw StateError('diag log is sealed');
    }
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.nlog'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final records = <DiagRecord>[];
    for (final file in files) {
      final date = file.uri.pathSegments.last.split('.').first;
      final dayKey = _deriveDayKey(key, date);
      try {
        final bytes = file.readAsBytesSync();
        var offset = 0;
        while (offset + 4 <= bytes.length) {
          final len = ByteData.sublistView(bytes, offset).getUint32(0);
          offset += 4;
          if (offset + len > bytes.length) {
            // Torn trailing frame (appends aren't atomic — review N2):
            // keep everything decoded so far, stop reading this file.
            break;
          }
          final sealed = Uint8List.sublistView(bytes, offset, offset + len);
          offset += len;
          final nonce = Uint8List.sublistView(sealed, 0, AtRestAead.nonceBytes);
          final ct = Uint8List.sublistView(sealed, AtRestAead.nonceBytes);
          final plain = _aead.decrypt(
            key: dayKey,
            nonce: nonce,
            ciphertext: ct,
            additionalData: _buildAd(date),
          );
          records.add(DiagCodec.decode(plain));
        }
      } finally {
        dayKey.dispose();
      }
    }
    return records;
  }

  // ---- internals -----------------------------------------------------

  /// Appends one encrypted record. Filesystem failures drop the record
  /// (review S2): logging must never break a product path — least of all
  /// the seal path, where a throw would leave keys in memory.
  void _append(DiagRecord record) {
    final key = _diagKey;
    final dir = _dir;
    if (key == null || dir == null) {
      return;
    }
    try {
      final now = DateTime.fromMillisecondsSinceEpoch(
        record.timestampMs,
        isUtc: true,
      );
      final date = _formatDay(now);
      final file = File('${dir.path}/$date.nlog');
      if (!file.existsSync()) {
        // Day rollover (or first record of the day): prune the ring.
        prune();
      }
      final dayKey = _deriveDayKey(key, date);
      try {
        final nonce = _aead.newNonce();
        final ct = _aead.encrypt(
          key: dayKey,
          nonce: nonce,
          plaintext: DiagCodec.encode(record),
          additionalData: _buildAd(date),
        );
        final framed = BytesBuilder(copy: false);
        final len = ByteData(4)..setUint32(0, nonce.length + ct.length);
        framed
          ..add(len.buffer.asUint8List())
          ..add(nonce)
          ..add(ct);
        file.writeAsBytesSync(framed.takeBytes(), mode: FileMode.append);
      } finally {
        dayKey.dispose();
      }
    } on FileSystemException {
      // Record dropped.
    }
  }

  /// `k_day = HKDF(k_diag, "nimna/app/diag/day/v1" ‖ ascii(YYYYMMDD))`.
  SecureKey _deriveDayKey(SecureKey diagKey, String date) {
    final info = BytesBuilder(copy: false)
      ..add(_dayLabel)
      ..add(ascii.encode(date));
    return diagKey.runUnlockedSync((keyBytes) {
      final okm = hkdfSha256(
        ikm: keyBytes,
        info: info.takeBytes(),
        length: AtRestAead.keyBytes,
      );
      final dayKey = SecureKey.fromList(_aead.sodium, okm);
      okm.fillRange(0, okm.length, 0);
      return dayKey;
    });
  }

  /// `ad = "nimna/app/ad/v1" ‖ 0x05 ‖ schema_ver ‖ date-bytes-padded(16)`
  /// — ascii `YYYYMMDD` right-padded with zero bytes to record-id width.
  Uint8List _buildAd(String date) {
    final padded = Uint8List(RecordCipher.recordIdBytes)
      ..setAll(0, ascii.encode(date));
    return RecordCipher.buildAd(storeId: StoreId.diag, recordId: padded);
  }

  static String _formatDay(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}';

  static int _utcDayNumber(DateTime utc) =>
      DateTime.utc(utc.year, utc.month, utc.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  static int? _parseDayFileName(String name) {
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})\.nlog$').firstMatch(name);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    return _utcDayNumber(DateTime.utc(year, month, day));
  }
}
