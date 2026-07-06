import 'package:flutter/material.dart';

import '../theme/nimna_tokens.dart';

/// The design system's back chevron (hi-fi navbar arrow: a horizontal
/// stroke with an angled head), drawn as a CustomPainter per the icon
/// doctrine (flutter-notes §Asset wiring). A11y label comes from
/// MaterialLocalizations (localized by the framework, not the ARB).
class NimnaBackButton extends StatelessWidget {
  const NimnaBackButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: InkWell(
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: NimnaSpacing.touchTargetMin,
          height: NimnaSpacing.touchTargetMin,
          child: CustomPaint(
            painter: _BackArrowPainter(color: tokens.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _BackArrowPainter extends CustomPainter {
  const _BackArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = size.center(Offset.zero);
    // Geometry from the hi-fi navbar svg (24 px grid, centered):
    // M19 12H5  M10.5 6.5 5 12 l5.5 5.5
    final s = 1.0; // 24-grid unit
    Offset p(double x, double y) => c + Offset((x - 12) * s, (y - 12) * s);
    canvas.drawLine(p(19, 12), p(5, 12), paint);
    final head = Path()
      ..moveTo(p(10.5, 6.5).dx, p(10.5, 6.5).dy)
      ..lineTo(p(5, 12).dx, p(5, 12).dy)
      ..lineTo(p(10.5, 17.5).dx, p(10.5, 17.5).dy);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_BackArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}
