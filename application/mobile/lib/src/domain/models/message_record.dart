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

  MessageRecord copyWith({DeliveryState? deliveryState, int? readAtMs}) =>
      MessageRecord(
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
      );

  Uint8List toBytes() => utf8.encode(
    json.encode({
      'v': 1,
      'dir': direction.id,
      if (msgId != null) 'msgId': base64.encode(msgId!),
      'tsMs': timestampMs,
      'type': type.id,
      if (text != null) 'text': text,
      if (mediaId != null) 'mediaId': base64.encode(mediaId!),
      'state': deliveryState.id,
      if (expirySeconds != null) 'expiryS': expirySeconds,
      if (readAtMs != null) 'readAtMs': readAtMs,
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
    );
  }
}
