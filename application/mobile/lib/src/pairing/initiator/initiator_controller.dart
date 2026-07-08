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
import '../joiner/safety_phrase_wordlist.dart';
import 'pending_pairing.dart';

/// TTL presets offered at generation (F2.1; S8 intake §5 CODE decision).
/// The protocol caps at 24 h (spec §3.1.2 two-candidate cover, §4
/// registration cap) — no longer option can ever exist. Default 24 h;
/// shorter is safer.
const List<Duration> ttlPresets = [
  Duration(hours: 1),
  Duration(hours: 8),
  Duration(hours: 24),
];

/// Default TTL (spec §3.1: default 24 h).
const Duration defaultTtl = Duration(hours: 24);

/// The initiator state machine (S8 intake §2):
/// `setup → generating → waiting ⇄ (offline gaps) → bridged (hold)`
/// with terminal exits `expired`, `cancelled`, and `spent` (bridge lost
/// before the S9 handshake — fail-closed per §3.1.6).
enum CreateLinePhase {
  /// F2.1 — TTL choice; nothing exists yet.
  setup,

  /// Create tapped: connect → generate → derive → register in flight.
  generating,

  /// F2.2/F2.4 — code live, registered (or politely re-registering after
  /// a drop), listening for the bridge.
  waiting,

  /// TOPIC_BRIDGED received — S8's terminal success: hold the socket at
  /// the F2.4→F2.5 boundary; the S9 responder engine attaches here.
  bridged,

  /// F2.6 — the handshake finished; the safety phrase is shown, awaiting
  /// match / don't-match (the closing ritual of pairing, spec §3.1.5).
  verifying,

  /// F2.7 — "They match": naming the line (label is local-only) before the
  /// sole persistence point.
  naming,

  /// The channel is persisted; the flow is complete (→ F4/F5). The code has
  /// done its job and is discarded.
  finalized,

  /// F2.9 — "They don't match": the pairing is thrown away LOCALLY (USER
  /// decision — no peer wire signal; the copy must NOT imply the peer is told).
  mismatch,

  /// F2.8 — TTL lapsed unused; code and keypair discarded.
  expired,

  /// User cancelled; code and keypair discarded. The joiner side gets
  /// silence (the topic died with the registration) — silence doctrine.
  cancelled,

  /// The bridge dropped before the handshake finished; everything
  /// discarded (spec §3.1.6 — a half-made channel never exists).
  spent,
}

/// Flow controller for the initiator side of pairing (ChangeNotifier per
/// app-architecture.md §8.2). Constructed ONLY by the flow's own route
/// wiring (create_line_entry.dart) — the G2 single-entry invariant.
class CreateLineController extends ChangeNotifier {
  CreateLineController({
    required this._sodium,
    required this._connector,
    required this._store,
    required this._diag,
    StorageService? storage,
    AtRestAead? aead,
    Future<List<String>> Function()? wordlistLoader,
    DateTime Function()? clock,
    this.backgroundGrace = const Duration(seconds: 30),
    // The finalize deps below are assigned in the initializer list rather than
    // as `this._x` formals so the public constructor keeps typed, meaningfully
    // named parameters (storage/aead/wordlistLoader) for call sites.
  }) : _clock = clock ?? DateTime.now,
       _storage = storage,
       // ignore: prefer_initializing_formals
       _wordlistLoader = wordlistLoader {
    // Finalize (F2.6/F2.7 — S16) is enabled when the creation composition root
    // supplies storage: the controller then drives the from-spec responder
    // itself, computes the safety phrase, and persists the channel on a match.
    // Absent storage (older tests that only exercise S8's setup→bridge hold),
    // behaviour is exactly S8's — the external attachResponder seam still works.
    if (aead != null) {
      _aead = aead;
    }
    _finalizeEnabled = storage != null;
  }

  final SodiumSumo _sodium;
  final RelayConnector _connector;
  final PendingPairingStore _store;
  final Diag _diag;
  final DateTime Function() _clock;

  /// S16 finalize deps (F2.6/F2.7). Null in the S8-era setup/hold tests.
  final StorageService? _storage;
  final Future<List<String>> Function()? _wordlistLoader;
  bool _finalizeEnabled = false;

  List<String>? _safetyPhrase;

  /// The three safety-phrase words (F2.6), available in [CreateLinePhase]
  /// `verifying`. Protocol output, one global wordlist, identical in every
  /// locale (spec §3.1.4) — never localized copy.
  List<String>? get safetyPhrase => _safetyPhrase;

  /// How long the socket is held after backgrounding before it closes
  /// (spec §3.3 ~30 s; symmetric by policy).
  final Duration backgroundGrace;

  CreateLinePhase _phase = CreateLinePhase.setup;
  CreateLinePhase get phase => _phase;

  /// F2.1 edge: the last create attempt failed to reach the relay.
  /// Nothing was generated (no phantom codes).
  bool _offline = false;
  bool get offline => _offline;

  Duration _ttl = defaultTtl;
  Duration get ttl => _ttl;
  set ttl(Duration value) {
    if (!ttlPresets.contains(value)) {
      throw ArgumentError.value(value, 'ttl', 'not a preset');
    }
    _ttl = value;
    notifyListeners();
  }

  PendingPairing? _pending;

  /// The live code (null before generation and after discard).
  PairingCode? get code => _pending?.code;

  DateTime? get expiresAt => _pending?.expiresAt;

  /// Rendezvous secrets held for S9 (psk untouched in S8).
  RendezvousSecrets? _secrets;
  RendezvousSecrets? get secrets => _secrets;

  /// The pending record (own static keypair) for the S9 responder engine.
  PendingPairing? get pending => _pending;

  /// Opaque PAIR_DATA payloads received since the bridge, in order. Used
  /// only when NO responder is attached (the S8 hold-and-buffer behavior).
  /// When a responder is attached (S9 write-seam), inbound PAIR_DATA is
  /// driven through the engine instead and never buffered here.
  final List<Uint8List> pairDataFrames = [];

  // ---- S9 responder write-seam ---------------------------------------
  // The creator is the Noise RESPONDER (spec §3.1.3). This opt-in seam lets
  // a caller (the end-to-end pairing test today; the creator-finalize UI in
  // a later session) drive the from-spec responder engine over the bridge:
  // S8 left `_conn.send` private, so without this seam the creator can hold
  // but never transmit M2/M4. Absent the attachment, behavior is exactly
  // S8's (buffer PAIR_DATA, fabricate nothing). Responder logic lives in
  // `lib/src/noise`; this file only shuttles frames and cancels the TTL
  // timer at the bridge (TTL is a pre-bridge gate only — CODE decision).
  void Function(PairingChannelMaterial material)? _onResponderComplete;
  void Function()? _onResponderFailed;
  AtRestAead? _aead;
  NoiseResponderHandshake? _responder;
  int _responderStep = 0;
  PairingChannelMaterial? _material;

  bool get _responderEnabled => _onResponderComplete != null;

  /// The finalized channel material (peer static, CRID, ss, peer token)
  /// after a valid handshake — held for the creator-finalize UI (a later
  /// session persists it behind F2.6/F2.7). Null until completion.
  PairingChannelMaterial? get pairingMaterial => _material;

  /// Attaches the from-spec responder engine. Must be called before the
  /// bridge forms. [onComplete] receives the finalized channel material;
  /// [onFailed] fires on any fail-closed handshake failure (§3.1.6).
  void attachResponder({
    required void Function(PairingChannelMaterial material) onComplete,
    void Function()? onFailed,
  }) {
    _onResponderComplete = onComplete;
    _onResponderFailed = onFailed;
  }

  RelayConnection? _conn;
  StreamSubscription<OuterFrame>? _sub;
  Timer? _expiryTimer;
  Timer? _reconnectTimer;
  Timer? _graceTimer;
  final ReconnectBackoff _backoff = ReconnectBackoff();
  bool _inForeground = true;
  bool _disposed = false;

  /// F2.1 → F2.2: connect, generate, derive, register, persist. Returns
  /// true when the code is live (navigate to the share screen); false on
  /// the offline edge (stay on F2.1, [offline] set). Nothing is generated
  /// without a live registration.
  Future<bool> createCode() async {
    if (_phase != CreateLinePhase.setup) {
      throw StateError('createCode outside setup');
    }
    _offline = false;
    _phase = CreateLinePhase.generating;
    notifyListeners();

    final RelayConnection conn;
    try {
      conn = await _connector.connect();
    } on RelayUnreachableError {
      _diag.log(DiagEvent.storageError, code: DiagCode.relayUnreachable);
      _offline = true;
      _phase = CreateLinePhase.setup;
      notifyListeners();
      return false;
    }

    final now = _clock().toUtc();
    final code = PairingCode.generate(
      (upperBound) => _sodium.randombytes.uniform(upperBound),
    );
    final keyPair = _sodium.crypto.box.keyPair();
    final date = utcDateString(now);
    // Argon2id (t=3, m=64 MiB) — a deliberate 0.2–0.8 s slow hash, once
    // per pairing and never in any other flow (spec §3.1.2).
    final secrets = deriveRendezvous(
      sodium: _sodium,
      code: code,
      utcDate: date,
    );

    _pending = PendingPairing(
      code: code,
      utcDate: date,
      ttl: _ttl,
      createdAt: now,
      publicKey: keyPair.publicKey,
      secretKey: keyPair.secretKey,
    );
    _secrets = secrets;
    _diag.log(DiagEvent.pairingCodeCreated);

    _attach(conn);
    _register();
    await _store.add(_pending!);

    _phase = CreateLinePhase.waiting;
    _armExpiryTimer();
    notifyListeners();
    return true;
  }

  /// Relaunch path (F2.4 edge): adopts a persisted entry. If it already
  /// lapsed while away → F2.8 immediately; otherwise re-derives the topic
  /// (same creation date) and re-registers. Takes ownership of [entry].
  Future<void> resume(PendingPairing entry) async {
    if (_phase != CreateLinePhase.setup) {
      throw StateError('resume outside setup');
    }
    _pending = entry;
    _ttl = entry.ttl;
    if (entry.isExpired(_clock())) {
      await _expire();
      return;
    }
    _secrets = deriveRendezvous(
      sodium: _sodium,
      code: entry.code,
      utcDate: entry.utcDate,
    );
    _phase = CreateLinePhase.waiting;
    _armExpiryTimer();
    notifyListeners();
    await _reconnect();
  }

  /// Cancel this code (F2.4 ghost action / back-confirm): discards code
  /// and keypair — "nothing was created". The joiner gets silence.
  Future<void> cancel() async {
    if (_phase != CreateLinePhase.waiting &&
        _phase != CreateLinePhase.bridged) {
      return;
    }
    _diag.log(DiagEvent.pairingCancelled);
    await _discard(CreateLinePhase.cancelled);
  }

  /// After a valid handshake (F2.5→F2.6): the relay is no longer needed, so
  /// the connection closes; the safety phrase is derived from the shared key
  /// material (identical on both ends — spec §3.1.4, order-independent salt)
  /// and shown for verification. Locale-independent protocol output.
  Future<void> _onHandshakeComplete() async {
    await _closeConnection();
    _expiryTimer?.cancel();
    final material = _material;
    final pending = _pending;
    if (material == null || pending == null) {
      return;
    }
    final words = await (_wordlistLoader ?? _defaultWordlist)();
    if (_disposed) {
      return;
    }
    _safetyPhrase = safetyPhraseWords(
      ss: material.ss,
      aPublic: pending.publicKey,
      bPublic: material.peerStaticPublic,
      wordlist: words,
    );
    _phase = CreateLinePhase.verifying;
    notifyListeners();
  }

  /// F2.6 "They match" → name the line (F2.7). The channel is NOT yet
  /// persisted; it is written only at [finish], strictly after this match.
  void confirmMatch() {
    if (_phase != CreateLinePhase.verifying) {
      return;
    }
    _phase = CreateLinePhase.naming;
    notifyListeners();
  }

  /// F2.6 "They don't match" → F2.9. A LOCAL-ONLY silent discard (USER
  /// decision): NO peer wire signal is ever sent (the relay connection was
  /// already closed at handshake completion), and nothing was persisted, so a
  /// decline leaves nothing to un-persist. The mismatch copy must never imply
  /// the peer is told.
  Future<void> declineMismatch() async {
    if (_phase != CreateLinePhase.verifying) {
      return;
    }
    await _discard(CreateLinePhase.mismatch);
  }

  /// F2.7 "Done" → persist the channel locally with [label] (label is
  /// local-only, spec §6). The sole persistence point, always after a match.
  /// Mirrors the joiner's finalize; the creator's own static keypair is the
  /// pending record's (it was the Noise responder's static, §3.1.3).
  Future<void> finish(String label) async {
    final storage = _storage;
    final material = _material;
    final pending = _pending;
    if (_phase != CreateLinePhase.naming ||
        storage == null ||
        material == null ||
        pending == null) {
      return;
    }
    final aead = _aead ??= AtRestAead(_sodium);
    final record = ChannelRecord(
      id: aead.randomBytes(16),
      // create() takes ownership of these buffers (moved into SecureKeys,
      // zeroized); pending.secretKey.extractBytes() copies, so the pending
      // record's own disposal below is safe.
      ownStaticPrivate: pending.secretKey.extractBytes(),
      ownStaticPublic: Uint8List.fromList(pending.publicKey),
      peerStaticPublic: material.peerStaticPublic,
      crid: material.crid,
      label: label,
      cdk: aead.randomBytes(32),
      createdAtMs: _clock().toUtc().millisecondsSinceEpoch,
      // Persist the §5.7 present-form token if the joiner shared one (§3.2.1);
      // S9 ships push-off, so no present token exists yet — no retrofit.
      peerDeviceToken: material.peerToken.isPresent
          ? material.peerToken.encode()
          : null,
    );
    await storage.channels.create(record);
    _diag.log(DiagEvent.pairingFinalized);
    // The code has done its job: discard it and all key material, land on
    // `finalized`.
    await _discard(CreateLinePhase.finalized);
  }

  /// Default wordlist loader (the pinned global EFF list, spec §3.1.4) — the
  /// same source the joiner uses. Tests inject a substitute via
  /// [CreateLineController]'s `wordlistLoader`.
  static Future<List<String>> _defaultWordlist() =>
      SafetyPhraseWordlist.load().then((w) => w.words);

  /// Wall-clock expiry check — run on every resume/launch and by the
  /// foreground timer.
  Future<void> checkExpiryNow() async {
    final pending = _pending;
    // TTL is a pre-bridge gate only (CODE decision): once bridged, a
    // progressing handshake is never aborted by a TTL crossing — its only
    // exits are handshake success or fail-closed failure (§3.1.6).
    if (pending == null || _phase != CreateLinePhase.waiting) {
      return;
    }
    if (pending.isExpired(_clock())) {
      await _expire();
    }
  }

  /// App lifecycle: backgrounded. The socket is held for [backgroundGrace]
  /// then closed — listening STOPS; the copy promises the code's lifetime,
  /// never background presence.
  void onAppPaused() {
    _inForeground = false;
    _reconnectTimer?.cancel();
    _graceTimer?.cancel();
    if (_conn != null) {
      _graceTimer = Timer(backgroundGrace, () async {
        await _closeConnection();
      });
    }
  }

  /// App lifecycle: foregrounded. Checks expiry, then quietly resumes the
  /// wait (one reconnect attempt, then backoff — never a tight loop).
  void onAppResumed() {
    _inForeground = true;
    _graceTimer?.cancel();
    _graceTimer = null;
    unawaited(() async {
      await checkExpiryNow();
      if (_phase == CreateLinePhase.waiting && _conn == null) {
        await _reconnect();
      }
    }());
  }

  // ---- internals -----------------------------------------------------

  void _attach(RelayConnection conn) {
    _conn = conn;
    _backoff.reset();
    _sub = conn.frames.listen(_onFrame, onDone: _onConnectionLost);
  }

  void _register() {
    final secrets = _secrets;
    final conn = _conn;
    if (secrets == null || conn == null) {
      return;
    }
    conn.send(
      OuterFrame(type: FrameType.registerTopic, routingId: secrets.topic),
    );
    _diag.log(DiagEvent.pairingTopicRegistered);
  }

  void _onFrame(OuterFrame frame) {
    final secrets = _secrets;
    if (secrets == null || !listEquals(frame.routingId, secrets.topic)) {
      return; // Not this flow's topic: drop.
    }
    switch (frame.type) {
      case FrameType.topicBridged:
        if (_phase == CreateLinePhase.waiting) {
          // TTL is a pre-bridge registration gate only (CODE decision): from
          // the bridge onward the only terminal states are handshake success
          // or a fail-closed handshake/bridge failure (§3.1.6). Cancel the
          // expiry timer so a mid-flight TTL crossing never aborts a
          // progressing handshake.
          _expiryTimer?.cancel();
          _phase = CreateLinePhase.bridged;
          _diag.log(DiagEvent.pairingBridged);
          if (_responderEnabled || _finalizeEnabled) {
            _startResponder();
          }
          notifyListeners();
        }
      case FrameType.pairData:
        if (_phase == CreateLinePhase.bridged) {
          if (_responderEnabled || _finalizeEnabled) {
            _driveResponder(frame.payload);
          } else {
            pairDataFrames.add(frame.payload);
            notifyListeners();
          }
        }
      default:
        break; // Everything else is meaningless on this plane: drop.
    }
  }

  void _startResponder() {
    final pending = _pending;
    final secrets = _secrets;
    if (pending == null || secrets == null) {
      return;
    }
    final aead = _aead ??= AtRestAead(_sodium);
    _responder = NoiseResponderHandshake(
      sodium: _sodium,
      aead: aead,
      // The pending record owns the static keypair; the responder never
      // disposes its `_static`, so wrapping it here transfers no ownership.
      staticKeyPair: NoiseKeyPair(
        publicKey: pending.publicKey,
        secretKey: pending.secretKey,
      ),
      psk: secrets.psk,
      // S9 ships push-off by default; the creator carries the "absent" form
      // (§3.2.1 / §5.7). token-on carriage rides the same path when push is
      // enabled — no retrofit needed for S15.
      tokenPayload: const TokenPayload.absent(),
    );
    _responderStep = 0;
  }

  void _driveResponder(Uint8List payload) {
    final responder = _responder;
    final secrets = _secrets;
    if (responder == null || secrets == null) {
      return;
    }
    try {
      if (_responderStep == 0) {
        responder.readM1(payload);
        _sendPairData(responder.writeM2());
      } else if (_responderStep == 1) {
        responder.readM3(payload);
        final header = Uint8List.sublistView(
          OuterFrame(
            type: FrameType.pairData,
            routingId: secrets.topic,
          ).encode(),
          0,
          outerHeaderBytes,
        );
        _sendPairData(responder.writeM4(header));
        _material = responder.finalizeChannel();
        if (_onResponderComplete != null) {
          // External seam (the end-to-end pairing test drives its own finalize).
          _onResponderComplete!.call(_material!);
        } else if (_finalizeEnabled) {
          // Production (S16): the controller finalizes itself — compute the
          // safety phrase and advance to F2.6.
          unawaited(_onHandshakeComplete());
        }
      }
      _responderStep++;
    } on PairingHandshakeError {
      responder.dispose();
      _responder = null;
      _onResponderFailed?.call();
      // Any failure inside the handshake window kills the topic and the
      // code (spec §3.1.6, fail-closed).
      unawaited(_discard(CreateLinePhase.spent));
    }
  }

  void _sendPairData(Uint8List payload) {
    final secrets = _secrets;
    if (secrets == null) {
      return;
    }
    _conn?.send(
      OuterFrame(
        type: FrameType.pairData,
        routingId: secrets.topic,
        payload: payload,
      ),
    );
  }

  void _onConnectionLost() {
    _conn = null;
    _sub = null;
    if (_disposed) {
      return;
    }
    switch (_phase) {
      case CreateLinePhase.bridged:
        // The topic died with the bridge; any failure inside the handshake
        // window kills the topic and the code (spec §3.1.6).
        unawaited(_discard(CreateLinePhase.spent));
      case CreateLinePhase.waiting:
        if (_inForeground) {
          _scheduleReconnect();
        }
      default:
        break;
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff.nextDelay(), () {
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (_disposed || _phase != CreateLinePhase.waiting || _conn != null) {
      return;
    }
    await checkExpiryNow();
    if (_phase != CreateLinePhase.waiting) {
      return;
    }
    try {
      final conn = await _connector.connect();
      _attach(conn);
      _register();
    } on RelayUnreachableError {
      _diag.log(DiagEvent.storageError, code: DiagCode.relayUnreachable);
      if (_inForeground) {
        _scheduleReconnect();
      }
    }
  }

  void _armExpiryTimer() {
    _expiryTimer?.cancel();
    final expiresAt = _pending?.expiresAt;
    if (expiresAt == null) {
      return;
    }
    final remaining = expiresAt.difference(_clock().toUtc());
    _expiryTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      unawaited(checkExpiryNow());
    });
  }

  Future<void> _expire() async {
    _diag.log(DiagEvent.pairingExpired);
    await _discard(CreateLinePhase.expired);
  }

  /// Discards code, keypair, secrets, and the persisted entry — a real
  /// erase; then lands on [terminal].
  Future<void> _discard(CreateLinePhase terminal) async {
    final pending = _pending;
    _expiryTimer?.cancel();
    _reconnectTimer?.cancel();
    _graceTimer?.cancel();
    _responder?.dispose();
    _responder = null;
    _material?.disposeSecret();
    _material = null;
    await _closeConnection();
    if (pending != null) {
      await _store.remove(pending.code);
      pending.dispose();
    }
    _secrets?.dispose();
    _secrets = null;
    _pending = null;
    pairDataFrames.clear();
    _phase = terminal;
    if (!_disposed) {
      notifyListeners();
    }
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
    _expiryTimer?.cancel();
    _reconnectTimer?.cancel();
    _graceTimer?.cancel();
    _responder?.dispose();
    _material?.disposeSecret();
    unawaited(_closeConnection());
    // Key material dies with the flow; the persisted record survives for
    // relaunch-resume (it is erased only by discard paths).
    _pending?.dispose();
    _secrets?.dispose();
    super.dispose();
  }
}
