import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'version 9 colonies retain data and default to hidden specialized counts',
    () async {
      final directory = await Directory.systemTemp.createTemp('antkeep-v9-');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        await directory.delete(recursive: true);
      });
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final old = await openDatabase(
        await applicationDatabasePath(),
        version: 9,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE colonies (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, species TEXT, acquired_on TEXT,
          source TEXT, queen_count INTEGER, initial_worker_count INTEGER,
          initial_egg_count INTEGER, initial_cocoon_count INTEGER,
          nest_type TEXT, target_temperature REAL, target_humidity REAL, cover_photo_path TEXT,
          archived INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )''');
          await db.execute('''CREATE TABLE inventory_items (
          id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
          purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
          expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
          purchased_at TEXT, expires_at TEXT, quantity INTEGER
        )''');
          await db.insert('colonies', {
            'id': 'legacy',
            'name': '旧蚁群',
            'queen_count': 1,
            'initial_worker_count': 20,
            'created_at': '2026-09-01T00:00:00.000',
            'updated_at': '2026-09-01T00:00:00.000',
          });
        },
      );
      await old.close();
      await AppDatabase.instance.open();
      final colony = (await AppDatabase.instance.findColony('legacy'))!;
      expect(colony.name, '旧蚁群');
      expect(colony.initialWorkerCount, 20);
      expect(colony.showSpecialized, isFalse);
      expect(colony.specializedCount, isNull);
      await AppDatabase.instance.saveColony(
        Colony.fromMap({
          ...colony.toMap(),
          'show_specialized': 1,
          'specialized_count': 0,
        }),
      );
      final updated = (await AppDatabase.instance.findColony('legacy'))!;
      expect(updated.showSpecialized, isTrue);
      expect(updated.specializedCount, 0);
    },
  );
}
