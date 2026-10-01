import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/record_increment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 1);
  Colony colony({GrowthPath path = GrowthPath.eggToCocoonToWorker}) => Colony(
    id: 'colony',
    name: '蚁群',
    createdAt: now,
    updatedAt: now,
    initialEggCount: 10,
    initialLarvaCount: 5,
    initialCocoonCount: 3,
    initialWorkerCount: 20,
    developmentPath: path,
  );
  CareRecord record({
    int? eggs,
    int? larvae,
    int? cocoons,
    int? workers,
    String id = 'record',
    DateTime? at,
  }) => CareRecord(
    id: id,
    colonyId: 'colony',
    type: CareRecordType.observation,
    occurredAt: at ?? now,
    createdAt: now,
    eggCount: eggs,
    larvaCount: larvae,
    pupaCount: cocoons,
    workerCount: workers,
  );

  test('legacy growth paths remain selected and invalid paths reject backup import', () {
    for (final path in GrowthPath.values) {
      final legacy = Colony.fromMap({
        ...colony().toMap(),
        'development_path': null,
        'auto_growth_json': ColonyGrowth(
          frequency: GrowthFrequency.daily,
          path: path,
          startedAt: now,
        ).encode(),
      });
      expect(legacy.developmentPath, path);
      expect(legacy.growth!.path, path);
    }
    expect(
      () =>
          Colony.fromMap({...colony().toMap(), 'development_path': 'invalid'}),
      throwsFormatException,
    );
  });

  test('larvae consume eggs and blank unrelated stages stay blank', () {
    final result = resolveRecordIncrement(colony(), [], record(larvae: 2));
    expect(result.eggCount, 8);
    expect(result.larvaCount, 7);
    expect(result.pupaCount, isNull);
    expect(result.workerCount, isNull);
  });
  test(
    'cocoons consume larvae; workers consume the selected upstream stage',
    () {
      final cocoon = resolveRecordIncrement(colony(), [], record(cocoons: 2));
      expect(cocoon.larvaCount, 3);
      expect(cocoon.pupaCount, 5);
      final worker = resolveRecordIncrement(colony(), [], record(workers: 2));
      expect(worker.pupaCount, 1);
      expect(worker.workerCount, 22);
      final direct = resolveRecordIncrement(
        colony(path: GrowthPath.eggToWorker),
        [],
        record(workers: 2),
      );
      expect(direct.larvaCount, 3);
      expect(direct.pupaCount, isNull);
      expect(direct.workerCount, 22);
    },
  );
  test(
    'simultaneous increments preserve stage transfers and explicit zero',
    () {
      final result = resolveRecordIncrement(
        colony(),
        [],
        record(eggs: 2, larvae: 3, cocoons: 2, workers: 1),
      );
      expect(
        [
          result.eggCount,
          result.larvaCount,
          result.pupaCount,
          result.workerCount,
        ],
        [9, 6, 4, 21],
      );
      expect(
        resolveRecordIncrement(colony(), [], record(workers: 0)).workerCount,
        20,
      );
      expect(resolveRecordIncrement(colony(), [], record()).eggCount, isNull);
    },
  );
  test(
    'historical records use preceding snapshots and ignore other colonies',
    () {
      final history = [
        record(
          id: 'past',
          eggs: 7,
          larvae: 8,
          at: now.subtract(const Duration(days: 1)),
        ),
        record(
          id: 'future',
          eggs: 100,
          larvae: 100,
          at: now.add(const Duration(days: 1)),
        ),
        CareRecord.fromMap({
          ...record(eggs: 900).toMap(),
          'colony_id': 'other',
        }),
      ];
      final result = resolveRecordIncrement(
        colony(),
        history,
        record(larvae: 2),
      );
      expect(result.eggCount, 5);
      expect(result.larvaCount, 10);
    },
  );
  test(
    'unknown, insufficient, negative and unsupported quantities are rejected',
    () {
      for (final input in [
        record(larvae: 11),
        record(workers: -1),
        record(eggs: 1000001),
      ]) {
        expect(
          () => resolveRecordIncrement(colony(), [], input),
          throwsFormatException,
        );
      }
      expect(
        () => resolveRecordIncrement(
          Colony.fromMap({...colony().toMap(), 'initial_larva_count': null}),
          [],
          record(larvae: 1),
        ),
        throwsFormatException,
      );
      expect(
        () => resolveRecordIncrement(
          colony(path: GrowthPath.eggToWorker),
          [],
          record(cocoons: 1),
        ),
        throwsFormatException,
      );
    },
  );

  test('transactional increments, absolute corrections, mode and backup round trip', () async {
    final directory = await Directory.systemTemp.createTemp(
      'antkeep-increments-',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await directory.delete(recursive: true);
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = AppDatabase.instance;
    await db.open();
    await db.saveColony(colony());
    await db.saveRecord(record(larvae: 2), incremental: true);
    var saved = (await db.listRecords('colony')).single;
    expect([saved.eggCount, saved.larvaCount], [8, 7]);
    await expectLater(
      db.saveRecord(record(id: 'invalid', workers: 4), incremental: true),
      throwsFormatException,
    );
    expect(await db.listRecords('colony'), hasLength(1));
    await db.saveRecord(
      record(id: 'absolute', larvae: 30, at: now.add(const Duration(hours: 1))),
    );
    await db.saveColony(colony(path: GrowthPath.eggToWorker));
    await db.saveRecord(
      record(id: 'direct', workers: 2, at: now.add(const Duration(hours: 2))),
      incremental: true,
    );
    saved = (await db.listRecords('colony')).first;
    expect([saved.larvaCount, saved.workerCount], [28, 22]);
    final snapshot = await db.snapshot();
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    final restored = (await db.findColony('colony'))!;
    expect(restored.developmentPath, GrowthPath.eggToWorker);
    expect(restored.initialLarvaCount, 5);
    expect(await db.listRecords('colony'), hasLength(3));
    final old =
        Map<String, Object?>.from((snapshot['colonies'] as List).single as Map)
          ..remove('development_path')
          ..remove('initial_larva_count');
    snapshot['colonies'] = [old];
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    expect((await db.findColony('colony'))!.initialLarvaCount, isNull);
  });
}
