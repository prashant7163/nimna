/// Bounded automatic recovery of a LIVE-session drop (spec §3.3 keepalive,
/// voice string 10) — the ONE place the app re-knocks on its own.
///
/// Doctrine (USER, 2026-07): a mid-conversation drop (transient network /
/// bridge death) silently retries — a fresh knock+KK via the launcher, spaced
/// by [ReconnectBackoff], for a bounded ~20 s window — surfacing
/// "…Trying to reconnect…" and recovering to "You're both here." or falling to
/// terminal "The line dropped." This is DISTINCT from the cold-knock
/// never-auto-retry doctrine: the coordinator engages ONLY after a session was
/// [SessionLineState.live]. A fresh (unanswered) knock is never retried here.
///
/// "Reconnect" is a FRESH [SessionController] (keys die per session, §3.3.1 —
/// there is no resumed transport), rebuilt via the launcher and seeded with
/// any offline-composed reactions so they survive the rebuild (decision 3).
/// The fresh session's `live` transition auto-flushes the text/reaction outbox.
///
/// Pure Dart, locale-independent. The window uses the injected [clock]; retry
/// spacing uses the injected [sleeper] — tests advance a virtual clock inside
/// the sleeper for deterministic exhaustion.
library;

import 'dart:async';
import 'dart:typed_data';

import '../diag/diag.dart';
import '../diag/diag_events.dart';
import '../session/connection/session_controller.dart';
import '../session/model/chat_event.dart';
import '../transport/relay_socket.dart';

// Pass-through deps are assigned in the initializer list (beside the
// defaulted backoff/sleeper/clock) rather than as `this._x` formals, keeping
// typed, named constructor parameters at call sites.
// ignore_for_file: prefer_initializing_formals

/// What the recovery is doing right now — maps to voice string 10:
/// [reconnecting] → session_lineDropped, [recovered] → session_lineRecovered,
/// [lost] → session_lineLost. [idle] is the steady live/adopted state.
enum ReconnectPhase { idle, reconnecting, recovered, lost }

class ReconnectCoordinator {
  ReconnectCoordinator({
    required SessionController Function(List<PendingReaction> seed) rebuild,
    required Uint8List Function() knockPayload,
    required Diag diag,
    this.window = const Duration(seconds: 20),
    ReconnectBackoff? backoff,
    Future<void> Function(Duration delay)? sleeper,
    DateTime Function()? clock,
  }) : _rebuild = rebuild,
       _knockPayload = knockPayload,
       _diag = diag,
       _backoff = backoff ?? ReconnectBackoff(),
       _sleeper = sleeper ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  /// The bounded recovery window before the drop becomes terminal (~20 s).
  final Duration window;

  final SessionController Function(List<PendingReaction> seed) _rebuild;
  final Uint8List Function() _knockPayload;
  final Diag _diag;
  final ReconnectBackoff _backoff;
  final Future<void> Function(Duration delay) _sleeper;
  final DateTime Function() _clock;

  final StreamController<ReconnectPhase> _phases =
      StreamController<ReconnectPhase>.broadcast();

  SessionController? _controller;
  StreamSubscription<ChatEvent>? _sub;
  ReconnectPhase _phase = ReconnectPhase.idle;
  bool _hasBeenLive = false;
  bool _recovering = false;
  bool _disposed = false;

  /// The current (possibly rebuilt) controller the UI should read from.
  SessionController? get controller => _controller;

  ReconnectPhase get phase => _phase;

  /// Phase changes (session_lineDropped / lineRecovered / lineLost mapping).
  Stream<ReconnectPhase> get phases => _phases.stream;

  /// Adopt the live/engaged controller and watch it for a mid-session drop.
  /// Call once, after the knock flow produced a controller.
  void adopt(SessionController controller) {
    if (_disposed) {
      return;
    }
    _controller = controller;
    _hasBeenLive = controller.isLive || _hasBeenLive;
    _listen(controller);
  }

  void _listen(SessionController controller) {
    _sub?.cancel();
    _sub = controller.events.listen(_onEvent);
  }

  void _onEvent(ChatEvent event) {
    if (_disposed || _recovering) {
      // While recovering, the loop drives its own controllers; ignore events.
      return;
    }
    if (event is LineStateChanged && event.state == SessionLineState.live) {
      _hasBeenLive = true;
      _setPhase(ReconnectPhase.idle);
      return;
    }
    if (event is SessionEnded &&
        event.reason == SessionEndReason.connectionLost &&
        _hasBeenLive) {
      // A LIVE session dropped — recover it. (A HANGUP `ended` never recovers;
      // an unanswered cold knock never reaches _hasBeenLive.)
      unawaited(_reconnect());
    }
  }

  Future<void> _reconnect() async {
    _recovering = true;
    _diag.log(DiagEvent.sessionReconnecting);
    _setPhase(ReconnectPhase.reconnecting);
    final seed = _controller?.pendingReactions ?? const <PendingReaction>[];
    final deadline = _clock().add(window);

    // The dropped controller's transport/keys are already destroyed; dispose it
    // so its broadcast event stream is closed too (no leak). Snapshot its seed
    // first (above). The reconnect loop replaces _controller with fresh ones.
    await _sub?.cancel();
    _sub = null;
    await _controller?.dispose();

    while (!_disposed && _clock().isBefore(deadline)) {
      await _sleeper(_backoff.nextDelay());
      if (_disposed || !_clock().isBefore(deadline)) {
        break;
      }
      final fresh = _rebuild(seed);
      _controller = fresh;
      await fresh.start(knockPushPayload: _knockPayload());
      await _settle();
      if (fresh.isLive) {
        _backoff.reset();
        _hasBeenLive = true;
        _recovering = false;
        _listen(fresh); // Resume watching for the NEXT drop.
        _diag.log(DiagEvent.sessionRecovered);
        _setPhase(ReconnectPhase.recovered);
        return;
      }
      await fresh.dispose(); // This attempt failed; try again (or exhaust).
    }

    _recovering = false;
    _setPhase(ReconnectPhase.lost);
  }

  /// Lets the in-memory bridge run the KNOCK→ACCEPT→S1/S2 hops. Real timing is
  /// the OS's; headless it is a handful of microtask turns.
  Future<void> _settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _setPhase(ReconnectPhase phase) {
    _phase = phase;
    if (!_phases.isClosed) {
      _phases.add(phase);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    await _phases.close();
  }
}
