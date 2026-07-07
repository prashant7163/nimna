/// Outgoing-knock UX for one channel (F5 status line, spec §3.2 / §4 / §6.1).
///
/// Sends the ONE knock, runs the 60 s waiting window, and — on a lapse —
/// settles to **"No answer."** with a manual **"Knock again"** (never a
/// countdown-time retry). The app NEVER auto-retries a cold knock (spec §4,
/// string 6): re-knocking is a deliberate human act. After an extended
/// unanswered stretch it surfaces the §6.1 stale-knock hint — a LOCAL-ONLY
/// heuristic (no wire signal): the knocker cannot tell offline from ignored,
/// and this never claims to (attribution-free, DECISIONS 2026-07-04).
///
/// The `reconnecting`/recovery choreography of a LIVE-session drop is a
/// SEPARATE unit (reconnect_coordinator) — this controller governs only the
/// cold knock's patience. A [ChangeNotifier]; the widget maps state → ARB
/// copy. Locale-independent logic.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diag/diag.dart';
import '../diag/diag_events.dart';
import '../session/connection/session_controller.dart';
import '../session/model/chat_event.dart';
import 'session_launcher.dart';

// Pass-through deps are assigned in the initializer list (beside the
// defaulted/transformed fields) rather than as `this._x` formals.
// ignore_for_file: prefer_initializing_formals

/// The outgoing-knock UX state.
enum KnockState {
  /// No knock in flight (F5.1 — compose-to-outbox; "Knock" available).
  idle,

  /// Knocked; the 60 s window is running (string 6).
  waiting,

  /// The line opened (a pick-up + KK). The chat surface takes over.
  live,

  /// The window closed unanswered — "No answer." + manual "Knock again".
  lapsed,
}

class KnockController extends ChangeNotifier {
  KnockController({
    required SessionLauncher launcher,
    required Uint8List channelId,
    required Diag diag,
    this.window = const Duration(seconds: 60),
    Timer Function(Duration, void Function())? timerFactory,
    DateTime Function()? clock,
    int staleHintAfterConsecutiveLapses = 2,
  }) : _launcher = launcher,
       _channelId = Uint8List.fromList(channelId),
       _diag = diag,
       _timerFactory = timerFactory ?? Timer.new,
       _clock = clock ?? DateTime.now,
       _staleHintThreshold = staleHintAfterConsecutiveLapses;

  /// The relay-side knock TTL (spec §3.2) the UI counts down against.
  final Duration window;

  final SessionLauncher _launcher;
  final Uint8List _channelId;
  final Diag _diag;
  final Timer Function(Duration, void Function()) _timerFactory;
  final DateTime Function() _clock;
  final int _staleHintThreshold;

  KnockState _state = KnockState.idle;
  bool _staleHint = false;
  int _consecutiveLapses = 0;
  DateTime? _deadline;
  SessionController? _controller;
  StreamSubscription<ChatEvent>? _sub;
  Timer? _lapseTimer;

  KnockState get state => _state;

  /// Whether to surface the §6.1 stale-knock hint (string 16) — a local
  /// heuristic after repeated unanswered knocks. NO wire signal, no attribution.
  bool get staleHint => _staleHint;

  /// The moment the current knock lapses (for the F5 countdown), or null when
  /// not waiting. The widget ticks against it; the controller holds no periodic
  /// timer.
  DateTime? get deadline => _deadline;

  /// The live/engaged controller once a knock is answered — the chat surface
  /// and the reconnect_coordinator adopt it.
  SessionController? get controller => _controller;

  /// Sends the ONE knock and opens the 60 s waiting window. No-op while already
  /// waiting or live (one live knock at a time — writing more joins the outbox,
  /// never a second knock).
  Future<void> knock() async {
    if (_state == KnockState.waiting || _state == KnockState.live) {
      return;
    }
    await _teardownController();
    final controller = _launcher.build(_channelId, role: SessionRole.knocker);
    _controller = controller;
    _sub = controller.events.listen(_onEvent);
    _state = KnockState.waiting;
    _deadline = _clock().add(window);
    _lapseTimer = _timerFactory(window, _onLapse);
    notifyListeners();
    await controller.start(
      knockPushPayload: _launcher.knockPayloadFor(_channelId),
    );
  }

  /// The manual "Knock again" (string 6) — only meaningful after a lapse; a
  /// deliberate human re-knock, never automatic.
  Future<void> knockAgain() => knock();

  void _onEvent(ChatEvent event) {
    if (event is LineStateChanged &&
        event.state == SessionLineState.live &&
        _state == KnockState.waiting) {
      _lapseTimer?.cancel();
      _lapseTimer = null;
      _deadline = null;
      _consecutiveLapses = 0;
      _staleHint = false;
      _state = KnockState.live;
      notifyListeners();
      return;
    }
    // A terminal outcome while still waiting (socket died mid-knock, or a
    // protocol error) reads as a lapse — "No answer.", never an attribution.
    if (event is SessionEnded && _state == KnockState.waiting) {
      _onLapse();
    }
  }

  void _onLapse() {
    if (_state != KnockState.waiting) {
      return;
    }
    _lapseTimer?.cancel();
    _lapseTimer = null;
    _deadline = null;
    _diag.log(DiagEvent.knockLapsed);
    unawaited(_teardownController());
    _consecutiveLapses++;
    if (_consecutiveLapses >= _staleHintThreshold) {
      _staleHint = true;
    }
    _state = KnockState.lapsed;
    notifyListeners();
  }

  Future<void> _teardownController() async {
    await _sub?.cancel();
    _sub = null;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  @override
  void dispose() {
    _lapseTimer?.cancel();
    unawaited(_teardownController());
    super.dispose();
  }
}
