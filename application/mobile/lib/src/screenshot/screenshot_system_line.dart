/// The screenshot system line (spec §5.2, voice string 12) — BINDING to
/// `designs/system/components.md` (System line — screenshot notice): a bare
/// centered `caption` in `textTertiary`, an EVENT not speech, NO bubble, NO
/// icon, 16 vertical padding. Symmetric on both platforms.
///
/// Renders one [ScreenshotNotice] the connection lane produced. Holds no
/// protocol state — a leaf widget the chat lane drops into the thread flow.
/// Every string is l10n; the copy is voice string 12, verbatim.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../ui/theme/nimna_tokens.dart';
import 'screenshot_notice.dart';

class ScreenshotSystemLine extends StatelessWidget {
  const ScreenshotSystemLine({required this.notice, super.key});

  final ScreenshotNotice notice;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    // string 12: own side names that they've been told; peer side is bare.
    final text = notice.own
        ? l10n.screenshot_systemLineOwn
        : l10n.screenshot_systemLinePeer;
    return Padding(
      // 16 vertical padding (components.md system line), no bubble, no icon.
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: NimnaText.caption.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }
}
