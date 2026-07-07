import 'package:flutter/material.dart';

import '../theme/nimna_tokens.dart';

/// The design-system toggle (components.md): track 44×26 radius full,
/// thumb 22. Off: track `surface3` + 1 px `hairline`, thumb
/// `textTertiary`. On: track `accent`, thumb `onAccent`. `durMicro`
/// slide, no bounce. Thumb travel is direction-aware.
class NimnaToggle extends StatelessWidget {
  const NimnaToggle({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: NimnaMotion.micro,
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? tokens.accent : tokens.surface3,
            borderRadius: BorderRadius.circular(NimnaRadius.full),
            border: value ? null : Border.all(color: tokens.hairline),
          ),
          child: AnimatedAlign(
            duration: NimnaMotion.micro,
            curve: NimnaMotion.easeStandard,
            alignment: value
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Container(
              width: value ? 22 : 20,
              height: value ? 22 : 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? tokens.onAccent : tokens.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
