import 'package:antkeep/domain/colony_growth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ColonyGrowth rule({
    int? eggs,
    int? larvae,
    int? cocoons,
    int? workers = 1,
    GrowthPath path = GrowthPath.eggToWorker,
  }) => ColonyGrowth(
    frequency: GrowthFrequency.daily,
    path: path,
    startedAt: DateTime(2026, 1, 1),
    eggs: eggs,
    larvae: larvae,
    cocoons: cocoons,
    workers: workers,
  );
  const initial = GrowthPopulation(
    eggs: 10,
    larvae: 10,
    cocoons: 5,
    workers: 20,
  );

  test('worker growth consumes larvae unless larva net growth is explicit', () {
    final converted = rule().advance(initial);
    expect(converted.larvae, 9);
    expect(converted.workers, 21);
    final independent = rule(eggs: 0, larvae: 2).advance(initial);
    expect(independent.larvae, 12);
    expect(independent.workers, 21);
    expect(rule(larvae: 0).advance(initial).larvae, 10);
  });

  test('cocoon path consumes the immediate upstream unspecified stage', () {
    final workers = rule(path: GrowthPath.eggToCocoonToWorker).advance(initial);
    expect(workers.eggs, 10);
    expect(workers.cocoons, 4);
    expect(workers.workers, 21);
    final cocoons = rule(
      path: GrowthPath.eggToCocoonToWorker,
      cocoons: 2,
    ).advance(initial);
    expect(cocoons.larvae, 8);
    expect(cocoons.cocoons, 7);
    expect(cocoons.workers, 21);
    final all = rule(
      path: GrowthPath.eggToCocoonToWorker,
      eggs: 3,
      cocoons: 2,
    ).advance(initial);
    expect(all.eggs, 13);
    expect(all.cocoons, 7);
    expect(all.workers, 21);
  });

  test('depleted or unknown sources cannot produce invented workers', () {
    final limited = rule(workers: 30).advance(initial);
    expect(limited.larvae, 0);
    expect(limited.workers, 30);
    final unknown = rule().advance(const GrowthPopulation(workers: 2));
    expect(unknown.eggs, isNull);
    expect(unknown.workers, 2);
    expect(rule(eggs: 2).advance(const GrowthPopulation()).eggs, isNull);
  });

  test('larval growth consumes eggs unless egg growth is explicit', () {
    final converted = rule(larvae: 2, workers: 0).advance(initial);
    expect(converted.eggs, 8);
    expect(converted.larvae, 12);
    final independent = rule(eggs: 3, larvae: 2, workers: 0).advance(initial);
    expect(independent.eggs, 13);
    expect(independent.larvae, 12);
  });

  test('calendar periods retain time and the original month-end anchor', () {
    final start = DateTime(2024, 1, 31, 9, 30);
    final monthly = ColonyGrowth(
      frequency: GrowthFrequency.monthly,
      path: GrowthPath.eggToWorker,
      startedAt: start,
      workers: 1,
    );
    expect(monthly.dueAt(1), DateTime(2024, 2, 29, 9, 30));
    expect(monthly.dueAt(2), DateTime(2024, 3, 31, 9, 30));
    final weekly = ColonyGrowth(
      frequency: GrowthFrequency.weekly,
      path: GrowthPath.eggToWorker,
      startedAt: start,
      workers: 1,
    );
    expect(weekly.dueAt(1), DateTime(2024, 2, 7, 9, 30));
    expect(rule().dueAt(1), DateTime(2026, 1, 2));
  });

  test(
    'configuration round trips with progress and rejects invalid counts',
    () {
      final encoded = rule(eggs: 2).completed(3).encode();
      final decoded = ColonyGrowth.decode(encoded)!;
      expect(decoded.encode(), encoded);
      expect(decoded.completedCycles, 3);
      expect(ColonyGrowth.decode(null), isNull);
      expect(
        () =>
            ColonyGrowth.decode(encoded.replaceFirst('"eggs":2', '"eggs":-2')),
        throwsFormatException,
      );
      expect(
        () => ColonyGrowth.decode(encoded.replaceFirst('daily', 'hourly')),
        throwsFormatException,
      );
    },
  );
}
