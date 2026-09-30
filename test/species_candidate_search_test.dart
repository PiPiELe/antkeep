import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (query, expected) in [
    (
      '肩角弓背蚁',
      {
        '丝腹弓背蚁（君王亚种）': 'Camponotus sericeiventris rex',
        '丝腹弓背蚁指名亚种': 'Camponotus sericeiventris sericeiventris',
      },
    ),
    ('拟黑多刺蚁', {'拟黑多刺蚁': '学名待核对', '双齿多刺蚁': 'Polyrhachis dives'}),
    (
      '多毛真猛蚁',
      {
        '多毛真猛蚁（Euponera pilosior）': 'Euponera pilosior',
        '多毛真猛蚁（Fisheropone pilosior）': 'Fisheropone pilosior',
      },
    ),
  ]) {
    testWidgets('shared $query shows distinguishable candidates', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
      await tester.tap(find.widgetWithText(TextFormField, '品种分类/细分种类'));
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(ListTile),
        ),
        findsNWidgets(expected.length),
      );
      for (final entry in expected.entries) {
        final tile = find.widgetWithText(ListTile, entry.key);
        expect(tile, findsOneWidget);
        final widget = tester.widget<ListTile>(tile);
        final visibleText =
            '${(widget.title as Text).data} ${(widget.subtitle as Text?)?.data ?? ''}';
        expect(visibleText, contains(entry.value));
      }
      await tester.tap(find.widgetWithText(ListTile, expected.keys.last));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '蚁群昵称 *'))
            .controller!
            .text,
        expected.keys.last,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
