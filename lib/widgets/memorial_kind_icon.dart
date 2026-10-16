import 'package:flutter/material.dart';

import '../domain/memorial.dart';

/// A small line illustration for the selected memorial type.
class MemorialKindIcon extends StatelessWidget {
  const MemorialKindIcon({
    super.key,
    required this.kind,
    this.size = 40,
    this.color,
  });

  final MemorialKind kind;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: switch (kind) {
      MemorialKind.queen => '蚁后纪念',
      MemorialKind.worker => '工蚁纪念',
      MemorialKind.brood => '幼体纪念',
      MemorialKind.colony => '蚁群纪念',
    },
    image: true,
    child: CustomPaint(
      size: Size.square(size),
      painter: _MemorialKindPainter(
        kind,
        color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _MemorialKindPainter extends CustomPainter {
  const _MemorialKindPainter(this.kind, this.color);

  final MemorialKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case MemorialKind.queen:
        _paintAnt(canvas, paint);
        paint.style = PaintingStyle.fill;
        final crown = Path()
          ..moveTo(11, 5)
          ..lineTo(12, 2)
          ..lineTo(15, 4)
          ..lineTo(18, 1)
          ..lineTo(20, 4)
          ..lineTo(23, 2)
          ..lineTo(22, 6)
          ..close();
        canvas.drawPath(crown, paint);
      case MemorialKind.worker:
        canvas.save();
        canvas.translate(16, 16);
        canvas.rotate(-0.65);
        canvas.translate(-16, -16);
        _paintAnt(canvas, paint);
        canvas.restore();
      case MemorialKind.brood:
        final cocoon = Path()
          ..moveTo(16, 6)
          ..cubicTo(22, 9, 21, 20, 16, 24)
          ..cubicTo(11, 20, 10, 9, 16, 6)
          ..close();
        canvas.drawPath(cocoon, paint);
        paint.strokeWidth = 1.2;
        canvas.drawLine(const Offset(12, 14), const Offset(20, 14), paint);
        canvas.drawLine(const Offset(12.5, 18), const Offset(19.5, 18), paint);
        paint.strokeWidth = 1.7;
        final leaves = Path()
          ..moveTo(15, 26)
          ..quadraticBezierTo(6, 25, 5, 16)
          ..quadraticBezierTo(10, 17, 12, 22)
          ..moveTo(17, 26)
          ..quadraticBezierTo(26, 25, 27, 16)
          ..quadraticBezierTo(22, 17, 20, 22);
        canvas.drawPath(leaves, paint);
        canvas.drawLine(const Offset(13, 27), const Offset(19, 27), paint);
      case MemorialKind.colony:
        paint.style = PaintingStyle.fill;
        for (final center in [
          const Offset(16, 8),
          const Offset(10, 20),
          const Offset(22, 20),
        ]) {
          final hexagon = Path();
          for (var i = 0; i < 6; i++) {
            final point = Offset(
              center.dx + [0.0, 5.2, 5.2, 0.0, -5.2, -5.2][i],
              center.dy + [-6.0, -3.0, 3.0, 6.0, 3.0, -3.0][i],
            );
            if (i == 0) {
              hexagon.moveTo(point.dx, point.dy);
            } else {
              hexagon.lineTo(point.dx, point.dy);
            }
          }
          hexagon.close();
          canvas.drawPath(hexagon, paint);
        }
    }
    canvas.restore();
  }

  void _paintAnt(Canvas canvas, Paint paint) {
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.7;
    for (final side in [-1.0, 1.0]) {
      for (final y in [12.0, 17.0, 21.0]) {
        canvas.drawLine(
          Offset(16 + side * 2, y),
          Offset(16 + side * 8, y - 3),
          paint,
        );
        canvas.drawLine(
          Offset(16 + side * 8, y - 3),
          Offset(16 + side * 11, y + 1),
          paint,
        );
      }
      canvas.drawLine(
        Offset(16 + side * 2, 9),
        Offset(16 + side * 7, 6),
        paint,
      );
    }
    paint.style = PaintingStyle.fill;
    canvas.drawOval(const Rect.fromLTWH(12.5, 8, 7, 6), paint);
    canvas.drawOval(const Rect.fromLTWH(13.5, 14, 5, 6), paint);
    canvas.drawOval(const Rect.fromLTWH(11.5, 20, 9, 10), paint);
  }

  @override
  bool shouldRepaint(_MemorialKindPainter oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}
