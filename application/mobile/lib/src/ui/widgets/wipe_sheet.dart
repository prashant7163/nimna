import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/nimna_tokens.dart';
import 'destructive_hold_button.dart';

/// The wipe confirmation sheets (components.md Sheet; wireframes F8.3 and
/// F7.2/F7.3; hi-fi screen 08). The hold IS the confirmation — no second
/// dialog. Release cancels; the safe word is "Keep", warm, never "Cancel"
/// (voice string 8 register).
///
/// Both show-functions resolve `true` when the wipe ran to completion and
/// `null` when the user kept everything (Keep / early release + swipe
/// down). [onWipe] is awaited BEFORE the sheet closes, so the caller
/// returns to an already-wiped world.

/// Full panic wipe — F8.3 / screen 08, string 8 verbatim, hold 2.5 s.
Future<bool?> showFullWipeSheet(
  BuildContext context, {
  required Future<void> Function() onWipe,
}) => _showWipeSheet(context, full: true, onWipe: onWipe);

/// Per-channel wipe — F7.2/F7.3, hold 1.5 s. The F7 host screen belongs
/// to a later session; this sheet + the WipeService seam ship with S13.
Future<bool?> showChannelWipeSheet(
  BuildContext context, {
  required Future<void> Function() onWipe,
}) => _showWipeSheet(context, full: false, onWipe: onWipe);

Future<bool?> _showWipeSheet(
  BuildContext context, {
  required bool full,
  required Future<void> Function() onWipe,
}) {
  final tokens = Theme.of(context).extension<NimnaTokens>()!;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: tokens.surface2,
    barrierColor: tokens.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(NimnaRadius.sheet),
      ),
    ),
    builder: (context) => WipeSheetBody(full: full, onWipe: onWipe),
  );
}

/// The shared sheet body (public for widget tests).
class WipeSheetBody extends StatefulWidget {
  const WipeSheetBody({required this.full, required this.onWipe, super.key});

  final bool full;
  final Future<void> Function() onWipe;

  @override
  State<WipeSheetBody> createState() => _WipeSheetBodyState();
}

class _WipeSheetBodyState extends State<WipeSheetBody> {
  bool _wiping = false;

  Future<void> _complete() async {
    setState(() => _wiping = true);
    await widget.onWipe();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle 32×4 hairline.
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: tokens.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (widget.full)
              _EmphasizedTitle(
                title: l10n.wipe_fullTitle,
                emphasis: l10n.wipe_fullTitleEmphasis,
                style: text.titleLarge!,
              )
            else
              Text(l10n.wipe_channelTitle, style: text.titleLarge),
            const SizedBox(height: 10),
            Text(
              widget.full ? l10n.wipe_fullBody : l10n.wipe_channelBody,
              style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
            ),
            if (!widget.full) ...[
              const SizedBox(height: 10),
              Text(
                l10n.wipe_channelPeerNote,
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ],
            const SizedBox(height: 24),
            DestructiveHoldButton(
              label: l10n.wipe_holdToWipe,
              holdDuration: Duration(
                milliseconds: widget.full
                    ? NimnaLine.holdToWipeFullMs
                    : NimnaLine.holdToWipeChannelMs,
              ),
              onComplete: _complete,
            ),
            const SizedBox(height: 8),
            Text(
              widget.full
                  ? l10n.wipe_fullHoldCaption
                  : l10n.wipe_channelHoldCaption,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
            const SizedBox(height: 10),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: tokens.textSecondary,
              ),
              onPressed: _wiping ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.wipe_actionKeep),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the title with its emphasized substring at weight 600 (hi-fi
/// screen 08: "Wipe *everything*?"). Falls back to the plain title when
/// the emphasis substring is absent in a locale's rendering.
class _EmphasizedTitle extends StatelessWidget {
  const _EmphasizedTitle({
    required this.title,
    required this.emphasis,
    required this.style,
  });

  final String title;
  final String emphasis;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final index = emphasis.isEmpty ? -1 : title.indexOf(emphasis);
    if (index < 0) {
      return Text(title, style: style);
    }
    final bold = style.copyWith(
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 600)],
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: title.substring(0, index)),
          TextSpan(text: emphasis, style: bold),
          TextSpan(text: title.substring(index + emphasis.length)),
        ],
      ),
    );
  }
}
