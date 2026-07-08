/// The screenshot system line as the thread renders it (spec §5.2, voice
/// string 12). An EVENT, not speech — a bare centered caption in the thread
/// flow (components.md system line). Deliberately TRANSIENT and session-scoped:
/// it is never a [MessageRecord], never persisted, never sealed to disk. A
/// screenshot notice is honor-system like expiry; it matters in the live
/// moment, and a fresh thread open starts without it.
///
/// Locale-independent: it carries only a side flag, a timestamp, and an anchor
/// id — every user-facing STRING is resolved in the widget layer via l10n. A
/// leaf type: it imports only `dart:typed_data`, so the Flutter-free connection
/// lane can hold it (the import-direction fence,
/// test/session/import_direction_test.dart).
library;

import 'dart:typed_data';

/// One screenshot notice in the thread timeline.
class ScreenshotNotice {
  const ScreenshotNotice({
    required this.own,
    required this.timestampMs,
    this.anchorRecordId,
  });

  /// True when THIS device took the screenshot — renders own-side "You took a
  /// screenshot. They've been told." (string 12); false when the peer did —
  /// "They took a screenshot." (string 12).
  final bool own;

  /// When the notice occurred (Unix ms) — for the caller's ordering/debugging;
  /// the timeline position is anchored by [anchorRecordId], never re-sorted.
  final int timestampMs;

  /// The local surrogate id (16 bytes) of the message this notice sits just
  /// AFTER in the timeline — the last record present when the notice occurred,
  /// or null when the thread had no messages yet (the notice leads the thread).
  /// The widget layer interleaves by this anchor and NEVER re-sorts messages
  /// (message order is the connection lane's insertion/seq order, not time).
  final Uint8List? anchorRecordId;
}
