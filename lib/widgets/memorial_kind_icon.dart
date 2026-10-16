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
        final crown = Path()
          ..moveTo(4.5, 10)
          ..lineTo(10.5, 16)
          ..lineTo(16, 7)
          ..lineTo(21.5, 16)
          ..lineTo(27.5, 10)
          ..lineTo(25, 23)
          ..lineTo(7, 23)
          ..close();
        canvas.drawPath(crown, paint);
        canvas.drawLine(const Offset(7, 26), const Offset(25, 26), paint);
        for (final tip in [
          const Offset(4.5, 10),
          const Offset(16, 7),
          const Offset(27.5, 10),
        ]) {
          canvas.drawCircle(tip, 1.2, paint);
        }
      case MemorialKind.worker:
        final shield = Path()
          ..moveTo(16, 4.5)
          ..lineTo(25, 8)
          ..lineTo(24, 19)
          ..quadraticBezierTo(22.5, 24, 16, 28)
          ..quadraticBezierTo(9.5, 24, 8, 19)
          ..lineTo(7, 8)
          ..close();
        canvas.drawPath(shield, paint);
        for (final side in [-1.0, 1.0]) {
          final tip = Offset(16 + side * 6, 9);
          final hilt = Offset(16 - side * 6, 22);
          canvas.drawLine(tip, hilt, paint);
          canvas.drawLine(
            Offset(16 - side * 4, 17.5),
            Offset(16 - side * 8, 19.5),
            paint,
          );
          canvas.drawCircle(hilt, 1, paint);
        }
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
        final monument = Path()
          ..moveTo(9, 25)
          ..lineTo(9, 12)
          ..lineTo(16, 6)
          ..lineTo(23, 12)
          ..lineTo(23, 25);
        canvas.drawPath(monument, paint);
        canvas.drawLine(const Offset(5, 27), const Offset(27, 27), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MemorialKindPainter oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}
