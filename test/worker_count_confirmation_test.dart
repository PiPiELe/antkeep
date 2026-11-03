import 'package:antkeep/online/worker_count_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'visible count is advisory and requires a separately entered total',
    (tester) async {
      int? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  confirmed = await confirmWorkerTotal(
                    context,
                    visibleCount: 12,
                    uncertain: true,
                  );
                },
                child: const Text('识别'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('识别'));
      await tester.pumpAndSettle();
      expect(find.text('照片中可见工蚁约 12 只。'), findsOneWidget);
      expect(find.text('画面有遮挡或模糊，识别结果可能不准确。'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        isEmpty,
      );

      await tester.tap(find.text('填入我确认的总数'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 0～1000000 的整数'), findsOneWidget);
      expect(confirmed, isNull);

      await tester.enterText(find.byType(TextFormField), '25');
      await tester.tap(find.text('填入我确认的总数'));
      await tester.pumpAndSettle();
      expect(confirmed, 25);
    },
  );

  testWidgets('viewing the estimate does not supply a diary total', (
    tester,
  ) async {
    int? confirmed = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmed = await confirmWorkerTotal(
                  context,
                  visibleCount: 12,
                  uncertain: false,
                );
              },
              child: const Text('识别'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('识别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅查看结果'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
  });
}
