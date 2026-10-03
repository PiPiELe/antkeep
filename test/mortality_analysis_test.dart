import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/mortality_analysis.dart';
import 'package:antkeep/domain/population_analysis.dart';
import 'package:antkeep/population_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 1, 15);
CareRecord record(
  String id,
  DateTime time,
  int? count, {
  String colonyId = 'a',
  CareRecordType type = CareRecordType.mortality,
}) => CareRecord(
  id: id,
  colonyId: colonyId,
  type: type,
  occurredAt: time,
  createdAt: now,
  workerMortalityCount: count,
);

void main() {
  test('sums events per local day, preserves zero and excludes missing or unrelated values', () {
    final points = dailyWorkerMortality('a', [
      record('later', DateTime(2026, 9, 30), 0),
      record('backdated', DateTime(2026, 9, 20, 8), 2),
      record('same-instant', DateTime(2026, 9, 20, 8), 3),
      record('evening', DateTime(2026, 9, 20, 20), 4),
      record('blank', DateTime(2026, 9, 21), null),
      record('invalid', DateTime(2026, 9, 22), -1),
      record('other', DateTime(2026, 9, 23), 999, colonyId: 'b'),
      record(
        'observation',
        DateTime(2026, 9, 24),
        999,
        type: CareRecordType.observation,
      ),
      record('future', DateTime(2026, 10, 2), 999),
      record('today', DateTime(2026, 10, 1, 12), 1),
    ], now: now);
    expect(points.map((p) => p.time), [
      DateTime(2026, 9, 20),
      DateTime(2026, 9, 30),
      DateTime(2026, 10, 1),
    ]);
    expect(points.map((p) => p.count), [9, 0, 1]);
  });

  test('compares equal completed calendar periods and excludes today and older events', () {
    final result = MortalityComparison([
      PopulationPoint(DateTime(2026, 9, 16), 999),
      PopulationPoint(DateTime(2026, 9, 17), 2),
      PopulationPoint(DateTime(2026, 9, 23), 3),
      PopulationPoint(DateTime(2026, 9, 24), 6),
      PopulationPoint(DateTime(2026, 9, 30), 4),
      PopulationPoint(DateTime(2026, 10, 1), 999),
    ], now: now);
    expect(result.previousTotal, 5);
    expect(result.recentTotal, 10);
    expect(result.previousDays, 2);
    expect(result.recentDays, 2);
    expect(result.delta, 5);
    expect(result.percent, 100);
    expect(result.label, '已记录死亡量上升');
  });

  test(
    'missing periods differ from explicit zero; handles decrease and flat',
    () {
      MortalityComparison compare(int? previous, int? recent) =>
          MortalityComparison([
            if (previous != null)
              PopulationPoint(DateTime(2026, 9, 20), previous),
            if (recent != null) PopulationPoint(DateTime(2026, 9, 28), recent),
          ], now: now);
      expect(compare(null, 5).comparable, isFalse);
      expect(compare(5, null).label, '数据不足，暂无法比较');
      expect(compare(0, 5).label, '已记录死亡量上升');
      expect(compare(0, 5).percent, isNull);
      expect(compare(5, 0).percent, -100);
      expect(compare(5, 0).label, '已记录死亡量下降');
      expect(compare(0, 0).label, '已记录死亡量持平');
      expect(compare(5, 5).percent, 0);
    },
  );

  testWidgets(
    'separate death tab sums events, switches colony, handles errors and preserves quantity analysis',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateTime.now();
      final previous = DateTime(today.year, today.month, today.day - 10);
      final recent = DateTime(today.year, today.month, today.day - 2);
      var fail = false;
      final colonies = [
        for (final id in ['a', 'b'])
          Colony(
            id: id,
            name: id,
            createdAt: previous.subtract(const Duration(days: 1)),
            updatedAt: today,
            initialWorkerCount: 10,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: PopulationAnalysisPage(
            loadColonies: () async => colonies,
            loadRecords: (id) async {
              if (fail) throw StateError('read failed');
              return id == 'a'
                  ? [
                      record('previous', previous, 2),
                      record('recent', recent, 3),
                      record('another', recent, 4),
                    ]
                  : [];
            },
            loadFeederRecords: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('死亡分析'));
      await tester.pumpAndSettle();
      expect(find.text('选择一窝蚁群，查看工蚁死亡量变化。'), findsOneWidget);
      Future<void> select(String id) async {
        await tester.tap(find.byKey(const ValueKey('mortality-subject')));
        await tester.pumpAndSettle();
        expect(find.text('DLC · 杜比亚'), findsNothing);
        await tester.tap(find.text('蚁群 · $id').last);
        await tester.pumpAndSettle();
      }

      await select('a');
      expect(find.text('已记录死亡量上升'), findsOneWidget);
      expect(find.text('最近 7 日 · 7 只 · 已记录 1/7 天'), findsOneWidget);
      expect(find.text('前 7 日 · 2 只 · 已记录 1/7 天'), findsOneWidget);
      expect(find.textContaining('+250.0%'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('population-forecast-toggle')),
        findsNothing,
      );
      await tester.scrollUntilVisible(find.text('每日明细'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('每日明细'));
      await tester.pumpAndSettle();
      expect(find.text('7 只'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mortality-subject')),
        -250,
      );
      await tester.pumpAndSettle();
      await select('b');
      expect(find.textContaining('暂无工蚁死亡数量记录'), findsOneWidget);
      fail = true;
      await select('a');
      expect(find.text('死亡数量读取失败，点击重试'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('死亡数量读取失败，点击重试'));
      await tester.pumpAndSettle();
      expect(find.text('已记录死亡量上升'), findsOneWidget);
      await tester.tap(find.text('数量分析'));
      await tester.pumpAndSettle();
      expect(find.text('工蚁 · 最近 1 只 · 3 个时间点'), findsOneWidget);
      expect(find.text('已记录死亡量上升'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('analysis-subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DLC · 杜比亚').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('死亡分析'));
      await tester.pumpAndSettle();
      expect(find.text('选择一窝蚁群，查看工蚁死亡量变化。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
