import 'package:flutter/material.dart';

import '../theme/nimna_tokens.dart';
import 'glyphs.dart';

/// The shared navigation bar (screens.css `.navbar`): height 52, back
/// glyph (44 px touch target) + `title2`. The back glyph mirrors under
/// RTL via [BackGlyph].
class NimnaNavBar extends StatelessWidget {
  const NimnaNavBar({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 20, end: 20),
        child: Row(
          children: [
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox.square(
                  dimension: NimnaSpacing.touchTargetMin,
                  child: Center(child: BackGlyph(color: tokens.textSecondary)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
