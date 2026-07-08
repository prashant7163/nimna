/// The sender-side sensitive-content whisper (spec §5.3, voice string 14) —
/// BINDING to `designs/system/components.md` (Whisper card) and
/// `designs/screens/15-whisper-attach.html`. A soft, NON-BLOCKING, NEVER-modal
/// card that rises above the attach preview when the on-device check flags the
/// chosen image: bg `surface2`, radius 16, padding 16, `body` text "This looks
/// like sensitive content — send anyway?", actions right-aligned — ghost
/// **Go back** · secondary-compact **Send anyway**. Never amber (this is
/// caution, not a session event), never `danger` (nothing is wrong). Rises
/// `durEnter` slide+fade; shown at most once per attachment.
///
/// Purely local (§5.3): the whisper protects the sender from a wrong-channel
/// slip. Nothing is blocked, logged, reported, or transmitted; the recipient
/// is never told. The preview stays live behind it.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../ui/theme/nimna_tokens.dart';

class SensitiveWhisperCard extends StatelessWidget {
  const SensitiveWhisperCard({
    required this.onSendAnyway,
    required this.onGoBack,
    super.key,
  });

  /// The user confirms — proceed with sending the attachment (string 14
  /// "Send anyway").
  final VoidCallback onSendAnyway;

  /// The user reconsiders — dismiss the whisper, leaving the live preview so
  /// they can edit or remove the attachment (string 14 "Go back").
  final VoidCallback onGoBack;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Voice string 14, verbatim — the question, never amber, never danger.
          Text(
            l10n.sensitive_whisperQuestion,
            style: NimnaText.body.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(height: NimnaSpacing.base * 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _action(
                context,
                label: l10n.sensitive_whisperGoBack,
                color: tokens.textSecondary,
                onTap: onGoBack,
              ),
              const SizedBox(width: NimnaSpacing.base * 3),
              _action(
                context,
                label: l10n.sensitive_whisperSendAnyway,
                color: tokens.textPrimary,
                onTap: onSendAnyway,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: NimnaSpacing.touchTargetMin,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NimnaSpacing.base * 3,
          ),
          alignment: Alignment.center,
          child: Text(label, style: NimnaText.label.copyWith(color: color)),
        ),
      ),
    );
  }
}
