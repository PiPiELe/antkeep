import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('count labels fit on a narrow screen at text scale $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: antKeepTheme(ThemeColor.forest),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const ColonyFormPage(),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['蚁后 *', '工蚁 *', '卵', '茧']) {
        final field = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
          reason: '$label must be fully visible',
        );
      }
      final queenField = find.widgetWithText(TextFormField, '蚁后 *');
      final workerField = find.widgetWithText(TextFormField, '工蚁 *');
      await tester.ensureVisible(queenField);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(queenField).dy,
        tester.getTopLeft(workerField).dy,
        reason: 'queen and worker fields must align at the top',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
