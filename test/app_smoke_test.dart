import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application shell can be constructed', () {
    expect(const AntKeepApp(), isA<AntKeepApp>());
  });

  testWidgets('date and time pickers stay Chinese on an English device', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(const AntKeepApp());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('zh', 'CN'));

    final dateResult = showDatePicker(
      context: context,
      initialDate: DateTime(2026, 9, 30),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026年9月'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.textContaining('September'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(await dateResult, DateTime(2026, 9, 30));

    final timeResult = showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 13, minute: 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(await timeResult, const TimeOfDay(hour: 13, minute: 5));
    expect(tester.takeException(), isNull);
  });
}
