import 'dart:convert';
import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_archive.dart';
import 'package:antkeep/data/backup_service.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/data/rollback_store.dart';
import 'package:antkeep/domain/models.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> fixture() {
  final time = DateTime(2026, 9, 29);
  return {
    'colonies': [
      Colony(id: 'c', name: '蚁群', createdAt: time, updatedAt: time).toMap(),
    ],
    'care_records': [
      CareRecord(
        id: 'r',
        colonyId: 'c',
        type: CareRecordType.observation,
        occurredAt: time,
        createdAt: time,
        photos: ['image.jpg'],
      ).toMap(),
    ],
    'feeder_records': [
      FeederRecord(
        id: 'f',
        feeder: FeederType.cricket,
        type: FeederRecordType.observation,
        occurredAt: time,
        createdAt: time,
      ).toMap(),
    ],
    'inventory_items': [
      InventoryItem(
        id: 'i',
        name: '物品',
        purchased: true,
        createdAt: time,
        quantity: 2,
        purchasePriceCents: 100,
      ).toMap(),
    ],
  };
}

Uint8List archiveBytes(
  Map<String, dynamic> data, {
  Map<String, List<int>>? media,
}) {
  media ??= {
    'image.jpg': [9, 9, 9],
  };
  final manifest = utf8.encode(
    jsonEncode({
      'format': 'antkeep',
      'version': 1,
      'data': data,
      'media': media.keys.toList(),
    }),
  );
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
  for (final entry in media.entries) {
    archive.addFile(
      ArchiveFile('media/${entry.key}', entry.value.length, entry.value),
    );
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase.instance;
  final media = LocalMediaStore.instance;
  final service = BackupService(database, media);
  late Directory directory;
  late Uint8List previousRollback;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'antkeep-backup-service-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await database.open();
    await media.initialize();
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
    await database.replaceAll(fixture());
    await media.restoreFiles({
      'image.jpg': [1, 2, 3],
    });
    previousRollback = await service.createBackupBytes();
    await RollbackStore.instance.save(previousRollback);
  });

  test(
    'valid restore and undo round-trip all tables and overwritten photos',
    () async {
      final before = await database.snapshot();
      final incoming = fixture();
      incoming['colonies'][0]['name'] = '导入蚁群';
      incoming['inventory_items'][0]['quantity'] = 8;
      await service.restoreBytes(archiveBytes(incoming));
      expect((await database.findColony('c'))!.name, '导入蚁群');
      expect((await database.listInventory()).single.quantity, 8);
      expect(await media.readImage('image.jpg'), [9, 9, 9]);
      await service.undoLastRestore();
      expect(await database.snapshot(), before);
      expect(await media.readImage('image.jpg'), [1, 2, 3]);
    },
  );

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'colony date': (d) => d['colonies'][0]['created_at'] = 'not-a-date',
    'optional date': (d) => d['colonies'][0]['acquired_on'] = 'not-a-date',
    'colony count type': (d) => d['colonies'][0]['queen_count'] = '2',
    'boolean flag': (d) => d['colonies'][0]['archived'] = 2,
    'missing id': (d) => d['colonies'][0].remove('id'),
    'unknown column': (d) => d['colonies'][0]['future_column'] = 1,
    'duplicate id': (d) =>
        d['colonies'].add(Map<String, Object?>.from(d['colonies'][0])),
    'record date': (d) => d['care_records'][0]['occurred_at'] = 'not-a-date',
    'photo list type': (d) => d['care_records'][0]['photos_json'] = '[3]',
    'photo column type': (d) => d['care_records'][0]['photos_json'] = [],
    'unknown record type': (d) =>
        d['care_records'][0]['record_type'] = 'future',
    'orphan record': (d) => d['care_records'][0]['colony_id'] = 'absent',
    'feeder date': (d) => d['feeder_records'][0]['created_at'] = 'not-a-date',
    'feeder count type': (d) => d['feeder_records'][0]['adult_count'] = '2',
    'inventory date': (d) =>
        d['inventory_items'][0]['purchased_at'] = 'not-a-date',
    'null required default': (d) => d['inventory_items'][0]['purchased'] = null,
    'negative quantity': (d) => d['inventory_items'][0]['quantity'] = -1,
    'negative price': (d) =>
        d['inventory_items'][0]['purchase_price_cents'] = -1,
    'duplicate inventory name': (d) => d['inventory_items'].add({
      ...d['inventory_items'][0] as Map<String, Object?>,
      'id': 'another',
      'group_name': '',
    }),
  };
  for (final corruption in corruptions.entries) {
    test(
      'rejects ${corruption.key} without changing data, media or rollback',
      () async {
        final before = await database.snapshot();
        final incoming = fixture();
        corruption.value(incoming);
        await expectLater(
          service.restoreBytes(archiveBytes(incoming)),
          throwsFormatException,
        );
        expect(await database.snapshot(), before);
        expect(await media.readImage('image.jpg'), [1, 2, 3]);
        expect(await RollbackStore.instance.read(), previousRollback);
      },
    );
  }

  test('legacy backups may omit newer tables and optional columns', () async {
    final time = '2026-09-01T00:00:00.000';
    await service.restoreBytes(
      archiveBytes({
        'colonies': [
          {'id': 'old', 'name': '旧数据', 'created_at': time, 'updated_at': time},
        ],
        'care_records': [],
      }, media: {}),
    );
    expect((await database.findColony('old'))!.initialWorkerCount, isNull);
    expect(await database.listRecords('old'), isEmpty);
    expect(await database.listFeederRecords(FeederType.cricket), isEmpty);
    // Older backups did not cover inventory, so existing items remain intact.
    expect((await database.listInventory()).single.id, 'i');
  });

  test(
    '499 photos export and restore successfully at the entry limit',
    () async {
      final files = {
        for (var i = 0; i < 499; i++) 'image-$i.jpg': <int>[i % 256],
      };
      final data = fixture();
      data['care_records'][0]['photos_json'] = jsonEncode(files.keys.toList());
      await media.restoreFiles(files);
      await database.replaceAll(data);
      final bytes = await service.createBackupBytes();
      expect(BackupArchive.decode(bytes).files, hasLength(500));
      await database.replaceAll(fixture());
      await service.restoreBytes(bytes);
      expect((await database.listRecords('c')).single.photos, hasLength(499));
      expect(await media.readImage('image-498.jpg'), files['image-498.jpg']);
    },
  );

  test(
    '500 photos fail export explicitly before reading attachments',
    () async {
      final data = fixture();
      data['care_records'][0]['photos_json'] = jsonEncode([
        for (var i = 0; i < 500; i++) 'absent-$i.jpg',
      ]);
      await database.replaceAll(data);
      await expectLater(
        service.createBackupBytes(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('499'),
          ),
        ),
      );
    },
  );
}
