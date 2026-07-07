import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../pairing/joiner/join_entry/qr_source.dart';
import '../../../theme/nimna_tokens.dart';
import '../../../widgets/nimna_back_button.dart';

/// F3.2 · Scan QR — the in-person path (spec §3.1 method iii). Returns the
/// decoded [PairingCode] (via `Navigator.pop`) on a successful detect, or
/// null on "Enter it instead" / Back. A foreign or unreadable QR is ignored
/// (no error state — the brackets keep looking); camera-denied falls back to
/// manual entry with the F3.2 canonical note.
class JoinScanScreen extends StatelessWidget {
  const JoinScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: NimnaSpacing.listRowSettings,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: NimnaBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NimnaSpacing.screenMargin,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.pairing_joinScanTitle, style: text.titleLarge),
                  const SizedBox(height: NimnaSpacing.base * 2),
                  Text(
                    l10n.pairing_joinScanCaption,
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NimnaSpacing.base * 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NimnaSpacing.screenMargin,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NimnaRadius.large),
                  child: JoinScannerView(
                    onCode: (code) => Navigator.of(context).pop(code),
                  ),
                ),
              ),
            ),
            const SizedBox(height: NimnaSpacing.base * 3),
            Text(
              // Honest fallback if the camera is unavailable/denied (F3.2).
              l10n.pairing_joinCameraDenied,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.pairing_joinScanEnterInstead),
            ),
            const SizedBox(height: NimnaSpacing.base * 4),
          ],
        ),
      ),
    );
  }
}
