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
    'version 10 preserves colony and DLC data when adding purchase prices',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-price-v10-',
      );
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
        version: 10,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE care_records (
            id TEXT PRIMARY KEY, colony_id TEXT NOT NULL, record_type TEXT NOT NULL,
            occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
            egg_count INTEGER, larva_count INTEGER, pupa_count INTEGER, worker_count INTEGER,
            photos_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL,
            FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE CASCADE
          )''');
          await db.execute('''CREATE TABLE colonies (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, species TEXT, acquired_on TEXT,
          source TEXT, queen_count INTEGER, initial_worker_count INTEGER,
          specialized_count INTEGER, show_specialized INTEGER NOT NULL DEFAULT 0,
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
          await db.execute('''CREATE TABLE feeder_records (
            id TEXT PRIMARY KEY, feeder_type TEXT NOT NULL, record_type TEXT NOT NULL,
            occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
            juvenile_count INTEGER, adult_count INTEGER, mortality_count INTEGER,
            created_at TEXT NOT NULL
          )''');
          await db.insert('feeder_records', {
            'id': 'legacy-feeder',
            'feeder_type': 'dubia',
            'record_type': 'observation',
            'occurred_at': '2026-09-01T00:00:00.000',
            'created_at': '2026-09-01T00:00:00.000',
            'adult_count': 20,
            'note': '原记录',
          });
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
      expect(colony.purchasePriceCents, isNull);
      final feeder = (await AppDatabase.instance.listFeederRecords(
        FeederType.dubia,
      )).single;
      expect(feeder.purchasePriceCents, isNull);
      expect(feeder.adultCount, 20);
      expect(feeder.note, '原记录');
      await AppDatabase.instance.saveColony(
        Colony.fromMap({...colony.toMap(), 'purchase_price_cents': 2999}),
      );
      expect(
        (await AppDatabase.instance.findColony('legacy'))!.purchasePriceCents,
        2999,
      );
      await AppDatabase.instance.saveFeederRecord(
        FeederRecord.fromMap({
          ...feeder.toMap(),
          'id': 'priced',
          'purchase_price_cents': 0,
        }),
      );
      final records = await AppDatabase.instance.listFeederRecords(
        FeederType.dubia,
      );
      expect(
        records.singleWhere((r) => r.id == 'priced').purchasePriceCents,
        0,
      );
      expect(
        records.singleWhere((r) => r.id == 'legacy-feeder').purchasePriceCents,
        isNull,
      );
    },
  );
}
