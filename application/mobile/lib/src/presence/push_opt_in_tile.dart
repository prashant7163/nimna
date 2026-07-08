/// The per-channel push opt-in row (F7, spec §3.2.1) — the minimal toggle +
/// its ALWAYS-VISIBLE honest trade (voice string 18). Per components.md the
/// caption IS the disclosure, never a one-time dialog: turning push on
/// re-states the same two lines, confirm-free. DEFAULT OFF; off is pure
/// burner-line mode (zero third-party touch).
///
/// A leaf widget — [enabled] + [onChanged] only; the mounting surface wires it
/// to [PushOptIn] (persistence). The full F7 channel-settings screen is S16;
/// this row is ready to drop into it (or any minimal surface) unchanged.
///
/// Every string is ARB-sourced (namespaced push_*); layout survives
/// German-length copy; no hardcoded left/right.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../ui/theme/nimna_tokens.dart';
import '../ui/widgets/nimna_toggle.dart';

class PushOptInTile extends StatelessWidget {
  const PushOptInTile({
    required this.enabled,
    required this.onChanged,
    this.hairline = true,
    super.key,
  });

  /// The channel's current opt-in (DEFAULT OFF).
  final bool enabled;

  /// Flip handler — the mount wires this to [PushOptIn.setEnabled].
  final ValueChanged<bool> onChanged;

  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final label = l10n.push_toggleLabel;
    // The two lines of string 18, always visible — the disclosure in place.
    final caption = '${l10n.push_tradeOff}\n${l10n.push_tradeOn}';
    return Semantics(
      container: true,
      toggled: enabled,
      label: label,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: NimnaSpacing.listRowSettings,
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: hairline
              ? Border(bottom: BorderSide(color: tokens.hairline))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: text.labelLarge?.copyWith(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: text.bodySmall?.copyWith(color: tokens.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            NimnaToggle(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
