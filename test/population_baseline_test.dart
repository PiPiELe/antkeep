import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/population_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime(2026, 10, 23, 10);
  Colony colony({DateTime? acquired, int? workers = 20}) => Colony(
    id: 'colony',
    name: '种群回归',
    queenCount: 1,
    initialWorkerCount: workers,
    createdAt: created,
    updatedAt: created,
    acquiredOn: acquired,
  );
  CareRecord death(String id, DateTime time, {int deaths = 2}) => CareRecord(
    id: id,
    colonyId: 'colony',
    type: CareRecordType.mortality,
    occurredAt: time,
    createdAt: created.add(const Duration(hours: 1)),
    workerMortalityCount: deaths,
  );

  for (final acquired in <DateTime?>[
    null,
    DateTime(2026, 10, 23),
    DateTime(2026, 10, 24),
  ]) {
    test(
      'date-only death never leaves the seed as the last point acquired=$acquired',
      () {
        final c = colony(acquired: acquired);
        final records = [death('date-only', DateTime(2026, 10, 23))];
        expect(c.currentWorkerCount(records), 18);
        expect(
          colonyPopulation(c, records, PopulationMetric.workers).last.count,
          18,
        );
        for (final brood in [false, true]) {
          expect(
            colonyPopulationTotal(c, records, includeBrood: brood).last.count,
            19,
          );
        }
        expect(records.single.occurredAt, DateTime(2026, 10, 23));
      },
    );
  }

  test(
    'backdated death edits and deletion remain consistent with current totals',
    () {
      final c = colony();
      final first = death('backdated', DateTime(2026, 10, 21));
      final second = death('same-day', DateTime(2026, 10, 21, 12), deaths: 3);
      for (final records in [
        [second, first],
        [second, death('backdated', first.occurredAt, deaths: 5)],
        [second],
        <CareRecord>[],
      ]) {
        expect(
          colonyPopulation(c, records, PopulationMetric.workers).last.count,
          c.currentWorkerCount(records),
        );
        expect(
          colonyPopulationTotal(c, records, includeBrood: false).last.count,
          c.currentWorkerCount(records)! + 1,
        );
      }
    },
  );

  test('unknown stays unknown and confirmed zero stays zero', () {
    final records = [death('old', DateTime(2026, 10, 20))];
    expect(
      colonyPopulation(
        colony(workers: null),
        records,
        PopulationMetric.workers,
      ),
      isEmpty,
    );
    expect(
      colonyPopulation(
        colony(workers: 0),
        records,
        PopulationMetric.workers,
      ).last.count,
      0,
    );
  });
}
