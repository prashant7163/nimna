/// S16 — the FOREGROUND presence-mount coordinator for ONE open line
/// (spec §3.2–§3.4). It owns exactly ONE live [SessionController] at a time and
/// maps the pure, S8–S12-tested presence controllers (knock / incoming-knock /
/// reconnect) → the screens and ARB copy. No protocol logic lives here; it is
/// composition only — the codec is frozen.
///
/// Trigger = OPENING a line (an F4 row tap), NOT foregrounding. On open the
/// coordinator connects as an [SessionRole.accepter] and sits LISTENING
/// (REGISTER_CRID → `connecting`), which is what makes this device receivable,
/// and renders the F5 "Not on the line" surface with a Knock affordance. From
/// there it drives the two postures spec §3.2 allows (either side may knock):
///
///  - Human presses Knock → the listening connection is disposed FIRST (the
///    one-CRID-per-device invariant), then [KnockController] builds a fresh
///    knocker that REGISTER_CRIDs + sends the ONE knock → screen 11 waiting;
///    a lapse settles to "No answer." + a manual "Knock again" (never auto).
///  - A KNOCK_FWD arrives on the listening connection → [IncomingKnock] → the
///    F6 pick-up surface → an EXPLICIT human pick-up → ACCEPT → bridge → live.
///    There is NO auto-ACCEPT (receiver deniability, N-3 boundary).
///
/// On live, the same controller is adopted into a [ReconnectCoordinator] and
/// handed to the chat body; a bounded ~20 s live-drop recovery renders the
/// three reconnect captions and, on exhaustion, settles back to F5.1 (a fresh
/// knock is offered, not fired).
///
/// PRESENCE SCOPE — the single opened line only. You receive an in-app knock
/// only while you have that specific line open and the app foregrounded (or
/// within the ~30 s background grace). A knock to a line you don't have open,
/// or a backgrounded app past grace, does not surface in-app — that's the
/// content-free push-wake path, device-deferred to S18/PUBLISH_READY.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../diag/diag.dart';
import '../../presence/incoming_knock_controller.dart';
import '../../presence/knock_controller.dart';
import '../../presence/reconnect_coordinator.dart';
import '../../presence/session_launcher.dart';
import '../../screenshot/screenshot_detector.dart';
import '../../sensitive/sensitive_content_analyzer.dart';
import '../../ui/theme/nimna_tokens.dart';
import '../connection/session_controller.dart';
import '../model/chat_event.dart';
import 'chat_screen.dart';

/// Route arguments for [LinePresence] — the channel to open and its local
/// label. The route builder resolves the production launcher + diag from
/// `AppScope`; the caller (an F4 row tap) supplies only channel identity.
class LinePresenceArgs {
  const LinePresenceArgs({required this.channelId, required this.label});

  final Uint8List channelId;
  final String label;
}

/// The current presence posture for the one open line.
enum LinePosture { listening, knocking, incoming, live }

class LinePresence extends StatefulWidget {
  const LinePresence({
    required this.launcher,
    required this.diag,
    required this.channelId,
    required this.label,
    this.knockWindow = const Duration(seconds: 60),
    this.screenshotDetector,
    this.sensitiveAnalyzer,
    super.key,
  });

  /// The production session factory (resolved from `AppScope` at the F4 row
  /// tap). A fresh launcher is bound to the currently-open repositories.
  final SessionLauncher launcher;
  final Diag diag;
  final Uint8List channelId;

  /// The channel's local label — the only user data the surfaces show.
  final String label;

  /// The relay-side knock TTL (spec §3.2, 60 s); the incoming-knock countdown
  /// and the knock controller run against it. Injectable for tests.
  final Duration knockWindow;

  /// S14 seams forwarded to every [ChatScreen] this coordinator builds — tests
  /// inject fakes (no platform channel); production uses the platform defaults.
  final ScreenshotDetector? screenshotDetector;
  final SensitiveContentAnalyzer? sensitiveAnalyzer;

  @override
  State<LinePresence> createState() => _LinePresenceState();
}

class _LinePresenceState extends State<LinePresence> {
  late final KnockController _knock;

  // The receivable accepter connection (F5 listening). Non-null except while a
  // knock is in flight or the line is live via our own knock.
  SessionController? _listening;
  StreamSubscription<ChatEvent>? _listeningSub;
  IncomingKnockController? _incoming;

  // The live line (once bridged) + its recovery coordinator.
  SessionController? _liveController;
  StreamSubscription<ChatEvent>? _liveSub;
  ReconnectCoordinator? _reconnect;
  StreamSubscription<ReconnectPhase>? _phaseSub;
  ReconnectPhase _phase = ReconnectPhase.idle;

  LinePosture _posture = LinePosture.listening;
  bool _showNoAnswer = false;

  // F6 countdown anchor (the incoming knock's remaining life at the relay). The
  // inline surface renders the remaining seconds computed at build time — no
  // self-scheduled ticker here (the standalone push-tap KnockReceivedScreen
  // owns the animated countdown for that path); a rebuild refreshes it.
  DateTime? _incomingDeadline;

  @override
  void initState() {
    super.initState();
    _knock = KnockController(
      launcher: widget.launcher,
      channelId: widget.channelId,
      diag: widget.diag,
      window: widget.knockWindow,
    )..addListener(_onKnockChanged);
    _buildListening();
    // start() is deferred one frame so the first build renders synchronously
    // and no setState runs during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_listening?.start());
    });
  }

  // ---- listening (accepter) -------------------------------------------------

  void _buildListening() {
    final controller = widget.launcher.build(
      widget.channelId,
      role: SessionRole.accepter,
    );
    _listening = controller;
    _listeningSub = controller.events.listen(_onListeningEvent);
    _incoming = IncomingKnockController(controller: controller)
      ..addListener(_onIncomingChanged);
    _posture = LinePosture.listening;
  }

  Future<void> _restartListening() async {
    _buildListening();
    if (mounted) {
      setState(() {});
    }
    await _listening?.start();
  }

  Future<void> _disposeListening() async {
    await _listeningSub?.cancel();
    _listeningSub = null;
    _incoming?.removeListener(_onIncomingChanged);
    _incoming?.dispose();
    _incoming = null;
    final listener = _listening;
    _listening = null;
    await listener?.dispose();
  }

  void _onListeningEvent(ChatEvent event) {
    if (!mounted) {
      return;
    }
    if (event is LineStateChanged && event.state == SessionLineState.live) {
      // A pick-up bridged this listening connection — it becomes the line.
      unawaited(_goLive(_listening!));
      return;
    }
    if (_posture == LinePosture.listening || _posture == LinePosture.incoming) {
      setState(() {});
    }
  }

  // ---- outgoing knock -------------------------------------------------------

  /// The human pressed Knock (F5.1) or Knock again (F5.13). Disposes the
  /// listening connection FIRST — the CRID is never registered on two live
  /// connections from one device — then hands to the knock controller.
  Future<void> _handleKnock() async {
    _showNoAnswer = false;
    await _disposeListening();
    await _knock.knock();
  }

  void _onKnockChanged() {
    if (!mounted) {
      return;
    }
    switch (_knock.state) {
      case KnockState.waiting:
        setState(() => _posture = LinePosture.knocking);
      case KnockState.live:
        unawaited(_goLive(_knock.controller!));
      case KnockState.lapsed:
        unawaited(_onLapsed());
      case KnockState.idle:
        break;
    }
  }

  /// The knock's 60 s window closed unanswered (F5.13). Re-open a listening
  /// connection so the line stays receivable, and surface "No answer.".
  Future<void> _onLapsed() async {
    _showNoAnswer = true;
    await _restartListening();
  }

  // ---- incoming knock (F6) --------------------------------------------------

  void _onIncomingChanged() {
    if (!mounted) {
      return;
    }
    final knocking = _incoming?.knocking ?? false;
    if (knocking) {
      _incomingDeadline ??= DateTime.now().add(widget.knockWindow);
      setState(() => _posture = LinePosture.incoming);
      return;
    }
    // No longer knocking. A pick-up settles to live via _onListeningEvent while
    // the connection is `connecting`; otherwise (ignore / self-dismiss) fall
    // back to the plain listening surface.
    _incomingDeadline = null;
    if (_posture == LinePosture.incoming) {
      final state = _listening?.lineState;
      if (state == SessionLineState.connecting ||
          state == SessionLineState.live) {
        return; // pick-up in flight; _onListeningEvent drives it to live.
      }
      setState(() => _posture = LinePosture.listening);
    }
  }

  // ---- live + reconnect -----------------------------------------------------

  Future<void> _goLive(SessionController controller) async {
    if (_posture == LinePosture.live) {
      return;
    }
    _posture = LinePosture.live;
    _showNoAnswer = false;
    _incomingDeadline = null;
    // Drop the listening WRAPPER without disposing its controller — it may BE
    // this live controller (an incoming pick-up). If we went live via our own
    // knock, _listening was already disposed in _handleKnock.
    _incoming?.removeListener(_onIncomingChanged);
    _incoming?.dispose();
    _incoming = null;
    await _listeningSub?.cancel();
    _listeningSub = null;
    _listening = null;

    _liveController = controller;
    _reconnect = ReconnectCoordinator(
      rebuild: (seed) => widget.launcher.build(
        widget.channelId,
        role: SessionRole.knocker,
        seedPendingReactions: seed,
      ),
      knockPayload: () => widget.launcher.knockPayloadFor(widget.channelId),
      diag: widget.diag,
    )..adopt(controller);
    _phaseSub = _reconnect!.phases.listen(_onPhase);
    await _followLive(controller);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _followLive(SessionController controller) async {
    await _liveSub?.cancel();
    _liveSub = controller.events.listen(_onLiveEvent);
  }

  void _onLiveEvent(ChatEvent event) {
    if (!mounted) {
      return;
    }
    if (event is SessionEnded && event.reason == SessionEndReason.ended) {
      // An authenticated HANGUP (either side, F5.12) — the line ended; return
      // to the receivable listening surface. (A connectionLost while live is
      // owned by the reconnect coordinator, not handled here.)
      unawaited(_returnToListening());
      return;
    }
    setState(() {});
  }

  void _onPhase(ReconnectPhase phase) {
    if (!mounted) {
      return;
    }
    _phase = phase;
    if (phase == ReconnectPhase.recovered) {
      final fresh = _reconnect?.controller;
      if (fresh != null) {
        unawaited(_followLive(fresh));
      }
    } else if (phase == ReconnectPhase.lost) {
      // F5.15 — recovery exhausted: settle back to F5.1 offline. A fresh knock
      // is offered, not fired automatically (spec §4).
      unawaited(_returnToListening());
      return;
    }
    setState(() {});
  }

  Future<void> _returnToListening() async {
    _showNoAnswer = false;
    _phase = ReconnectPhase.idle;
    await _liveSub?.cancel();
    _liveSub = null;
    await _phaseSub?.cancel();
    _phaseSub = null;
    await _reconnect?.dispose(); // disposes the live controller
    _reconnect = null;
    _liveController = null;
    await _restartListening();
  }

  @override
  void dispose() {
    _knock.removeListener(_onKnockChanged);
    _incoming?.removeListener(_onIncomingChanged);
    unawaited(_listeningSub?.cancel());
    unawaited(_liveSub?.cancel());
    unawaited(_phaseSub?.cancel());
    _incoming?.dispose();
    _knock
        .dispose(); // disposes its knocker controller (idempotent double-free)
    unawaited(_reconnect?.dispose());
    unawaited(_listening?.dispose());
    super.dispose();
  }

  // ---- rendering ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    switch (_posture) {
      case LinePosture.incoming:
        return _incomingKnockSurface();
      case LinePosture.knocking:
        final controller = _knock.controller;
        if (controller == null) {
          return _listeningSurface();
        }
        return ChatScreen(
          controller: controller,
          label: widget.label,
          autoStart: false,
          knockDeadline: _knock.deadline,
          screenshotDetector: widget.screenshotDetector,
          sensitiveAnalyzer: widget.sensitiveAnalyzer,
        );
      case LinePosture.live:
        final controller = _reconnect?.controller ?? _liveController;
        if (controller == null) {
          return _listeningSurface();
        }
        return ChatScreen(
          controller: controller,
          label: widget.label,
          autoStart: false,
          reconnectPhase: _phase,
          screenshotDetector: widget.screenshotDetector,
          sensitiveAnalyzer: widget.sensitiveAnalyzer,
        );
      case LinePosture.listening:
        return _listeningSurface();
    }
  }

  Widget _listeningSurface() {
    final controller = _listening;
    if (controller == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return ChatScreen(
      controller: controller,
      label: widget.label,
      autoStart: false,
      onKnock: () => unawaited(_handleKnock()),
      knockLapsed: _showNoAnswer,
      knockStaleHint: _knock.staleHint,
      screenshotDetector: widget.screenshotDetector,
      sensitiveAnalyzer: widget.sensitiveAnalyzer,
    );
  }

  Widget _incomingKnockSurface() {
    final remaining = _incomingDeadline == null
        ? widget.knockWindow.inSeconds
        : _incomingDeadline!.difference(DateTime.now()).inSeconds;
    return IncomingKnockView(
      label: widget.label,
      remainingSeconds: remaining < 0 ? 0 : remaining,
      onPickUp: () => unawaited(_incoming?.pickUp() ?? Future.value()),
      onIgnore: () => unawaited(_incoming?.ignore() ?? Future.value()),
    );
  }
}

/// F6.3 — the in-app incoming-knock surface (spec §3.2.2; screens/06). Label +
/// "is knocking." + the knock's remaining life, and two verbs. Pick up →
/// ACCEPT → live; Ignore → silence (no wire signal, nothing recorded). A pure
/// stateless view (no controller/DB) so it renders under a plain widget test;
/// [LinePresence] wires it to the IncomingKnockController and presence_flow_test
/// proves the KNOCK_FWD → IncomingKnock → explicit-pick-up-only behaviour.
class IncomingKnockView extends StatelessWidget {
  const IncomingKnockView({
    required this.label,
    required this.remainingSeconds,
    required this.onPickUp,
    required this.onIgnore,
    super.key,
  });

  final String label;
  final int remainingSeconds;
  final VoidCallback onPickUp;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: tokens.surface0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.screenMargin,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: NimnaSpacing.base * 24),
              Text(
                label,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: NimnaSpacing.base * 6),
              Container(height: NimnaLine.thickness, color: tokens.lineLive),
              const SizedBox(height: NimnaSpacing.base * 3),
              Text(
                l10n.knock_incomingKnocking(label),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: NimnaSpacing.base),
              Text(
                l10n.knock_lapsesInSeconds(remainingSeconds),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: tokens.textTertiary),
              ),
              const Spacer(),
              FilledButton(onPressed: onPickUp, child: Text(l10n.knock_pickUp)),
              const SizedBox(height: NimnaSpacing.base * 2),
              TextButton(onPressed: onIgnore, child: Text(l10n.knock_ignore)),
              const SizedBox(height: NimnaSpacing.base * 6),
            ],
          ),
        ),
      ),
    );
  }
}
