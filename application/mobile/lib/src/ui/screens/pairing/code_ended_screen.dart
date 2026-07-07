import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../theme/nimna_tokens.dart';

/// The flow's quiet endings:
///
/// - **F2.8 · code expired unused** — "close the loop with zero drama":
///   nothing was created, no channel, no residue. Silence doctrine: expiry
///   is surfaced only to the creator; a dead code meets silence at the
///   relay forever.
/// - **spent** (F2.5 edge copy, wireframe verbatim) — the bridge dropped
///   before the handshake finished; both sides discard partial state and a
///   half-made channel never exists (spec §3.1.6).
///
/// Same frame both ways: headline/body, primary "Make a new code", ghost
/// "Not now".
class CodeEndedScreen extends StatelessWidget {
  const CodeEndedScreen._({
    required this.onMakeNewCode,
    required this.expired,
    super.key,
  });

  const CodeEndedScreen.expired({required VoidCallback onMakeNewCode, Key? key})
    : this._(onMakeNewCode: onMakeNewCode, expired: true, key: key);

  const CodeEndedScreen.spent({required VoidCallback onMakeNewCode, Key? key})
    : this._(onMakeNewCode: onMakeNewCode, expired: false, key: key);

  final VoidCallback onMakeNewCode;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.screenMargin,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              if (expired) ...[
                Text(l10n.pairing_expiredHeadline, style: text.displaySmall),
                const SizedBox(height: NimnaSpacing.base * 3),
                Text(
                  l10n.pairing_expiredBody,
                  style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
                ),
              ] else
                Text(
                  l10n.pairing_spentBody,
                  style: text.bodyLarge?.copyWith(color: tokens.textSecondary),
                ),
              const Spacer(flex: 3),
              FilledButton(
                onPressed: onMakeNewCode,
                child: Text(l10n.pairing_makeNewCode),
              ),
              const SizedBox(height: NimnaSpacing.base * 2),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.pairing_notNow),
              ),
              const SizedBox(height: NimnaSpacing.base * 6),
            ],
          ),
        ),
      ),
    );
  }
}
