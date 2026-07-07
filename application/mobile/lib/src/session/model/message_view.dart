/// Immutable per-message view model for the chat thread (S10). Built by the
/// connection layer ([SessionController]) from a decrypted [MessageRecord]
/// plus the LOCAL resolution of any `reply_to` referent; consumed by the chat
/// widgets. Deliberately a leaf seam type: no keys, no transport, no store,
/// no Flutter — so `chat/` can hold it without touching protocol state (the
/// import-direction fence, test/session/import_direction_test.dart).
///
/// Locale-independent: it carries only ids, bytes, and the user's own message
/// text; every user-facing STRING (delivery labels, tombstone, durations) is
/// resolved in the widget layer via l10n, never here.
library;

import 'dart:typed_data';

import '../../domain/models/message_record.dart';

/// What kind of message a `reply_to` referent is — drives the quoted preview
/// rendering (text excerpt vs media thumbnail + "Photo"/"Document",
/// components.md quoted-reply-preview).
enum ReplyReferentKind {
  /// A TEXT referent — the preview shows a 2-line excerpt.
  text,

  /// A MEDIA_CHUNK image manifest — thumbnail + "Photo" (S11 renders the
  /// thumbnail; S10 resolves the kind).
  photo,

  /// A MEDIA_CHUNK document manifest — thumbnail + "Document" (S11).
  document,
}

/// The resolved quoted-reply preview for a reply message (spec §5.8;
/// components.md quoted-reply-preview). Resolution is always from the LOCAL
/// copy — the wire carries only the 16-byte `msg_id`.
class ReplyPreview {
  const ReplyPreview.referent({
    required this.referentRecordId,
    required this.kind,
    this.excerpt,
  }) : tombstone = false;

  /// The neutral tombstone: the referent is unknown, deleted, or expired.
  /// Identical for all three causes — it never says why (spec §5.8;
  /// components.md). Carries no referent id: tapping it does nothing.
  const ReplyPreview.tombstone()
    : tombstone = true,
      referentRecordId = null,
      kind = null,
      excerpt = null;

  /// True when the referent is gone — render "Message no longer available."
  final bool tombstone;

  /// The referent's local record id (for tap-to-scroll); null when a
  /// tombstone.
  final Uint8List? referentRecordId;

  /// The referent's kind; null when a tombstone.
  final ReplyReferentKind? kind;

  /// The referent's text excerpt (TEXT referents only), else null.
  final String? excerpt;
}

/// One message as the thread renders it. Immutable; rebuilt (never mutated)
/// whenever its record or reaction slots change.
class MessageView {
  const MessageView({
    required this.recordId,
    required this.msgId,
    required this.outbound,
    required this.type,
    required this.timestampMs,
    required this.deliveryState,
    this.text,
    this.expirySeconds,
    this.purgeAtMs,
    this.reply,
    this.ownReaction,
    this.peerReaction,
  });

  /// Local surrogate record id (16 bytes) — the thread's stable key and the
  /// tap-to-scroll target.
  final Uint8List recordId;

  /// Protocol inner-envelope `msg_id` (16 bytes), or null for a record that
  /// never carried one.
  final Uint8List? msgId;

  /// True when this device sent the message (right-aligned, delivery chrome);
  /// false when received (left-aligned, no delivery chrome).
  final bool outbound;

  final MessageType type;
  final int timestampMs;
  final DeliveryState deliveryState;

  /// The UTF-8 text (TEXT messages), else null.
  final String? text;

  /// Sender-dictated disappearing instruction (seconds after read), or null.
  final int? expirySeconds;

  /// Absolute removal deadline (epoch ms) once the message has been read —
  /// `read_at + expiry_s*1000`; null until read or for non-expiring messages.
  final int? purgeAtMs;

  /// The resolved quoted-reply preview, or null when this is not a reply.
  final ReplyPreview? reply;

  /// This device's own reaction emoji on this message, or null.
  final String? ownReaction;

  /// The peer's reaction emoji on this message, or null.
  final String? peerReaction;

  /// True when either side has reacted (adds the 14 px bottom clearance,
  /// components.md reaction-chip).
  bool get hasReactions => ownReaction != null || peerReaction != null;

  /// A reactable/replyable referent is a TEXT or a media manifest (spec §5.8).
  /// S10 only ever holds TEXT here; media arrives in S11.
  bool get isReferentEligible => type == MessageType.text;
}
