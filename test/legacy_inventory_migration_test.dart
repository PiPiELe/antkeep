import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'version 4 creates current inventory without adding its columns twice',
    () async {
      final directory = await Directory.systemTemp.createTemp('antkeep-v4-');
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
        version: 4,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE colonies (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, species TEXT, acquired_on TEXT,
          source TEXT, queen_count INTEGER, initial_worker_count INTEGER,
          nest_type TEXT, target_temperature REAL, target_humidity REAL,
          cover_photo_path TEXT, archived INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )''');
          await db.insert('colonies', {
            'id': 'legacy',
            'name': '旧蚁群',
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
      expect(colony.initialEggCount, isNull);
      final nutrition = (await AppDatabase.instance.listInventory())
          .singleWhere((item) => item.name == '营养液');
      expect(nutrition.shelfLifeMonths, 3);
      expect(nutrition.groupName, isNull);
      await AppDatabase.instance.setInventoryPurchased(
        nutrition,
        true,
        quantity: 2,
        purchasePriceCents: 1500,
      );
      final saved = (await AppDatabase.instance.listInventory()).singleWhere(
        (item) => item.id == nutrition.id,
      );
      expect(saved.quantity, 2);
      expect(saved.purchasePriceCents, 1500);
    },
  );
}
