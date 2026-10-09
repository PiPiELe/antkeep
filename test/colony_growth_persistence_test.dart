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
      initialLarvaCount: 10,
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
      expect(records.first.larvaCount, 7);
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
    'automatic catch-up preserves mortality before and between cycles',
    () async {
      final colony = await seed('mortality-growth');
      for (final entry in [
        (1, start.add(const Duration(hours: 1)), 3),
        (2, start.add(const Duration(hours: 25)), 2),
      ]) {
        await db.saveRecord(
          CareRecord(
            id: 'growth-death-${entry.$1}',
            colonyId: colony.id,
            type: CareRecordType.mortality,
            occurredAt: entry.$2,
            createdAt: entry.$2,
            workerMortalityCount: entry.$3,
          ),
        );
      }
      final end = start.add(const Duration(days: 3));
      await db.applyColonyGrowth(now: end, colonyId: colony.id);
      var records = await db.listRecords(colony.id);
      expect(
        records.where((r) => r.workerCount != null).map((r) => r.workerCount),
        [18, 17, 18],
      );
      expect(colony.currentWorkerCount(records), 18);
      await db.applyColonyGrowth(now: end, colonyId: colony.id);
      records = await db.listRecords(colony.id);
      expect(records, hasLength(5));
      expect(colony.currentWorkerCount(records), 18);
    },
  );

  test(
    'backdated mortality recalculates settled estimates in time order',
    () async {
      final colony = await seed('backdated-estimates');
      final thirdDay = start.add(const Duration(days: 2));
      await db.applyColonyGrowth(now: thirdDay, colonyId: colony.id);
      var estimates = (await db.listRecords(colony.id))
          .where((record) => record.id.startsWith('growth:'))
          .toList();
      expect(estimates.map((record) => record.workerCount).toList(), [22, 21]);

      final death = CareRecord(
        id: 'backdated-death',
        colonyId: colony.id,
        type: CareRecordType.mortality,
        occurredAt: start.add(const Duration(hours: 1)),
        createdAt: thirdDay.add(const Duration(hours: 1)),
        workerMortalityCount: 5,
      );
      await db.saveRecord(death);
      estimates = (await db.listRecords(colony.id))
          .where((record) => record.id.startsWith('growth:'))
          .toList();
      expect(estimates.map((record) => record.workerCount).toList(), [17, 16]);
      expect(colony.currentWorkerCount(await db.listRecords(colony.id)), 17);

      await db.updateRecord(
        CareRecord.fromMap({...death.toMap(), 'worker_mortality_count': 8}),
      );
      estimates = (await db.listRecords(colony.id))
          .where((record) => record.id.startsWith('growth:'))
          .toList();
      expect(estimates.map((record) => record.workerCount).toList(), [14, 13]);

      await db.deleteRecord(death);
      estimates = (await db.listRecords(colony.id))
          .where((record) => record.id.startsWith('growth:'))
          .toList();
      expect(estimates.map((record) => record.workerCount).toList(), [22, 21]);
    },
  );

  test(
    'manual worker total remains a correction point for later estimates',
    () async {
      final colony = await seed('manual-correction');
      final secondDay = start.add(const Duration(days: 1));
      final thirdDay = start.add(const Duration(days: 2));
      await db.applyColonyGrowth(now: thirdDay, colonyId: colony.id);
      await db.saveRecord(
        CareRecord(
          id: 'manual-total',
          colonyId: colony.id,
          type: CareRecordType.observation,
          occurredAt: secondDay.add(const Duration(hours: 1)),
          createdAt: thirdDay.add(const Duration(hours: 1)),
          workerCount: 100,
        ),
      );
      await db.saveRecord(
        CareRecord(
          id: 'death-before-manual',
          colonyId: colony.id,
          type: CareRecordType.mortality,
          occurredAt: start.add(const Duration(hours: 1)),
          createdAt: thirdDay.add(const Duration(hours: 2)),
          workerMortalityCount: 5,
        ),
      );
      final estimates = (await db.listRecords(colony.id))
          .where((record) => record.id.startsWith('growth:'))
          .toList();
      expect(estimates.map((record) => record.workerCount).toList(), [101, 16]);
      expect(colony.currentWorkerCount(await db.listRecords(colony.id)), 101);
    },
  );

  test('backdated brood correction replays transfer limits', () async {
    final colony = await seed('brood-shortage');
    final thirdDay = start.add(const Duration(days: 2));
    await db.applyColonyGrowth(now: thirdDay, colonyId: colony.id);
    await db.saveRecord(
      CareRecord(
        id: 'brood-correction',
        colonyId: colony.id,
        type: CareRecordType.observation,
        occurredAt: start.add(const Duration(hours: 1)),
        createdAt: thirdDay.add(const Duration(hours: 1)),
        larvaCount: 0,
      ),
    );
    final estimates = (await db.listRecords(colony.id))
        .where((record) => record.id.startsWith('growth:'))
        .toList();
    expect(estimates.map((record) => record.workerCount).toList(), [20, 20]);
    expect(estimates.map((record) => record.larvaCount).toList(), [0, 0]);
  });

  test('an observation at cycle due time precedes that estimate', () async {
    final colony = await seed('same-time-death');
    final secondDay = start.add(const Duration(days: 1));
    await db.applyColonyGrowth(now: secondDay, colonyId: colony.id);
    await db.saveRecord(
      CareRecord(
        id: 'same-time-death-entry',
        colonyId: colony.id,
        type: CareRecordType.mortality,
        occurredAt: secondDay,
        createdAt: secondDay.add(const Duration(days: 1)),
        workerMortalityCount: 5,
      ),
    );
    final records = await db.listRecords(colony.id);
    final estimate = records.singleWhere(
      (record) => record.id.startsWith('growth:'),
    );
    expect(estimate.workerCount, 16);
    expect(colony.currentWorkerCount(records), 16);
  });

  test('older than 30 days requires explicit global replay', () async {
    final now = DateTime.now();
    final oldStart = DateTime(now.year, now.month, now.day - 33, 12);
    const id = 'old-global-replay';
    await db.saveColony(
      Colony(
        id: id,
        name: id,
        createdAt: oldStart,
        updatedAt: oldStart,
        initialWorkerCount: 20,
        initialLarvaCount: 100,
      ),
    );
    await db.configureColonyGrowth(
      id,
      ColonyGrowth(
        frequency: GrowthFrequency.daily,
        path: GrowthPath.eggToWorker,
        startedAt: oldStart,
        workers: 1,
      ),
      now: oldStart,
    );
    await db.applyColonyGrowth(
      now: oldStart.add(const Duration(days: 33)),
      colonyId: id,
    );
    final death = CareRecord(
      id: 'old-death',
      colonyId: id,
      type: CareRecordType.mortality,
      occurredAt: oldStart.add(const Duration(hours: 1)),
      createdAt: DateTime.now(),
      workerMortalityCount: 5,
    );
    expect(
      await db.needsGlobalGrowthRecalculation(id, [death.occurredAt]),
      isTrue,
    );
    await expectLater(db.saveRecord(death), throwsStateError);
    expect(
      (await db.listRecords(id)).any((record) => record.id == death.id),
      isFalse,
    );
    await db.saveRecord(death, recalculateAllGrowth: true);
    final estimates = (await db.listRecords(id))
        .where((record) => record.id.startsWith('growth:'))
        .toList();
    expect(estimates.last.workerCount, 16);
    expect(estimates.first.workerCount, 48);
  });

  test('global replay preflight settles pending cycles', () async {
    final now = DateTime.now();
    final oldStart = DateTime(now.year, now.month, now.day - 32, 8);
    const id = 'pending-boundary';
    await db.saveColony(
      Colony(
        id: id,
        name: id,
        createdAt: oldStart,
        updatedAt: oldStart,
        initialWorkerCount: 20,
        initialLarvaCount: 100,
      ),
    );
    await db.configureColonyGrowth(
      id,
      ColonyGrowth(
        frequency: GrowthFrequency.daily,
        path: GrowthPath.eggToWorker,
        startedAt: oldStart,
        workers: 1,
      ),
      now: oldStart,
    );
    expect(await db.needsGlobalGrowthRecalculation(id, [oldStart]), isTrue);
    final pending = ((await db.snapshot())['care_records'] as List).where(
      (row) => (row as Map)['colony_id'] == id,
    );
    expect(pending, isEmpty);
    expect(
      (await db.listRecords(id)).where((r) => r.id.startsWith('growth:')),
      isNotEmpty,
    );
  });

  test(
    'editing an estimate makes an explicit boundary for later cycles',
    () async {
      final colony = await seed('edited-estimate');
      final thirdDay = start.add(const Duration(days: 2));
      await db.applyColonyGrowth(now: thirdDay, colonyId: colony.id);
      final estimates = (await db.listRecords(colony.id))
          .where((record) => record.isAutomaticGrowthEstimate)
          .toList();
      final firstDay = estimates.last;
      await db.updateRecord(
        CareRecord.fromMap({...firstDay.toMap(), 'worker_count': 50}),
      );
      final after = await db.listRecords(colony.id);
      final correction = after.singleWhere(
        (record) => record.id == firstDay.id,
      );
      expect(correction.workerCount, 50);
      expect(correction.growthRule, isNull);
      expect(correction.note, startsWith('手动校正'));
      expect(after.first.workerCount, 51);
      expect(colony.currentWorkerCount(after), 51);
    },
  );

  test(
    'unknown historical rule aborts replay without partial changes',
    () async {
      final colony = await seed('unknown-old-rule');
      final secondDay = start.add(const Duration(days: 1));
      await db.applyColonyGrowth(now: secondDay, colonyId: colony.id);
      final snapshot = await db.snapshot();
      final rows = (snapshot['care_records'] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      final legacy = rows.singleWhere((row) => row['colony_id'] == colony.id);
      legacy.remove('auto_growth_rule_json');
      snapshot['care_records'] = rows;
      final colonyRows = (snapshot['colonies'] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      colonyRows.singleWhere(
        (row) => row['id'] == colony.id,
      )['auto_growth_json'] = null;
      snapshot['colonies'] = colonyRows;
      await db.replaceAll(snapshot);
      final death = CareRecord(
        id: 'unknown-rule-death',
        colonyId: colony.id,
        type: CareRecordType.mortality,
        occurredAt: start.add(const Duration(hours: 1)),
        createdAt: secondDay.add(const Duration(hours: 1)),
        workerMortalityCount: 5,
      );
      await expectLater(db.saveRecord(death), throwsStateError);
      final after = await db.listRecords(colony.id);
      expect(after, hasLength(1));
      expect(after.single.workerCount, 21);
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
          larvaCount: 50,
          workerCount: 100,
        ),
      );
      await db.applyColonyGrowth(
        now: DateTime(2040, 2, 2, 12),
        colonyId: 'observed',
      );
      final records = await db.listRecords('observed');
      expect(records.first.workerCount, 101);
      expect(records.first.larvaCount, 49);
      expect(records.first.pupaCount, 5);
    },
  );

  test('editing the colony path controls the next automatic cycle and preserves progress', () async {
    await seed('shared-path');
    await db.applyColonyGrowth(
      now: DateTime(2040, 2, 1, 12),
      colonyId: 'shared-path',
    );
    final before = (await db.findColony('shared-path'))!;
    await db.saveColony(
      Colony.fromMap({
        ...before.toMap(),
        'development_path': GrowthPath.eggToCocoonToWorker.name,
      }),
    );
    final edited = (await db.findColony('shared-path'))!;
    expect(edited.growth!.completedCycles, 1);
    expect(edited.growth!.path, GrowthPath.eggToCocoonToWorker);
    await db.applyColonyGrowth(
      now: DateTime(2040, 2, 2, 12),
      colonyId: 'shared-path',
    );
    final records = await db.listRecords('shared-path');
    expect(records, hasLength(2));
    expect(records.first.larvaCount, 9);
    expect(records.first.pupaCount, 4);
    expect(records.first.workerCount, 22);
  });

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
      expect(records.first.eggCount, 12);
      expect(records.first.workerCount, 22);
    },
  );

  for (final path in GrowthPath.values) {
    test('disabling restored legacy growth preserves ${path.name}', () async {
      final id = 'legacy-${path.name}';
      await db.saveColony(
        Colony(
          id: id,
          name: id,
          createdAt: start,
          updatedAt: start,
          initialEggCount: 10,
          initialWorkerCount: 20,
          initialCocoonCount: path == GrowthPath.eggToWorker ? 0 : 5,
          growth: ColonyGrowth(
            frequency: GrowthFrequency.daily,
            path: path,
            startedAt: start,
            workers: 1,
          ),
        ),
      );
      await db.saveRecord(
        CareRecord(
          id: '$id-larvae',
          colonyId: id,
          type: CareRecordType.observation,
          occurredAt: start,
          createdAt: start,
          larvaCount: 5,
        ),
      );
      final legacy = await db.snapshot();
      legacy['colonies'] = [
        for (final row in legacy['colonies'] as List)
          Map<String, Object?>.from(row as Map)
            ..remove('development_path')
            ..remove('initial_larva_count'),
      ];
      BackupData.validate(legacy);
      await db.replaceAll(legacy);
      expect((await db.findColony(id))!.developmentPath, path);

      await db.configureColonyGrowth(id, null, now: start);
      final disabled = (await db.findColony(id))!;
      expect(disabled.growth, isNull);
      expect(disabled.developmentPath, path);
      expect(disabled.toMap()['development_path'], path.name);
      await db.saveRecord(
        CareRecord(
          id: '$id-worker',
          colonyId: id,
          type: CareRecordType.observation,
          occurredAt: start.add(const Duration(hours: 1)),
          createdAt: start,
          workerCount: 1,
        ),
        incremental: true,
      );
      final population = disabled.currentPopulation(await db.listRecords(id));
      expect(population.workers, 21);
      expect(population.larvae, path == GrowthPath.eggToWorker ? 4 : 5);
      expect(population.cocoons, path == GrowthPath.eggToWorker ? 0 : 4);

      final backup = await db.snapshot();
      BackupData.validate(backup);
      await db.replaceAll(backup);
      expect((await db.findColony(id))!.developmentPath, path);
      await db.configureColonyGrowth(
        id,
        ColonyGrowth(
          frequency: GrowthFrequency.daily,
          path: path,
          startedAt: start.add(const Duration(days: 1)),
          workers: 1,
        ),
        now: start.add(const Duration(days: 1)),
      );
      expect((await db.findColony(id))!.growth!.path, path);
    });
  }
}
