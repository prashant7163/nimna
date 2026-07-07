import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../protocol/pairing_code.dart';
import '../../../theme/nimna_tokens.dart';

/// The F3.1 segmented code field: nine mono cells grouped `XXX-XXX-XXX`,
/// backed by one text field so typing auto-advances and a paste fills all
/// nine (with or without hyphens; `I→1 · O→0 · L→1` folded silently — spec
/// §3.1.1). Reports the canonical string on every edit; the tone follows
/// [FieldTone] (own-code guidance is warning-toned and shake-free — the one
/// permitted shake stays with wrong-code, DECISIONS 2026-07-05 03:25).
enum FieldTone { normal, warning, error }

class CodeField extends StatefulWidget {
  const CodeField({
    required this.controller,
    required this.onChanged,
    this.tone = FieldTone.normal,
    this.shakeTrigger = 0,
    super.key,
  });

  final TextEditingController controller;
  final void Function(String canonical) onChanged;
  final FieldTone tone;

  /// Increment to fire the one permitted 2 px shake (wrong-code only).
  final int shakeTrigger;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(CodeField old) {
    super.didUpdateWidget(old);
    if (widget.shakeTrigger != old.shakeTrigger) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _focus.dispose();
    super.dispose();
  }

  Color _cellColor(NimnaTokens tokens) => switch (widget.tone) {
    FieldTone.warning => tokens.warning,
    FieldTone.error => tokens.danger,
    FieldTone.normal => tokens.hairline,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    final text = Theme.of(context).textTheme;
    final chars = widget.controller.text;

    Widget cell(int i) {
      final filled = i < chars.length;
      return Container(
        width: 26,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _cellColor(tokens), width: 2),
          ),
        ),
        child: Text(
          filled ? chars[i] : '',
          style: text.titleLarge?.copyWith(
            fontFamily: 'Spline Sans Mono',
            color: tokens.textPrimary,
          ),
        ),
      );
    }

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < pairingCodeLength; i++) ...[
          cell(i),
          if (i == 2 || i == 5)
            // The XXX-XXX-XXX group separator (spec §3.1.1 display form),
            // drawn as a hairline dash — format punctuation, not copy.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Container(width: 8, height: 2, color: tokens.textTertiary),
            )
          else
            const SizedBox(width: 4),
        ],
      ],
    );

    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final dx = _shake.isAnimating
                  ? 2 *
                        (1 - _shake.value) *
                        (widget.shakeTrigger.isEven ? 1 : -1) *
                        ((_shake.value * 8).floor().isEven ? 1 : -1)
                  : 0.0;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: row,
          ),
          // The real input, transparent, capturing keystrokes and pastes.
          Opacity(
            opacity: 0,
            child: SizedBox(
              width: 240,
              height: 44,
              child: TextField(
                focusNode: _focus,
                controller: widget.controller,
                autofocus: true,
                maxLength: pairingCodeLength,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                inputFormatters: [_CrockfordFormatter()],
                keyboardType: TextInputType.visiblePassword,
                onChanged: (_) =>
                    setState(() => widget.onChanged(widget.controller.text)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Folds input to canonical Crockford characters live (spec §3.1.1): strips
/// whitespace/hyphens, uppercases, maps `I/L→1 · O→0`, drops anything else,
/// caps at nine.
class _CrockfordFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final out = StringBuffer();
    for (final unit in newValue.text.toUpperCase().codeUnits) {
      var c = String.fromCharCode(unit);
      if (c == 'I' || c == 'L') {
        c = '1';
      } else if (c == 'O') {
        c = '0';
      }
      if (crockfordAlphabet.contains(c) && out.length < pairingCodeLength) {
        out.write(c);
      }
    }
    final result = out.toString();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
