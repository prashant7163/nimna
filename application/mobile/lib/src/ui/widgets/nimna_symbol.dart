import 'package:flutter/widgets.dart';

import '../theme/nimna_tokens.dart';

/// The brand symbol — dot · line · dot (screens.css `.sym`: 9 px dots in
/// `textPrimary`, a 52×7 `accent` line radius 4, 8 px gaps). Horizontally
/// symmetric, so no RTL concern. The lock screen's only mark.
class NimnaSymbol extends StatelessWidget {
  const NimnaSymbol({required this.tokens, super.key});

  final NimnaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: tokens.textPrimary,
        borderRadius: BorderRadius.circular(NimnaRadius.full),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 8),
        Container(
          width: 52,
          height: 7,
          decoration: BoxDecoration(
            color: tokens.accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        dot,
      ],
    );
  }
}
