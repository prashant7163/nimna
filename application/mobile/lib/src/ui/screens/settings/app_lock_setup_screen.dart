import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/app_scope.dart';
import '../../../lock/lock_config_store.dart';
import '../../theme/nimna_tokens.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/nimna_toggle.dart';
import '../../widgets/pin_pad.dart';

/// F8.2 — App-lock setup.
///
/// Lock off: Choose a PIN → confirm (same frame pattern) → enrolled with
/// the biometric toggle's state (ships ON when hardware exists — spec §6
/// strongly recommended; row hidden without hardware). Lock on: the
/// current PIN gates everything (F8.2 edge), then the biometric toggle
/// and Turn off are offered. `‹` at any point → no lock change, no
/// scolding. The no-recovery consequence is stated at setup time.
class AppLockSetupScreen extends StatefulWidget {
  const AppLockSetupScreen({super.key});

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

enum _Stage { choose, confirm, verify, manage }

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  _Stage? _stage;
  String _entered = '';
  String _chosenPin = '';
  String _verifiedPin = '';
  bool _mismatch = false;
  bool _biometricAvailable = false;
  bool _biometricToggle = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stage == null) {
      final lock = AppScope.of(context).lockController;
      _stage = lock.enabled ? _Stage.verify : _Stage.choose;
      _biometricToggle = lock.biometricEnabled;
      lock.biometricAvailable().then((available) {
        if (mounted) {
          setState(() {
            _biometricAvailable = available;
            // Recommended-on posture (spec §6) — only in the setup flow.
            if (!lock.enabled) {
              _biometricToggle = available;
            }
          });
        }
      });
    }
  }

  Future<void> _onDigit(String digit) async {
    if (_busy || _entered.length >= LockConfig.pinLengthMax) {
      return;
    }
    setState(() {
      _entered += digit;
      _mismatch = false;
    });
    final lock = AppScope.of(context).lockController;
    switch (_stage!) {
      case _Stage.choose:
        break; // Advances via Next (the pad accepts 4-8 digits).
      case _Stage.confirm:
        if (_entered.length == _chosenPin.length) {
          if (_entered == _chosenPin) {
            setState(() => _busy = true);
            await lock.enableLock(
              pin: _chosenPin,
              biometricEnabled: _biometricAvailable && _biometricToggle,
            );
            if (mounted) {
              Navigator.of(context).maybePop();
            }
          } else {
            setState(() {
              _mismatch = true;
              _stage = _Stage.choose;
              _entered = '';
              _chosenPin = '';
            });
          }
        }
      case _Stage.verify:
        if (_entered.length == lock.pinLength) {
          final pin = _entered;
          setState(() => _busy = true);
          final ok = await lock.confirmPin(pin);
          if (!mounted) {
            return;
          }
          setState(() {
            _busy = false;
            _entered = '';
            if (ok) {
              _verifiedPin = pin;
              _stage = _Stage.manage;
            }
          });
        }
      case _Stage.manage:
        break;
    }
  }

  void _onBackspace() {
    if (_entered.isNotEmpty) {
      setState(() => _entered = _entered.substring(0, _entered.length - 1));
    }
  }

  void _onNext() {
    setState(() {
      _chosenPin = _entered;
      _entered = '';
      _stage = _Stage.confirm;
    });
  }

  Future<void> _turnOff() async {
    final lock = AppScope.of(context).lockController;
    setState(() => _busy = true);
    final ok = await lock.disableLock(pin: _verifiedPin);
    if (mounted) {
      if (ok) {
        Navigator.of(context).maybePop();
      } else {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    final lock = AppScope.of(context).lockController;
    final stage = _stage ?? _Stage.choose;

    final showsPad = stage != _Stage.manage;
    final dotCount = switch (stage) {
      _Stage.choose =>
        _entered.length > 6 ? _entered.length : 6, // 6 shown, accepts 4-8
      _Stage.confirm => _chosenPin.length,
      _Stage.verify => lock.pinLength,
      _Stage.manage => 0,
    };
    final title = switch (stage) {
      _Stage.choose => l10n.lock_choosePinTitle,
      _Stage.confirm => l10n.lock_confirmPinTitle,
      _Stage.verify => l10n.lock_enterPinTitle,
      _Stage.manage => l10n.settings_rowAppLock,
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NimnaNavBar(title: l10n.settings_rowAppLock),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Text(title, style: text.titleMedium),
                    if (stage == _Stage.choose) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.lock_choosePinCaption,
                        style: text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                    if (_mismatch) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.lock_confirmPinMismatch,
                        style: text.bodySmall?.copyWith(color: tokens.danger),
                      ),
                    ],
                    if (showsPad) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: PinDots(
                          count: dotCount,
                          filled: _entered.length,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: PinPad(
                          enabled: !_busy && lock.padArmed,
                          onDigit: _onDigit,
                          onBackspace: _onBackspace,
                          backspaceLabel: l10n.lock_keypadDeleteA11y,
                        ),
                      ),
                      if (stage == _Stage.choose) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: tokens.textSecondary,
                          ),
                          onPressed: _entered.length >= LockConfig.pinLengthMin
                              ? _onNext
                              : null,
                          child: Text(l10n.lock_actionNext),
                        ),
                      ],
                    ],
                    if ((stage == _Stage.choose || stage == _Stage.manage) &&
                        _biometricAvailable) ...[
                      const SizedBox(height: 16),
                      _BiometricRow(
                        value: _biometricToggle,
                        onChanged: _busy
                            ? null
                            : (value) async {
                                setState(() => _biometricToggle = value);
                                if (stage == _Stage.manage) {
                                  await lock.setBiometricEnabled(value);
                                }
                              },
                      ),
                    ],
                    if (stage == _Stage.manage) ...[
                      const SizedBox(height: 24),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.danger,
                        ),
                        onPressed: _busy ? null : _turnOff,
                        child: Text(l10n.lock_actionTurnOff),
                      ),
                    ],
                    const SizedBox(height: 32),
                    Text(
                      l10n.lock_noRecoveryCaption,
                      style: text.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// F8.2 biometric toggle row: label + caption + design-system toggle.
class _BiometricRow extends StatelessWidget {
  const _BiometricRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.lock_biometricToggleLabel, style: text.labelLarge),
              const SizedBox(height: 2),
              Text(
                l10n.lock_biometricToggleCaption,
                style: text.bodySmall?.copyWith(color: tokens.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        NimnaToggle(value: value, onChanged: onChanged),
      ],
    );
  }
}
