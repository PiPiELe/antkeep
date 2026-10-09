import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/care_task.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/care_tasks_section.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase.instance;
  late Directory directory;

  Future<void> settleDatabase(WidgetTester tester) async {
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-care-tasks-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await database.open();
    await LocalMediaStore.instance.initialize();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  setUp(() async {
    final date = DateTime(2026, 10, 1);
    await database.replaceAll({
      'colonies': [
        Colony(
          id: 'colony',
          name: '测试蚁群',
          createdAt: date,
          updatedAt: date,
        ).toMap(),
      ],
      'care_records': <Map<String, Object?>>[],
      'care_tasks': <Map<String, Object?>>[],
      'memorials': <Map<String, Object?>>[],
      'feeder_records': <Map<String, Object?>>[],
      'inventory_items': <Map<String, Object?>>[],
    });
  });

  test(
    'completing a feeding task stores the journal and advances its cycle',
    () async {
      final today = DateTime.now();
      final task = CareTask(
        id: 'task',
        colonyId: 'colony',
        type: CareTaskType.feeding,
        intervalDays: 3,
        nextDueOn: DateTime(today.year, today.month, today.day),
      );
      await database.saveCareTask(task);
      final record = CareRecord(
        id: 'record',
        colonyId: 'colony',
        type: CareRecordType.feeding,
        occurredAt: today,
        createdAt: today,
        feedingFood: '面包虫',
        feedingAmount: '半只',
        feedingResponse: FeedingResponse.eager,
        feedingLeftovers: false,
      );
      await database.saveRecord(record, completingTaskId: task.id);

      final stored = (await database.listRecords('colony')).single;
      expect(stored.feedingFood, '面包虫');
      expect(stored.feedingAmount, '半只');
      expect(stored.feedingResponse, FeedingResponse.eager);
      expect(stored.feedingLeftovers, false);
      final completed = (await database.listCareTasks(colonyId: 'colony'))
          .single;
      expect(
        completed.lastCompletedOn,
        DateTime(today.year, today.month, today.day),
      );
      expect(
        completed.nextDueOn,
        DateTime(today.year, today.month, today.day + 3),
      );

      final snapshot = await database.snapshot();
      BackupData.validate(snapshot);
      await database.replaceAll(snapshot);
      expect(
        (await database.listCareTasks()).single.nextDueOn,
        completed.nextDueOn,
      );
      expect((await database.listRecords('colony')).single.feedingFood, '面包虫');
    },
  );

  test('mismatched task and journal roll back together', () async {
    await database.saveCareTask(
      CareTask(
        id: 'watering',
        colonyId: 'colony',
        type: CareTaskType.watering,
        intervalDays: 2,
        nextDueOn: DateTime(2026, 10, 1),
      ),
    );
    final now = DateTime.now();
    await expectLater(
      database.saveRecord(
        CareRecord(
          id: 'wrong',
          colonyId: 'colony',
          type: CareRecordType.feeding,
          occurredAt: now,
          createdAt: now,
        ),
        completingTaskId: 'watering',
      ),
      throwsStateError,
    );
    expect(await database.listRecords('colony'), isEmpty);
    expect((await database.listCareTasks()).single.lastCompletedOn, isNull);
  });

  test(
    'old snapshots without tasks or feeding fields remain restorable',
    () async {
      final snapshot = await database.snapshot();
      snapshot.remove('care_tasks');
      for (final row in snapshot['care_records'] as List) {
        (row as Map).remove('feeding_food');
        row.remove('feeding_amount');
        row.remove('feeding_response');
        row.remove('feeding_leftovers');
      }
      BackupData.validate(snapshot);
      await database.replaceAll(snapshot);
      expect(await database.listCareTasks(), isEmpty);
    },
  );

  testWidgets(
    'a due task can be completed through a structured feeding journal',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final date = DateTime(2026, 10, 1);
      final colony = Colony(
        id: 'colony',
        name: '测试蚁群',
        createdAt: date,
        updatedAt: date,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: CareTasksSection(
                  colony: colony,
                  onRecord: (task) async =>
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              RecordFormPage(colony: colony, task: task),
                        ),
                      ) ==
                      true,
                ),
              ),
            ),
          ),
        ),
      );
      await settleDatabase(tester);
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '每隔几天'), '2');
      await tester.tap(find.text('保存'));
      await settleDatabase(tester);
      expect(find.textContaining('已到期'), findsOneWidget);

      await tester.tap(find.text('完成并记日记'));
      await settleDatabase(tester);
      expect(find.text('投喂结果（可选）'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(TextField, '食物'));
      await tester.enterText(find.widgetWithText(TextField, '食物'), '面包虫');
      await tester.ensureVisible(find.widgetWithText(TextField, '投喂量'));
      await tester.enterText(find.widgetWithText(TextField, '投喂量'), '半只');
      await tester.tap(find.byTooltip('保存记录'));
      await settleDatabase(tester);
      expect(
        (await tester.runAsync(() => database.listRecords('colony')))!
            .single
            .feedingFood,
        '面包虫',
      );
      expect(
        (await tester.runAsync(() => database.listCareTasks()))!
            .single
            .lastCompletedOn,
        isNotNull,
      );
    },
  );
}
