import 'package:flutter/material.dart';

import '../../pairing/initiator/qr_matrix.dart';
import '../../protocol/pairing_code.dart';
import '../theme/nimna_tokens.dart';

/// QR display (components.md): the QR on a `#FFFFFF` card — QR needs true
/// white even in dark mode, never amber-tinted — radius `rLarge` 16,
/// padding 24. Rendered by an in-repo CustomPainter over the `qr`
/// encoder's module matrix. A11y: the QR is the code in machine-readable
/// form, so its semantics value is the code's display form.
class QrCard extends StatelessWidget {
  QrCard({required this.code, super.key}) : matrix = QrMatrix.forCode(code);

  final PairingCode code;
  final QrMatrix matrix;

  /// True white/black in BOTH themes (components.md) — deliberate literal
  /// exemption alongside the tokens file: QR contrast is a scanner
  /// requirement, not a theme surface.
  static const Color _cardWhite = Color(0xFFFFFFFF);
  static const Color _moduleBlack = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      value: code.display,
      child: Container(
        decoration: const BoxDecoration(
          color: _cardWhite,
          borderRadius: BorderRadius.all(Radius.circular(NimnaRadius.large)),
        ),
        padding: const EdgeInsets.all(NimnaSpacing.base * 6),
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _QrPainter(matrix: matrix)),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.matrix});

  final QrMatrix matrix;

  @override
  void paint(Canvas canvas, Size size) {
    final module = size.shortestSide / matrix.moduleCount;
    final paint = Paint()..color = QrCard._moduleBlack;
    for (var y = 0; y < matrix.moduleCount; y++) {
      for (var x = 0; x < matrix.moduleCount; x++) {
        if (matrix.isDark(x, y)) {
          // Overlap by a hairline to avoid anti-aliasing seams.
          canvas.drawRect(
            Rect.fromLTWH(x * module, y * module, module + 0.3, module + 0.3),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.matrix != matrix;
}
