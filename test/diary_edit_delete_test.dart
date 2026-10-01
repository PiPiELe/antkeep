import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/widgets/diary_record_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = AppDatabase.instance;
  final at = DateTime(2026, 6, 26, 15, 11);
  final colony = Colony(
    id: 'diary-colony',
    name: '日记测试',
    initialWorkerCount: 10,
    createdAt: at,
    updatedAt: at,
  );
  CareRecord record({
    String id = 'diary',
    int? workers = 18,
    List<String> photos = const [],
  }) => CareRecord(
    id: id,
    colonyId: colony.id,
    type: CareRecordType.observation,
    occurredAt: at,
    createdAt: at,
    note: '新后',
    temperature: 25,
    humidity: 60,
    eggCount: 0,
    workerCount: workers,
    photos: photos,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-diary-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
    await LocalMediaStore.instance.initialize();
  });
  setUp(() async {
    await db.deleteColony(colony.id);
    await db.saveColony(colony);
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test(
    'editing updates identity in place and deletion restores prior population',
    () async {
      await db.saveRecord(record(id: 'earlier', workers: 12));
      final original = record(photos: ['retained.jpg']);
      await db.saveRecord(original);
      final edited = CareRecord.fromMap({
        ...original.toMap(),
        'note': '已编辑',
        'worker_count': 21,
        'egg_count': null,
        'occurred_at': at.add(const Duration(hours: 1)).toIso8601String(),
        'created_at': DateTime(2026, 9, 1).toIso8601String(),
      });
      await db.updateRecord(edited);
      var records = await db.listRecords(colony.id);
      expect(records, hasLength(2));
      expect(records.first.id, original.id);
      expect(records.first.createdAt, original.createdAt);
      expect(records.first.photos, ['retained.jpg']);
      expect(records.first.eggCount, isNull);
      expect(records.first.note, '已编辑');
      expect(colony.currentWorkerCount(records), 21);
      expect((await db.findColony(colony.id))!.updatedAt.isAfter(at), isTrue);
      final snapshot = await db.snapshot();
      await db.replaceAll(snapshot);
      expect((await db.listRecords(colony.id)).first.note, '已编辑');
      await db.deleteRecord(edited);
      records = await db.listRecords(colony.id);
      expect(records.single.id, 'earlier');
      expect(colony.currentWorkerCount(records), 12);
      expect(
        db.photoPaths(await db.snapshot()),
        isNot(contains('retained.jpg')),
      );
      await expectLater(db.updateRecord(edited), throwsStateError);
      expect(await db.listRecords(colony.id), hasLength(1));
      await db.deleteRecord(records.single);
      expect(colony.currentWorkerCount(await db.listRecords(colony.id)), 10);
    },
  );

  test('record mutations are scoped to their colony', () async {
    final original = record();
    await db.saveRecord(original);
    final wrongColony = CareRecord.fromMap({
      ...original.toMap(),
      'colony_id': 'another-colony',
    });
    await expectLater(db.updateRecord(wrongColony), throwsStateError);
    await db.deleteRecord(wrongColony);
    expect((await db.listRecords(colony.id)).single.toMap(), original.toMap());
  });

  Future<void> settleDatabase(WidgetTester tester) async {
    // Let real SQLite/file I/O complete between fake animation frames.
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  Future<void> openDiary(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ColonyDetailPage(colonyId: colony.id)),
    );
    await settleDatabase(tester);
    await tester.scrollUntilVisible(
      find.byType(DiaryRecordActions),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byType(DiaryRecordActions));
    await settleDatabase(tester);
  }

  testWidgets(
    'tap edits existing values and preserves counts and photos on save',
    (tester) async {
      final original = record(photos: ['existing.jpg']);
      await tester.runAsync(() => db.saveRecord(original));
      await openDiary(tester);
      await tester.tap(find.text('新后'));
      await settleDatabase(tester);
      expect(find.text('编辑日记'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '备注'))
            .controller!
            .text,
        '新后',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '温度 °C'))
            .controller!
            .text,
        '25.0',
      );
      expect(find.text('增量'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, '备注'), '日记已修改');
      await tester.scrollUntilVisible(
        find.text('保存记录'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await settleDatabase(tester);
      expect(find.text('已有照片'), findsOneWidget);
      await tester.tap(find.text('保存记录'));
      await settleDatabase(tester);
      await tester.scrollUntilVisible(
        find.text('日记已修改'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final records = await tester.runAsync(() => db.listRecords(colony.id));
      expect(records, hasLength(1));
      expect(records!.single.id, original.id);
      expect(records.single.createdAt, original.createdAt);
      expect(records.single.photos, original.photos);
      expect(records.single.workerCount, 18);
      expect(records.single.eggCount, 0);
      expect(records.single.larvaCount, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'swipe reveals delete; cancel retains diary; confirm refreshes empty state',
    (tester) async {
      await tester.runAsync(() => db.saveRecord(record()));
      await openDiary(tester);
      expect(find.text('删除'), findsNothing);
      await tester.drag(find.byType(DiaryRecordActions), const Offset(-180, 0));
      await settleDatabase(tester);
      expect(find.text('删除'), findsOneWidget);
      expect(
        await tester.runAsync(() => db.listRecords(colony.id)),
        hasLength(1),
      );
      await tester.tap(find.text('删除'));
      await settleDatabase(tester);
      expect(find.text('删除日记？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settleDatabase(tester);
      expect(find.text('新后'), findsOneWidget);
      await tester.drag(find.byType(DiaryRecordActions), const Offset(-180, 0));
      await settleDatabase(tester);
      await tester.tap(find.text('删除'));
      await settleDatabase(tester);
      await tester.tap(find.text('确认删除'));
      await settleDatabase(tester);
      await tester.scrollUntilVisible(
        find.text('还没有记录'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(DiaryRecordActions), findsNothing);
      expect(await tester.runAsync(() => db.listRecords(colony.id)), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
