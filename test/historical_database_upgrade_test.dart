import 'dart:convert';
import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/backup_service.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/models.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only access to capture production callbacks; no runtime dependency.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/factory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Capture the production open callbacks without exposing migration-only APIs.
class _OpenOptionsFactory implements SqfliteDatabaseFactory {
  late OpenDatabaseOptions options;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    this.options = options!;
    return databaseFactoryFfi.openDatabase(path, options: options);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = jsonDecode(
    File('test/fixtures/historical_schemas.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final versions = fixtures['versions'] as Map<String, dynamic>;
  final factory = _OpenOptionsFactory();
  final app = AppDatabase.instance;
  final media = LocalMediaStore.instance;
  late Directory root;
  final date = DateTime(2040, 1, 1);
  const photos = {
    'cover.jpg': <int>[1, 2, 3],
    'diary.jpg': <int>[4, 5, 6],
  };

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('antkeep-upgrade-history-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    sqfliteFfiInit();
    databaseFactory = factory;
    await app.open();
    databaseFactory = databaseFactoryFfi;
    await media.initialize();
    await media.restoreFiles(photos);
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await root.delete(recursive: true);
  });

  Future<Map<String, List<Map<String, Object?>>>> readTables(
    Database db,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    return {
      for (final table in tables)
        table['name']! as String: await db.query(table['name']! as String),
    };
  }

  Future<Map<String, List<Map<String, Object?>>>> createLegacy(
    String path,
    int version,
  ) async {
    final statements = versions['$version']['statements'] as List;
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final key in statements) {
            await db.execute(fixtures['statements'][key] as String);
          }
          final tables = await readTables(db);
          final seeds = <String, List<Map<String, Object?>>>{
            'colonies': [
              for (final archived in [false, true])
                Colony(
                  id: archived ? 'archived' : 'active',
                  name: '历史蚁群',
                  species: '收获蚁',
                  acquiredOn: date,
                  source: '旧来源',
                  queenCount: 1,
                  initialWorkerCount: 20,
                  initialEggCount: 0,
                  initialLarvaCount: null,
                  initialCocoonCount: 5,
                  specializedCount: 0,
                  showSpecialized: true,
                  purchasePriceCents: 1999,
                  coverPhotoPath: 'cover.jpg',
                  archived: archived,
                  createdAt: date,
                  updatedAt: date,
                  growth: ColonyGrowth(
                    frequency: GrowthFrequency.daily,
                    path: GrowthPath.eggToWorker,
                    startedAt: date,
                    workers: 1,
                  ),
                ).toMap(),
            ],
            'care_records': [
              for (final id in ['active', 'archived'])
                CareRecord(
                  id: 'record-$id',
                  colonyId: id,
                  type: CareRecordType.observation,
                  occurredAt: date,
                  createdAt: date,
                  eggCount: 0,
                  larvaCount: 8,
                  pupaCount: null,
                  workerCount: 20,
                  workerMortalityCount: 0,
                  temperature: 26.5,
                  humidity: 60,
                  note: '历史日记',
                  photos: ['diary.jpg'],
                ).toMap(),
            ],
            'inventory_items': [
              InventoryItem(
                id: 'custom',
                name: '自定义物品',
                purchased: true,
                createdAt: date,
                quantity: 0,
                purchasePriceCents: 850,
                expiryType: InventoryExpiryType.shelfLife,
                shelfLifeMonths: 3,
                purchasedAt: date,
              ).toMap(),
              InventoryItem(
                id: 'default-0',
                name: '防逃液',
                purchased: true,
                createdAt: date,
                quantity: 2,
                purchasePriceCents: 0,
              ).toMap(),
            ],
            'feeder_records': [
              FeederRecord(
                id: 'feeder',
                feeder: FeederType.dubia,
                type: FeederRecordType.observation,
                occurredAt: date,
                createdAt: date,
                juvenileCount: 0,
                adultCount: 10,
                mortalityCount: null,
                purchasePriceCents: 500,
                note: '旧饲料记录',
              ).toMap(),
            ],
            'app_settings': [
              {'setting_key': 'themeMode', 'setting_value': 'dark'},
              {'setting_key': 'custom-history', 'setting_value': '历史设置'},
            ],
          };
          for (final table in tables.keys) {
            final columns = (await db.rawQuery('PRAGMA table_info($table)'))
                .map((row) => row['name'])
                .toSet();
            for (final row in seeds[table]!) {
              await db.insert(
                table,
                Map.of(row)..removeWhere((key, _) => !columns.contains(key)),
              );
            }
          }
        },
      ),
    );
    final before = await readTables(old);
    await old.close();
    return before;
  }

  for (final version in versions.keys.map(int.parse)) {
    test(
      'v$version upgrade and reopen retain every historical field and photo',
      () async {
        final path = '${root.path}/v$version.sqlite';
        final before = await createLegacy(path, version);
        final upgraded = await databaseFactoryFfi.openDatabase(
          path,
          options: factory.options,
        );
        expect(await upgraded.getVersion(), 20);
        expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await upgraded.rawQuery('PRAGMA integrity_check'))
              .single
              .values
              .single,
          'ok',
        );
        await upgraded.close();
        final reopened = await databaseFactoryFfi.openDatabase(
          path,
          options: factory.options,
        );
        final after = await readTables(reopened);
        for (final entry in before.entries) {
          // New nullable columns may be added; no existing value may be lost.
          final oldColumns = entry.value.first.keys.toSet();
          expect(
            [
              for (final row in after[entry.key]!)
                Map.of(row)..removeWhere((key, _) => !oldColumns.contains(key)),
            ],
            entry.value,
            reason: 'v$version ${entry.key}',
          );
        }
        expect(after['memorials'], isEmpty);
        if (version < 17) {
          expect(
            after['care_records']!.map((r) => r['worker_mortality_count']),
            everyElement(isNull),
          );
        }
        if (version < 16) {
          expect(
            after['colonies']!.map((r) => r['initial_larva_count']),
            everyElement(isNull),
          );
        }
        if (version >= 15) {
          expect(
            Colony.fromMap(after['colonies']!.first).developmentPath,
            GrowthPath.eggToWorker,
          );
        }
        final snapshot = Map<String, dynamic>.from(after)
          ..remove('app_settings');
        BackupData.validate(snapshot);
        await app.replaceAll(snapshot);
        final service = BackupService(app, media);
        final zip = await service.createBackupBytes();
        await service.restoreBytes(zip);
        expect(await app.snapshot(), snapshot);
        expect(await media.readFiles(photos.keys), photos);
        // A format-1 backup carries the original columns, without migrations.
        final legacyData = Map<String, dynamic>.from(before)
          ..remove('app_settings');
        final manifest = utf8.encode(
          jsonEncode({
            'format': 'antkeep',
            'version': 1,
            'data': legacyData,
            'media': photos.keys.toList(),
          }),
        );
        final archive = Archive()
          ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
        for (final photo in photos.entries) {
          archive.addFile(
            ArchiveFile('media/${photo.key}', photo.value.length, photo.value),
          );
        }
        await service.restoreBytes(
          Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
        );
        final restored = await app.snapshot();
        for (final entry in legacyData.entries) {
          final rows = entry.value as List<Map<String, Object?>>;
          final columns = rows.first.keys.toSet();
          expect(
            [
              for (final row in restored[entry.key] as List)
                Map<String, Object?>.from(row as Map)
                  ..removeWhere((key, _) => !columns.contains(key)),
            ],
            rows,
            reason: 'legacy ZIP v$version ${entry.key}',
          );
        }
        expect(await media.readFiles(photos.keys), photos);
        expect(await readTables(reopened), after);
        await reopened.close();
      },
    );
  }

  test(
    'failed upgrade rolls back schema, version and every historical row',
    () async {
      final path = '${root.path}/failed-v10.sqlite';
      final before = await createLegacy(path, 10);
      await expectLater(
        databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: factory.options.version,
            onConfigure: factory.options.onConfigure,
            onUpgrade: (db, oldVersion, newVersion) async {
              await factory.options.onUpgrade!(db, oldVersion, newVersion);
              throw StateError('Simulated interruption before commit');
            },
          ),
        ),
        throwsA(anything),
      );
      final reopened = await databaseFactoryFfi.openDatabase(path);
      expect(await reopened.getVersion(), 10);
      expect(await readTables(reopened), before);
      await reopened.close();
      // Retry the real upgrade using the untouched original data.
      final retry = await databaseFactoryFfi.openDatabase(
        path,
        options: factory.options,
      );
      expect(await retry.getVersion(), 20);
      expect((await retry.query('care_records')).length, 2);
      await retry.close();
    },
  );
}
