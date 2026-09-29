import 'package:antkeep/domain/spending_analysis.dart';
import 'package:antkeep/population_analysis_page.dart';
import 'package:antkeep/spending_analysis_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const empty = SpendingSummary(
  coloniesCents: 0,
  inventoryCents: 0,
  feedersCents: 0,
);
const spending = SpendingSummary(
  coloniesCents: 10001,
  inventoryCents: 5000,
  feedersCents: 5000,
);

void main() {
  testWidgets(
    'analysis tabs show all spending and preserve population selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: PopulationAnalysisPage(
            loadColonies: () async => [],
            loadFeederRecords: (_) async => [],
            loadSpending: () async => spending,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analysis-subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DLC · 杜比亚').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('消费占比'));
      await tester.pumpAndSettle();
      expect(find.text('¥200.01'), findsOneWidget);
      expect(find.text('蚁群\n¥100.01 · 50.0%'), findsOneWidget);
      expect(find.text('已购物品\n¥50.00 · 25.0%'), findsOneWidget);
      expect(find.text('DLC 养殖\n¥50.00 · 25.0%'), findsOneWidget);
      expect(find.byKey(const ValueKey('spending-pie')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('数量分析'));
      await tester.pumpAndSettle();
      expect(find.text('DLC · 杜比亚'), findsOneWidget);
      expect(find.textContaining('暂无有效数量记录'), findsOneWidget);
    },
  );

  testWidgets('empty totals show no pie; retry and refresh load new amounts', (
    tester,
  ) async {
    var fail = true;
    var value = empty;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpendingAnalysisView(
            loadSummary: () async {
              if (fail) throw StateError('read failed');
              return value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('消费读取失败，点击重试'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('消费读取失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.textContaining('暂无可展示的消费占比'), findsOneWidget);
    expect(find.byKey(const ValueKey('spending-pie')), findsNothing);
    value = const SpendingSummary(
      coloniesCents: 29,
      inventoryCents: 0,
      feedersCents: 0,
    );
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    expect(find.text('蚁群\n¥0.29 · 100.0%'), findsOneWidget);
    expect(find.byKey(const ValueKey('spending-pie')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
