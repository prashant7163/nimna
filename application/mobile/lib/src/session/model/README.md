# lib/src/session/model/

The IMMUTABLE seam types shared between the connection lane and the chat lane —
a Flutter-free leaf (imports neither `connection/` nor `chat/`), so neither lane
can grow a shared mutable surface through it (the import-direction fence).

- `chat_event.dart` — the sealed `ChatEvent` vocabulary the connection layer
  emits (`MessageArrived`, `MessageRemoved`, `DeliveryChanged`, `ReactionArrived`,
  `PeerTyping`, `LineStateChanged`, `SessionEnded`) plus the `SessionLineState`,
  `ReactionSide`, and `SessionEndReason{ended, connectionLost}` enums. Events are
  notifications — the UI re-reads the controller's `messages`/`lineState`/
  `peerTyping` for the truth.
- `message_view.dart` — the immutable `MessageView` (text/delivery/expiry/reactions)
  and `ReplyPreview` (a resolved referent excerpt/media kind, or the neutral
  tombstone). Reply resolution is always from the LOCAL copy (spec §5.8).

Locale-independent: these types carry only ids, bytes, and the user's own message
text — every user-facing string is resolved in the widget layer via l10n.
