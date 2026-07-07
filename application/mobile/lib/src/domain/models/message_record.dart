import 'dart:convert';
import 'dart:typed_data';

/// Wire ids are explicit and append-only (they live inside stored
/// ciphertext and must stay stable across app versions).
enum MessageDirection {
  sent(0),
  received(1);

  const MessageDirection(this.id);

  final int id;

  static final Map<int, MessageDirection> byId = {
    for (final d in values) d.id: d,
  };
}

enum MessageType {
  text(0),
  media(1);

  const MessageType(this.id);

  final int id;

  static final Map<int, MessageType> byId = {for (final t in values) t.id: t};
}

enum DeliveryState {
  waiting(0),
  sent(1),
  delivered(2);

  const DeliveryState(this.id);

  final int id;

  static final Map<int, DeliveryState> byId = {for (final s in values) s.id: s};
}

/// The plaintext content of one message record — lives ONLY inside the
/// message row's ciphertext (app-architecture.md §4): direction,
/// inner-envelope fields (msg_id, timestamp, type, body/text), delivery
/// state, expiry, read_at. Timestamps stay inside ciphertext; ordering is
/// the plaintext `seq` counter.
///
/// S10 interior additions (version bump 1 → 2, additive; pre-launch
/// destructive-reset means no migration code): `replyTo` — the 16-byte
/// protocol `msg_id` this message replies to (spec §5.8; ENCRYPTED interior
/// only, never a plaintext graph column — app-architecture §4 adjudication),
/// and `ownReaction`/`peerReaction` — this line's two reaction slots folded
/// into the REFERENT's own record (spec §5.8: a reaction is an adjunct of
/// its referent, so folding it here makes inherit-expiry / die-with-referent
/// automatic — no reaction table, no reaction rows). Each slot is the emoji
/// string or null.
class MessageRecord {
  const MessageRecord({
    required this.id,
    required this.direction,
    required this.timestampMs,
    required this.type,
    this.msgId,
    this.text,
    this.mediaId,
    this.deliveryState = DeliveryState.waiting,
    this.expirySeconds,
    this.readAtMs,
    this.replyTo,
    this.ownReaction,
    this.peerReaction,
  });

  /// Random local surrogate id (16 bytes).
  final Uint8List id;

  final MessageDirection direction;

  /// Protocol inner-envelope message id (S9 fills this for real traffic).
  final Uint8List? msgId;

  final int timestampMs;
  final MessageType type;
  final String? text;

  /// media_ix record id for media messages.
  final Uint8List? mediaId;

  final DeliveryState deliveryState;
  final int? expirySeconds;
  final int? readAtMs;

  /// The 16-byte protocol `msg_id` this message replies to (spec §5.8), or
  /// null. The wire carries only this id; the quoted preview resolves from
  /// the LOCAL copy of the referenced message (§5.8), never a cached excerpt.
  final Uint8List? replyTo;

  /// This device's own reaction on THIS message (spec §5.8), the emoji
  /// string, or null for none. At most one per sender per message.
  final String? ownReaction;

  /// The peer's reaction on THIS message (spec §5.8), the emoji string, or
  /// null for none.
  final String? peerReaction;

  /// Field-scoped copy. Nullable slots use the `T? Function()?` sentinel so a
  /// caller can explicitly clear them (pass `() => null`) versus leave them
  /// untouched (omit the argument) — `remove` clears a reaction to null.
  MessageRecord copyWith({
    DeliveryState? deliveryState,
    int? readAtMs,
    String? Function()? ownReaction,
    String? Function()? peerReaction,
  }) => MessageRecord(
    id: id,
    direction: direction,
    msgId: msgId,
    timestampMs: timestampMs,
    type: type,
    text: text,
    mediaId: mediaId,
    deliveryState: deliveryState ?? this.deliveryState,
    expirySeconds: expirySeconds,
    readAtMs: readAtMs ?? this.readAtMs,
    replyTo: replyTo,
    ownReaction: ownReaction != null ? ownReaction() : this.ownReaction,
    peerReaction: peerReaction != null ? peerReaction() : this.peerReaction,
  );

  Uint8List toBytes() => utf8.encode(
    json.encode({
      'v': 2,
      'dir': direction.id,
      if (msgId != null) 'msgId': base64.encode(msgId!),
      'tsMs': timestampMs,
      'type': type.id,
      if (text != null) 'text': text,
      if (mediaId != null) 'mediaId': base64.encode(mediaId!),
      'state': deliveryState.id,
      if (expirySeconds != null) 'expiryS': expirySeconds,
      if (readAtMs != null) 'readAtMs': readAtMs,
      if (replyTo != null) 'replyTo': base64.encode(replyTo!),
      if (ownReaction != null) 'ownRxn': ownReaction,
      if (peerReaction != null) 'peerRxn': peerReaction,
    }),
  );

  static MessageRecord fromBytes(Uint8List id, Uint8List bytes) {
    final map = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    return MessageRecord(
      id: id,
      direction: MessageDirection.byId[map['dir'] as int]!,
      msgId: map.containsKey('msgId')
          ? base64.decode(map['msgId'] as String)
          : null,
      timestampMs: map['tsMs'] as int,
      type: MessageType.byId[map['type'] as int]!,
      text: map['text'] as String?,
      mediaId: map.containsKey('mediaId')
          ? base64.decode(map['mediaId'] as String)
          : null,
      deliveryState: DeliveryState.byId[map['state'] as int]!,
      expirySeconds: map['expiryS'] as int?,
      readAtMs: map['readAtMs'] as int?,
      replyTo: map.containsKey('replyTo')
          ? base64.decode(map['replyTo'] as String)
          : null,
      ownReaction: map['ownRxn'] as String?,
      peerReaction: map['peerRxn'] as String?,
    );
  }
}
