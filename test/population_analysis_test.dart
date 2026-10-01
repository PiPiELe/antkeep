import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/population_analysis.dart';
import 'package:antkeep/population_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final start = DateTime(2026, 1, 1);
final colony = Colony(
  id: 'a',
  name: '一号蚁群',
  createdAt: start,
  updatedAt: start,
  initialWorkerCount: 0,
);

CareRecord record(
  String id,
  int day,
  int? count, {
  String colonyId = 'a',
  int? createdDay,
}) => CareRecord(
  id: id,
  colonyId: colonyId,
  type: CareRecordType.observation,
  occurredAt: start.add(Duration(days: day)),
  createdAt: start.add(Duration(days: createdDay ?? day)),
  workerCount: count,
);

FeederRecord feederRecord(
  String id,
  int day,
  int? juveniles,
  int? adults, {
  FeederType feeder = FeederType.dubia,
}) => FeederRecord(
  id: id,
  feeder: feeder,
  type: FeederRecordType.values.first,
  occurredAt: start.add(Duration(days: day)),
  createdAt: start.add(Duration(days: day)),
  juvenileCount: juveniles,
  adultCount: adults,
  mortalityCount: 5,
);

void main() {
  test(
    'classifies equal, monotonic and fluctuating observations conservatively',
    () {
      PopulationTrend trend(List<int> counts) => populationTrend([
        for (var i = 0; i < counts.length; i++)
          PopulationPoint(start.add(Duration(days: i)), counts[i]),
      ]);
      expect(trend([]), PopulationTrend.insufficient);
      expect(trend([0]), PopulationTrend.insufficient);
      expect(trend([0, 2]), PopulationTrend.insufficient);
      expect(trend([0, 0, 0]), PopulationTrend.flat);
      expect(trend([10, 10, 10]), PopulationTrend.flat);
      expect(trend([0, 2, 2, 5]), PopulationTrend.rising);
      expect(trend([10, 5, 5, 0]), PopulationTrend.falling);
      expect(trend([10, 12, 11]), PopulationTrend.fluctuating);
    },
  );

  test('sorts backdated records, isolates colonies, skips unknown and retains zero', () {
    final points = colonyPopulation(colony, [
      record('late', 10, 20),
      record('backdated', 2, 4, createdDay: 12),
      record('unknown', 5, null),
      record('other', 4, 999, colonyId: 'b'),
      record('invalid', 6, -1),
    ], PopulationMetric.workers);
    expect(points.map((p) => p.count), [0, 4, 20]);
    expect(points.map((p) => p.time), [
      start,
      start.add(const Duration(days: 2)),
      start.add(const Duration(days: 10)),
    ]);
    expect(populationTrend(points), PopulationTrend.rising);
    expect(colonyPopulation(colony, [], PopulationMetric.larvae), isEmpty);
  });

  test(
    'same instant uses newest known observation, including over initial count',
    () {
      final points = colonyPopulation(colony, [
        record('new', 0, 5, createdDay: 5),
        record('old', 0, 3, createdDay: 1),
        record('blank', 0, null, createdDay: 6),
      ], PopulationMetric.workers);
      expect(points.single.count, 5);
      expect(populationTrend(points), PopulationTrend.insufficient);
    },
  );

  test('colony total keeps latest known counts and can include brood', () {
    final totalColony = Colony(
      id: 'total',
      name: '总数测试',
      queenCount: 1,
      initialWorkerCount: 5,
      initialEggCount: 2,
      initialCocoonCount: 3,
      createdAt: start,
      updatedAt: start,
    );
    final records = [
      CareRecord(
        id: 'workers-and-eggs',
        colonyId: totalColony.id,
        type: CareRecordType.observation,
        occurredAt: start.add(const Duration(days: 1)),
        createdAt: start.add(const Duration(days: 1)),
        workerCount: 6,
        eggCount: 4,
      ),
      CareRecord(
        id: 'larvae',
        colonyId: totalColony.id,
        type: CareRecordType.observation,
        occurredAt: start.add(const Duration(days: 2)),
        createdAt: start.add(const Duration(days: 2)),
        larvaCount: 1,
      ),
    ];

    expect(
      colonyPopulationTotal(
        totalColony,
        records,
        includeBrood: false,
      ).map((point) => point.count),
      [6, 7],
    );
    expect(
      colonyPopulationTotal(
        totalColony,
        records,
        includeBrood: true,
      ).map((point) => point.count),
      [11, 14, 15],
    );
  });

  test('DLC totals require both counts and never subtract event mortality', () {
    final records = [
      feederRecord('first', 0, 10, 2),
      feederRecord('partial', 1, 20, null),
      feederRecord('zero', 2, 0, 0),
      feederRecord('other', 3, 999, 999, feeder: FeederType.cricket),
    ];
    expect(
      feederPopulation(
        FeederType.dubia,
        records,
        PopulationMetric.total,
      ).map((p) => p.count),
      [12, 0],
    );
    expect(
      feederPopulation(
        FeederType.dubia,
        records,
        PopulationMetric.juveniles,
      ).map((p) => p.count),
      [10, 20, 0],
    );
  });

  testWidgets(
    'switches between colonies and DLC, and handles missing quantities',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final other = Colony(
        id: 'b',
        name: '二号蚁群',
        createdAt: start,
        updatedAt: start,
        initialWorkerCount: 50,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PopulationAnalysisPage(
            loadColonies: () async => [colony, other],
            loadRecords: (id) async =>
                id == 'a' ? [record('1', 1, 2), record('2', 2, 4)] : [],
            loadFeederRecords: (feeder) async => [feederRecord('f', 0, 2, 3)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> select(String text) async {
        await tester.tap(find.byKey(const ValueKey('analysis-subject')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      await select('蚁群 · 一号蚁群');
      expect(find.text('稳定上升'), findsOneWidget);
      expect(find.text('工蚁 · 最近 4 只 · 3 个时间点'), findsOneWidget);
      await tester.tap(find.text('幼虫'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无有效数量记录'), findsOneWidget);
      await select('蚁群 · 二号蚁群');
      expect(find.text('工蚁 · 最近 50 只 · 1 个时间点'), findsOneWidget);
      expect(find.text('数据不足'), findsOneWidget);
      await select('DLC · 杜比亚');
      expect(find.text('总数量 · 最近 5 只 · 1 个时间点'), findsOneWidget);
      await tester.tap(find.text('成体'));
      await tester.pumpAndSettle();
      expect(find.text('成体 · 最近 3 只 · 1 个时间点'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forecast defaults off, changes horizon and never changes history statistics',
    (tester) async {
      final now = DateTime.now();
      final growing = Colony(
        id: 'forecast',
        name: '预测群',
        createdAt: now,
        updatedAt: now,
        initialWorkerCount: 10,
        initialEggCount: 0,
        initialLarvaCount: 100,
        growth: ColonyGrowth(
          frequency: GrowthFrequency.daily,
          path: GrowthPath.eggToWorker,
          startedAt: now,
          workers: 1,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PopulationAnalysisPage(
            loadColonies: () async => [growing],
            loadRecords: (_) async => [],
            loadFeederRecords: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analysis-subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('蚁群 · 预测群').last);
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('population-forecast-toggle'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(
        find.byKey(const ValueKey('population-forecast-summary')),
        findsNothing,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 天'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('population-forecast-summary')),
      );
      expect(find.textContaining('17 只（估算）'), findsOneWidget);
      expect(find.text('工蚁 · 最近 10 只 · 1 个时间点'), findsOneWidget);
      expect(find.text('数据不足'), findsOneWidget);
      await tester.ensureVisible(find.text('14 天'));
      await tester.tap(find.text('14 天'));
      await tester.pumpAndSettle();
      expect(find.textContaining('24 只（估算）'), findsOneWidget);
      await tester.ensureVisible(find.text('幼虫'));
      await tester.tap(find.text('幼虫'));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(
        find.byKey(const ValueKey('population-forecast-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('86 只（估算）'), findsOneWidget);
      expect(find.text('幼虫 · 最近 100 只 · 1 个时间点'), findsOneWidget);
      await tester.tap(find.text('工蚁'));
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('population-forecast-summary')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'DLC remains available without any colonies and record failures can retry',
    (tester) async {
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: PopulationAnalysisPage(
            loadColonies: () async => [],
            loadFeederRecords: (_) async {
              if (fail) throw StateError('read failed');
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analysis-subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DLC · 杜比亚').last);
      await tester.pumpAndSettle();
      expect(find.text('数量读取失败，点击重试'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('数量读取失败，点击重试'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无有效数量记录'), findsOneWidget);
    },
  );
}
