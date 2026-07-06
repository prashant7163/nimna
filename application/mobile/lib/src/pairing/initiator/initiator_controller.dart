import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../diag/diag.dart';
import '../../diag/diag_events.dart';
import '../../protocol/outer_frame.dart';
import '../../protocol/pairing_code.dart';
import '../../protocol/rendezvous.dart';
import '../../transport/relay_socket.dart';
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
    DateTime Function()? clock,
    this.backgroundGrace = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  final SodiumSumo _sodium;
  final RelayConnector _connector;
  final PendingPairingStore _store;
  final Diag _diag;
  final DateTime Function() _clock;

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

  /// Opaque PAIR_DATA payloads received since the bridge, in order — the
  /// S9 responder engine consumes exactly this (S8 never interprets them
  /// and never replies).
  final List<Uint8List> pairDataFrames = [];

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

  /// Wall-clock expiry check — run on every resume/launch and by the
  /// foreground timer.
  Future<void> checkExpiryNow() async {
    final pending = _pending;
    if (pending == null ||
        (_phase != CreateLinePhase.waiting &&
            _phase != CreateLinePhase.bridged)) {
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
          _phase = CreateLinePhase.bridged;
          _diag.log(DiagEvent.pairingBridged);
          notifyListeners();
        }
      case FrameType.pairData:
        if (_phase == CreateLinePhase.bridged) {
          pairDataFrames.add(frame.payload);
          notifyListeners();
        }
      default:
        break; // Everything else is meaningless on this plane: drop.
    }
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
    unawaited(_closeConnection());
    // Key material dies with the flow; the persisted record survives for
    // relaunch-resume (it is erased only by discard paths).
    _pending?.dispose();
    _secrets?.dispose();
    super.dispose();
  }
}
