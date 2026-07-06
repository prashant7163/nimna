import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/nimna_tokens.dart';

/// The Destructive-hold button (components.md; USER 2026-07-03 21:32):
/// fill `dangerFill`, text `onDanger`; a darker burn overlay grows from
/// the start edge while held (screens.css `.btn.hold .burn`); haptic ticks
/// ride the burn, heavy impact on completion (flutter-notes). Durations
/// are the token values — 1.5 s per-channel, 2.5 s full wipe.
///
/// RELEASE CANCELS — nothing happens, ever partially: [onComplete] fires
/// exactly once, only when the hold reaches the full duration; any earlier
/// release or interruption (call, banner → gesture cancel) snaps the track
/// back and invokes nothing. The 480 ms completion fade (`wipeCut`) plays
/// after firing; input is dead from that moment.
class DestructiveHoldButton extends StatefulWidget {
  const DestructiveHoldButton({
    required this.label,
    required this.holdDuration,
    required this.onComplete,
    super.key,
  });

  final String label;
  final Duration holdDuration;
  final VoidCallback onComplete;

  @override
  State<DestructiveHoldButton> createState() => _DestructiveHoldButtonState();
}

class _DestructiveHoldButtonState extends State<DestructiveHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _fired = false;
  int _lastTickQuarter = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    );
    _controller.addListener(_onProgress);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onProgress() {
    // Haptic tick with the burn (F7.3), at each quarter crossed.
    final quarter = (_controller.value * 4).floor();
    if (quarter > _lastTickQuarter && quarter < 4 && !_fired) {
      _lastTickQuarter = quarter;
      HapticFeedback.selectionClick();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_fired) {
      _fired = true;
      HapticFeedback.heavyImpact();
      setState(() {});
      widget.onComplete();
    }
  }

  void _startHold(TapDownDetails _) {
    if (_fired) {
      return;
    }
    _lastTickQuarter = 0;
    HapticFeedback.selectionClick();
    _controller.forward(from: 0);
  }

  void _cancelHold() {
    if (_fired) {
      return;
    }
    // Release before completion → cancel; the bar snaps back (F7.3).
    _controller.stop();
    _controller.animateBack(0, duration: NimnaMotion.micro);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _fired ? null : _startHold,
        onTapUp: (_) => _cancelHold(),
        onTapCancel: _cancelHold,
        child: AnimatedOpacity(
          // Completion animation (480 ms, once) — the button dies with
          // the content it destroyed.
          opacity: _fired ? 0.4 : 1,
          duration: NimnaMotion.wipeCut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NimnaRadius.medium),
            child: Container(
              height: 52,
              color: tokens.dangerFill,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: _controller.value,
                        heightFactor: 1,
                        child: const ColoredBox(
                          color: NimnaEffects.holdBurnOverlay,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      widget.label,
                      style: NimnaText.label.copyWith(color: tokens.onDanger),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
