import 'package:antkeep/colony_overview_page.dart';
import 'package:antkeep/domain/memorial.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 16);

  Colony colony(
    String id, {
    int? queens,
    int? workers,
    bool archived = false,
  }) => Colony(
    id: id,
    name: id,
    queenCount: queens,
    initialWorkerCount: workers,
    archived: archived,
    createdAt: day,
    updatedAt: day,
  );

  CareRecord record(
    String id,
    String colonyId,
    int dayOffset, {
    int? workers,
    int? workerDeaths,
    int? queenDeaths,
  }) => CareRecord(
    id: id,
    colonyId: colonyId,
    type: workerDeaths != null || queenDeaths != null
        ? CareRecordType.mortality
        : CareRecordType.observation,
    occurredAt: day.add(Duration(days: dayOffset)),
    createdAt: day.add(Duration(days: dayOffset)),
    workerCount: workers,
    workerMortalityCount: workerDeaths,
    queenMortalityCount: queenDeaths,
  );

  Memorial memorial(String id, MemorialKind kind) =>
      Memorial(id: id, kind: kind, name: id, createdAt: day);

  test('overview separates lifetime, active, and memorial counts', () {
    final stats = ColonyOverviewStats.fromData(
      [
        colony('new', queens: 2, workers: 0),
        colony('archived', queens: 1, workers: 10, archived: true),
        colony('unknown'),
      ],
      {
        'new': [
          record('n1', 'new', 1, workers: 5),
          record('n2', 'new', 2, workerDeaths: 2, queenDeaths: 1),
          record('n3', 'new', 3, workers: 5, workerDeaths: 1),
        ],
        'archived': [
          record('a1', 'archived', 1, workers: 15),
          record('a2', 'archived', 2, workerDeaths: 5),
        ],
        'unknown': [record('u1', 'unknown', 1, workers: 7)],
      },
      [
        memorial('queen', MemorialKind.queen),
        memorial('worker1', MemorialKind.worker),
        memorial('worker2', MemorialKind.worker),
        memorial('brood', MemorialKind.brood),
      ],
    );

    expect(stats.historicalColonies, 3);
    expect(stats.historicalNewQueenColonies, 1);
    expect(stats.historicalQueens, '≥3');
    expect(stats.historicalWorkers, '≥30');
    expect(stats.activeColonies, 2);
    expect(stats.activeNewQueenColonies, 1);
    expect(stats.activeQueens, '≥1');
    expect(stats.activeWorkers, '12');
    expect(stats.memorialColonies, 1);
    expect(stats.memorialQueens, 1);
    expect(stats.memorialWorkers, 2);
  });

  testWidgets('overview sections fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stats = ColonyOverviewStats.fromData([], {}, []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColonyOverviewPage(active: true, loadStats: () async => stats),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('现役'), findsOneWidget);
    expect(find.text('英灵殿'), findsOneWidget);
    expect(find.text('工蚁数'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
