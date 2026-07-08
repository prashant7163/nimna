import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/transitions.dart';
import '../../presence/incoming_knock_controller.dart';
import '../../session/chat/chat_screen.dart';
import '../../session/connection/session_controller.dart';
import '../../session/model/chat_event.dart';
import '../theme/nimna_tokens.dart';

/// Route arguments for the F6 knock screen — the engaged session that surfaced
/// the incoming knock and the channel's local label.
class KnockScreenArgs {
  const KnockScreenArgs({required this.session, required this.label});

  final SessionController session;
  final String label;
}

/// F6.3 — the full-screen "incoming call" the push-tap route lands on (spec
/// §3.2.2; designs/screens/06-knock-received.html). The app opens INTO a live
/// knock: label + "is knocking." + a countdown of the knock's remaining life,
/// and two verbs — Pick up / Ignore.
///
///  - Pick up → ACCEPT → the line goes live → the chat takes over (F5).
///  - Ignore → SILENCE: no wire signal, nothing recorded; the peer only ever
///    observes silence and the relay expires the pending knock at 60 s. No
///    "missed knock" list exists anywhere (that would be stored state).
///
/// Every string is ARB-sourced; the label is local user data; no hardcoded
/// left/right. The countdown is attribution-neutral — it states only time.
class KnockReceivedScreen extends StatefulWidget {
  const KnockReceivedScreen({
    required this.session,
    required this.label,
    this.window = const Duration(seconds: 60),
    super.key,
  });

  final SessionController session;
  final String label;

  /// The knock's relay-side lifetime (spec §3.2, 60 s) the countdown runs
  /// against. Injectable for tests.
  final Duration window;

  @override
  State<KnockReceivedScreen> createState() => _KnockReceivedScreenState();
}

class _KnockReceivedScreenState extends State<KnockReceivedScreen> {
  late final IncomingKnockController _knock;
  StreamSubscription<ChatEvent>? _sub;
  Timer? _tick;
  late DateTime _deadline;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _knock = IncomingKnockController(controller: widget.session);
    _knock.addListener(_onKnock);
    _sub = widget.session.events.listen(_onEvent);
    _deadline = DateTime.now().add(widget.window);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _knock.removeListener(_onKnock);
    unawaited(_sub?.cancel());
    _tick?.cancel();
    _knock.dispose();
    super.dispose();
  }

  void _onEvent(ChatEvent event) {
    if (event is LineStateChanged &&
        event.state == SessionLineState.live &&
        !_navigated &&
        mounted) {
      // Picked up (here) → the line is live: hand off to the chat surface.
      _navigated = true;
      Navigator.of(context).pushReplacement(
        NimnaPageRoute<void>(
          builder: (_) =>
              ChatScreen(controller: widget.session, label: widget.label),
        ),
      );
    }
  }

  void _onKnock() {
    // The knock lapsed (self-dismiss at 60 s) without a pick-up: leave quietly,
    // back to wherever the user came from (F6 ignore/lapse both = silence).
    if (!_knock.knocking && !_navigated && mounted) {
      Navigator.of(context).maybePop();
    } else if (mounted) {
      setState(() {});
    }
  }

  int get _remaining {
    final secs = _deadline.difference(DateTime.now()).inSeconds;
    return secs < 0 ? 0 : secs;
  }

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
                widget.label,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: NimnaSpacing.base * 6),
              Container(height: NimnaLine.thickness, color: tokens.lineLive),
              const SizedBox(height: NimnaSpacing.base * 3),
              Text(
                l10n.knock_incomingKnocking(widget.label),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: NimnaSpacing.base),
              Text(
                l10n.knock_lapsesInSeconds(_remaining),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: tokens.textTertiary),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => unawaited(_knock.pickUp()),
                child: Text(l10n.knock_pickUp),
              ),
              const SizedBox(height: NimnaSpacing.base * 2),
              TextButton(
                onPressed: () {
                  final navigator = Navigator.of(context);
                  unawaited(_knock.ignore().then((_) => navigator.maybePop()));
                },
                child: Text(l10n.knock_ignore),
              ),
              const SizedBox(height: NimnaSpacing.base * 6),
            ],
          ),
        ),
      ),
    );
  }
}
