import 'package:flutter/material.dart';

import '../theme/nimna_tokens.dart';
import 'glyphs.dart';

/// The PIN dot row (screen 12 / F8.2): 12 px dots, gap 14, 1.5 px
/// `textTertiary` ring; a filled dot is `textPrimary` (passcode-dot glyph
/// language — CODE 2026-07-03: never a padlock).
class PinDots extends StatelessWidget {
  const PinDots({required this.count, required this.filled, super.key});

  final int count;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 14),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? tokens.textPrimary : null,
                border: i < filled
                    ? null
                    : Border.all(color: tokens.textTertiary, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// The PIN pad (screen 12 / F8.2): 3×4 grid of 72 px circular keys on
/// `surface1`, 24 px digits; blank bottom-start cell, backspace glyph
/// bottom-end; gaps 20 (rows) × 36 (columns) per screens.css `.pinpad`.
class PinPad extends StatelessWidget {
  const PinPad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.backspaceLabel,
    super.key,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// A11y label for the backspace key (from the ARB — the pad itself is
  /// locale-independent).
  final String backspaceLabel;

  static const double keySize = 72;
  static const double _rowGap = 20;
  static const double _columnGap = 36;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;

    Widget key({String? digit, bool backspace = false}) {
      if (digit == null && !backspace) {
        return const SizedBox.square(dimension: keySize);
      }
      final child = backspace
          ? BackspaceGlyph(
              color: enabled ? tokens.textSecondary : tokens.textDisabled,
            )
          : Text(
              digit!,
              style: TextStyle(
                fontFamily: NimnaText.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w400,
                fontVariations: const [FontVariation('wght', 400)],
                color: enabled ? tokens.textPrimary : tokens.textDisabled,
              ),
            );
      return Semantics(
        button: true,
        enabled: enabled,
        label: backspace ? backspaceLabel : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () => backspace ? onBackspace() : onDigit(digit!)
              : null,
          child: Container(
            width: keySize,
            height: keySize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backspace ? null : tokens.surface1,
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
    }

    Widget row(List<Widget> keys) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        keys[0],
        const SizedBox(width: _columnGap),
        keys[1],
        const SizedBox(width: _columnGap),
        keys[2],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([key(digit: '1'), key(digit: '2'), key(digit: '3')]),
        const SizedBox(height: _rowGap),
        row([key(digit: '4'), key(digit: '5'), key(digit: '6')]),
        const SizedBox(height: _rowGap),
        row([key(digit: '7'), key(digit: '8'), key(digit: '9')]),
        const SizedBox(height: _rowGap),
        row([key(), key(digit: '0'), key(backspace: true)]),
      ],
    );
  }
}
