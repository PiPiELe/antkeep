import 'package:antkeep/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('husbandry duration counts calendar days from arrival', () {
    Colony colony(DateTime? arrival) => Colony(
      id: 'duration',
      name: '养殖天数',
      acquiredOn: arrival,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    expect(colony(null).husbandryDays(DateTime(2026, 9, 29)), isNull);
    expect(
      colony(DateTime(2026, 8, 21)).husbandryDays(DateTime(2026, 9, 26)),
      36,
    );
    expect(
      colony(DateTime(2026, 9, 29, 23)).husbandryDays(DateTime(2026, 9, 29)),
      0,
    );
    expect(
      colony(DateTime(2026, 9, 28, 23, 59))
          .husbandryDays(DateTime(2026, 9, 29, 0, 1)),
      1,
    );
    expect(
      colony(DateTime(2024, 2, 28)).husbandryDays(DateTime(2024, 3, 1)),
      2,
    );
    expect(
      colony(DateTime(2025, 12, 31)).husbandryDays(DateTime(2026, 1, 1)),
      1,
    );
    expect(
      colony(DateTime(2026, 10, 1)).husbandryDays(DateTime(2026, 9, 29)),
      0,
    );
  });

  test('unknown worker count remains distinct from zero', () {
    final now = DateTime.utc(2026, 9, 28, 12);
    final unknown = CareRecord(
      id: 'unknown',
      colonyId: 'c',
      type: CareRecordType.observation,
      occurredAt: now,
      createdAt: now,
    );
    final zero = CareRecord(
      id: 'zero',
      colonyId: 'c',
      type: CareRecordType.observation,
      occurredAt: now,
      createdAt: now,
      workerCount: 0,
    );
    expect(CareRecord.fromMap(unknown.toMap()).workerCount, isNull);
    expect(CareRecord.fromMap(zero.toMap()).workerCount, 0);
  });

  test('record map retains portable photo paths', () {
    final now = DateTime.utc(2026, 9, 28, 12);
    final record = CareRecord(
      id: 'r',
      colonyId: 'c',
      type: CareRecordType.feeding,
      occurredAt: now,
      createdAt: now,
      photos: const ['a.jpg'],
    );
    expect(CareRecord.fromMap(record.toMap()).photos, ['a.jpg']);
  });

  test('colony map retains the initial queen and worker counts', () {
    final now = DateTime.utc(2026, 9, 28, 12);
    final colony = Colony(
      id: 'c',
      name: '红土一号',
      queenCount: 1,
      specializedCount: 3,
      showSpecialized: true,
      initialWorkerCount: 18,
      createdAt: now,
      updatedAt: now,
    );
    final restored = Colony.fromMap(colony.toMap());
    expect(restored.queenCount, 1);
    expect(restored.specializedCount, 3);
    expect(restored.showSpecialized, isTrue);
    expect(restored.initialWorkerCount, 18);
    final legacyMap = colony.toMap()
      ..remove('specialized_count')
      ..remove('show_specialized');
    final legacy = Colony.fromMap(legacyMap);
    expect(legacy.specializedCount, isNull);
    expect(legacy.showSpecialized, isFalse);
  });

  test('colony scale follows the worker count boundaries', () {
    final now = DateTime(2026, 9, 29);
    final cases = <int?, ColonyScale?>{
      null: null,
      0: ColonyScale.small,
      1: ColonyScale.small,
      10: ColonyScale.small,
      100: ColonyScale.small,
      101: ColonyScale.medium,
      499: ColonyScale.medium,
      500: ColonyScale.large,
      1000: ColonyScale.large,
      9999: ColonyScale.large,
      10000: ColonyScale.superLarge,
      10001: ColonyScale.superLarge,
    };
    for (final entry in cases.entries) {
      final colony = Colony(
        id: 'scale',
        name: '分级测试',
        initialWorkerCount: entry.key,
        createdAt: now,
        updatedAt: now,
      );
      expect(colony.scale, entry.value, reason: 'workers: ${entry.key}');
    }
  });

  test('new queen origin stays independent of current worker scale', () {
    final date = DateTime(2026, 9, 1);
    final colony = Colony(
      id: 'queen-origin',
      name: '从新后养起',
      initialWorkerCount: 0,
      createdAt: date,
      updatedAt: date,
    );
    CareRecord record(String id, int days, int? workers, {String? colonyId}) =>
        CareRecord(
          id: id,
          colonyId: colonyId ?? colony.id,
          type: CareRecordType.observation,
          occurredAt: date.add(Duration(days: days)),
          createdAt: date,
          workerCount: workers,
        );
    final records = [
      record('brood-only', 4, null),
      record('older', 1, 20),
      record('latest-workers', 3, 1000),
      record('other-colony', 5, 10000, colonyId: 'other'),
    ];
    expect(colony.isNewQueenColony, isTrue);
    expect(colony.currentWorkerCount([]), 0);
    expect(colony.currentWorkerCount(records), 1000);
    expect(
      ColonyScale.fromWorkerCount(colony.currentWorkerCount(records)),
      ColonyScale.large,
    );
    records.add(record('zero-workers', 6, 0));
    expect(colony.currentWorkerCount(records), 0);
    expect(colony.isNewQueenColony, isTrue);
    final unknown = Colony.fromMap({
      ...colony.toMap(),
      'initial_worker_count': null,
    });
    expect(unknown.isNewQueenColony, isFalse);
    expect(unknown.currentWorkerCount([]), isNull);
    final established = Colony.fromMap({
      ...colony.toMap(),
      'initial_worker_count': 20,
    });
    expect(established.currentWorkerCount(records), 0);
    expect(established.isNewQueenColony, isFalse);
  });

  test('shelf life expiry uses the purchase date and calendar months', () {
    final item = InventoryItem(
      id: 'nutrition',
      name: '营养液',
      purchased: true,
      purchasedAt: DateTime(2026, 1, 31),
      expiryType: InventoryExpiryType.shelfLife,
      shelfLifeMonths: 3,
      createdAt: DateTime(2026, 1, 1),
    );
    expect(item.effectiveExpiryDate(), DateTime(2026, 4, 30));
    expect(item.isExpired(DateTime(2026, 4, 30)), isFalse);
    expect(item.isExpired(DateTime(2026, 5, 1)), isTrue);
  });
}
