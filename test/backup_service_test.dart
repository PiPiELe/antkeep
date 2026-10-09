import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/data/backup_archive.dart';
import 'package:antkeep/data/backup_resources.dart';
import 'package:antkeep/data/backup_service.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/data/rollback_store.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/care_task.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/memorial.dart';
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
  int version = 1,
}) {
  media ??= {
    'image.jpg': [9, 9, 9],
  };
  final manifest = utf8.encode(
    jsonEncode({
      'format': 'antkeep',
      'version': version,
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
    'ZIP restore keeps colony tasks and structured feeding results',
    () async {
      final today = DateTime(2026, 10, 9);
      await database.saveCareTask(
        CareTask(
          id: 'care-feeding',
          colonyId: 'c',
          type: CareTaskType.feeding,
          intervalDays: 4,
          nextDueOn: today,
        ),
      );
      await database.saveRecord(
        CareRecord(
          id: 'feeding-result',
          colonyId: 'c',
          type: CareRecordType.feeding,
          occurredAt: today,
          createdAt: today,
          feedingFood: '杜比亚',
          feedingAmount: '1只',
          feedingResponse: FeedingResponse.normal,
          feedingLeftovers: true,
        ),
      );
      final expected = await database.snapshot();
      final bytes = await service.createBackupBytes();
      await database.replaceAll(fixture());
      await service.restoreBytes(bytes, mode: BackupRestoreMode.overwrite);
      expect(await database.snapshot(), expected);
    },
  );

  test('incremental restore keeps the local plan for the same type', () async {
    final date = DateTime(2026, 10, 9);
    final local = CareTask(
      id: 'local-plan',
      colonyId: 'c',
      type: CareTaskType.watering,
      intervalDays: 2,
      nextDueOn: date,
    );
    await database.saveCareTask(local);
    final incoming = fixture();
    incoming['care_tasks'] = [
      CareTask(
        id: 'other-plan',
        colonyId: 'c',
        type: CareTaskType.watering,
        intervalDays: 5,
        nextDueOn: date.add(const Duration(days: 5)),
      ).toMap(),
    ];
    await service.restoreBytes(
      archiveBytes(incoming),
      mode: BackupRestoreMode.incremental,
    );
    final tasks = await database.listCareTasks(colonyId: 'c');
    expect(tasks, hasLength(1));
    expect(tasks.single.id, local.id);
    expect(tasks.single.intervalDays, 2);
  });

  test('incremental growth restore preserves history and resumes exactly once', () async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 2));
    final colony = Colony(
      id: 'growth',
      name: '旧蚁群',
      createdAt: start,
      updatedAt: start,
      initialWorkerCount: 10,
      initialEggCount: 10,
      initialLarvaCount: 10,
      initialCocoonCount: 10,
      developmentPath: GrowthPath.eggToWorker,
    );
    await database.saveColony(colony);
    final rule = ColonyGrowth(
      frequency: GrowthFrequency.daily,
      path: GrowthPath.eggToWorker,
      startedAt: start,
      eggs: 0,
      larvae: 0,
      workers: 1,
    );
    await database.configureColonyGrowth(colony.id, rule, now: start);
    final olderBackup = await service.createBackupBytes();
    await database.applyColonyGrowth(now: now);
    final history = (await database.snapshot())['care_records'];
    final newerBackup = await service.createBackupBytes();
    await service.restoreBytes(olderBackup);
    await service.restoreBytes(
      newerBackup,
      mode: BackupRestoreMode.incremental,
    );
    await database.listColonies();
    expect((await database.snapshot())['care_records'], history);
    expect((await database.findColony(colony.id))!.growth!.completedCycles, 2);
    final records = await database.listRecords(colony.id);
    expect(records.map((r) => r.workerCount), [12, 11]);
    // Importing again and restarting from a snapshot must not duplicate cycles.
    await service.restoreBytes(
      newerBackup,
      mode: BackupRestoreMode.incremental,
    );
    await database.replaceAll(await database.snapshot());
    await database.applyColonyGrowth(now: rule.dueAt(3));
    final next = await database.listRecords(colony.id);
    expect(next, hasLength(3));
    expect(next.first.workerCount, 13);
    expect(next.first.larvaCount, 10);
    expect(next.skip(1).map((r) => r.toMap()), records.map((r) => r.toMap()));
    expect(await media.readImage('image.jpg'), [1, 2, 3]);
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

  test('incremental restore preserves local rows and photos, adds missing data and undoes', () async {
    final before = await database.snapshot();
    final incoming = fixture();
    incoming['colonies'][0]['name'] = '不应覆盖';
    incoming['colonies'].add({
      ...incoming['colonies'][0] as Map<String, Object?>,
      'id': 'new-colony',
      'cover_photo_path': 'image.jpg',
    });
    incoming['care_records'][0]['note'] = '不应覆盖';
    incoming['care_records'].add({
      ...incoming['care_records'][0] as Map<String, Object?>,
      'id': 'new-record',
    });
    incoming['care_records'].add({
      ...incoming['care_records'][0] as Map<String, Object?>,
      'id': 'new-colony-record',
      'colony_id': 'new-colony',
    });
    incoming['feeder_records'][0]['note'] = '不应覆盖';
    incoming['feeder_records'].add({
      ...incoming['feeder_records'][0] as Map<String, Object?>,
      'id': 'new-feeder',
    });
    incoming['inventory_items'][0]['quantity'] = 99;
    incoming['inventory_items'].add({
      ...incoming['inventory_items'][0] as Map<String, Object?>,
      'id': 'new-item',
      'name': '新物品',
    });
    await service.restoreBytes(
      archiveBytes(incoming),
      mode: BackupRestoreMode.incremental,
    );
    final after = await database.snapshot();
    for (final table in before.keys) {
      expect(after[table], containsAll(before[table] as List));
    }
    expect(after['colonies'], hasLength(2));
    expect(after['care_records'], hasLength(3));
    expect(after['feeder_records'], hasLength(2));
    expect(after['inventory_items'], hasLength(2));
    final imported = (await database.listRecords('new-colony'))
        .single
        .photos
        .single;
    expect(imported, isNot('image.jpg'));
    expect((await database.findColony('new-colony'))!.coverPhotoPath, imported);
    expect(await media.readImage(imported), [9, 9, 9]);
    expect(await media.readImage('image.jpg'), [1, 2, 3]);
    await service.undoLastRestore();
    expect(await database.snapshot(), before);
    expect(await media.readImage('image.jpg'), [1, 2, 3]);
  });

  test(
    'repeated incremental import is idempotent and skips same-name inventory',
    () async {
      final incoming = fixture();
      incoming['inventory_items'][0]['id'] = 'different-id';
      incoming['inventory_items'][0]['group_name'] = '';
      incoming['inventory_items'][0]['quantity'] = 99;
      incoming['care_records'][0]['id'] = 'new-record';
      final bytes = archiveBytes(incoming);
      await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
      final once = await database.snapshot();
      final photoPaths = database.photoPaths(once);
      await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
      expect(await database.snapshot(), once);
      expect(database.photoPaths(await database.snapshot()), photoPaths);
      expect((await database.listInventory()).single.id, 'i');
      expect((await database.listInventory()).single.quantity, 2);
      expect(await media.readImage('image.jpg'), [1, 2, 3]);
    },
  );

  test(
    'legacy incremental backup retains tables absent from the archive',
    () async {
      final before = await database.snapshot();
      final incoming = fixture()
        ..remove('feeder_records')
        ..remove('inventory_items');
      incoming['colonies'][0]['id'] = 'legacy';
      incoming['care_records'] = [];
      await service.restoreBytes(
        archiveBytes(incoming, media: {}),
        mode: BackupRestoreMode.incremental,
      );
      final after = await database.snapshot();
      expect(after['colonies'], hasLength(2));
      for (final table in [
        'care_records',
        'feeder_records',
        'inventory_items',
      ]) {
        expect(after[table], before[table]);
      }
    },
  );

  test(
    'incremental merge exceeding backup limits leaves data and rollback intact',
    () async {
      final before = await database.snapshot();
      final incoming = fixture();
      incoming['care_records'][0]['id'] = 'new-record';
      final files = {
        for (var i = 0; i < 1999; i++) 'new-$i.jpg': <int>[i % 256],
      };
      incoming['care_records'][0]['photos_json'] = jsonEncode(
        files.keys.toList(),
      );
      await expectLater(
        service.restoreBytes(
          archiveBytes(incoming, media: files),
          mode: BackupRestoreMode.incremental,
        ),
        throwsFormatException,
      );
      expect(await database.snapshot(), before);
      expect(await media.readImage('image.jpg'), [1, 2, 3]);
      expect(await RollbackStore.instance.read(), previousRollback);
    },
  );

  test('v2 ZIP restores memorial links, archived history and photos; undo preserves them', () async {
    for (final kind in [MemorialKind.queen, MemorialKind.colony]) {
      await database.saveMemorial(
        Memorial(
          id: kind.name,
          kind: kind,
          name: '纪念',
          colonyId: 'c',
          createdAt: DateTime(2026, 10, 2),
        ),
      );
    }
    final before = await database.snapshot();
    final bytes = await service.createBackupBytes();
    final manifest = jsonDecode(
      utf8.decode(
        BackupArchive.decode(bytes).findFile('manifest.json')!.content,
      ),
    );
    expect(manifest['version'], 2);
    await service.restoreBytes(archiveBytes(fixture()));
    expect(await database.listMemorials(), isEmpty);
    await service.undoLastRestore();
    expect(await database.snapshot(), before);
    await database.replaceAll(fixture());
    await service.restoreBytes(bytes);
    expect(await database.snapshot(), before);
    expect(await database.listColonies(), isEmpty);
    expect((await database.listRecords('c')).single.photos, ['image.jpg']);
    expect(await media.readImage('image.jpg'), [1, 2, 3]);
  });

  for (final archiveAgain in [false, true]) {
    test(
      'incremental memorial restore preserves local state (archived: $archiveAgain)',
      () async {
        final time = DateTime(2026, 10, 2);
        for (final kind in MemorialKind.values) {
          await database.saveMemorial(
            Memorial(
              id: kind.name,
              kind: kind,
              name: kind.label,
              colonyId: 'c',
              createdAt: time,
            ),
          );
        }
        final bytes = await service.createBackupBytes();
        await database.restoreMemorialColony('colony');
        await database.deleteMemorial('queen');
        await database.deleteMemorial('worker');
        await database.deleteMemorial('brood');
        if (archiveAgain) {
          await database.saveMemorial(
            Memorial(
              id: 'local-ending',
              kind: MemorialKind.colony,
              name: '本地新的整群纪念',
              colonyId: 'c',
              createdAt: time,
            ),
          );
        }
        final before = await database.snapshot();
        await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
        final after = await database.snapshot();
        expect(after['colonies'], before['colonies']);
        expect(after['care_records'], before['care_records']);
        expect(await media.readImage('image.jpg'), [1, 2, 3]);
        expect(
          (await database.listMemorials()).map((m) => m.id),
          unorderedEquals([
            'queen',
            'worker',
            'brood',
            if (archiveAgain) 'local-ending',
          ]),
        );
        await service.createBackupBytes();
        await service.undoLastRestore();
        expect(await database.snapshot(), before);
        // Repeated imports must neither duplicate endings nor change photos.
        await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
        await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
        expect(await database.snapshot(), after);
      },
    );
  }

  test(
    'incremental restore imports a missing archived colony and its memorials',
    () async {
      final time = DateTime(2026, 10, 2);
      for (final kind in MemorialKind.values) {
        await database.saveMemorial(
          Memorial(
            id: kind.name,
            kind: kind,
            name: kind.label,
            colonyId: 'c',
            createdAt: time,
          ),
        );
      }
      final bytes = await service.createBackupBytes();
      await database.replaceAll({'colonies': [], 'care_records': []});
      await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
      expect((await database.findColony('c'))!.archived, isTrue);
      expect((await database.findColony('c'))!.growth, isNull);
      expect(
        (await database.listMemorials()).map((m) => m.kind),
        unorderedEquals(MemorialKind.values),
      );
      final photo = (await database.listRecords('c')).single.photos.single;
      expect(await media.readImage(photo), [1, 2, 3]);
      final after = await database.snapshot();
      await service.restoreBytes(bytes, mode: BackupRestoreMode.incremental);
      expect(await database.snapshot(), after);
      await service.createBackupBytes();
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
  for (final mode in BackupRestoreMode.values) {
    for (final corruption in corruptions.entries) {
      test(
        '$mode rejects ${corruption.key} without changing data, media or rollback',
        () async {
          final before = await database.snapshot();
          final incoming = fixture();
          corruption.value(incoming);
          await expectLater(
            service.restoreBytes(archiveBytes(incoming), mode: mode),
            throwsFormatException,
          );
          expect(await database.snapshot(), before);
          expect(await media.readImage('image.jpg'), [1, 2, 3]);
          expect(await RollbackStore.instance.read(), previousRollback);
        },
      );
    }
  }

  test('database failure restores overwritten photos and previous rollback', () async {
    final before = await database.snapshot();
    final db = await openDatabase(await applicationDatabasePath());
    await db.execute("CREATE TRIGGER reject_restore BEFORE INSERT ON colonies BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END");
    try {
      await expectLater(service.restoreBytes(archiveBytes(fixture())), throwsA(isA<DatabaseException>()));
      expect(await database.snapshot(), before);
      expect(await media.readImage('image.jpg'), [1, 2, 3]);
      expect(await RollbackStore.instance.read(), previousRollback);
    } finally {
      await db.execute('DROP TRIGGER reject_restore');
    }
  });

  test('file APIs restore and undo without a byte-array export', () async {
    final output = File('${directory.path}/streamed.zip');
    await service.writeBackupFile(output);
    await media.restoreFiles({'image.jpg': [6, 6]});
    await service.restoreFile(output);
    expect(await media.readImage('image.jpg'), [1, 2, 3]);
    await service.undoLastRestore();
    expect(await media.readImage('image.jpg'), [6, 6]);
  });

  test('disk shortage leaves database, photos and previous rollback intact', () async {
    final before = await database.snapshot();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(BackupResources.channel, (_) async => {'freeDisk': 1, 'availableMemory': 1024 * 1024 * 1024});
    try {
      await expectLater(service.restoreBytes(archiveBytes(fixture())), throwsStateError);
      expect(await database.snapshot(), before);
      expect(await media.readImage('image.jpg'), [1, 2, 3]);
      expect(await RollbackStore.instance.read(), previousRollback);
    } finally {
      messenger.setMockMethodCallHandler(BackupResources.channel, null);
    }
  });

  test('corrupt attachment preserves database, photos and previous rollback', () async {
    final before = await database.snapshot();
    final zip = archiveBytes(fixture());
    // Corrupt central CRC while keeping the local CRC consistent so extraction
    // must detect the actual mismatch, rather than only validating headers.
    final view = ByteData.sublistView(zip);
    for (var i = 0; i + 46 <= zip.length; i++) {
      if (view.getUint32(i, Endian.little) == 0x02014b50 &&
          utf8.decode(zip.sublist(i + 46, i + 46 + view.getUint16(i + 28, Endian.little))).startsWith('media/')) {
        final offset = view.getUint32(i + 42, Endian.little);
        view.setUint32(i + 16, 123, Endian.little);
        view.setUint32(offset + 14, 123, Endian.little);
      }
    }
    await expectLater(service.restoreBytes(zip), throwsFormatException);
    expect(await database.snapshot(), before);
    expect(await media.readImage('image.jpg'), [1, 2, 3]);
    expect(await RollbackStore.instance.read(), previousRollback);
  });

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

  test('format 1 and 2 feeding history imports without new fields', () async {
    for (final version in [1, 2]) {
      await database.replaceAll(fixture());
      final localTask = CareTask(
        id: 'local-task',
        colonyId: 'c',
        type: CareTaskType.feeding,
        intervalDays: 3,
        nextDueOn: DateTime(2026, 10, 9),
      );
      await database.saveCareTask(localTask);
      final oldData = fixture();
      final oldRecord = Map<String, Object?>.from(oldData['care_records'][0]);
      oldRecord['id'] = 'old-feeding';
      oldRecord['record_type'] = 'feeding';
      oldRecord['note'] = '旧版投喂：果蝇，已吃完';
      oldRecord.removeWhere((key, _) => key.startsWith('feeding_'));
      oldData['care_records'] = [oldRecord];
      if (version == 2) oldData['memorials'] = <Map<String, Object?>>[];
      await service.restoreBytes(
        archiveBytes(oldData, version: version),
        mode: BackupRestoreMode.incremental,
      );
      final records = await database.listRecords('c');
      final imported = records.singleWhere(
        (record) => record.id == 'old-feeding',
      );
      expect(imported.note, '旧版投喂：果蝇，已吃完');
      expect(imported.feedingFood, isNull);
      expect(imported.feedingAmount, isNull);
      expect(imported.feedingResponse, isNull);
      expect(imported.feedingLeftovers, isNull);
      expect(await media.readImage(imported.photos.single), [9, 9, 9]);
      expect(
        (await database.listCareTasks(colonyId: 'c')).single.id,
        localTask.id,
      );

      await service.restoreBytes(
        archiveBytes(oldData, version: version),
        mode: BackupRestoreMode.overwrite,
      );
      final restored = (await database.listRecords('c')).single;
      expect(restored.id, 'old-feeding');
      expect(restored.note, '旧版投喂：果蝇，已吃完');
      expect(await media.readImage(restored.photos.single), [9, 9, 9]);
      expect(await database.listCareTasks(colonyId: 'c'), isEmpty);
    }
  });

  test(
    '1999 photos export and restore successfully at the entry limit',
    () async {
      final files = {
        for (var i = 0; i < 1999; i++) 'image-$i.jpg': <int>[i % 256],
      };
      final data = fixture();
      data['care_records'][0]['photos_json'] = jsonEncode(files.keys.toList());
      await media.restoreFiles(files);
      await database.replaceAll(data);
      final bytes = await service.createBackupBytes();
      expect(BackupArchive.decode(bytes).files, hasLength(2000));
      await database.replaceAll(fixture());
      await service.restoreBytes(bytes);
      expect((await database.listRecords('c')).single.photos, hasLength(1999));
      expect(await media.readImage('image-1998.jpg'), files['image-1998.jpg']);
    },
  );

  test(
    '2000 photos fail export explicitly before reading attachments',
    () async {
      final data = fixture();
      data['care_records'][0]['photos_json'] = jsonEncode([
        for (var i = 0; i < 2000; i++) 'absent-$i.jpg',
      ]);
      await database.replaceAll(data);
      await expectLater(
        service.createBackupBytes(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('1999'),
          ),
        ),
      );
    },
  );
}
