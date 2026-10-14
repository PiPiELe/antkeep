import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/domain/milestone.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/milestone_page.dart';
import 'package:antkeep/milestones_overview_page.dart';
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

  Future<void> settleDatabase(WidgetTester tester) async {
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

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

  test(
    'unlinked milestone survives backup and can be edited and deleted',
    () async {
      final unlinked = Milestone(
        id: 'unlinked',
        title: '独立成长节点',
        occurredAt: date,
        createdAt: date,
      );
      await db.saveMilestone(unlinked);
      expect(await db.listRecords(colony.id), isEmpty);
      expect(
        (await db.listAllMilestones())
            .firstWhere((item) => item.milestone.id == unlinked.id)
            .milestone
            .colonyId,
        isNull,
      );
      final snapshot = await db.snapshot();
      BackupData.validate(snapshot);
      await db.replaceAll(snapshot);
      await db.saveMilestone(
        Milestone(
          id: unlinked.id,
          title: '独立成长节点已更新',
          occurredAt: date,
          createdAt: date,
        ),
      );
      expect(
        (await db.listAllMilestones())
            .firstWhere((item) => item.milestone.id == unlinked.id)
            .milestone
            .title,
        '独立成长节点已更新',
      );
      await db.deleteColony(colony.id);
      expect(
        (await db.listAllMilestones()).any(
          (item) => item.milestone.id == unlinked.id,
        ),
        isTrue,
      );
      await db.saveColony(colony);
      await db.deleteMilestone(unlinked);
      expect(
        (await db.listAllMilestones()).where(
          (item) => item.milestone.id == unlinked.id,
        ),
        isEmpty,
      );
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
    final option = find.widgetWithText(CheckboxListTile, '设为里程碑');
    await tester.scrollUntilVisible(
      option,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(option);
    await tester.pumpAndSettle();
    final title = find.widgetWithText(TextField, '里程碑标题');
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

  testWidgets('diary form sections fit a narrow screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in [320.0, 360.0, 440.0]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpWidget(
        MaterialApp(home: RecordFormPage(colony: colony)),
      );
      expect(find.text('记录类型'), findsOneWidget);
      expect(find.text('保存日记'), findsOneWidget);
      for (final (title, subtitle) in [
        ('记录类型', '选择养护内容'),
        ('记录时间', '支持补记过去'),
        ('记录内容', '写下观察与变化'),
      ]) {
        expect(
          (tester.getCenter(find.text(title)).dy -
                  tester.getCenter(find.text(subtitle)).dy)
              .abs(),
          lessThan(8),
        );
      }
      expect(
        (tester.getCenter(find.text(colony.name)).dy -
                tester.getCenter(find.text('记录养殖日常')).dy)
            .abs(),
        lessThan(8),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.physicalSize = const Size(360, 720);
    await tester.pumpWidget(MaterialApp(home: RecordFormPage(colony: colony)));
    final timeOption = find.widgetWithText(CheckboxListTile, '记录具体时间');
    final option = find.widgetWithText(CheckboxListTile, '设为里程碑');
    expect(timeOption, findsOneWidget);
    expect(option, findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(tester.widget<CheckboxListTile>(timeOption).dense, isTrue);
    expect(tester.widget<CheckboxListTile>(option).dense, isTrue);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '里程碑标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('standalone milestone page adds and edits a milestone', (
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
    await tester.enterText(find.widgetWithText(TextField, '里程碑标题'), '首批工蚁羽化');
    await tester.tap(find.text('保存里程碑'));
    await settle();
    expect(find.text('首批工蚁羽化'), findsOneWidget);

    await tester.tap(find.text('首批工蚁羽化'));
    await settle();
    await tester.enterText(find.widgetWithText(TextField, '里程碑标题'), '首次羽化');
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

  testWidgets(
    'overview shows milestones from multiple colonies and opens detail',
    (tester) async {
      final secondColony = Colony(
        id: 'overview-second',
        name: '第二蚁群',
        createdAt: date,
        updatedAt: date,
      );
      await tester.runAsync(() async {
        await db.deleteColony(colony.id);
        await db.saveColony(colony);
        await db.saveColony(secondColony);
        await db.saveMilestone(
          Milestone(
            id: 'overview-second-milestone',
            colonyId: secondColony.id,
            title: '第二蚁群搬家',
            occurredAt: date.add(const Duration(days: 1)),
            createdAt: date,
          ),
        );
      });
      final all = await tester.runAsync(() => db.listAllMilestones());
      expect(all!.first.milestone.title, '第二蚁群搬家');
      expect(all.first.colonyName, '第二蚁群');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MilestonesOverviewPage(active: true)),
        ),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(find.text('第二蚁群搬家'), findsOneWidget);
      expect(find.textContaining('第二蚁群 ·'), findsOneWidget);
      await tester.tap(find.text('第二蚁群搬家'));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(find.text('第二蚁群 · 里程碑'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => db.deleteColony(secondColony.id));
    },
  );

  testWidgets('overview creates a milestone without a colony or diary', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db.deleteColony(colony.id);
      await db.saveColony(colony);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MilestonesOverviewPage(active: true)),
      ),
    );
    await settleDatabase(tester);
    await tester.tap(find.text('添加里程碑'));
    await settleDatabase(tester);
    expect(find.text('不关联蚁群'), findsOneWidget);
    expect(find.text('同步一条蚁群日记'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '里程碑标题'), '独立节点');
    await tester.tap(find.text('保存里程碑'));
    await settleDatabase(tester);
    expect(find.text('独立节点'), findsOneWidget);
    expect(find.textContaining('独立里程碑 ·'), findsOneWidget);
    expect(
      (await tester.runAsync(() => db.listAllMilestones()))!
          .singleWhere((item) => item.milestone.title == '独立节点')
          .milestone
          .colonyId,
      isNull,
    );
    expect(await tester.runAsync(() => db.listRecords(colony.id)), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overview can link a colony and sync one observation diary', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db.deleteColony(colony.id);
      await db.saveColony(colony);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MilestonesOverviewPage(active: true)),
      ),
    );
    await settleDatabase(tester);
    await tester.tap(find.text('添加里程碑'));
    await settleDatabase(tester);
    await tester.tap(find.text('不关联蚁群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试蚁群').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '同步一条蚁群日记'));
    await tester.enterText(find.widgetWithText(TextField, '里程碑标题'), '首批羽化');
    await tester.enterText(find.widgetWithText(TextField, '里程碑说明（可选）'), '工蚁诞生');
    await tester.tap(find.text('保存里程碑'));
    await settleDatabase(tester);
    final milestones = await tester.runAsync(
      () => db.listMilestones(colony.id),
    );
    final diaries = await tester.runAsync(() => db.listRecords(colony.id));
    expect(milestones!.single.title, '首批羽化');
    expect(diaries!.single.type, CareRecordType.observation);
    expect(diaries.single.note, '首批羽化\n工蚁诞生');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'diary filter shows milestones without counting them as diaries',
    (tester) async {
      final today = DateUtils.dateOnly(DateTime.now());
      await tester.runAsync(() async {
        await db.deleteColony(colony.id);
        await db.saveColony(colony);
        await db.saveRecord(
          CareRecord(
            id: 'filtered-diary',
            colonyId: colony.id,
            type: CareRecordType.observation,
            occurredAt: today,
            createdAt: today,
            note: '普通日记',
          ),
        );
        for (final (id, title, occurredAt) in [
          ('recent', '近期里程碑', today),
          ('old', '历史里程碑', DateTime(today.year, today.month, today.day - 8)),
        ]) {
          await db.saveMilestone(
            Milestone(
              id: id,
              colonyId: colony.id,
              title: title,
              occurredAt: occurredAt,
              createdAt: today,
            ),
          );
        }
      });
      await tester.pumpWidget(
        MaterialApp(home: ColonyDetailPage(colonyId: colony.id)),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      final typeFilter = find.byKey(const ValueKey('diary-type-filter'));
      await tester.scrollUntilVisible(
        typeFilter,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(typeFilter);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 条记录'), findsOneWidget);
      await tester.tap(typeFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '里程碑'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 / 2 条里程碑'), findsOneWidget);
      expect(find.text('普通日记'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('diary-time-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('近 7 天').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 / 2 条里程碑'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('近期里程碑'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('历史里程碑'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
