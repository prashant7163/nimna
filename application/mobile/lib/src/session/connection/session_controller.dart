/// The live 1:1 session — establishment, the §3.3.1 KK handshake, the
/// transport send/receive loop, the delivery FSM, and the §5.8 reaction/reply
/// state rules (S10, connection lane). Owns the [SessionTransport] and its
/// per-direction counters; exposes a READ-ONLY [events] stream plus typed send
/// methods. Imports NO Flutter and NO chat widget — the import-direction fence
/// (test/session/import_direction_test.dart) keeps this lane free of any
/// shared mutable UI surface, which is what makes G4 (S11 ∥ S12) safe.
///
/// SCOPE (S10 = the LIVE text path). Marked `// TODO(S12)` seams are the
/// presence lane's — the rate-limit-aware "knocked — waiting" state, the
/// lapsed-knock "No answer.", reconnect, 30 s background grace, the
/// offline-compose outbox auto-flush, device-token refresh, per-channel push.
/// NONE of those are built here; the connection folder is only seeded so S12
/// adds files without collision. Auto-retry of a knock is NEVER done.
///
/// Locale-independent: protocol/storage code renders identically in every
/// locale — the only strings this file touches are the user's own message
/// text and emoji bytes, never UI copy.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../crypto/at_rest_aead.dart';
import '../../diag/diag.dart';
import '../../diag/diag_events.dart';
import '../../domain/message_repository.dart';
import '../../domain/models/message_record.dart';
import '../../noise/dh.dart';
import '../../noise/noise_transport.dart';
import '../../noise/session_kk.dart';
import '../../protocol/inner_envelope.dart';
import '../../protocol/outer_frame.dart';
import '../../protocol/reaction_body.dart';
import '../../transport/relay_socket.dart';
import '../model/chat_event.dart';
import '../model/message_view.dart';

/// Whether this device initiates the session (the knocker = Noise initiator)
/// or answers it (the accepter = Noise responder), spec §3.3.1.
enum SessionRole {
  /// The knocker: registers the CRID, sends KNOCK, and runs the KK initiator
  /// (writes S1, reads S2).
  knocker,

  /// The accepter: registers the CRID, ACCEPTs an incoming knock, and runs
  /// the KK responder (reads S1, writes S2).
  accepter,
}

/// How long a received typing indicator keeps its silent three-dot glyph
/// before it fades (no explicit "stopped typing" frame exists — CONTROL 0x01
/// is a heartbeat, spec §5.5).
const Duration _typingLinger = Duration(seconds: 5);

/// Drives one live session for one channel.
class SessionController {
  SessionController({
    required this._sodium,
    required this._aead,
    required this._connector,
    required this._messages,
    required Uint8List channelId,
    required this._ownStatic,
    required Uint8List peerStaticPublic,
    required Uint8List crid,
    required this.role,
    required this._diag,
    DateTime Function()? clock,
    // Typing is sent by default (USER, 2026-07-07); the per-channel F7 toggle
    // is a later session — [typingEnabled] is the single internal seam for it.
    this.typingEnabled = true,
  }) : _channelId = Uint8List.fromList(channelId),
       _peerStaticPublic = Uint8List.fromList(peerStaticPublic),
       _crid = Uint8List.fromList(crid),
       _clock = clock ?? DateTime.now;

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final RelayConnector _connector;
  final MessageRepository _messages;
  final Uint8List _channelId;

  /// Caller-owned static keypair (from the channel record). NEVER disposed
  /// here — the KK drivers never dispose their `_static` either (§3.3.1).
  final NoiseKeyPair _ownStatic;
  final Uint8List _peerStaticPublic;
  final Uint8List _crid;

  /// Whether this device knocks (initiator) or accepts (responder), spec
  /// §3.3.1.
  final SessionRole role;
  final Diag _diag;
  final DateTime Function() _clock;

  /// The single seam for the future F7 per-channel typing toggle (default on,
  /// USER 2026-07-07). Never surfaced as UI in S10.
  final bool typingEnabled;

  final StreamController<ChatEvent> _events =
      StreamController<ChatEvent>.broadcast();

  /// The thread, in `seq` order. In-memory mirror of the encrypted store; the
  /// only user content this lane holds (decrypted for display anyway).
  final List<MessageRecord> _records = [];
  final Map<String, int> _byMsgId = {};
  final Map<String, int> _byRecordId = {};

  RelayConnection? _conn;
  StreamSubscription<OuterFrame>? _sub;

  SessionInitiatorHandshake? _initiator;
  SessionResponderHandshake? _responder;
  SessionTransport? _transport;
  bool _awaitingHandshakeFrame = false;

  SessionLineState _lineState = SessionLineState.offline;
  bool _peerTyping = false;
  Timer? _typingTimer;
  bool _closed = false;

  // ---- read-only surface ---------------------------------------------

  /// The event stream (broadcast). Notifications only — re-read [messages] /
  /// [lineState] / [peerTyping] for the truth.
  Stream<ChatEvent> get events => _events.stream;

  /// The current thread as immutable view models, with reply referents
  /// resolved from the LOCAL copy and reaction slots applied (spec §5.8).
  List<MessageView> get messages => [for (final r in _records) _view(r)];

  SessionLineState get lineState => _lineState;

  bool get peerTyping => _peerTyping;

  bool get isLive => _transport != null && _lineState == SessionLineState.live;

  // ---- establishment --------------------------------------------------

  /// Loads this channel's history, connects, registers the CRID, and — for a
  /// [SessionRole.knocker] — sends the one KNOCK. Never knocks twice on its
  /// own (spec §4). Rich presence (knocked-waiting, lapse, reconnect,
  /// background grace, push) is S12.
  Future<void> start() async {
    if (_closed) {
      return;
    }
    await _loadHistory();
    final RelayConnection conn;
    try {
      conn = await _connector.connect();
    } on RelayUnreachableError {
      _diag.log(DiagEvent.storageError, code: DiagCode.relayUnreachable);
      // Offline: the composer still works (spec §3.4) — writes wait locally.
      // TODO(S12): the reconnect schedule + offline-compose outbox lifecycle.
      _setLineState(SessionLineState.offline);
      return;
    }
    _conn = conn;
    _sub = conn.frames.listen(_onFrame, onDone: _onConnectionClosed);
    conn.send(OuterFrame(type: FrameType.registerCrid, routingId: _crid));
    if (role == SessionRole.knocker) {
      // One knock. Empty payload = push-off (§3.2.1 default; S9/S15 precedent).
      // TODO(S15): carry the peer device-token here when per-channel push is on.
      conn.send(OuterFrame(type: FrameType.knock, routingId: _crid));
    }
    _setLineState(SessionLineState.connecting);
  }

  void _onFrame(OuterFrame frame) {
    if (_closed) {
      return;
    }
    switch (frame.type) {
      case FrameType.knockFwd:
        // The accepter answers an incoming knock. TODO(S12): gate ACCEPT
        // behind the pick-up UX (in-app banner / knock screen, F6) — S10
        // answers immediately so the live path is exercisable end to end.
        if (role == SessionRole.accepter &&
            _lineState == SessionLineState.connecting) {
          _conn?.send(OuterFrame(type: FrameType.accept, routingId: _crid));
        }
      case FrameType.sessionBridged:
        _onBridged();
      case FrameType.sessionData:
        _onSessionData(frame.payload);
      case FrameType.teardown:
        // The relay tore the bridge down. Without a HANGUP this is a
        // connection loss, never "ended" (spec §3.3).
        _connectionLost();
      default:
        break; // Nothing else is meaningful on this plane: drop.
    }
  }

  void _onBridged() {
    if (_transport != null || _awaitingHandshakeFrame) {
      return;
    }
    _diag.log(DiagEvent.pairingBridged);
    try {
      if (role == SessionRole.knocker) {
        final hs = SessionInitiatorHandshake(
          sodium: _sodium,
          aead: _aead,
          staticKeyPair: _ownStatic,
          peerStaticPublic: _peerStaticPublic,
        );
        _initiator = hs;
        _awaitingHandshakeFrame = true;
        _sendSessionData(hs.writeS1()); // S1 is the first SESSION_DATA frame.
      } else {
        _responder = SessionResponderHandshake(
          sodium: _sodium,
          aead: _aead,
          staticKeyPair: _ownStatic,
          peerStaticPublic: _peerStaticPublic,
        );
        _awaitingHandshakeFrame = true; // Await S1.
      }
    } on SessionHandshakeError {
      _protocolError();
    }
  }

  void _onSessionData(Uint8List payload) {
    if (_awaitingHandshakeFrame) {
      _onHandshakeFrame(payload);
      return;
    }
    final transport = _transport;
    if (transport == null) {
      return; // No transport yet and not awaiting a handshake frame: drop.
    }
    final Uint8List plain;
    try {
      plain = transport.receive.open(
        outerHeader: _sessionHeader(),
        ciphertext: payload,
      );
    } on TransportError {
      // AEAD failure / counter violation — the receive key is already
      // destroyed (§3.3.1). Kill the whole session.
      _protocolError();
      return;
    }
    final InnerEnvelope env;
    try {
      env = InnerEnvelope.decode(plain);
    } on InnerEnvelopeError {
      _protocolError();
      return;
    }
    _dispatchInbound(env);
  }

  void _onHandshakeFrame(Uint8List payload) {
    try {
      if (role == SessionRole.knocker) {
        _transport = _initiator!.completeWithS2(payload); // S2.
        _initiator = null;
      } else {
        final hs = _responder!;
        hs.readS1(payload); // S1.
        _sendSessionData(hs.writeS2()); // S2 is our reply SESSION_DATA frame.
        _transport = hs.deriveTransport();
        _responder = null;
      }
    } on SessionHandshakeError {
      _protocolError();
      return;
    }
    _awaitingHandshakeFrame = false;
    _setLineState(SessionLineState.live);
  }

  // ---- outbound -------------------------------------------------------

  /// Sends a TEXT message (spec §5.5). The 5000-char soft cap is compose-time
  /// (the composer), never enforced here or in the codec. [expirySeconds] is
  /// the sender-dictated disappearing instruction; [replyTo] the 16-byte
  /// referent `msg_id` (§5.8). Persisted immediately as waiting; sealed and
  /// sent (waiting → sent) only when the line is live — offline it waits
  /// locally (spec §3.4). TODO(S12): the outbox auto-flush on the next bridge.
  Future<void> sendText(
    String text, {
    int? expirySeconds,
    Uint8List? replyTo,
  }) async {
    if (_closed) {
      return;
    }
    final msgId = _aead.randomBytes(msgIdBytes);
    final now = _nowMs();
    final expiring = expirySeconds != null;
    final record = MessageRecord(
      id: _aead.randomBytes(16),
      direction: MessageDirection.sent,
      msgId: msgId,
      timestampMs: now,
      type: MessageType.text,
      text: text,
      deliveryState: DeliveryState.waiting,
      expirySeconds: expirySeconds,
      // Own copy disappears too (string 7 "yours will too"): the sender's
      // "read" is compose time, so its purge deadline starts now.
      readAtMs: expiring ? now : null,
      replyTo: replyTo,
    );
    await _messages.append(
      _channelId,
      record,
      purgeAt: expiring ? now + expirySeconds * 1000 : null,
    );
    _insert(record);
    _emit(MessageArrived(_view(record)));

    if (!isLive) {
      return; // Waits in the outbox (spec §3.4); no auto-retry knock (§4).
    }
    final env = InnerEnvelope(
      type: InnerType.text,
      msgId: msgId,
      timestampMs: now,
      expirySeconds: expirySeconds,
      replyTo: replyTo,
      body: Uint8List.fromList(utf8.encode(text)),
    );
    if (!_seal(env)) {
      return; // Protocol error already handled.
    }
    await _advanceDelivery(record.id, DeliveryState.sent);
  }

  /// A reply is an ordinary TEXT that names a referent `msg_id` (spec §5.8);
  /// `reply_to` and `expiry_s` compose freely.
  Future<void> sendReply(
    String text,
    Uint8List replyToMsgId, {
    int? expirySeconds,
  }) => sendText(text, expirySeconds: expirySeconds, replyTo: replyToMsgId);

  /// Sets or replaces this device's reaction on the referent named by
  /// [referentMsgId] (spec §5.8 add). One per sender per message; a REACTION
  /// is never ACKed. No-op if the referent is unknown locally.
  Future<void> sendReaction(Uint8List referentMsgId, String emoji) =>
      _sendReaction(referentMsgId, ReactionOp.add, emoji);

  /// Clears this device's reaction on [referentMsgId] unconditionally (spec
  /// §5.8 remove). The carried emoji is not compared on the wire; we send the
  /// current one (or a filler) to keep the body shape uniform.
  Future<void> removeReaction(Uint8List referentMsgId) async {
    final idx = _byMsgId[_hex(referentMsgId)];
    final carried = idx == null ? null : _records[idx].ownReaction;
    await _sendReaction(referentMsgId, ReactionOp.remove, carried ?? '👍');
  }

  /// Local per-message delete (spec §6; the actions-card Delete row). Removes
  /// the record from the store and the thread; a reaction adjunct dies with
  /// its referent (spec §5.8). Purely local — no wire signal.
  Future<void> deleteMessage(Uint8List recordId) async {
    final idx = _byRecordId[_hex(recordId)];
    if (idx == null) {
      return;
    }
    final record = _records.removeAt(idx);
    await _messages.delete(record.id);
    _reindex();
    _emit(MessageRemoved(record.id));
  }

  Future<void> _sendReaction(
    Uint8List referentMsgId,
    ReactionOp op,
    String emoji,
  ) async {
    if (_closed) {
      return;
    }
    final idx = _byMsgId[_hex(referentMsgId)];
    if (idx == null) {
      return; // Nothing to react to locally.
    }
    final referent = _records[idx];
    final emojiBytes = Uint8List.fromList(utf8.encode(emoji));
    final ReactionBody body;
    try {
      body = ReactionBody(refMsgId: referentMsgId, op: op, emoji: emojiBytes);
    } on InnerEnvelopeError {
      return; // A malformed local emoji is never put on the wire.
    }
    final newEmoji = op == ReactionOp.add ? emoji : null;
    final updated = referent.copyWith(ownReaction: () => newEmoji);
    await _messages.update(_channelId, updated);
    _records[idx] = updated;
    _emit(
      ReactionArrived(
        referentRecordId: referent.id,
        side: ReactionSide.own,
        emoji: newEmoji,
      ),
    );
    if (!isLive) {
      return; // Rides the outbox silently offline (spec §3.4).
    }
    _seal(
      InnerEnvelope(
        type: InnerType.reaction,
        msgId: _aead.randomBytes(msgIdBytes),
        timestampMs: _nowMs(),
        body: body.encode(),
      ),
    );
  }

  /// Sends a typing heartbeat (CONTROL 0x01, empty body) — ON BY DEFAULT
  /// (USER, 2026-07-07). Silently gated by the single [typingEnabled] seam
  /// (the future F7 per-channel toggle) and by liveness.
  void setTyping() {
    if (_closed || !typingEnabled || !isLive) {
      return;
    }
    _seal(
      InnerEnvelope(
        type: InnerType.control,
        msgId: _aead.randomBytes(msgIdBytes),
        timestampMs: _nowMs(),
        body: ControlBody(
          rawType: ControlType.typing.wire,
          payload: Uint8List(0),
        ).encode(),
      ),
    );
  }

  /// Ends the session (explicit hang up / leave chat): sends the authenticated
  /// HANGUP envelope, then the relay TEARDOWN, destroys all session keys, and
  /// settles to "You hung up." (spec §3.3 — the relay cannot forge this, so
  /// the peer honestly renders "ended", not "connection lost").
  Future<void> hangup() async {
    if (_closed) {
      return;
    }
    if (isLive) {
      _seal(
        InnerEnvelope(
          type: InnerType.hangup,
          msgId: _aead.randomBytes(msgIdBytes),
          timestampMs: _nowMs(),
          body: Uint8List(0),
        ),
      );
    }
    _teardownRelay();
    _destroyKeys();
    _setLineState(SessionLineState.endedByYou);
    _emit(const SessionEnded(SessionEndReason.ended));
    await _closeConnection();
  }

  // ---- inbound dispatch ----------------------------------------------

  void _dispatchInbound(InnerEnvelope env) {
    switch (env.type) {
      case InnerType.text:
        _onInboundText(env);
      case InnerType.ack:
        _onInboundAck(env);
      case InnerType.reaction:
        _onInboundReaction(env);
      case InnerType.control:
        _onInboundControl(env);
      case InnerType.hangup:
        _onInboundHangup();
      case InnerType.mediaChunk:
        // TODO(S11): reassemble media; a manifest becomes a reactable/
        // replyable referent. Untestable until media exists — not a defect.
        break;
    }
  }

  void _onInboundText(InnerEnvelope env) {
    // The codec deliberately does NOT validate TEXT bodies as UTF-8 (it
    // mirrors the Go stack), so a transport-valid, envelope-valid TEXT can
    // still carry a non-UTF-8 body. Per §3.3.1 that is a malformed frame:
    // fail CLOSED (destroy keys + TEARDOWN), never tolerate it — no
    // allowMalformed, which would silently accept garbage.
    final String text;
    try {
      text = utf8.decode(env.body);
    } on FormatException {
      _protocolError();
      return;
    }
    final now = _nowMs();
    final expiring = env.expirySeconds != null;
    final record = MessageRecord(
      id: _aead.randomBytes(16),
      direction: MessageDirection.received,
      msgId: env.msgId,
      timestampMs: env.timestampMs,
      type: MessageType.text,
      text: text,
      deliveryState: DeliveryState.delivered,
      expirySeconds: env.expirySeconds,
      // Received disappearing message: read = now (we display on receipt);
      // purge_at = read_at + expiry_s*1000, mirrored to the plaintext column.
      readAtMs: expiring ? now : null,
      replyTo: env.replyTo,
    );
    unawaited(
      _messages.append(
        _channelId,
        record,
        purgeAt: expiring ? now + env.expirySeconds! * 1000 : null,
      ),
    );
    _insert(record);
    _emit(MessageArrived(_view(record)));
    // ACK on successful decrypt + display of a peer TEXT (spec §3.3).
    _seal(
      InnerEnvelope(
        type: InnerType.ack,
        msgId: _aead.randomBytes(msgIdBytes),
        timestampMs: now,
        body: AckBody(ackedMsgId: env.msgId).encode(),
      ),
    );
  }

  void _onInboundAck(InnerEnvelope env) {
    final AckBody ack;
    try {
      ack = AckBody.decode(env.body);
    } on InnerEnvelopeError {
      _protocolError();
      return;
    }
    final idx = _byMsgId[_hex(ack.ackedMsgId)];
    if (idx == null) {
      return; // ACK for a message we don't hold: ignore.
    }
    unawaited(_advanceDelivery(_records[idx].id, DeliveryState.delivered));
  }

  void _onInboundReaction(InnerEnvelope env) {
    final ReactionBody rxn;
    try {
      rxn = ReactionBody.decode(env.body);
    } on InnerEnvelopeError {
      // A structural (byte-level) malformation is a protocol error, exactly
      // as any malformed frame (spec §5.8, §3.3.1).
      _protocolError();
      return;
    }
    final idx = _byMsgId[_hex(rxn.refMsgId)];
    if (idx == null) {
      return; // Unknown/deleted referent → SILENT DROP (spec §5.8).
    }
    final referent = _records[idx];
    if (_isExpired(referent)) {
      return; // Expired referent → SILENT DROP (spec §5.8).
    }
    // The peer's emoji is well-formed 1–64 UTF-8 bytes (codec-guaranteed);
    // sanitization for a11y announcements happens in the widget layer.
    final newEmoji = rxn.op == ReactionOp.add ? utf8.decode(rxn.emoji) : null;
    final updated = referent.copyWith(peerReaction: () => newEmoji);
    unawaited(_messages.update(_channelId, updated));
    _records[idx] = updated;
    _emit(
      ReactionArrived(
        referentRecordId: referent.id,
        side: ReactionSide.peer,
        emoji: newEmoji,
      ),
    );
    // A REACTION is never ACKed (spec §5.8).
  }

  void _onInboundControl(InnerEnvelope env) {
    final ControlBody control;
    try {
      control = ControlBody.decode(env.body);
    } on InnerEnvelopeError {
      _protocolError();
      return;
    }
    switch (control.controlType) {
      case ControlType.typing:
        _onPeerTyping();
      case ControlType.readReceipt:
        // TODO(F7): read receipts default OFF; do not render "Seen" here.
        break;
      case ControlType.screenshot:
        // TODO(S14): screenshot notice system line.
        break;
      case ControlType.tokenRefresh:
        // TODO(S15): device-token refresh (per-channel push).
        break;
      case null:
        break; // Unknown control type: ignored (forward compat, spec §5.5).
    }
  }

  void _onInboundHangup() {
    _destroyKeys();
    _setLineState(SessionLineState.endedByPeer);
    _emit(const SessionEnded(SessionEndReason.ended));
    unawaited(_closeConnection());
  }

  void _onPeerTyping() {
    _peerTyping = true;
    _emit(const PeerTyping());
    _typingTimer?.cancel();
    _typingTimer = Timer(_typingLinger, () {
      _peerTyping = false;
      if (!_closed) {
        _emit(const LineStateChanged(SessionLineState.live));
      }
    });
  }

  // ---- kill paths -----------------------------------------------------

  /// The §3.3.1 protocol-error kill path: destroy all session keys, send relay
  /// TEARDOWN, and settle to connection-lost (NOT "ended" — the peer never
  /// authenticated an end).
  void _protocolError() {
    // A session-layer kill (transport AEAD/counter, malformed frame/body, or
    // a session KK-handshake failure) — NOT a pairing event. Events only.
    _diag.log(DiagEvent.sessionProtocolError);
    _connectionLost();
  }

  void _connectionLost() {
    if (_lineState == SessionLineState.endedByYou ||
        _lineState == SessionLineState.endedByPeer ||
        _lineState == SessionLineState.connectionLost) {
      return; // Already terminal.
    }
    _teardownRelay();
    _destroyKeys();
    _setLineState(SessionLineState.connectionLost);
    _emit(const SessionEnded(SessionEndReason.connectionLost));
    unawaited(_closeConnection());
  }

  void _onConnectionClosed() {
    _conn = null;
    _sub = null;
    if (_closed) {
      return;
    }
    // A bridge dying without a HANGUP is a connection loss (spec §3.3). If we
    // already ended (HANGUP) this is a no-op.
    if (_lineState == SessionLineState.live ||
        _lineState == SessionLineState.connecting) {
      _connectionLost();
    }
  }

  // ---- helpers --------------------------------------------------------

  /// Seals [env] and sends it as a SESSION_DATA frame. Returns false (after
  /// firing the protocol-error kill path) if the transport rejects the seal.
  bool _seal(InnerEnvelope env) {
    final transport = _transport;
    if (transport == null) {
      return false;
    }
    try {
      final ct = transport.send.seal(
        outerHeader: _sessionHeader(),
        plaintext: env.encode(),
      );
      _conn?.send(
        OuterFrame(type: FrameType.sessionData, routingId: _crid, payload: ct),
      );
      return true;
    } on TransportError {
      _protocolError();
      return false;
    }
  }

  /// Test-only: seals [env] over the LIVE transport exactly as an ordinary
  /// outbound frame would (same counter advance + REKEY), so a test can inject
  /// an envelope the public send API can never produce — e.g. a TEXT whose body
  /// is not valid UTF-8 (the codec deliberately does not validate TEXT bodies).
  /// Returns false if the line is not live. Adds no production behavior.
  @visibleForTesting
  bool sealForTest(InnerEnvelope env) => _seal(env);

  void _sendSessionData(Uint8List payload) {
    _conn?.send(
      OuterFrame(
        type: FrameType.sessionData,
        routingId: _crid,
        payload: payload,
      ),
    );
  }

  Future<void> _advanceDelivery(Uint8List recordId, DeliveryState state) async {
    final idx = _byRecordId[_hex(recordId)];
    if (idx == null) {
      return;
    }
    final updated = _records[idx].copyWith(deliveryState: state);
    await _messages.update(_channelId, updated);
    _records[idx] = updated;
    _emit(DeliveryChanged(recordId: recordId, state: state));
  }

  Future<void> _loadHistory() async {
    final history = await _messages.byChannel(_channelId);
    for (final r in history) {
      _insert(r);
    }
  }

  void _insert(MessageRecord record) {
    final at = _records.length;
    _records.add(record);
    _byRecordId[_hex(record.id)] = at;
    if (record.msgId != null) {
      _byMsgId[_hex(record.msgId!)] = at;
    }
  }

  /// Rebuilds the id indices after a removal (delete shifts positions).
  void _reindex() {
    _byRecordId.clear();
    _byMsgId.clear();
    for (var i = 0; i < _records.length; i++) {
      final r = _records[i];
      _byRecordId[_hex(r.id)] = i;
      if (r.msgId != null) {
        _byMsgId[_hex(r.msgId!)] = i;
      }
    }
  }

  MessageView _view(MessageRecord r) {
    return MessageView(
      recordId: r.id,
      msgId: r.msgId,
      outbound: r.direction == MessageDirection.sent,
      type: r.type,
      timestampMs: r.timestampMs,
      deliveryState: r.deliveryState,
      text: r.text,
      expirySeconds: r.expirySeconds,
      purgeAtMs: _purgeAt(r),
      reply: _resolveReply(r),
      ownReaction: r.ownReaction,
      peerReaction: r.peerReaction,
    );
  }

  ReplyPreview? _resolveReply(MessageRecord r) {
    final replyTo = r.replyTo;
    if (replyTo == null) {
      return null;
    }
    final idx = _byMsgId[_hex(replyTo)];
    if (idx == null) {
      return const ReplyPreview.tombstone(); // Unknown referent.
    }
    final ref = _records[idx];
    if (_isExpired(ref)) {
      return const ReplyPreview.tombstone(); // Expired referent.
    }
    if (ref.type == MessageType.text) {
      return ReplyPreview.referent(
        referentRecordId: ref.id,
        kind: ReplyReferentKind.text,
        excerpt: ref.text,
      );
    }
    // TODO(S11): distinguish photo vs document from the media manifest.
    return ReplyPreview.referent(
      referentRecordId: ref.id,
      kind: ReplyReferentKind.document,
    );
  }

  int? _purgeAt(MessageRecord r) {
    if (r.expirySeconds == null || r.readAtMs == null) {
      return null;
    }
    return r.readAtMs! + r.expirySeconds! * 1000;
  }

  bool _isExpired(MessageRecord r) {
    final purge = _purgeAt(r);
    return purge != null && purge <= _nowMs();
  }

  Uint8List _sessionHeader() => Uint8List.sublistView(
    OuterFrame(type: FrameType.sessionData, routingId: _crid).encode(),
    0,
    outerHeaderBytes,
  );

  void _teardownRelay() {
    _conn?.send(OuterFrame(type: FrameType.teardown, routingId: _crid));
  }

  void _destroyKeys() {
    _transport?.destroy();
    _transport = null;
    _initiator?.dispose();
    _initiator = null;
    _responder?.dispose();
    _responder = null;
    _awaitingHandshakeFrame = false;
  }

  void _setLineState(SessionLineState state) {
    _lineState = state;
    _emit(LineStateChanged(state));
  }

  void _emit(ChatEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  int _nowMs() => _clock().toUtc().millisecondsSinceEpoch;

  Future<void> _closeConnection() async {
    final conn = _conn;
    _conn = null;
    await _sub?.cancel();
    _sub = null;
    await conn?.close();
  }

  /// Tears the session down and releases everything. Every session starts from
  /// a fresh handshake (§3.3), so there is no reuse after this.
  Future<void> dispose() async {
    _closed = true;
    _typingTimer?.cancel();
    _destroyKeys();
    await _closeConnection();
    await _events.close();
  }

  static String _hex(Uint8List bytes) {
    const digits = '0123456789abcdef';
    final out = StringBuffer();
    for (final b in bytes) {
      out
        ..write(digits[(b >> 4) & 0x0F])
        ..write(digits[b & 0x0F]);
    }
    return out.toString();
  }
}
