import 'package:antkeep/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      initialWorkerCount: 18,
      createdAt: now,
      updatedAt: now,
    );
    final restored = Colony.fromMap(colony.toMap());
    expect(restored.queenCount, 1);
    expect(restored.initialWorkerCount, 18);
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
