import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/memorial.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/memorial_page.dart';
import 'package:antkeep/widgets/tombstone_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final db = AppDatabase.instance;
  late Directory directory;
  final now = DateTime.now();
  final colony = Colony(
    id: 'kingdom',
    name: '小小王国',
    species: '收获蚁',
    initialWorkerCount: 30,
    queenCount: 2,
    coverPhotoPath: 'cover.jpg',
    createdAt: now,
    updatedAt: now,
  );
  Memorial memorial(String id, MemorialKind kind, {String? colonyId}) =>
      Memorial(
        id: id,
        kind: kind,
        name: '纪念 $id',
        colonyId: colonyId,
        createdAt: now,
        cause: '未知',
        observation: '最后观察',
        lesson: '经验',
      );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-memorial-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
  });

  setUp(() async {
    await db.replaceAll({
      'colonies': [colony.toMap()],
      'care_records': [],
    });
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  test('standalone queen and worker memorials preserve unknown dates and optional links', () async {
    await db.saveMemorial(
      memorial('queen', MemorialKind.queen, colonyId: colony.id),
    );
    await db.saveMemorial(memorial('worker', MemorialKind.worker));
    expect(await db.listMemorials(), hasLength(2));
    final current = (await db.findColony(colony.id))!;
    expect(current.archived, isFalse);
    expect(current.queenCount, 2);
    expect(current.initialWorkerCount, 30);
    expect((await db.listMemorials()).every((m) => m.diedOn == null), isTrue);
    final snapshot = await db.snapshot();
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    expect((await db.listMemorials()).map((m) => m.lesson), everyElement('经验'));
    await db.deleteColony(colony.id);
    expect((await db.listMemorials()).every((m) => m.colonyId == null), isTrue);
  });

  test('brood memorial persists, edits and restores without changing colony counts', () async {
    final original = memorial('brood', MemorialKind.brood, colonyId: colony.id);
    await db.saveMemorial(original);
    await db.saveMemorial(
      Memorial.fromMap({...original.toMap(), 'farewell': '尚未羽化，亦值得被铭记'}),
    );
    final current = (await db.findColony(colony.id))!;
    expect(current.toMap(), colony.toMap());
    final snapshot = await db.snapshot();
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    final reopened = await openDatabase(
      '${directory.path}/antkeep/antkeep.sqlite',
      readOnly: true,
      singleInstance: false,
    );
    try {
      final saved = Memorial.fromMap(
        (await reopened.query('memorials')).single,
      );
      expect(saved.kind, MemorialKind.brood);
      expect(saved.colonyId, colony.id);
      expect(saved.diedOn, isNull);
      expect(saved.farewell, '尚未羽化，亦值得被铭记');
    } finally {
      await reopened.close();
    }
    await db.saveMemorial(
      memorial('end', MemorialKind.colony, colonyId: colony.id),
    );
    await db.restoreMemorialColony('end');
    expect((await db.listMemorials()).single.kind, MemorialKind.brood);
    await db.deleteMemorial(original.id);
    expect(await db.listMemorials(), isEmpty);
  });

  test(
    'standalone queen can be linked later and persists on a second connection',
    () async {
      final original = memorial('queen', MemorialKind.queen);
      await db.saveMemorial(original);
      await db.saveMemorial(
        Memorial.fromMap({
          ...original.toMap(),
          'colony_id': colony.id,
          'farewell': '再见',
        }),
      );
      final reopened = await openDatabase(
        '${directory.path}/antkeep/antkeep.sqlite',
        readOnly: true,
        singleInstance: false,
      );
      try {
        final saved = Memorial.fromMap(
          (await reopened.query('memorials')).single,
        );
        expect(saved.colonyId, colony.id);
        expect(saved.createdAt, original.createdAt);
        expect(saved.farewell, '再见');
      } finally {
        await reopened.close();
      }
    },
  );

  for (final path in GrowthPath.values) {
    test(
      'archiving legacy ${path.name} preserves history and development path',
      () async {
        final start = DateTime(2040, 1, 1);
        final legacy = colony.toMap()
          ..['initial_larva_count'] = 5
          ..['initial_cocoon_count'] = path == GrowthPath.eggToWorker ? 0 : 5
          ..['development_path'] = null
          ..['auto_growth_json'] = ColonyGrowth(
            frequency: GrowthFrequency.daily,
            path: path,
            startedAt: start,
            workers: 1,
          ).encode();
        final record = CareRecord(
          id: 'history',
          colonyId: colony.id,
          type: CareRecordType.observation,
          occurredAt: now,
          createdAt: now,
          photos: ['history.jpg'],
          note: '旧日记',
        );
        await db.replaceAll({
          'colonies': [legacy],
          'care_records': [record.toMap()],
        });
        await db.saveMemorial(
          memorial('end', MemorialKind.colony, colonyId: colony.id),
        );
        final archived = (await db.findColony(colony.id))!;
        expect(archived.developmentPath, path);
        expect(archived.growth, isNull);
        expect(
          (await db.listRecords(colony.id)).single.toMap(),
          record.toMap(),
        );
        final snapshot = await db.snapshot();
        BackupData.validate(snapshot);
        await db.replaceAll(snapshot);
        await db.restoreMemorialColony('end');
        final restored = (await db.findColony(colony.id))!;
        expect(restored.developmentPath, path);
        expect(restored.growth, isNull);
        expect(restored.coverPhotoPath, colony.coverPhotoPath);
        await db.saveRecord(
          CareRecord(
            id: 'worker',
            colonyId: colony.id,
            type: CareRecordType.observation,
            occurredAt: start,
            createdAt: start,
            workerCount: 1,
          ),
          incremental: true,
        );
        final population = restored.currentPopulation(
          await db.listRecords(colony.id),
        );
        expect(population.workers, 31);
        expect(population.larvae, path == GrowthPath.eggToWorker ? 4 : 5);
        expect(population.cocoons, path == GrowthPath.eggToWorker ? 0 : 4);
      },
    );
  }

  test('whole colony archives atomically, retains history and restores without growth catch-up', () async {
    await db.saveRecord(
      CareRecord(
        id: 'history',
        colonyId: colony.id,
        type: CareRecordType.observation,
        occurredAt: now,
        createdAt: now,
        photos: ['history.jpg'],
        note: '第一只工蚁',
      ),
    );
    await db.configureColonyGrowth(
      colony.id,
      ColonyGrowth(
        frequency: GrowthFrequency.daily,
        path: GrowthPath.eggToWorker,
        startedAt: now,
        eggs: 0,
        larvae: 0,
        workers: 1,
      ),
    );
    await db.saveMemorial(
      memorial('queen', MemorialKind.queen, colonyId: colony.id),
    );
    await db.saveMemorial(
      memorial('end', MemorialKind.colony, colonyId: colony.id),
    );
    expect(await db.listColonies(), isEmpty);
    expect((await db.findColony(colony.id))!.growth, isNull);
    expect((await db.listRecords(colony.id)).single.id, 'history');
    final snapshot = await db.snapshot();
    BackupData.validate(snapshot);
    expect(db.photoPaths(snapshot), {'cover.jpg', 'history.jpg'});
    await db.replaceAll(snapshot);
    expect(
      (await db.listMemorials()).where((m) => m.colonyId == colony.id),
      hasLength(2),
    );
    await expectLater(
      db.saveMemorial(
        memorial('duplicate', MemorialKind.colony, colonyId: colony.id),
      ),
      throwsStateError,
    );
    expect(await db.listMemorials(), hasLength(2));
    await expectLater(db.deleteMemorial('end'), throwsStateError);
    await db.restoreMemorialColony('end');
    expect((await db.listColonies()).single.id, colony.id);
    expect((await db.listMemorials()).single.kind, MemorialKind.queen);
    await db.applyColonyGrowth(now: now.add(const Duration(days: 30)));
    expect((await db.listRecords(colony.id)).single.note, '第一只工蚁');
    expect((await db.findColony(colony.id))!.coverPhotoPath, 'cover.jpg');
  });

  test(
    'missing link and invalid whole-colony save leave database unchanged',
    () async {
      await expectLater(
        db.saveMemorial(
          memorial('missing', MemorialKind.colony, colonyId: 'missing'),
        ),
        throwsStateError,
      );
      await expectLater(
        db.saveMemorial(memorial('unlinked', MemorialKind.colony)),
        throwsFormatException,
      );
      expect(await db.listMemorials(), isEmpty);
      expect((await db.findColony(colony.id))!.archived, isFalse);
    },
  );

  test('backup validates memorial types, references, duplicate endings and old backups', () async {
    final snapshot = await db.snapshot();
    for (final row in [
      {...memorial('bad', MemorialKind.queen).toMap(), 'kind': 'invalid'},
      memorial('bad', MemorialKind.queen, colonyId: 'missing').toMap(),
      memorial('bad', MemorialKind.colony, colonyId: colony.id).toMap(),
    ]) {
      expect(
        () => BackupData.validate({
          ...snapshot,
          'memorials': [row],
        }),
        throwsFormatException,
      );
    }
    await db.saveMemorial(
      memorial('end', MemorialKind.colony, colonyId: colony.id),
    );
    final archived = await db.snapshot();
    expect(
      () => BackupData.validate({
        ...archived,
        'memorials': [
          memorial('end', MemorialKind.colony, colonyId: colony.id).toMap(),
          memorial('end2', MemorialKind.colony, colonyId: colony.id).toMap(),
        ],
      }),
      throwsFormatException,
    );
    snapshot.remove('memorials');
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    expect(await db.listMemorials(), isEmpty);
    expect(await db.listColonies(), hasLength(1));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  Future<void> tapVisible(WidgetTester tester, String text) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    final finder = find.text(text);
    await tester.scrollUntilVisible(
      finder,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  for (final (kind, label, epitaph) in [
    (MemorialKind.worker, '工蚁死亡', '将士守山河'),
    (MemorialKind.brood, '幼体夭折（幼虫／蛹／茧）', '未绽放的生命'),
  ]) {
    testWidgets(
      'standalone ${kind.name} entry can be saved without colony or date',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: MemorialFormPage()));
        await settle(tester);
        expect(find.byType(TombstoneIcon), findsOneWidget);
        expect(find.text('君王死社稷'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<MemorialKind>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(find.text(epitaph), findsOneWidget);
        final name = find.widgetWithText(TextFormField, '纪念名称 *');
        await tester.ensureVisible(name);
        await tester.enterText(name, '小小生命');
        await tapVisible(tester, '保存纪念');
        final saved = (await tester.runAsync(db.listMemorials))!.single;
        expect(saved.kind, kind);
        expect(saved.colonyId, isNull);
        expect(saved.diedOn, isNull);
        expect(saved.name, '小小生命');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'queen continuation archives whole colony and links both memorials',
    (tester) async {
      await tester.runAsync(
        () => db.saveMemorial(
          memorial('queen', MemorialKind.queen, colonyId: colony.id),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MemorialDetailPage(
            memorialId: 'queen',
            onOpenColony: (_, _) async {},
          ),
        ),
      );
      await settle(tester);
      expect(find.text('仍在饲养中'), findsOneWidget);
      await tapVisible(tester, '记录后续：整群结束');
      await settle(tester);
      expect(find.text('遗失的文明'), findsOneWidget);
      await tapVisible(tester, '保存纪念');
      expect(find.text('整群移入英灵殿？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => db.findColony(colony.id)))!.archived,
        isFalse,
      );
      await tester.tap(find.text('保存纪念'));
      await settle(tester);
      await tester.tap(find.text('确认移入'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => db.findColony(colony.id)))!.archived,
        isTrue,
      );
      expect(find.text('整群已结束 · 档案与日记保留'), findsOneWidget);
      expect(find.text('记录后续：整群结束'), findsNothing);
      expect((await tester.runAsync(db.listMemorials))!, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'archived colony history is read-only and has no running duration or growth',
    (tester) async {
      await tester.runAsync(
        () => db.saveMemorial(
          memorial('end', MemorialKind.colony, colonyId: colony.id),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: ColonyDetailPage(colonyId: colony.id)),
      );
      await settle(tester);
      expect(find.byTooltip('编辑蚁群'), findsNothing);
      expect(find.byTooltip('删除蚁群'), findsNothing);
      expect(find.text('添加记录'), findsNothing);
      expect(find.text('群落自动扩充'), findsNothing);
      expect(find.text('遗失的文明 · 养殖已结束'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'memorial list refreshes on archive and restore at narrow width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(body: MemorialPage(onOpenColony: (_, _) async {})),
        ),
      );
      await settle(tester);
      expect(find.text('为逝去的小生命留一份纪念'), findsOneWidget);
      await tester.runAsync(
        () => db.saveMemorial(
          memorial('end', MemorialKind.colony, colonyId: colony.id),
        ),
      );
      await settle(tester);
      expect(find.text('纪念 end'), findsOneWidget);
      await tester.tap(find.text('纪念 end'));
      await settle(tester);
      await tapVisible(tester, '恢复到饲养列表');
      await tester.tap(find.text('确认恢复'));
      await settle(tester);
      expect(find.text('为逝去的小生命留一份纪念'), findsOneWidget);
      expect((await tester.runAsync(db.listColonies))!.single.id, colony.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
