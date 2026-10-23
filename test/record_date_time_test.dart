import 'package:antkeep/record_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final current = DateTime(2020, 6, 10, 12, 30);

  for (final hasTime in [false, true]) {
    testWidgets(
      'date selection preserves only an enabled specific time ($hasTime)',
      (tester) async {
        DateTime? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => selected = await pickRecordDate(
                  context,
                  current,
                  hasSpecificTime: hasTime,
                ),
                child: const Text('Pick'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('14'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          selected,
          DateTime(2020, 6, 14, hasTime ? 12 : 0, hasTime ? 30 : 0),
        );
      },
    );
  }

  testWidgets('canceling either picker returns no change', (tester) async {
    DateTime? selected = current;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () async => selected = await pickRecordDate(
                  context,
                  current,
                  hasSpecificTime: true,
                ),
                child: const Text('Date'),
              ),
              TextButton(
                onPressed: () async => selected = await pickRecordTime(
                  context,
                  current,
                  hasSpecificTime: true,
                ),
                child: const Text('Time'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final action in ['Date', 'Time']) {
      selected = current;
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    }
  });

  testWidgets('specific time selection preserves the selected date', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => selected = await pickRecordTime(
              context,
              current,
              hasSpecificTime: true,
            ),
            child: const Text('Pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime,
      const TimeOfDay(hour: 12, minute: 30),
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selected, current);
  });
}
