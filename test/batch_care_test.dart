import 'dart:io';

import 'package:antkeep/batch_care_page.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = AppDatabase.instance;
  final now = DateTime(2026, 10, 11);

  Colony colony(String id) =>
      Colony(id: id, name: id, createdAt: now, updatedAt: now);

  CareRecord record(String id, String colonyId) => CareRecord(
    id: id,
    colonyId: colonyId,
    type: CareRecordType.feeding,
    occurredAt: now,
    createdAt: now,
    feedingFood: '面包虫',
    feedingResponse: FeedingResponse.eager,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-batch-');
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
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test(
    'batch writes distinct colony records and rolls back on failure',
    () async {
      await db.saveColony(colony('batch-a'));
      await db.saveColony(colony('batch-b'));
      await db.saveRecordsBatch([
        record('batch-record-a', 'batch-a'),
        record('batch-record-b', 'batch-b'),
      ]);
      expect((await db.listRecords('batch-a')).single.feedingFood, '面包虫');
      expect(
        (await db.listRecords('batch-b')).single.feedingResponse,
        FeedingResponse.eager,
      );

      await expectLater(
        db.saveRecordsBatch([
          record('rollback-a', 'batch-a'),
          record('rollback-missing', 'missing-colony'),
        ]),
        throwsStateError,
      );
      expect(await db.listRecords('batch-a'), hasLength(1));
      expect(await db.listRecords('batch-b'), hasLength(1));

      await expectLater(
        db.saveRecordsBatch([
          record('duplicate-a', 'batch-a'),
          record('duplicate-b', 'batch-a'),
        ]),
        throwsArgumentError,
      );
      expect(await db.listRecords('batch-a'), hasLength(1));
    },
  );

  testWidgets('batch page selects colonies individually', (tester) async {
    final first = colony('batch-ui-a');
    final second = colony('batch-ui-b');
    await tester.pumpWidget(
      MaterialApp(home: BatchCarePage(colonies: [first, second])),
    );
    expect(find.text('保存 (0)'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('保存 (1)'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('保存 (0)'), findsOneWidget);
  });
}
