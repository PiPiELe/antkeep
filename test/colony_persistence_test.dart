import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-colony-edit-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AppDatabase.instance.open();
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
    'updating a colony retains its foreign-key-linked care records',
    () async {
      final now = DateTime(2026, 9, 29);
      final colony = Colony(
        id: 'colony',
        name: '原档案',
        initialWorkerCount: 0,
        createdAt: now,
        updatedAt: now,
        coverPhotoPath: 'cover.jpg',
      );
      await AppDatabase.instance.saveColony(colony);
      await AppDatabase.instance.saveRecord(
        CareRecord(
          id: 'record',
          colonyId: colony.id,
          type: CareRecordType.observation,
          occurredAt: now,
          createdAt: now,
          note: '保留历史记录',
          photos: const ['record.jpg'],
        ),
      );
      final edited = Colony.fromMap({
        ...colony.toMap(),
        'name': '修改后的档案',
        'initial_worker_count': 10000,
      });
      await AppDatabase.instance.saveColony(edited);
      expect(await AppDatabase.instance.listColonies(), hasLength(1));
      final restored = (await AppDatabase.instance.findColony(colony.id))!;
      expect(restored.name, '修改后的档案');
      expect(restored.scale, ColonyScale.superLarge);
      expect(restored.coverPhotoPath, 'cover.jpg');
      expect(restored.createdAt, now);
      final record = (await AppDatabase.instance.listRecords(colony.id)).single;
      expect(record.note, '保留历史记录');
      expect(record.photos, ['record.jpg']);
    },
  );
}
