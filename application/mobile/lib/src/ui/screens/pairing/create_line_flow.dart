import 'dart:async';

import 'package:flutter/material.dart';

import '../../../pairing/initiator/initiator_controller.dart';
import '../../../pairing/initiator/pairing_initiator_service.dart';
import '../../../pairing/initiator/pending_pairing.dart';
import '../../theme/nimna_tokens.dart';
import 'code_ended_screen.dart';
import 'create_code_setup_screen.dart';
import 'create_finalize_screen.dart';
import 'share_code_screen.dart';

/// The F2 initiator flow host: one route whose surface follows the
/// controller's phase — F2.2 and F2.4 are one screen, and F2.8 swaps in
/// place when the TTL lapses (wireframe annotations). Owns the controller
/// lifecycle and forwards app-lifecycle events (the ~30 s background
/// grace / resume re-register live in the controller).
class CreateLineFlow extends StatefulWidget {
  const CreateLineFlow({required this.pairing, this.resume, super.key});

  final PairingInitiatorService pairing;

  /// Relaunch path: a persisted pending pairing to adopt (F2.4 edge —
  /// reopening the app re-registers and the wait resumes; if it lapsed
  /// while away, F2.8).
  final PendingPairing? resume;

  @override
  State<CreateLineFlow> createState() => _CreateLineFlowState();
}

class _CreateLineFlowState extends State<CreateLineFlow>
    with WidgetsBindingObserver {
  late CreateLineController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.pairing.newController();
    _controller.addListener(_onPhase);
    final resume = widget.resume;
    if (resume != null) {
      unawaited(_controller.resume(resume));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onPhase);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _controller.onAppPaused();
      case AppLifecycleState.resumed:
        _controller.onAppResumed();
      default:
        break;
    }
  }

  void _onPhase() {
    final phase = _controller.phase;
    if (phase == CreateLinePhase.cancelled ||
        phase == CreateLinePhase.finalized) {
      // Cancel → F4 ("nothing was created"); finalized → F4, where the new
      // line now shows (F5 chat is one tap away — the first knock).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });
    }
    setState(() {});
  }

  /// F2.8 "Make a new code" → F2.1 with a fresh keypair and a fresh code.
  void _restart() {
    _controller.removeListener(_onPhase);
    _controller.dispose();
    setState(() {
      _controller = widget.pairing.newController()..addListener(_onPhase);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget surface = switch (_controller.phase) {
      CreateLinePhase.setup || CreateLinePhase.generating =>
        CreateCodeSetupScreen(controller: _controller),
      CreateLinePhase.waiting ||
      CreateLinePhase.bridged => ShareCodeScreen(controller: _controller),
      CreateLinePhase.verifying => CreateVerifyScreen(controller: _controller),
      CreateLinePhase.naming => CreateNameScreen(controller: _controller),
      CreateLinePhase.mismatch => CreateMismatchScreen(onMakeNewCode: _restart),
      CreateLinePhase.expired => CodeEndedScreen.expired(
        onMakeNewCode: _restart,
      ),
      CreateLinePhase.spent => CodeEndedScreen.spent(onMakeNewCode: _restart),
      CreateLinePhase.finalized ||
      CreateLinePhase.cancelled => const SizedBox.shrink(),
    };
    // Surface identity: F2.2/F2.4 (and the bridged hold) are ONE screen;
    // generating is still F2.1. Phase changes inside one surface must not
    // re-animate it.
    final surfaceKey = switch (_controller.phase) {
      CreateLinePhase.setup || CreateLinePhase.generating => 0,
      CreateLinePhase.waiting || CreateLinePhase.bridged => 1,
      CreateLinePhase.expired => 2,
      CreateLinePhase.spent => 3,
      CreateLinePhase.cancelled || CreateLinePhase.finalized => 4,
      CreateLinePhase.verifying => 5,
      CreateLinePhase.naming => 6,
      CreateLinePhase.mismatch => 7,
    };
    if (MediaQuery.disableAnimationsOf(context)) {
      return surface;
    }
    return AnimatedSwitcher(
      duration: NimnaMotion.enter,
      switchInCurve: NimnaMotion.easeDecelerate,
      switchOutCurve: NimnaMotion.easeDecelerate,
      child: KeyedSubtree(key: ValueKey(surfaceKey), child: surface),
    );
  }
}
