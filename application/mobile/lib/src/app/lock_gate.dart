import 'package:flutter/material.dart';

import '../storage/keys/key_service.dart';
import '../ui/theme/nimna_tokens.dart';

/// The app-lock perimeter widget (app-architecture.md §3): sits ABOVE the
/// Navigator and *replaces the entire subtree* while the KeyService is
/// sealed — the zero-leak rule (DECISIONS 2026-07-03): never a route
/// stacked above content, no blur over live widgets, nothing to leak.
///
/// S7 ships the structural gate (open() is unconditional at boot, so the
/// sealed surface only appears if the app seals at runtime); S13 puts
/// PIN/biometric UI on the sealed surface. Nothing else moves.
class LockGate extends StatelessWidget {
  const LockGate({required this.keyService, required this.child, super.key});

  final KeyService keyService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: keyService,
      builder: (context, _) {
        if (keyService.sealed) {
          return const _SealedSurface();
        }
        return child;
      },
    );
  }
}

/// The locked state leaks nothing: a bare brand surface (wireframe F4.2 —
/// symbol + PIN pad arrive with S13's lock UI).
class _SealedSurface extends StatelessWidget {
  const _SealedSurface();

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<NimnaTokens>() ?? NimnaTokens.dark;
    return ColoredBox(color: tokens.surface0, child: const SizedBox.expand());
  }
}
