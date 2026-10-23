import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/backup_service.dart';
import 'package:antkeep/data/excel_export.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/care_task.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
  late Directory root;
  final day = DateTime(2026, 1, 1);
  Colony colony() =>
      Colony(id: 'c', name: '测试蚁群', createdAt: day, updatedAt: day);
  Future<CareTask> task(CareTaskType type) async =>
      (await db.listCareTasks()).singleWhere((t) => t.type == type);
  Future<void> configure(CareTaskType type, int? hours) async {
    final old = await task(type);
    final row = old.toMap()..['removal_hours'] = hours;
    if (hours == null) row['removal_due_at'] = null;
    await db.saveCareTask(CareTask.fromMap(row));
  }

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('antkeep-split-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
    await LocalMediaStore.instance.initialize();
  });
  tearDownAll(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  setUp(() async {
    await db.replaceAll({
      'colonies': [colony().toMap()],
      'care_records': [],
      'care_tasks': [],
      'memorials': [],
      'feeder_records': [],
      'inventory_items': [],
    });
  });

  test('optional split preserves diaries, keeps unrelated tasks and starts no invented timers', () async {
    await db.saveCareTask(
      CareTask(
        id: 'generic',
        colonyId: 'c',
        type: CareTaskType.feeding,
        intervalDays: 3,
        nextDueOn: day,
      ),
    );
    await db.saveCareTask(
      CareTask(
        id: 'water',
        colonyId: 'c',
        type: CareTaskType.watering,
        intervalDays: 2,
        nextDueOn: day,
      ),
    );
    await db.saveRecord(
      CareRecord(
        id: 'old',
        colonyId: 'c',
        type: CareRecordType.feeding,
        occurredAt: day,
        createdAt: day,
        feedingFood: '旧食物',
      ),
    );
    await db.setSplitFeeding('c', true);
    final tasks = await db.listCareTasks();
    expect(tasks.length, 4);
    for (final type in [
      CareTaskType.protein,
      CareTaskType.sugar,
      CareTaskType.seeds,
    ]) {
      final t = await task(type);
      expect(t.intervalDays, 3);
      expect(t.lastFedAt, isNull);
      expect(t.removalHours, isNull);
    }
    await db.setSplitFeeding('c', false);
    expect(
      (await db.listCareTasks()).map((t) => t.type),
      containsAll([CareTaskType.feeding, CareTaskType.watering]),
    );
    expect((await db.listRecords('c')).single.feedingFood, '旧食物');
  });

  test('three food timers and removal switches are independent and survive restart', () async {
    await db.setSplitFeeding('c', true);
    await configure(CareTaskType.protein, 8);
    await configure(CareTaskType.sugar, 24);
    final p = await task(CareTaskType.protein);
    await db.completeCareTask(p.id);
    final fedProtein = await task(CareTaskType.protein);
    expect(
      fedProtein.removalDueAt!.difference(fedProtein.lastFedAt!),
      const Duration(hours: 8),
    );
    expect((await task(CareTaskType.sugar)).lastFedAt, isNull);
    await db.completeCareTask((await task(CareTaskType.seeds)).id);
    expect((await task(CareTaskType.seeds)).lastFedAt, isNotNull);
    expect((await task(CareTaskType.seeds)).removalDueAt, isNull);
    await db.completeCareTask((await task(CareTaskType.sugar)).id);
    final sugar = await task(CareTaskType.sugar);
    await db.completeFoodRemoval(p.id);
    expect((await task(CareTaskType.protein)).removalDueAt, isNull);
    expect((await task(CareTaskType.protein)).nextDueOn, fedProtein.nextDueOn);
    expect((await task(CareTaskType.sugar)).removalDueAt, sugar.removalDueAt);
    await db.close();
    await db.open();
    expect((await task(CareTaskType.sugar)).removalDueAt, sugar.removalDueAt);
    await configure(CareTaskType.sugar, null);
    expect((await task(CareTaskType.sugar)).removalDueAt, isNull);
    expect((await task(CareTaskType.protein)).removalHours, 8);
  });

  test(
    'completing only a reminder preserves feeding and removal timers',
    () async {
      await db.setSplitFeeding('c', true);
      await configure(CareTaskType.protein, 12);
      final beforeFeeding = await task(CareTaskType.protein);
      await db.completeCareTask(beforeFeeding.id, markFed: false);
      final reminderOnly = await task(CareTaskType.protein);
      expect(reminderOnly.lastFedAt, isNull);
      expect(reminderOnly.removalDueAt, isNull);
      expect(reminderOnly.lastCompletedOn, isNotNull);
      expect(reminderOnly.nextDueOn.isAfter(beforeFeeding.nextDueOn), isTrue);

      await db.completeCareTask(beforeFeeding.id);
      final fed = await task(CareTaskType.protein);
      await db.completeCareTask(beforeFeeding.id, markFed: false);
      final after = await task(CareTaskType.protein);
      expect(after.lastFedAt, fed.lastFedAt);
      expect(after.removalDueAt, fed.removalDueAt);
    },
  );

  test('backdated classified diary does not rewind a newer timer, mismatch rolls back', () async {
    await db.setSplitFeeding('c', true);
    await configure(CareTaskType.protein, 12);
    final p = await task(CareTaskType.protein);
    Future<void> record(String id, DateTime at, String category) =>
        db.saveRecord(
          CareRecord(
            id: id,
            colonyId: 'c',
            type: CareRecordType.feeding,
            occurredAt: at,
            createdAt: DateTime.now(),
            feedingCategory: category,
          ),
          completingTaskId: p.id,
        );
    final recent = DateTime.now().subtract(const Duration(hours: 1));
    await record('new', recent, p.type.storageValue);
    await record(
      'old',
      recent.subtract(const Duration(days: 4)),
      p.type.storageValue,
    );
    expect((await task(CareTaskType.protein)).lastFedAt, recent);
    expect(
      (await task(CareTaskType.protein)).removalDueAt,
      recent.add(const Duration(hours: 12)),
    );
    await expectLater(
      record('wrong', recent, CareTaskType.sugar.storageValue),
      throwsStateError,
    );
    await expectLater(
      record(
        'future',
        recent.add(const Duration(days: 4)),
        p.type.storageValue,
      ),
      throwsStateError,
    );
    expect((await db.listRecords('c')).length, 2);
    final oldSnapshot = await db.snapshot();
    BackupData.validate(oldSnapshot);
  });

  test('ZIP and Excel round trips retain category, timers and individual reminder settings', () async {
    await db.setSplitFeeding('c', true);
    await configure(CareTaskType.protein, 6);
    final p = await task(CareTaskType.protein);
    await db.saveRecord(
      CareRecord(
        id: 'r',
        colonyId: 'c',
        type: CareRecordType.feeding,
        occurredAt: DateTime.now(),
        createdAt: DateTime.now(),
        feedingCategory: p.type.storageValue,
      ),
      completingTaskId: p.id,
    );
    final before = (await db.listCareTasks()).map((t) => t.toMap()).toList();
    final service = BackupService(db, LocalMediaStore.instance);
    final file = File('${root.path}/feeding.zip');
    await service.writeBackupFile(file);
    final bytes = await file.readAsBytes();
    await db.setSplitFeeding('c', false);
    await service.restoreBytes(bytes, mode: BackupRestoreMode.overwrite);
    expect((await db.listCareTasks()).map((t) => t.toMap()).toList(), before);
    expect(
      (await db.listRecords('c')).single.feedingCategory,
      p.type.storageValue,
    );
    final excel = ExcelExport.decode(ExcelExport.encode(await db.snapshot()));
    await db.replaceAll(excel);
    expect((await db.listCareTasks()).map((t) => t.toMap()).toList(), before);
    await db.setSplitFeeding('c', false);
    await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
    expect((await db.listCareTasks()).single.type, CareTaskType.feeding);
  });

  test(
    'invalid reminder data and mixed feeding modes are rejected before restore',
    () async {
      await db.setSplitFeeding('c', true);
      final p = await task(CareTaskType.protein);
      expect(
        () => CareTask.fromMap({...p.toMap(), 'removal_hours': 0}),
        throwsFormatException,
      );
      expect(
        () => CareTask.fromMap({...p.toMap(), 'removal_hours': 721}),
        throwsFormatException,
      );
      expect(
        () => CareTask.fromMap({
          ...p.toMap(),
          'removal_due_at': day.toIso8601String(),
        }),
        throwsFormatException,
      );
      final generic = CareTask(
        id: 'g',
        colonyId: 'c',
        type: CareTaskType.feeding,
        intervalDays: 2,
        nextDueOn: day,
      );
      await expectLater(db.saveCareTask(generic), throwsStateError);
      final snapshot = await db.snapshot();
      snapshot['care_tasks'] = [
        ...snapshot['care_tasks'] as List,
        generic.toMap(),
      ];
      expect(() => BackupData.validate(snapshot), throwsFormatException);
    },
  );

  test('v34 upgrade keeps existing feeding diary and generic plan without enabling reminders', () async {
    await db.saveCareTask(
      CareTask(
        id: 'legacy',
        colonyId: 'c',
        type: CareTaskType.feeding,
        intervalDays: 4,
        nextDueOn: day,
      ),
    );
    await db.saveRecord(
      CareRecord(
        id: 'legacy-r',
        colonyId: 'c',
        type: CareRecordType.feeding,
        occurredAt: day,
        createdAt: day,
        feedingFood: '糖水',
      ),
    );
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(
      '${root.path}/antkeep/antkeep.sqlite',
    );
    // These four nullable columns are the only v35 schema additions.
    await raw.execute('ALTER TABLE care_records DROP COLUMN feeding_category');
    for (final column in ['last_fed_at', 'removal_hours', 'removal_due_at']) {
      await raw.execute('ALTER TABLE care_tasks DROP COLUMN $column');
    }
    await raw.setVersion(34);
    await raw.close();
    await db.open();
    expect((await db.listRecords('c')).single.feedingFood, '糖水');
    expect((await task(CareTaskType.feeding)).intervalDays, 4);
    expect((await task(CareTaskType.feeding)).removalHours, isNull);
    await db.setSplitFeeding('c', true);
    await configure(CareTaskType.sugar, 24);
    await db.completeCareTask((await task(CareTaskType.sugar)).id);
    expect((await task(CareTaskType.sugar)).removalDueAt, isNotNull);
  });
}
