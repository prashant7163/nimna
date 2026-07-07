import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../crypto/at_rest_aead.dart';
import '../../diag/diag.dart';
import '../../diag/diag_events.dart';
import '../../domain/models/channel_record.dart';
import '../../noise/dh.dart';
import '../../noise/xxpsk2.dart';
import '../../protocol/channel_identity.dart';
import '../../protocol/outer_frame.dart';
import '../../protocol/pairing_code.dart';
import '../../protocol/rendezvous.dart';
import '../../protocol/token_payload.dart';
import '../../storage/storage_service.dart';
import '../../transport/relay_socket.dart';
import '../initiator/pending_pairing.dart';
import 'safety_phrase_wordlist.dart';

/// The joiner flow (F3, spec §3.1 step 3 → finalization). The joiner is the
/// Noise INITIATOR (§3.1.3): it enters the code (four methods, all funnelled
/// through [PairingCode.canonicalize] before reaching this controller),
/// registers today's + yesterday's rendezvous topics (two Argon2id
/// derivations, on the main isolate — S8 precedent, §3.1.2), runs the
/// XXpsk2 handshake on the bridge, shows the safety phrase (F3.4), and
/// **persists the channel only AFTER "They match"** (USER decision). A
/// decline is a LOCAL-ONLY silent discard — no peer wire signal.
enum JoinPhase {
  /// F3.1 — entering the code (with [JoinEntryError] / self-join guard).
  entry,

  /// F3.3 — deriving, registering, handshaking. Sub-second in the happy
  /// path; the frame may only flash.
  joining,

  /// F3.4 — the safety phrase is shown; awaiting match / don't-match.
  verify,

  /// F3.5 — name the line (label is local-only).
  naming,

  /// The channel is persisted; the flow is complete (→ F5/F4).
  done,

  /// F3.4 decline — the pairing was thrown away locally (the F2.9-equivalent
  /// mismatch screen). Nothing was persisted; no peer signal was sent.
  mismatch,
}

/// The inline error rendered on the entry screen (F3.1/F3.6/F3.7/F3.8). All
/// of these render on the one entry surface; none is a distinct route.
enum JoinEntryError {
  none,

  /// F3.1 edge — the device is offline; nothing was sent.
  offline,

  /// F3.6/F3.7 — the code matched nothing (wrong / expired / used / never
  /// existed — indistinguishable by design). The one generic response.
  noMatch,

  /// F3.3 edge — the handshake/bridge failed; the code is spent.
  spent,

  /// F3.2 edge — camera permission denied; fall back to typing.
  cameraDenied,

  /// F3.1 edge — an uploaded file held no readable QR.
  noQrInFile,
}

class JoinController extends ChangeNotifier {
  JoinController({
    required this._sodium,
    required this._aead,
    required this._storage,
    required this._pendingStore,
    required this._connector,
    required this._diag,
    this._cost = Argon2Cost.production,
    DateTime Function()? clock,
    this.noAnswerTimeout = const Duration(seconds: 30),
    Future<List<String>> Function()? wordlistLoader,
  }) : _clock = clock ?? DateTime.now,
       _wordlistLoader =
           wordlistLoader ??
           (() => SafetyPhraseWordlist.load().then((w) => w.words));

  final SodiumSumo _sodium;
  final AtRestAead _aead;
  final StorageService _storage;
  final PendingPairingStore _pendingStore;
  final RelayConnector _connector;
  final Diag _diag;
  final Argon2Cost _cost;
  final DateTime Function() _clock;
  final Future<List<String>> Function() _wordlistLoader;

  /// How long the joiner waits on the bridge before the one generic
  /// no-answer response (silence doctrine, §3.1.6).
  final Duration noAnswerTimeout;

  JoinPhase _phase = JoinPhase.entry;
  JoinPhase get phase => _phase;

  JoinEntryError _entryError = JoinEntryError.none;
  JoinEntryError get entryError => _entryError;

  bool _selfJoinBlocked = false;

  /// F3.8 — the current input is this device's OWN outstanding code: Join is
  /// blocked, the guard string shows, nothing is sent.
  bool get selfJoinBlocked => _selfJoinBlocked;

  List<String>? _safetyPhrase;

  /// The three safety-phrase words (F3.4), available in [JoinPhase.verify].
  List<String>? get safetyPhrase => _safetyPhrase;

  NoiseKeyPair? _ownStatic;
  RendezvousSecrets? _todaySecrets;
  RendezvousSecrets? _yesterdaySecrets;
  Uint8List? _matchedTopic;
  NoiseJoinerHandshake? _handshake;
  int _hsStep = 0;
  PairingChannelMaterial? _material;

  RelayConnection? _conn;
  StreamSubscription<OuterFrame>? _sub;
  Timer? _noAnswerTimer;
  bool _disposed = false;

  /// Self-join guard (F3.8, spec §3.1 step 3): compares the canonicalized
  /// [code] against this device's own OUTSTANDING codes only (the creator
  /// holds them until finalization). Purely local — nothing reaches the
  /// relay, so the silence doctrine is untouched. Sets [selfJoinBlocked].
  Future<bool> checkSelfJoin(PairingCode code) async {
    final own = await _isOwnCode(code);
    _selfJoinBlocked = own;
    if (own) {
      _entryError = JoinEntryError.none;
    }
    notifyListeners();
    return own;
  }

  /// Clears the per-input error state (called when the field is edited or
  /// cleared) — the guard and the last-attempt error do not outlive a fresh
  /// edit.
  void clearInputState() {
    if (_selfJoinBlocked ||
        _entryError != JoinEntryError.none ||
        _phase != JoinPhase.entry) {
      _selfJoinBlocked = false;
      _entryError = JoinEntryError.none;
      _phase = JoinPhase.entry;
      notifyListeners();
    }
  }

  /// Records an error surfaced by a join-method source (camera denied, no QR
  /// in the uploaded file) on the entry screen.
  void reportEntryError(JoinEntryError error) {
    _entryError = error;
    _phase = JoinPhase.entry;
    notifyListeners();
  }

  /// Begins joining with a validated, canonical [code] (from any of the four
  /// methods). No-op if a self-join is blocked or a flow is already running.
  Future<void> join(PairingCode code) async {
    if (_phase != JoinPhase.entry || _selfJoinBlocked) {
      return;
    }
    // Defensive re-check of the self-join guard before anything is sent.
    if (await _isOwnCode(code)) {
      _selfJoinBlocked = true;
      notifyListeners();
      return;
    }

    _entryError = JoinEntryError.none;
    _phase = JoinPhase.joining;
    notifyListeners();

    final RelayConnection conn;
    try {
      conn = await _connector.connect();
    } on RelayUnreachableError {
      _diag.log(DiagEvent.storageError, code: DiagCode.relayUnreachable);
      _entryError = JoinEntryError.offline;
      _phase = JoinPhase.entry;
      notifyListeners();
      return;
    }

    // Fresh X25519 static keypair for this channel (spec §3.1 step 3).
    _ownStatic = generateNoiseKeyPair(_sodium);

    // Today, then yesterday — two Argon2id derivations always covering a
    // TTL ≤ 24 h (§3.1.2). Registering both up front bridges immediately
    // regardless of which UTC day the code was created on.
    final now = _clock().toUtc();
    _todaySecrets = deriveRendezvous(
      sodium: _sodium,
      code: code,
      utcDate: utcDateString(now),
      cost: _cost,
    );
    _yesterdaySecrets = deriveRendezvous(
      sodium: _sodium,
      code: code,
      utcDate: utcDateString(now.subtract(const Duration(days: 1))),
      cost: _cost,
    );

    _attach(conn);
    conn.send(
      OuterFrame(
        type: FrameType.registerTopic,
        routingId: _todaySecrets!.topic,
      ),
    );
    conn.send(
      OuterFrame(
        type: FrameType.registerTopic,
        routingId: _yesterdaySecrets!.topic,
      ),
    );
    _diag.log(DiagEvent.pairingTopicRegistered);
    _armNoAnswer();
    notifyListeners();
  }

  /// F3.4 "They match" → name the line (F3.5). The channel is NOT yet
  /// persisted; it is written only at [finish], strictly after this match.
  void confirmMatch() {
    if (_phase != JoinPhase.verify) {
      return;
    }
    _phase = JoinPhase.naming;
    notifyListeners();
  }

  /// F3.4 "They don't match" → LOCAL-ONLY silent discard (USER decision).
  /// No peer wire signal is ever sent (the relay connection was already
  /// closed at handshake completion); nothing was persisted, so a decline
  /// leaves nothing to un-persist.
  Future<void> declineMismatch() async {
    if (_phase != JoinPhase.verify) {
      return;
    }
    await _discardMaterial();
    _phase = JoinPhase.mismatch;
    notifyListeners();
  }

  /// F3.5 "Done" → persist the channel locally with [label] (label is
  /// local-only, §6). This is the sole persistence point, always after a
  /// match.
  Future<void> finish(String label) async {
    if (_phase != JoinPhase.naming || _material == null || _ownStatic == null) {
      return;
    }
    final material = _material!;
    final own = _ownStatic!;
    final priv = own.secretKey.extractBytes();
    final record = ChannelRecord(
      id: _aead.randomBytes(16),
      ownStaticPrivate: priv,
      ownStaticPublic: Uint8List.fromList(own.publicKey),
      peerStaticPublic: material.peerStaticPublic,
      crid: material.crid,
      label: label,
      cdk: _aead.randomBytes(32),
      createdAtMs: _clock().toUtc().millisecondsSinceEpoch,
      // Store the peer's device-token if it rode the handshake (§3.2.1) so
      // S15 needs no retrofit; S9 ships push-off so the joiner sent absent.
      peerDeviceToken: material.peerToken.isPresent
          ? material.peerToken.token
          : null,
    );
    // create() takes ownership of `priv` and `cdk` (moved into SecureKeys,
    // buffers zeroized).
    await _storage.channels.create(record);
    _diag.log(DiagEvent.pairingFinalized);
    await _discardMaterial();
    _phase = JoinPhase.done;
    notifyListeners();
  }

  /// Returns the flow to the entry screen (Clear / try again / Go back).
  void reset() {
    unawaited(_discardMaterial());
    unawaited(_closeConnection());
    _selfJoinBlocked = false;
    _entryError = JoinEntryError.none;
    _safetyPhrase = null;
    _phase = JoinPhase.entry;
    notifyListeners();
  }

  // ---- internals -----------------------------------------------------

  Future<bool> _isOwnCode(PairingCode code) async {
    final entries = await _pendingStore.readAll();
    try {
      return entries.any((e) => e.code == code);
    } finally {
      for (final e in entries) {
        e.dispose();
      }
    }
  }

  void _attach(RelayConnection conn) {
    _conn = conn;
    _sub = conn.frames.listen(_onFrame, onDone: _onConnectionLost);
  }

  void _onFrame(OuterFrame frame) {
    switch (frame.type) {
      case FrameType.topicBridged:
        _onBridged(frame.routingId);
      case FrameType.pairData:
        _onPairData(frame);
      default:
        break; // Nothing else is meaningful on this plane: drop.
    }
  }

  RendezvousSecrets? _matchSecrets(Uint8List topic) {
    if (_todaySecrets != null && listEquals(topic, _todaySecrets!.topic)) {
      return _todaySecrets;
    }
    if (_yesterdaySecrets != null &&
        listEquals(topic, _yesterdaySecrets!.topic)) {
      return _yesterdaySecrets;
    }
    return null;
  }

  void _onBridged(Uint8List topic) {
    if (_phase != JoinPhase.joining || _handshake != null) {
      return;
    }
    final secrets = _matchSecrets(topic);
    if (secrets == null) {
      return; // Not one of our topics: drop.
    }
    _matchedTopic = Uint8List.fromList(topic);
    _noAnswerTimer?.cancel();
    _diag.log(DiagEvent.pairingBridged);
    _handshake = NoiseJoinerHandshake(
      sodium: _sodium,
      aead: _aead,
      staticKeyPair: _ownStatic!,
      psk: secrets.psk,
      // S9 ships push-off by default; the joiner carries the "absent" form
      // (§3.2.1 / §5.7). token-on carriage rides the same path with no
      // retrofit for S15.
      tokenPayload: const TokenPayload.absent(),
    );
    try {
      _send(_handshake!.writeM1());
    } on PairingHandshakeError {
      _failClosed();
    }
  }

  void _onPairData(OuterFrame frame) {
    final hs = _handshake;
    if (hs == null ||
        _phase != JoinPhase.joining ||
        !listEquals(frame.routingId, _matchedTopic)) {
      return;
    }
    try {
      if (_hsStep == 0) {
        hs.readM2(frame.payload);
        _send(hs.writeM3());
        _hsStep++;
      } else if (_hsStep == 1) {
        hs.completeWithM4(frame.payload, _pairHeader());
        _material = hs.finalizeChannel();
        _hsStep++;
        unawaited(_onHandshakeComplete());
      }
    } on PairingHandshakeError {
      _failClosed();
    }
  }

  Future<void> _onHandshakeComplete() async {
    // The relay is no longer needed; closing frees the rendezvous topic.
    await _closeConnection();
    _noAnswerTimer?.cancel();
    final material = _material;
    final own = _ownStatic;
    if (material == null || own == null) {
      return;
    }
    final words = await _wordlistLoader();
    if (_disposed) {
      return;
    }
    _safetyPhrase = safetyPhraseWords(
      ss: material.ss,
      aPublic: own.publicKey,
      bPublic: material.peerStaticPublic,
      wordlist: words,
    );
    _phase = JoinPhase.verify;
    notifyListeners();
  }

  Uint8List _pairHeader() => Uint8List.sublistView(
    OuterFrame(type: FrameType.pairData, routingId: _matchedTopic!).encode(),
    0,
    outerHeaderBytes,
  );

  void _send(Uint8List payload) {
    _conn?.send(
      OuterFrame(
        type: FrameType.pairData,
        routingId: _matchedTopic!,
        payload: payload,
      ),
    );
  }

  void _armNoAnswer() {
    _noAnswerTimer?.cancel();
    _noAnswerTimer = Timer(noAnswerTimeout, () => unawaited(_toNoAnswer()));
  }

  Future<void> _toNoAnswer() async {
    if (_phase != JoinPhase.joining || _handshake != null) {
      return;
    }
    await _discardMaterial();
    await _closeConnection();
    _entryError = JoinEntryError.noMatch;
    _phase = JoinPhase.entry;
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _failClosed() {
    _diag.log(DiagEvent.pairingHandshakeFailed);
    unawaited(_toSpent());
  }

  Future<void> _toSpent() async {
    await _discardMaterial();
    await _closeConnection();
    _entryError = JoinEntryError.spent;
    _phase = JoinPhase.entry;
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _onConnectionLost() {
    _conn = null;
    _sub = null;
    if (_disposed || _phase != JoinPhase.joining) {
      return;
    }
    if (_handshake != null) {
      // A bridge lost mid-handshake kills the attempt (§3.1.6, fail-closed).
      _failClosed();
    } else {
      // A drop before bridging is a non-bridging outcome: the one generic
      // response (silence doctrine).
      unawaited(_toNoAnswer());
    }
  }

  Future<void> _discardMaterial() async {
    _noAnswerTimer?.cancel();
    _handshake?.dispose();
    _handshake = null;
    _material?.disposeSecret();
    _material = null;
    _ownStatic?.dispose();
    _ownStatic = null;
    _todaySecrets?.dispose();
    _todaySecrets = null;
    _yesterdaySecrets?.dispose();
    _yesterdaySecrets = null;
    _hsStep = 0;
    _matchedTopic = null;
  }

  Future<void> _closeConnection() async {
    final conn = _conn;
    _conn = null;
    await _sub?.cancel();
    _sub = null;
    await conn?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _noAnswerTimer?.cancel();
    _handshake?.dispose();
    _material?.disposeSecret();
    _ownStatic?.dispose();
    _todaySecrets?.dispose();
    _yesterdaySecrets?.dispose();
    unawaited(_closeConnection());
    super.dispose();
  }
}
