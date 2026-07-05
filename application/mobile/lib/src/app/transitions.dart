import 'package:flutter/material.dart';

import '../ui/theme/nimna_tokens.dart';

/// Global page transition: fade + 8 px vertical drift, 320 ms decelerate
/// (designs/handoff/flutter-notes.md — Motion & platform hygiene). No
/// sideways pushes. Honors `MediaQuery.disableAnimations` by rendering the
/// child static.
class NimnaPageTransitionsBuilder extends PageTransitionsBuilder {
  const NimnaPageTransitionsBuilder();

  static const double _driftPx = 8;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: NimnaMotion.easeDecelerate,
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, staticChild) => Transform.translate(
          offset: Offset(0, _driftPx * (1 - curved.value)),
          child: staticChild,
        ),
        child: child,
      ),
    );
  }
}

/// Named route carrier applying the Nimna transition with the token
/// duration (MaterialPageRoute's default duration differs; routes are
/// generated through this everywhere).
class NimnaPageRoute<T> extends PageRouteBuilder<T> {
  NimnaPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: NimnaMotion.enter,
        reverseTransitionDuration: NimnaMotion.enter,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: NimnaMotion.easeDecelerate,
          );
          return FadeTransition(
            opacity: curved,
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, staticChild) => Transform.translate(
                offset: Offset(
                  0,
                  NimnaPageTransitionsBuilder._driftPx * (1 - curved.value),
                ),
                child: staticChild,
              ),
              child: child,
            ),
          );
        },
      );
}
