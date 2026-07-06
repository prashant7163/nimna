import 'package:flutter/material.dart';

import '../theme/nimna_tokens.dart';

/// The line motif in its IDLE state (tokens.json `line`): a 2 px dotted
/// line — 2 px dots, 7 px gaps, round caps, 3 px endpoint dots at both
/// ends — in `lineIdle`. The dotted line reads "nothing yet": the same
/// visual language every screen uses (F2.4). Static by design here; the
/// breathing/connect choreography belongs to later session states.
class IdleLine extends StatelessWidget {
  const IdleLine({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NimnaTokens>()!;
    return SizedBox(
      height: NimnaLine.endpointRadius * 2,
      width: double.infinity,
      child: CustomPaint(painter: _IdleLinePainter(color: tokens.lineIdle)),
    );
  }
}

class _IdleLinePainter extends CustomPainter {
  const _IdleLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dotPaint = Paint()..color = color;

    // Endpoint dots (radius 3).
    canvas.drawCircle(
      Offset(NimnaLine.endpointRadius, y),
      NimnaLine.endpointRadius,
      dotPaint,
    );
    canvas.drawCircle(
      Offset(size.width - NimnaLine.endpointRadius, y),
      NimnaLine.endpointRadius,
      dotPaint,
    );

    // Dotted run between the endpoints: 2 px dots, 7 px gaps, round caps.
    final stroke = Paint()
      ..color = color
      ..strokeWidth = NimnaLine.thickness
      ..strokeCap = StrokeCap.round;
    final dot = NimnaLine.dotGapIdle[0];
    final gap = NimnaLine.dotGapIdle[1];
    var x = NimnaLine.endpointRadius * 2 + gap;
    final end = size.width - NimnaLine.endpointRadius * 2 - gap;
    while (x + dot <= end) {
      canvas.drawLine(Offset(x, y), Offset(x + dot, y), stroke);
      x += dot + gap;
    }
  }

  @override
  bool shouldRepaint(_IdleLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
