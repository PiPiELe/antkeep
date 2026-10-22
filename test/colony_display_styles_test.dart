import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/colony_display_styles.dart';
import 'package:antkeep/domain/care_task.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/colony_list_filter.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();
  final colony = Colony(
    id: 'colony-1',
    name: '一号群 · 黑金弓背蚁',
    species: '黑金弓背蚁',
    nestType: '试管巢',
    acquiredOn: now.subtract(const Duration(days: 44)),
    purchasePriceCents: 1000000,
    queenCount: 2,
    initialWorkerCount: 235,
    initialEggCount: 8,
    createdAt: now,
    updatedAt: now,
  );
  final dueTasks = [
    CareTask(
      id: 'feed',
      colonyId: colony.id,
      type: CareTaskType.feeding,
      intervalDays: 3,
      nextDueOn: now,
    ),
    CareTask(
      id: 'water',
      colonyId: colony.id,
      type: CareTaskType.watering,
      intervalDays: 3,
      nextDueOn: now,
    ),
  ];

  for (final style in [
    ColonyDisplayStyle.showcase,
    ColonyDisplayStyle.compact,
  ]) {
    for (final (width, scale) in [(360.0, 1.0), (320.0, 1.3)]) {
      testWidgets(
        '${style.label} card fits ${width.toInt()}px at text scale $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var opened = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: antKeepTheme(ThemeColor.amber, dark: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ColonyShowcaseOverview(
                      count: 1,
                      queens: '2',
                      workers: '235',
                    ),
                    const SizedBox(height: 12),
                    ColonyShowcaseCard(
                      style: style,
                      colony: colony,
                      population: const GrowthPopulation(
                        eggs: 8,
                        larvae: 12,
                        cocoons: 4,
                        workers: 235,
                      ),
                      queens: 2,
                      workers: 235,
                      dueTasks: dueTasks,
                      onTap: () => opened = true,
                      onDurationTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('万元级'), findsOneWidget);
          expect(find.text('蚁群总数'), findsOneWidget);
          expect(find.text('一号群 · 黑金弓背蚁'), findsOneWidget);
          expect(find.text('今日待办'), findsOneWidget);
          expect(find.text('2 项'), findsOneWidget);
          expect(
            tester.getCenter(find.text('今日待办')).dy,
            closeTo(tester.getCenter(find.text('投喂')).dy, 1),
          );
          expect(find.text('235'), findsWidgets);
          await tester.tap(find.text('一号群 · 黑金弓背蚁'));
          expect(opened, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('showcase and compact share the single-row toolbar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    ColonyWorkerOrder? selectedOrder;
    var filtered = false;
    var batched = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: antKeepTheme(ThemeColor.amber, dark: true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ColonyShowcaseToolbar(
              visibleCount: 2,
              totalCount: 4,
              filterCount: 5,
              workerOrder: ColonyWorkerOrder.manual,
              canBatchCare: true,
              onBatchCare: () => batched = true,
              onWorkerOrder: (value) => selectedOrder = value,
              onFilter: () => filtered = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 4 群'), findsOneWidget);
    expect(find.text('默认排序'), findsOneWidget);
    expect(find.text('筛选 5'), findsOneWidget);
    expect(find.text('卡片右滑删除\n长按滑动排序'), findsOneWidget);
    expect(find.text('批量养护记录'), findsNothing);
    expect(
      tester.getSize(find.byType(ColonyShowcaseToolbar)).height,
      lessThan(70),
    );
    await tester.tap(find.text('筛选 5'));
    expect(filtered, isTrue);
    await tester.tap(find.text('默认排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工蚁多到少'));
    await tester.pumpAndSettle();
    expect(selectedOrder, ColonyWorkerOrder.descending);
    await tester.tap(find.text('默认排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量养护记录'));
    expect(batched, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showcase layout follows the selected light color theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: antKeepTheme(ThemeColor.amber),
        home: Scaffold(
          body: ColonyShowcaseCard(
            style: ColonyDisplayStyle.showcase,
            colony: colony,
            population: const GrowthPopulation(workers: 235),
            queens: 2,
            workers: 235,
            dueTasks: const [],
            onTap: () {},
            onDurationTap: () {},
          ),
        ),
      ),
    );
    final name = tester.widget<Text>(find.text('一号群 · 黑金弓背蚁'));
    expect(
      name.style?.color,
      antKeepTheme(ThemeColor.amber).colorScheme.onSurface,
    );
    expect(tester.takeException(), isNull);
  });
}
