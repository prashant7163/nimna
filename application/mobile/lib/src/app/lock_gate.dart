import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../lock/lock_controller.dart';
import '../storage/keys/key_service.dart';
import '../ui/theme/nimna_tokens.dart';
import '../ui/widgets/nimna_symbol.dart';
import '../ui/widgets/pin_pad.dart';
import 'theme.dart';

/// The app-lock perimeter widget (app-architecture.md §3): sits ABOVE the
/// Navigator and *replaces the entire subtree* while the KeyService is
/// sealed — the zero-leak rule (DECISIONS 2026-07-03): never a route
/// stacked above content, no blur over live widgets, nothing to leak.
///
/// S13 (amendment foreseen by S7 §3): the sealed surface becomes screen 12
/// — symbol + PIN dots + PIN pad, biometric auto-prompt when enabled. When
/// lock is DISABLED the sealed surface stays the bare brand surface (it
/// only appears transiently at boot). The subtree-replacement mechanics
/// are untouched.
class LockGate extends StatelessWidget {
  const LockGate({
    required this.keyService,
    required this.lockController,
    required this.child,
    super.key,
  });

  final KeyService keyService;
  final LockController lockController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([keyService, lockController]),
      builder: (context, _) {
        if (keyService.sealed) {
          // MaterialApp.builder contexts sit outside the app theme; give
          // the sealed subtree its own token-correct Theme so the lock
          // surface renders identically to the rest of the app.
          final brightness = MediaQuery.platformBrightnessOf(context);
          return Theme(
            data: nimnaTheme(brightness),
            child: lockController.enabled
                ? _LockScreen(controller: lockController)
                : const _SealedSurface(),
          );
        }
        return child;
      },
    );
  }
}

/// The lock-disabled sealed state leaks nothing: a bare brand surface.
class _SealedSurface extends StatelessWidget {
  const _SealedSurface();

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<NimnaTokens>() ?? NimnaTokens.dark;
    return ColoredBox(color: tokens.surface0, child: const SizedBox.expand());
  }
}

/// Screen 12 — locked. Only the symbol and the pad; no copy, no counts,
/// not even how many lines you have (F8.2's own promise). One dot per
/// enrolled PIN digit; a full row auto-submits. Biometric auto-prompts on
/// appearance and again on each return to `resumed` while still sealed;
/// the pad is always the fallback.
class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.controller});

  final LockController controller;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> with WidgetsBindingObserver {
  String _entered = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptBiometric());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _promptBiometric();
    }
  }

  void _promptBiometric() {
    if (!mounted || !widget.controller.biometricEnabled) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return;
    }
    // The controller guards re-entrancy and the already-open case.
    widget.controller.tryBiometric(reason: l10n.lock_biometricPromptReason);
  }

  Future<void> _onDigit(String digit) async {
    if (_entered.length >= widget.controller.pinLength) {
      return;
    }
    setState(() => _entered += digit);
    if (_entered.length == widget.controller.pinLength) {
      final pin = _entered;
      final ok = await widget.controller.submitPin(pin);
      if (!ok && mounted) {
        setState(() => _entered = '');
      }
      // On success the gate flips via the KeyService listenable.
    }
  }

  void _onBackspace() {
    if (_entered.isNotEmpty) {
      setState(() => _entered = _entered.substring(0, _entered.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    final controller = widget.controller;

    return Material(
      color: tokens.surface0,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NimnaSymbol(tokens: tokens),
                const SizedBox(height: 56),
                PinDots(count: controller.pinLength, filled: _entered.length),
                const SizedBox(height: 56),
                PinPad(
                  enabled: controller.padArmed,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  backspaceLabel: l10n.lock_keypadDeleteA11y,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
