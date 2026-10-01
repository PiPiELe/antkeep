import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/population_analysis.dart';
import 'package:antkeep/domain/population_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2028, 1, 31, 12);
  Colony colony({
    GrowthFrequency frequency = GrowthFrequency.daily,
    GrowthPath path = GrowthPath.eggToWorker,
    int? eggs,
    int? cocoons,
    int? workers = 1,
    int? initialWorkers = 20,
  }) => Colony(
    id: 'a',
    name: '预测测试',
    createdAt: now,
    updatedAt: now,
    queenCount: 1,
    initialEggCount: 10,
    initialCocoonCount: 5,
    initialWorkerCount: initialWorkers,
    growth: ColonyGrowth(
      frequency: frequency,
      path: path,
      startedAt: now,
      eggs: eggs,
      cocoons: cocoons,
      workers: workers,
    ),
  );

  test('horizon never exceeds one calendar month, including month-end and leap years', () {
    expect(ForecastHorizon.month.endFrom(now), DateTime(2028, 2, 29, 12));
    expect(
      ForecastHorizon.month.endFrom(DateTime(2027, 1, 31)),
      DateTime(2027, 2, 28),
    );
    expect(ForecastHorizon.week.endFrom(now), DateTime(2028, 2, 7, 12));
    expect(ForecastHorizon.fortnight.endFrom(now), DateTime(2028, 2, 14, 12));
    final points = colonyPopulationForecast(colony(eggs: 2), [], now: now);
    expect(points.first.time, now);
    expect(points.last.time, DateTime(2028, 2, 29, 12));
    expect(points.last.count, 49);
    expect(points, hasLength(30));
  });

  test('forecast shares conversion limits and net growth semantics', () {
    final conversion = colonyPopulationForecast(colony(), [], now: now);
    expect(conversion.last.count, 30);
    final eggs = colonyPopulationForecast(
      colony(),
      [],
      now: now,
      metric: PopulationMetric.eggs,
    );
    expect(eggs.last.count, 0);
    final independent = colonyPopulationForecast(
      colony(eggs: 2),
      [],
      now: now,
      horizon: ForecastHorizon.week,
      metric: PopulationMetric.eggs,
    );
    expect(independent.last.count, 24);
    final cocoons = colonyPopulationForecast(
      colony(path: GrowthPath.eggToCocoonToWorker),
      [],
      now: now,
      metric: PopulationMetric.pupae,
    );
    expect(cocoons.last.count, 0);
    final workers = colonyPopulationForecast(
      colony(path: GrowthPath.eggToCocoonToWorker),
      [],
      now: now,
    );
    expect(workers.last.count, 25);
  });

  test('weekly and monthly rules only change on their scheduled cycles', () {
    final weekly = colonyPopulationForecast(
      colony(frequency: GrowthFrequency.weekly, eggs: 0),
      [],
      now: now,
      horizon: ForecastHorizon.fortnight,
    );
    expect(weekly.map((p) => p.count), [20, 21, 22]);
    final monthly = colonyPopulationForecast(
      colony(frequency: GrowthFrequency.monthly),
      [],
      now: now,
    );
    expect(monthly.map((p) => p.count), [20, 21]);
    final short = colonyPopulationForecast(
      colony(frequency: GrowthFrequency.monthly),
      [],
      now: now,
      horizon: ForecastHorizon.week,
    );
    expect(short.map((p) => p.count), [20, 20]);
    expect(short.last.time, ForecastHorizon.week.endFrom(now));
  });

  test('latest partial observations anchor forecast without mutating data or using future/other colonies', () {
    final c = colony(eggs: 2);
    CareRecord observation(
      String id,
      DateTime time, {
      String colonyId = 'a',
      int? workers,
      int? eggs,
    }) => CareRecord(
      id: id,
      colonyId: colonyId,
      type: CareRecordType.observation,
      occurredAt: time,
      createdAt: time,
      workerCount: workers,
      eggCount: eggs,
    );
    final records = [
      observation('old', now.subtract(const Duration(hours: 2)), workers: 30),
      observation('new', now.subtract(const Duration(hours: 1)), eggs: 50),
      observation('other', now, colonyId: 'b', workers: 999),
      observation('future', now.add(const Duration(days: 2)), workers: 999),
    ];
    final beforeColony = c.toMap();
    final beforeRecords = records.map((r) => r.toMap()).toList();
    final points = colonyPopulationForecast(
      c,
      records,
      now: now,
      horizon: ForecastHorizon.week,
    );
    expect(points.first.count, 30);
    expect(points.last.count, 37);
    expect(
      colonyPopulationForecast(
        c,
        records,
        now: now,
        horizon: ForecastHorizon.week,
        metric: PopulationMetric.eggs,
      ).last.count,
      64,
    );
    expect(c.toMap(), beforeColony);
    expect(records.map((r) => r.toMap()).toList(), beforeRecords);
  });

  test('total respects brood selection and predictions do not fabricate unknown quantities', () {
    final withBrood = colonyPopulationForecast(
      colony(),
      [],
      now: now,
      metric: PopulationMetric.total,
      includeBrood: true,
    );
    expect(withBrood.first.count, 36);
    expect(withBrood.last.count, 36);
    final withoutBrood = colonyPopulationForecast(
      colony(),
      [],
      now: now,
      metric: PopulationMetric.total,
      includeBrood: false,
    );
    expect(withoutBrood.first.count, 21);
    expect(withoutBrood.last.count, 31);
    expect(
      colonyPopulationForecast(colony(initialWorkers: null), [], now: now),
      isEmpty,
    );
    expect(
      colonyPopulationForecast(
        colony(),
        [],
        now: now,
        metric: PopulationMetric.larvae,
      ),
      isEmpty,
    );
    expect(
      colonyPopulationForecast(
        Colony.fromMap({...colony().toMap(), 'auto_growth_json': null}),
        [],
        now: now,
      ),
      isEmpty,
    );
  });

  test(
    'saved progress is not replayed and overdue cycles are not applied twice',
    () {
      final c = colony(eggs: 0);
      final later = now.add(const Duration(days: 5, hours: 1));
      final completed = Colony.fromMap({
        ...c.toMap(),
        'auto_growth_json': c.growth!.completed(5).encode(),
      });
      final record = CareRecord(
        id: 'settled',
        colonyId: c.id,
        type: CareRecordType.observation,
        occurredAt: now.add(const Duration(days: 5)),
        createdAt: later,
        workerCount: 25,
      );
      final points = colonyPopulationForecast(
        completed,
        [record],
        now: later,
        horizon: ForecastHorizon.week,
      );
      expect(points.first.count, 25);
      expect(points[1].time, now.add(const Duration(days: 6)));
      expect(points.last.count, 32);
    },
  );
}
