import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
  late Directory directory;
  final start = DateTime(2040, 1, 31, 12);
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-growth-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });
  Future<Colony> seed(String id, {bool archived = false}) async {
    final colony = Colony(
      id: id,
      name: id,
      createdAt: start,
      updatedAt: start,
      initialEggCount: 10,
      initialCocoonCount: 5,
      initialWorkerCount: 20,
      archived: archived,
    );
    await db.saveColony(colony);
    await db.configureColonyGrowth(
      id,
      ColonyGrowth(
        frequency: GrowthFrequency.daily,
        path: GrowthPath.eggToWorker,
        startedAt: start,
        workers: 1,
      ),
      now: start,
    );
    return colony;
  }

  test(
    'offline catch-up is idempotent, atomic and survives restore and edits',
    () async {
      final colony = await seed('catchup');
      await seed('archived', archived: true);
      final end = DateTime(2040, 2, 3, 12);
      await Future.wait([
        db.applyColonyGrowth(now: end),
        db.applyColonyGrowth(now: end),
      ]);
      var records = await db.listRecords(colony.id);
      expect(records, hasLength(3));
      expect(records.first.eggCount, 7);
      expect(records.first.workerCount, 23);
      expect(records.first.note, contains('估算'));
      expect(await db.listRecords('archived'), isEmpty);
      final snapshot = await db.snapshot();
      BackupData.validate(snapshot);
      await db.replaceAll(snapshot);
      // Editing from a stale colony object must preserve the settlement watermark.
      await db.saveColony(Colony.fromMap({...colony.toMap(), 'name': '已编辑'}));
      await db.applyColonyGrowth(now: end);
      records = await db.listRecords(colony.id);
      expect(records, hasLength(3));
      expect((await db.findColony(colony.id))!.growth!.completedCycles, 3);
      // Rolling the clock backwards does not remove or duplicate prior cycles.
      await db.applyColonyGrowth(now: start);
      expect(await db.listRecords(colony.id), hasLength(3));
    },
  );

  test(
    'actual observations override counts before later automatic cycles',
    () async {
      await seed('observed');
      await db.saveRecord(
        CareRecord(
          id: 'actual',
          colonyId: 'observed',
          type: CareRecordType.observation,
          occurredAt: DateTime(2040, 2, 1, 13),
          createdAt: start,
          eggCount: 50,
          workerCount: 100,
        ),
      );
      await db.applyColonyGrowth(
        now: DateTime(2040, 2, 2, 12),
        colonyId: 'observed',
      );
      final records = await db.listRecords('observed');
      expect(records.first.workerCount, 101);
      expect(records.first.eggCount, 49);
      expect(records.first.pupaCount, 5);
    },
  );

  test(
    'disable settles old periods; re-enable does not catch up disabled time',
    () async {
      await seed('toggle');
      await db.configureColonyGrowth(
        'toggle',
        null,
        now: DateTime(2040, 2, 1, 12),
      );
      expect(await db.listRecords('toggle'), hasLength(1));
      await db.applyColonyGrowth(now: DateTime(2040, 3, 1), colonyId: 'toggle');
      expect(await db.listRecords('toggle'), hasLength(1));
      final restart = DateTime(2040, 3, 1, 12);
      await db.configureColonyGrowth(
        'toggle',
        ColonyGrowth(
          frequency: GrowthFrequency.monthly,
          path: GrowthPath.eggToWorker,
          startedAt: restart,
          eggs: 2,
          workers: 1,
        ),
        now: restart,
      );
      await db.applyColonyGrowth(
        now: DateTime(2040, 4, 1, 12),
        colonyId: 'toggle',
      );
      final records = await db.listRecords('toggle');
      expect(records, hasLength(2));
      expect(records.first.eggCount, 11);
      expect(records.first.workerCount, 22);
    },
  );
}
