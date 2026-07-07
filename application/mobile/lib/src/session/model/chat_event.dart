/// The read-only event vocabulary the connection layer emits to the chat UI
/// (S10). A sealed hierarchy so `switch` is exhaustive; every variant is
/// immutable and Flutter-free (the import-direction fence,
/// test/session/import_direction_test.dart). The UI reacts to these and
/// re-reads [SessionController.messages] / [SessionController.lineState] —
/// the events are notifications, never the source of truth.
library;

import 'dart:typed_data';

import '../../domain/models/message_record.dart';
import 'message_view.dart';

/// Which end owns a reaction (spec §5.8: one per sender per message; a line
/// has exactly two people, so at most two chips).
enum ReactionSide {
  /// This device's own reaction slot.
  own,

  /// The peer's reaction slot.
  peer,
}

/// Why a live session ended — the honest distinction of spec §3.3: an
/// authenticated HANGUP the relay cannot forge is [ended]; a bridge that died
/// without one (the only kind the relay can produce) is [connectionLost].
enum SessionEndReason {
  /// A HANGUP envelope was exchanged (either side) — "ended".
  ended,

  /// The bridge died with no HANGUP — "connection lost".
  connectionLost,
}

/// The session's line state (components.md session-status-indicator). S10
/// seeds the minimal set; S12 extends the rich presence choreography
/// (knocking/waiting/lapse). The connection lane owns this enum.
enum SessionLineState {
  /// No live session (Not on the line).
  offline,

  /// Establishing — knock/accept/handshake in flight. S12 refines the UX
  /// (rate-limit-aware "knocked — waiting").
  connecting,

  /// Transport is up (On the line).
  live,

  /// You ended with an authenticated HANGUP (You hung up.).
  endedByYou,

  /// The peer ended with an authenticated HANGUP (They hung up.).
  endedByPeer,

  /// The bridge died without a HANGUP (The line dropped…). S12 owns the
  /// reconnect/recovery behavior; S10 only surfaces the state.
  connectionLost,
}

/// Base of the event hierarchy.
sealed class ChatEvent {
  const ChatEvent();
}

/// A new message (sent or received) was appended to the thread.
final class MessageArrived extends ChatEvent {
  const MessageArrived(this.message);

  final MessageView message;
}

/// A message was locally deleted (the actions-card Delete row, spec §6) — the
/// thread drops it (and any reaction adjunct dies with it, spec §5.8).
final class MessageRemoved extends ChatEvent {
  const MessageRemoved(this.recordId);

  final Uint8List recordId;
}

/// A sent message's delivery state advanced (waiting→sent on relay send,
/// sent→delivered on the peer's ACK — spec §3.3).
final class DeliveryChanged extends ChatEvent {
  const DeliveryChanged({required this.recordId, required this.state});

  final Uint8List recordId;
  final DeliveryState state;
}

/// A reaction was set, replaced, or cleared on a referent (spec §5.8).
/// [emoji] is null when the reaction was removed.
final class ReactionArrived extends ChatEvent {
  const ReactionArrived({
    required this.referentRecordId,
    required this.side,
    required this.emoji,
  });

  final Uint8List referentRecordId;
  final ReactionSide side;
  final String? emoji;
}

/// The peer is typing (CONTROL 0x01). Renders as a silent animated three-dot
/// glyph — NO text (USER, 2026-07-07).
final class PeerTyping extends ChatEvent {
  const PeerTyping();
}

/// The line state changed — the UI re-reads [SessionController.lineState].
final class LineStateChanged extends ChatEvent {
  const LineStateChanged(this.state);

  final SessionLineState state;
}

/// The session ended. [reason] carries the honest ended-vs-connection-lost
/// distinction (spec §3.3).
final class SessionEnded extends ChatEvent {
  const SessionEnded(this.reason);

  final SessionEndReason reason;
}
