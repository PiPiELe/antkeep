import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/population_analysis.dart';
import 'package:antkeep/domain/population_forecast.dart';
import 'package:antkeep/domain/record_increment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 1, 1);
  final colony = Colony(
    id: 'colony',
    name: '测试',
    createdAt: start,
    updatedAt: start,
    queenCount: 1,
    initialWorkerCount: 100,
    initialEggCount: 10,
    initialLarvaCount: 8,
    initialCocoonCount: 5,
  );
  CareRecord record(
    String id,
    int day, {
    int? deaths,
    int? workers,
    int? eggs,
    int? createdDay,
    String colonyId = 'colony',
    CareRecordType type = CareRecordType.mortality,
  }) => CareRecord(
    id: id,
    colonyId: colonyId,
    type: type,
    occurredAt: start.add(Duration(days: day)),
    createdAt: start.add(Duration(days: createdDay ?? day)),
    workerMortalityCount: deaths,
    workerCount: workers,
    eggCount: eggs,
  );
  List<int> counts(List<CareRecord> records, {bool brood = false}) =>
      colonyPopulationTotal(
        colony,
        records,
        includeBrood: brood,
      ).map((p) => p.count).toList();

  test('death-only events reduce current workers and both quantity charts', () {
    final records = [
      record('death', 1, deaths: 3),
      record('death2', 2, deaths: 2),
    ];
    expect(colony.currentPopulation(records).workers, 95);
    expect(colony.currentWorkerCount(records.reversed), 95);
    expect(counts(records), [101, 98, 96]);
    expect(counts(records, brood: true), [124, 121, 119]);
    expect(
      colonyPopulation(
        colony,
        records,
        PopulationMetric.workers,
      ).map((p) => p.count),
      [100, 97, 95],
    );
    expect(colony.currentPopulation(records).cocoons, 5);
    expect(
      colonyPopulation(
        colony,
        records,
        PopulationMetric.eggs,
      ).map((p) => p.count),
      [10],
    );
  });

  test('backdated deaths replay chronologically and later totals reset the baseline', () {
    final records = [
      record('snapshot', 3, workers: 80, deaths: 4),
      record('later', 4, deaths: 2),
      record('backdated', 1, deaths: 3, eggs: 4, createdDay: 10),
      record('brood-only', 2, eggs: 6),
      record('other', 5, deaths: 100, colonyId: 'other'),
    ];
    expect(colony.currentWorkerCount(records), 78);
    expect(counts(records), [101, 98, 81, 79]);
    expect(counts(records, brood: true), [124, 115, 117, 100, 98]);
    expect(colony.currentPopulation(records).eggs, 6);
  });

  test('edits, deletion and changing the record type replay death events', () {
    final first = record('first', 1, deaths: 3);
    final last = record('last', 2, deaths: 2);
    expect(colony.currentWorkerCount([first, last]), 95);
    expect(
      colony.currentWorkerCount([record('first', 1, deaths: 8), last]),
      90,
    );
    expect(colony.currentWorkerCount([last]), 98);
    expect(
      colony.currentWorkerCount([
        record('first', 1, deaths: 8, type: CareRecordType.observation),
        last,
      ]),
      98,
    );
    expect(
      colony.currentWorkerCount([
        first,
        record('snapshot', 3, workers: 50),
        last,
      ]),
      50,
    );
  });

  test(
    'unknown stays unknown, zero and excessive mortality never yield negatives',
    () {
      final unknown = Colony.fromMap({
        ...colony.toMap(),
        'initial_worker_count': null,
      });
      expect(
        unknown.currentWorkerCount([record('death', 1, deaths: 3)]),
        isNull,
      );
      expect(
        colonyPopulation(unknown, [
          record('death', 1, deaths: 3),
        ], PopulationMetric.workers),
        isEmpty,
      );
      expect(colony.currentWorkerCount([record('zero', 1, deaths: 0)]), 100);
      expect(colony.currentWorkerCount([record('unknown', 1)]), 100);
      expect(
        colony.currentWorkerCount([record('invalid', 1, deaths: -1)]),
        100,
      );
      expect(colony.currentWorkerCount([record('many', 1, deaths: 101)]), 0);
      expect(
        colony.currentWorkerCount([
          record('zero-snapshot', 1, workers: 0, deaths: 3),
        ]),
        0,
      );
    },
  );

  test(
    'same timestamp has stable ordering and every death is counted once',
    () {
      final records = [record('b', 1, deaths: 2), record('a', 1, deaths: 3)];
      expect(counts(records), [101, 96]);
      expect(colony.currentWorkerCount(records), 95);
      records.add(record('c', 1, workers: 70, deaths: 10));
      expect(counts(records), [101, 71]);
      expect(colony.currentWorkerCount(records.reversed), 70);
    },
  );

  test(
    'increments use the reduced baseline and combined deaths are deducted once',
    () {
      final death = record('death', 1, deaths: 3);
      final deathOnly = resolveRecordIncrement(colony, [], death);
      expect(deathOnly.workerCount, isNull);
      expect(colony.currentWorkerCount([deathOnly]), 97);
      final added = resolveRecordIncrement(colony, [
        death,
      ], record('added', 2, workers: 2));
      expect(added.workerCount, 99);
      expect(added.pupaCount, 3);
      final combined = resolveRecordIncrement(colony, [
        death,
      ], record('both', 2, workers: 2, deaths: 4));
      expect(combined.workerCount, 95);
      expect(combined.pupaCount, 3);
      expect(colony.currentWorkerCount([death, combined]), 95);
      final zero = resolveRecordIncrement(
        colony,
        [],
        record('zero', 1, workers: 0, deaths: 3),
      );
      expect(colony.currentWorkerCount([zero]), 97);
    },
  );

  test(
    'growth forecast starts from post-mortality population without mutation',
    () {
      final growing = Colony.fromMap({
        ...colony.toMap(),
        'auto_growth_json': ColonyGrowth(
          frequency: GrowthFrequency.daily,
          path: GrowthPath.eggToCocoonToWorker,
          startedAt: start,
          workers: 1,
        ).encode(),
      });
      final death = record('death', 1, deaths: 3);
      final forecast = colonyPopulationForecast(
        growing,
        [death],
        now: start.add(const Duration(days: 1)),
        horizon: ForecastHorizon.week,
      );
      expect(forecast.first.count, 97);
      expect(forecast[1].count, 98);
      expect(death.workerCount, isNull);
      expect(growing.growth!.completedCycles, 0);
    },
  );
}
