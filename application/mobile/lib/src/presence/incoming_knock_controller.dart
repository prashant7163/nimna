/// Receiving-knock UX (F6, spec §3.2.2 peer-online branch).
///
/// Watches an engaged channel's controller for an [IncomingKnock] and drives
/// the in-app banner / knock screen: a label + "is knocking." + two verbs
/// (Pick up / Ignore), auto-dismissing at 60 s. Pick up →
/// [SessionController.acceptKnock] (ACCEPT → bridge → live). Ignore → drop:
/// nothing is recorded and NO wire signal is sent — the peer only ever
/// observes silence, and the relay expires the pending knock at 60 s (F6.1).
/// No "missed knock" list exists anywhere (that would be stored state).
///
/// A [ChangeNotifier]; the widget maps state → ARB copy ("{label} is
/// knocking.", Pick up, Ignore). Locale-independent logic.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../session/connection/session_controller.dart';
import '../session/model/chat_event.dart';

class IncomingKnockController extends ChangeNotifier {
  IncomingKnockController({
    required SessionController controller,
    this.autoDismiss = const Duration(seconds: 60),
    Timer Function(Duration, void Function())? timerFactory,
    // ignore: prefer_initializing_formals
  }) : _controller = controller,
       _timerFactory = timerFactory ?? Timer.new {
    _sub = _controller.events.listen(_onEvent);
    // A knock may already be pending if the controller surfaced it before this
    // banner subscribed.
    if (_controller.incomingKnockPending) {
      _raise();
    }
  }

  /// The banner's self-dismiss window (mirrors the relay-side knock TTL).
  final Duration autoDismiss;

  final SessionController _controller;
  final Timer Function(Duration, void Function()) _timerFactory;
  StreamSubscription<ChatEvent>? _sub;
  Timer? _dismissTimer;
  bool _knocking = false;

  /// Whether the banner is showing (a knock is live and un-answered).
  bool get knocking => _knocking;

  void _onEvent(ChatEvent event) {
    if (event is IncomingKnock) {
      _raise();
    } else if (event is LineStateChanged &&
        event.state == SessionLineState.live) {
      // Answered (here or elsewhere) — the banner's job is done.
      _clear();
    }
  }

  void _raise() {
    if (_knocking) {
      return;
    }
    _knocking = true;
    _dismissTimer?.cancel();
    _dismissTimer = _timerFactory(autoDismiss, _clear);
    notifyListeners();
  }

  /// F6 pick-up → ACCEPT.
  Future<void> pickUp() async {
    if (!_knocking) {
      return;
    }
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _knocking = false;
    notifyListeners();
    await _controller.acceptKnock();
  }

  /// F6 ignore → silent drop (no record, no wire signal).
  Future<void> ignore() async {
    if (!_knocking) {
      return;
    }
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _knocking = false;
    notifyListeners();
    await _controller.ignoreKnock();
  }

  void _clear() {
    if (!_knocking) {
      return;
    }
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _knocking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
