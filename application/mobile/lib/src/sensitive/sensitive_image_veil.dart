/// The recipient-side sensitive-content veil (spec §5.3, voice string 15) —
/// BINDING to `designs/system/components.md` (media veil) and
/// `designs/screens/14-sensitive-blur.html`. Runs the on-device analysis after
/// decryption, before display; a FLAGGED received image renders blurred
/// (`NimnaMedia.blurSigma` = 24) under the `mediaVeil` overlay with the caption
/// "Sensitive content — tap to view." Tap reveals IN PLACE with a `durStandard`
/// cross-fade.
///
/// Fail-open (§5.3): a miss, an unavailable framework, or a non-iOS platform
/// yields no blur — this is display sugar, not security. Recipient-only:
/// callers wrap ONLY received images; a sender's own attachment is never
/// blurred (they chose to send it). Nothing is blocked, logged, reported, or
/// transmitted; the sender is never told.
///
/// Holds no protocol/store state — it takes already-decrypted bytes and the
/// injected analyzer, so the reveal/cross-fade is provable headlessly with a
/// fake analyzer (a real analysis needs a device — the S18 rung).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../ui/theme/nimna_tokens.dart';
import 'sensitive_content_analyzer.dart';

class SensitiveImageVeil extends StatefulWidget {
  const SensitiveImageVeil({
    required this.imageBytes,
    required this.analyzer,
    required this.child,
    super.key,
  });

  /// The already-decrypted image bytes to analyse (never re-decrypted here).
  final Uint8List imageBytes;

  /// The on-device analysis (injected; fail-open by contract).
  final SensitiveContentAnalyzer analyzer;

  /// The plain image widget shown once revealed / not-sensitive.
  final Widget child;

  @override
  State<SensitiveImageVeil> createState() => _SensitiveImageVeilState();
}

class _SensitiveImageVeilState extends State<SensitiveImageVeil> {
  // Analyse exactly once for these bytes — never re-run on rebuild.
  late final Future<bool> _flagged = widget.analyzer.isSensitive(
    widget.imageBytes,
  );
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _flagged,
      builder: (context, snapshot) {
        final resolved = snapshot.connectionState == ConnectionState.done;
        final sensitive = snapshot.data ?? false;
        // Veil while the analysis is pending (so nothing sensitive flashes
        // "before display", §5.3) and while flagged-and-unrevealed. Once
        // resolved-and-clear, or revealed, the plain child shows.
        final veiled = (!resolved || sensitive) && !_revealed;
        return AnimatedSwitcher(
          duration: NimnaMotion.standard,
          switchInCurve: NimnaMotion.easeStandard,
          switchOutCurve: NimnaMotion.easeStandard,
          child: veiled
              ? _veil(context, captioned: resolved && sensitive)
              : KeyedSubtree(
                  key: const ValueKey('sensitive-revealed'),
                  child: widget.child,
                ),
        );
      },
    );
  }

  Widget _veil(BuildContext context, {required bool captioned}) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final l10n = AppLocalizations.of(context)!;
    // Tap reveals only once the flag is known — a pending veil is inert.
    final onTap = captioned ? () => setState(() => _revealed = true) : null;
    return Semantics(
      key: const ValueKey('sensitive-veiled'),
      label: captioned ? l10n.sensitive_veilCaption : null,
      button: captioned,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: NimnaMedia.blurSigma,
                sigmaY: NimnaMedia.blurSigma,
                tileMode: TileMode.decal,
              ),
              child: widget.child,
            ),
            Positioned.fill(child: ColoredBox(color: tokens.mediaVeil)),
            if (captioned)
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(NimnaSpacing.base * 3),
                    child: Text(
                      // Voice string 15, verbatim.
                      l10n.sensitive_veilCaption,
                      textAlign: TextAlign.center,
                      style: NimnaText.caption.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
