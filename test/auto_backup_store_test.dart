import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/auto_backup_store_io.dart';
import 'package:antkeep/data/auto_backup_model.dart';
import 'package:antkeep/data/backup_service_io.dart';
import 'package:antkeep/data/backup_zip_io.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase.instance;
  final media = LocalMediaStore.instance;
  late Directory directory;
  late Directory backups;
  late LocalAutoBackupStorage storage;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-auto-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await database.open();
    await media.initialize();
    backups = Directory('${directory.path}/backups');
    storage = LocalAutoBackupStorage(
      BackupService(database, media),
      directory: backups,
    );
  });

  tearDownAll(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('full backups retain photos, rotate only owned files, and restore stable IDs', () async {
    final at = DateTime(2026, 10, 21);
    await database.saveColony(
      Colony(
        id: 'queen-1',
        name: '小黑',
        coverPhotoPath: 'photo.jpg',
        createdAt: at,
        updatedAt: at,
      ),
    );
    await media.restoreFiles({
      'photo.jpg': [1, 2, 3, 4],
    });
    await backups.create(recursive: true);
    final manual = File('${backups.path}/manual.zip');
    await manual.writeAsString('manual backup');
    for (var day = 0; day < 4; day++) {
      await storage.create(at.add(Duration(days: day)));
    }
    expect(await manual.readAsString(), 'manual backup');
    var entries = await storage.list();
    expect(entries.length, 3);
    final newest = entries.first;
    final zip = await BackupZip.inspect(File('${backups.path}/${newest.name}'));
    expect(
      zip.map((e) => e.name),
      containsAll(['manifest.json', 'media/photo.jpg']),
    );
    await database.deleteColony('queen-1');
    await media.deleteFiles(['photo.jpg']);
    await storage.restore(newest, incremental: true);
    expect((await database.findColony('queen-1'))!.name, '小黑');
    final restored = (await database.findColony('queen-1'))!;
    expect(await media.readImage(restored.coverPhotoPath!), [1, 2, 3, 4]);
    // A rollback of the device clock retains the newly published backup too.
    await storage.create(at.subtract(const Duration(days: 1)));
    entries = await storage.list();
    expect(entries.length, 3);
    expect(
      entries.any((e) => e.createdAt == at.subtract(const Duration(days: 1))),
      isTrue,
    );
  });

  test(
    'failed snapshot preserves previous ZIPs and never prunes them',
    () async {
      final before = (await storage.list()).map((e) => e.name).toSet();
      final at = DateTime(2026, 11, 1);
      await database.saveColony(
        Colony(
          id: 'missing',
          name: 'missing photo',
          coverPhotoPath: 'missing.jpg',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await expectLater(storage.create(at), throwsStateError);
      expect((await storage.list()).map((e) => e.name).toSet(), before);
      expect(
        await File(
          '${backups.path}/antkeep-auto-${at.microsecondsSinceEpoch}.zip',
        ).exists(),
        isFalse,
      );
    },
  );

  test('rejects forged backup paths', () async {
    final entry = LocalBackupEntry('../manual.zip', DateTime(2026), 1);
    await expectLater(
      storage.restore(entry, incremental: false),
      throwsFormatException,
    );
  });
}
