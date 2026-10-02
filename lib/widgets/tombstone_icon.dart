import 'package:flutter/material.dart';

/// A hollow headstone with an ant emblem, drawn in the current theme color.
class TombstoneIcon extends StatelessWidget {
  const TombstoneIcon({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '墓碑',
    image: true,
    child: CustomPaint(
      size: Size.square(size),
      painter: _TombstonePainter(
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _TombstonePainter extends CustomPainter {
  const _TombstonePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final stone = Path()
      ..moveTo(6, 25.5)
      ..lineTo(6, 12)
      ..cubicTo(6, -0.5, 26, -0.5, 26, 12)
      ..lineTo(26, 25.5);
    canvas.drawPath(stone, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.5, 25.5, 25, 4),
        const Radius.circular(2),
      ),
      paint,
    );

    // Leave the stone and base unfilled so the surrounding surface shows through.
    paint.strokeWidth = 1.15;
    final appendages = Path()
      ..moveTo(15.4, 10.6)
      ..quadraticBezierTo(15, 9, 14, 8.8)
      ..moveTo(16.6, 10.6)
      ..quadraticBezierTo(17, 9, 18, 8.8);
    for (final side in [-1.0, 1.0]) {
      appendages
        ..moveTo(16 + side * 0.7, 13)
        ..lineTo(16 + side * 2.5, 12.5)
        ..lineTo(16 + side * 3.3, 11.4)
        ..moveTo(16 + side * 0.8, 13.9)
        ..lineTo(16 + side * 2.7, 14)
        ..lineTo(16 + side * 3.6, 15.2)
        ..moveTo(16 + side * 0.7, 14.7)
        ..lineTo(16 + side * 2.2, 15.8)
        ..lineTo(16 + side * 2.9, 17.3);
    }
    canvas.drawPath(appendages, paint);
    canvas.drawLine(const Offset(16, 11.4), const Offset(16, 17), paint);
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(16, 11.3), 1.25, paint);
    canvas.drawOval(const Rect.fromLTWH(14.9, 12.5, 2.2, 2.8), paint);
    canvas.drawOval(const Rect.fromLTWH(14.6, 15.6, 2.8, 3.7), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TombstonePainter oldDelegate) =>
      color != oldDelegate.color;
}
