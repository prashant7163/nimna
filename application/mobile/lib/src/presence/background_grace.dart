/// The ~30 s background-grace window (spec §3.3) — CLIENT-SIDE ONLY.
///
/// When the app is backgrounded the live socket is held for a short grace so a
/// brief app-switch does not tear the line down (an inbound message/knock in
/// the window lands as if foregrounded). Foregrounding cancels it silently;
/// on expiry the session is closed (the caller's [onExpired] calls
/// [SessionController.dispose], whose socket close IS an implicit TEARDOWN,
/// §5.4). There is NO relay state and NO VoIP/background-audio socket
/// extension (review-fatal, §3.3): after grace, re-entry is a fresh
/// knock→(push)→reconnect, never a resumed session.
///
/// Pure Dart, locale-independent. The clock is the injected [Timer] factory so
/// tests drive the window deterministically.
library;

import 'dart:async';

import '../diag/diag.dart';
import '../diag/diag_events.dart';

class BackgroundGrace {
  BackgroundGrace({
    required this.onExpired,
    required Diag diag,
    this.window = const Duration(seconds: 30),
    Timer Function(Duration, void Function())? timerFactory,
  }) : _diag = diag, // ignore: prefer_initializing_formals
       _timerFactory = timerFactory ?? Timer.new;

  /// Called once, when the grace window closes with the app still backgrounded.
  final void Function() onExpired;

  /// The grace length (~30 s; spec §3.3).
  final Duration window;

  final Diag _diag;
  final Timer Function(Duration, void Function()) _timerFactory;
  Timer? _timer;

  /// Whether a grace window is currently running.
  bool get pending => _timer != null;

  /// Backgrounded: start (or restart) the grace window.
  void onBackground() {
    _timer?.cancel();
    _timer = _timerFactory(window, _fire);
  }

  /// Foregrounded within the window: cancel silently — nothing logged, no
  /// callback (the session simply stays live).
  void onForeground() {
    _timer?.cancel();
    _timer = null;
  }

  void _fire() {
    _timer = null;
    _diag.log(DiagEvent.backgroundGraceExpired);
    onExpired();
  }

  /// Cancels any pending window without firing (e.g. the session ended by
  /// another path).
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
