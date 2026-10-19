import 'dart:ui' as ui;

import 'package:antkeep/widgets/fading_horizontal_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'edges fade only while content is hidden, including after resize',
    (tester) async {
      final boundaryKey = GlobalKey();
      Future<void> show(double contentWidth) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 200,
                  height: 40,
                  child: ColoredBox(
                    color: Colors.white,
                    child: FadingHorizontalScroll(
                      child: SizedBox(
                        width: contentWidth,
                        height: 40,
                        child: const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> checkEdges(bool left, bool right) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes!;
        });
        int red(int x) => pixels!.getUint8((20 * 200 + x) * 4);
        expect(red(1), left ? greaterThan(200) : 0);
        expect(red(198), right ? greaterThan(200) : 0);
        expect(red(100), 0);
        if (left) expect(red(1), greaterThan(red(10)));
        if (right) expect(red(198), greaterThan(red(190)));
      }

      await show(500);
      await checkEdges(false, true);
      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      scroll.jumpTo(150);
      await tester.pumpAndSettle();
      await checkEdges(true, true);
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      await checkEdges(true, false);
      await show(200);
      await checkEdges(false, false);
      expect(tester.takeException(), isNull);
    },
  );
}
