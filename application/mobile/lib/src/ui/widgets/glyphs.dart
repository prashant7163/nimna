import 'package:flutter/widgets.dart';

/// Hand-painted glyphs (iconography is CustomPainter per the design
/// system — app-architecture.md §1: cupertino_icons removed). Paths mirror
/// the hi-fi mockup SVGs (designs/screens/*.html): 24-box, stroke 1.75,
/// round caps/joins. Directional glyphs auto-mirror under RTL — left/right
/// is never hardcoded.

const double _strokeWidth = 1.75;

Widget _mirrorForRtl(BuildContext context, Widget child) =>
    Directionality.of(context) == TextDirection.rtl
    ? Transform.flip(flipX: true, child: child)
    : child;

/// The back arrow (screens navbar: `M19 12H5M10.5 6.5 5 12l5.5 5.5`).
class BackGlyph extends StatelessWidget {
  const BackGlyph({required this.color, this.size = 24, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => _mirrorForRtl(
    context,
    CustomPaint(
      size: Size.square(size),
      painter: _BackPainter(color: color),
    ),
  );
}

class _BackPainter extends CustomPainter {
  const _BackPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(19 * s, 12 * s)
      ..lineTo(5 * s, 12 * s)
      ..moveTo(10.5 * s, 6.5 * s)
      ..lineTo(5 * s, 12 * s)
      ..lineTo(10.5 * s, 17.5 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BackPainter oldDelegate) => color != oldDelegate.color;
}

/// The settings-row trailing chevron (wireframe `›`).
class ChevronGlyph extends StatelessWidget {
  const ChevronGlyph({required this.color, this.size = 16, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => _mirrorForRtl(
    context,
    CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(color: color),
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(9.5 * s, 6 * s)
      ..lineTo(15.5 * s, 12 * s)
      ..lineTo(9.5 * s, 18 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => color != oldDelegate.color;
}

/// The dismiss ✕ (hi-fi screen 09 navbar / F9.2: `m6 6 12 12M18 6 6 18`).
/// Horizontally symmetric — no RTL concern; its trailing POSITION is set by
/// the caller with a directional alignment.
class CloseGlyph extends StatelessWidget {
  const CloseGlyph({required this.color, this.size = 24, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ClosePainter(color: color),
  );
}

class _ClosePainter extends CustomPainter {
  const _ClosePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(6 * s, 6 * s), Offset(18 * s, 18 * s), paint);
    canvas.drawLine(Offset(18 * s, 6 * s), Offset(6 * s, 18 * s), paint);
  }

  @override
  bool shouldRepaint(_ClosePainter oldDelegate) => color != oldDelegate.color;
}

/// The PIN-pad backspace key (screen 12:
/// `M9 6h9a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H9L3.5 12 9 6ZM12 9.5l5 5M17 9.5l-5 5`).
class BackspaceGlyph extends StatelessWidget {
  const BackspaceGlyph({required this.color, this.size = 24, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => _mirrorForRtl(
    context,
    CustomPaint(
      size: Size.square(size),
      painter: _BackspacePainter(color: color),
    ),
  );
}

class _BackspacePainter extends CustomPainter {
  const _BackspacePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = 2 * s;
    final body = Path()
      ..moveTo(9 * s, 6 * s)
      ..lineTo(18 * s, 6 * s)
      ..arcToPoint(Offset(20 * s, 8 * s), radius: Radius.circular(r))
      ..lineTo(20 * s, 16 * s)
      ..arcToPoint(Offset(18 * s, 18 * s), radius: Radius.circular(r))
      ..lineTo(9 * s, 18 * s)
      ..lineTo(3.5 * s, 12 * s)
      ..close();
    final cross = Path()
      ..moveTo(12 * s, 9.5 * s)
      ..lineTo(17 * s, 14.5 * s)
      ..moveTo(17 * s, 9.5 * s)
      ..lineTo(12 * s, 14.5 * s);
    canvas.drawPath(body, paint);
    canvas.drawPath(cross, paint);
  }

  @override
  bool shouldRepaint(_BackspacePainter oldDelegate) =>
      color != oldDelegate.color;
}
