import 'package:flutter/material.dart';

/// A neutral headstone silhouette, drawn locally at any display scale.
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
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final stone = Path()
      ..moveTo(7, 27)
      ..lineTo(7, 12)
      ..cubicTo(7, 1, 25, 1, 25, 12)
      ..lineTo(25, 27)
      ..close();
    canvas.drawPath(stone, paint);
    canvas.drawLine(const Offset(4, 28), const Offset(28, 28), paint);
    canvas.drawLine(const Offset(12, 13), const Offset(20, 13), paint);
    canvas.drawLine(const Offset(13, 18), const Offset(19, 18), paint);
  }

  @override
  bool shouldRepaint(_TombstonePainter oldDelegate) =>
      color != oldDelegate.color;
}
