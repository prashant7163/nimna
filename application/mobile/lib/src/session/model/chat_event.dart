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

  /// S12 (append-only) — the knocker sent its ONE knock and is waiting for a
  /// pick-up (the F5/F6 "knocked — waiting" state, spec §3.2, string 6). The
  /// 60 s countdown + lapse UX lives in the presence lane's knock_controller;
  /// the app NEVER auto-retries a cold knock (§4). MERGE HOTSPOT: chat/
  /// status-line switch adds this case at fold (see SESSION-12 notes).
  waiting,

  /// S12 (append-only) — a LIVE-session drop is being auto-recovered inside
  /// the bounded ~20 s window (string 10 "…Trying to reconnect…",
  /// session_lineDropped). A fresh knock+KK is in flight via the presence
  /// lane's reconnect_coordinator; distinct from the never-retried cold knock
  /// ([waiting]). MERGE HOTSPOT: chat/ status-line switch adds this case at
  /// fold (see SESSION-12 notes).
  reconnecting,
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

/// S12 (append-only) — a knock arrived for this engaged channel and is
/// waiting on an explicit pick-up (F6). The connection lane no longer
/// auto-ACCEPTs (S10 did, to be end-to-end exercisable); the UI shows the
/// in-app banner / knock screen and calls
/// [SessionController.acceptKnock]/[SessionController.ignoreKnock]. Carries no
/// payload — no content exists until the line is bridged (F6.1); the peer
/// label the banner shows is the channel's local label the UI already holds.
final class IncomingKnock extends ChatEvent {
  const IncomingKnock();
}

/// S12 (append-only) — a reaction (spec §5.8) composed while the line was down
/// that must ride the outbox on the next bridge (§3.4). The referent's own
/// slot is already persisted on its [MessageRecord]; this marker records that
/// the reaction still needs SENDING. [emoji] is the own-reaction to put on the
/// wire, or null for a clear (remove op).
///
/// FOLD COORDINATION (S11): S12 carries this marker in session memory and
/// hands it forward across a reconnect (fresh SessionController) via the
/// reconnect_coordinator. A PERSISTED equivalent — a pending flag on the
/// MessageRecord domain model so an offline reaction also survives an app
/// RESTART — is deferred to the fold with S11 (who owns message rendering);
/// S12 does not add a domain-model column (append-only, minimal).
final class PendingReaction {
  const PendingReaction({required this.referentRecordId, required this.emoji});

  /// The local 16-byte surrogate id of the referent message record.
  final Uint8List referentRecordId;

  /// The own-reaction emoji to send, or null for a remove (clear).
  final String? emoji;
}
