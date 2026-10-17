import 'dart:math';

import 'package:flutter/material.dart';

const lotteryBackground = Color(0xFF071425);
const lotteryText = Color(0xFFEAF3FF);
const lotteryMuted = Color(0xFF9CB3D6);
const lotteryBlue = Color(0xFF4B87FF);

class LotteryAntEmblem extends StatelessWidget {
  const LotteryAntEmblem({
    super.key,
    this.size = 42,
    this.color = lotteryMuted,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _AntEmblemPainter(color));
}

class _AntEmblemPainter extends CustomPainter {
  const _AntEmblemPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 42, size.height / 42);
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(const Rect.fromLTWH(3, 22, 15, 12), fill);
    canvas.drawOval(const Rect.fromLTWH(17, 20, 10, 10), fill);
    canvas.drawCircle(const Offset(31, 19), 8, fill);
    canvas.drawLine(const Offset(20, 28), const Offset(13, 40), line);
    canvas.drawLine(const Offset(23, 28), const Offset(25, 40), line);
    canvas.drawLine(const Offset(27, 27), const Offset(38, 35), line);
    canvas.drawLine(const Offset(18, 22), const Offset(13, 12), line);
    canvas.drawLine(const Offset(24, 21), const Offset(24, 10), line);
    canvas.drawLine(const Offset(30, 12), const Offset(31, 3), line);
    canvas.drawLine(const Offset(35, 13), const Offset(39, 5), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AntEmblemPainter oldDelegate) =>
      oldDelegate.color != color;
}

class LotteryConfettiPainter extends CustomPainter {
  const LotteryConfettiPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    const colors = [
      Color(0xFFFFD461),
      Color(0xFF3ABEFF),
      Color(0xFFE74DFA),
      Color(0xFFFFFFFF),
    ];
    final random = Random(29);
    for (var i = 0; i < 28; i++) {
      final x = size.width * (.08 + random.nextDouble() * .84);
      final y = size.height * (.14 + random.nextDouble() * .56);
      final drift = (random.nextDouble() - .5) * size.width * .28;
      final fall = progress * (65 + random.nextDouble() * 95);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(
          alpha: (1 - progress).clamp(0, 1),
        );
      canvas.save();
      canvas.translate(x + drift * progress, y + fall);
      canvas.rotate(progress * (i.isEven ? 5 : -5));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -5, 6, 10),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(LotteryConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
