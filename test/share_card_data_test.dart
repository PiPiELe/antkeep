import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/share_card_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final colony = Colony(
    id: 'c',
    name: '测试',
    createdAt: DateTime(2026, 8, 1),
    updatedAt: DateTime(2026, 10, 1),
    acquiredOn: DateTime(2026, 8, 1),
    initialWorkerCount: 5,
  );
  CareRecord record(
    String id,
    DateTime at, {
    int? workers,
    int? eggs,
    String? note,
    String colonyId = 'c',
    List<String> photos = const [],
  }) => CareRecord(
    id: id,
    colonyId: colonyId,
    type: CareRecordType.observation,
    occurredAt: at,
    createdAt: at,
    workerCount: workers,
    eggCount: eggs,
    note: note,
    photos: photos,
  );

  test('snapshots keep latest per stage, zero differs from unknown and future excluded', () {
    final snapshot = shareSnapshot(colony, [
      record('2', DateTime(2026, 9, 3), eggs: 0),
      record('1', DateTime(2026, 9, 2), workers: 20),
      record('3', DateTime(2026, 11, 1), workers: 999),
      record('other', DateTime(2026, 9, 5), workers: 999, colonyId: 'other'),
    ], DateTime(2026, 10, 1));
    expect(snapshot.workers.value, 20);
    expect(snapshot.quantities['卵']!.value, 0);
    expect(snapshot.quantities['幼虫']!.value, isNull);
    expect(
      shareSnapshot(colony, [], DateTime(2026, 7, 31)).workers.value,
      isNull,
    );
  });

  test(
    'estimate label follows the source of each latest stage independently',
    () {
      final records = [
        record(
          'estimate',
          DateTime(2026, 9, 1),
          workers: 20,
          eggs: 30,
          note: '自动扩充（估算） · 每日',
        ),
        record('actual', DateTime(2026, 9, 2), workers: 18),
      ];
      final snapshot = shareSnapshot(colony, records, DateTime(2026, 10, 1));
      expect(snapshot.workers.estimated, isFalse);
      expect(snapshot.quantities['卵']!.estimated, isTrue);
      expect(
        shareSnapshot(colony, records, DateTime(2026, 9, 1)).workers.text,
        '20（估算）',
      );
    },
  );

  test('monthly boundaries use occurredAt and keep manual and automatic records separate', () {
    final records = [
      record('before', DateTime(2026, 8, 31, 23, 59), workers: 10),
      record('start', DateTime(2026, 9, 1), workers: 20, photos: ['a.png']),
      record('same-day', DateTime(2026, 9, 1, 12), photos: ['a.png', 'b.png']),
      record('estimate', DateTime(2026, 9, 15), workers: 40, note: '自动扩充（估算）'),
      record('end', DateTime(2026, 9, 30, 23, 59), workers: 30),
      record('after', DateTime(2026, 10, 1), workers: 70),
    ];
    final month = ShareMonth(
      colony,
      records,
      DateTime(2026, 9),
      DateTime(2026, 10, 2),
    );
    expect(month.diaryCount, 3);
    expect(month.estimateCount, 1);
    expect(month.activeDays, 2);
    expect(month.before.workers.value, 10);
    expect(month.after.workers.value, 30);
    expect(month.change, '工蚁 +20');
    expect(month.photos, ['a.png', 'b.png']);
    expect(month.workerRecords.length, 3);
  });

  test('current month excludes future records', () {
    final month = ShareMonth(
      colony,
      [record('future', DateTime(2026, 10, 20), workers: 999)],
      DateTime(2026, 10),
      DateTime(2026, 10, 2),
    );
    expect(month.records, isEmpty);
    expect(month.after.workers.value, 5);
    expect(month.change, contains('暂无记录'));
  });

  test('colony acquired during month starts with initial population', () {
    final fresh = Colony(
      id: 'c',
      name: '新窝',
      acquiredOn: DateTime(2026, 9, 12),
      initialWorkerCount: 5,
      createdAt: DateTime(2026, 9, 12),
      updatedAt: DateTime(2026, 9, 12),
    );
    final month = ShareMonth(
      fresh,
      [record('r', DateTime(2026, 9, 20), workers: 8)],
      DateTime(2026, 9),
      DateTime(2026, 10),
    );
    expect(month.change, '工蚁 +3');
  });

  test('unknown endpoints do not become zero, decreases and estimates remain explicit', () {
    expect(
      shareWorkerChange(const ShareQuantity(null), const ShareQuantity(20)),
      contains('数据不足'),
    );
    expect(
      shareWorkerChange(
        const ShareQuantity(20, estimated: true),
        const ShareQuantity(10),
      ),
      '工蚁 -10（含估算）',
    );
    expect(
      shareWorkerChange(const ShareQuantity(0), const ShareQuantity(0)),
      '工蚁 0',
    );
  });
}
