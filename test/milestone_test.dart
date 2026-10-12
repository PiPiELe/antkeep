import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/domain/milestone.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/milestone_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = AppDatabase.instance;
  final date = DateTime(2026, 10, 12);
  final colony = Colony(
    id: 'colony',
    name: '测试蚁群',
    initialWorkerCount: 10,
    createdAt: date,
    updatedAt: date,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-milestone-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await Directory('${directory.path}/antkeep').create();
    await db.open();
    await db.saveColony(colony);
  });

  tearDownAll(() async {
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test(
    'standalone and diary milestones stay outside diary statistics',
    () async {
      final standalone = Milestone(
        id: 'standalone',
        colonyId: colony.id,
        title: '首批工蚁羽化',
        occurredAt: date,
        createdAt: date,
      );
      await db.saveMilestone(standalone);
      expect(await db.listRecords(colony.id), isEmpty);
      expect(colony.currentWorkerCount(await db.listRecords(colony.id)), 10);

      final record = CareRecord(
        id: 'diary',
        colonyId: colony.id,
        type: CareRecordType.observation,
        occurredAt: date,
        createdAt: date,
        note: '完成搬家',
      );
      final synced = Milestone(
        id: 'diary:diary',
        colonyId: colony.id,
        title: '搬入新巢',
        occurredAt: date,
        createdAt: date,
        note: record.note,
      );
      await db.saveRecord(record, milestone: synced);
      expect(await db.listRecords(colony.id), hasLength(1));
      expect(await db.listMilestones(colony.id), hasLength(2));
      expect(colony.currentWorkerCount(await db.listRecords(colony.id)), 10);

      await db.deleteRecord(record);
      expect(await db.listRecords(colony.id), isEmpty);
      expect(await db.listMilestones(colony.id), hasLength(2));

      final snapshot = await db.snapshot();
      BackupData.validate(snapshot);
      await db.replaceAll(snapshot);
      expect(await db.listMilestones(colony.id), hasLength(2));

      await db.saveMilestone(
        Milestone(
          id: standalone.id,
          colonyId: colony.id,
          title: '首批工蚁羽化完成',
          occurredAt: date,
          createdAt: date,
        ),
      );
      expect(
        (await db.listMilestones(colony.id))
            .firstWhere((entry) => entry.id == standalone.id)
            .title,
        '首批工蚁羽化完成',
      );
      await db.deleteMilestone(standalone);
      expect(await db.listMilestones(colony.id), hasLength(1));
    },
  );

  test('invalid linked milestone rolls back diary save', () async {
    final record = CareRecord(
      id: 'invalid-diary',
      colonyId: colony.id,
      type: CareRecordType.observation,
      occurredAt: date,
      createdAt: date,
    );
    await expectLater(
      db.saveRecord(
        record,
        milestone: Milestone(
          id: 'invalid',
          colonyId: colony.id,
          title: ' ',
          occurredAt: date,
          createdAt: date,
        ),
      ),
      throwsFormatException,
    );
    expect(await db.listRecords(colony.id), isEmpty);
  });

  testWidgets('diary form opt-in creates a separate milestone', (tester) async {
    await tester.runAsync(() async {
      await db.deleteColony(colony.id);
      await db.saveColony(colony);
    });
    await tester.pumpWidget(MaterialApp(home: RecordFormPage(colony: colony)));
    final option = find.widgetWithText(CheckboxListTile, '同步记录为里程碑事件');
    await tester.scrollUntilVisible(
      option,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(option);
    await tester.pumpAndSettle();
    final title = find.widgetWithText(TextField, '里程碑事件标题');
    await tester.scrollUntilVisible(
      title,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(title, '首批工蚁羽化');
    await tester.tap(find.byTooltip('保存记录'));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final records = await tester.runAsync(() => db.listRecords(colony.id));
    final milestones = await tester.runAsync(
      () => db.listMilestones(colony.id),
    );
    expect(records, hasLength(1));
    expect(milestones, hasLength(1));
    expect(milestones!.single.title, '首批工蚁羽化');
    expect(milestones.single.occurredAt, records!.single.occurredAt);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('standalone milestone page adds and edits an event', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db.deleteColony(colony.id);
      await db.saveColony(colony);
    });
    Future<void> settle() async {
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
    }

    await tester.pumpWidget(MaterialApp(home: MilestonePage(colony: colony)));
    await settle();
    await tester.tap(find.text('添加里程碑'));
    await settle();
    await tester.enterText(find.widgetWithText(TextField, '事件标题'), '首批工蚁羽化');
    await tester.tap(find.text('保存里程碑'));
    await settle();
    expect(find.text('首批工蚁羽化'), findsOneWidget);

    await tester.tap(find.text('首批工蚁羽化'));
    await settle();
    await tester.enterText(find.widgetWithText(TextField, '事件标题'), '首次羽化');
    await tester.tap(find.text('保存里程碑'));
    await settle();
    expect(find.text('首次羽化'), findsOneWidget);
    expect((await tester.runAsync(() => db.listRecords(colony.id))), isEmpty);

    await tester.tap(find.byTooltip('分享里程碑'));
    await settle();
    expect(find.text('里程碑分享图'), findsOneWidget);
    expect(find.text('勇士狩猎-软体昆虫'), findsOneWidget);
    expect(find.text('卵幼铺底'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
