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
    'version 12 preserves existing inventory while adding group names',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-groups-v12-',
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
      final legacy = InventoryItem(
        id: 'legacy',
        name: '干巢',
        purchased: true,
        createdAt: DateTime(2026, 9, 1),
        quantity: 2,
        purchasePriceCents: 500,
        expiryType: InventoryExpiryType.shelfLife,
        shelfLifeMonths: 3,
        purchasedAt: DateTime(2026, 9, 2),
      );
      final old = await openDatabase(
        await applicationDatabasePath(),
        version: 12,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
        purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
        expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
        purchased_at TEXT, expires_at TEXT, quantity INTEGER,
        purchase_price_cents INTEGER
      )''');
          await db.insert(
            'inventory_items',
            legacy.toMap()..remove('group_name'),
          );
        },
      );
      await old.close();
      await AppDatabase.instance.open();
      final restored = (await AppDatabase.instance.listInventory()).singleWhere(
        (item) => item.id == 'legacy',
      );
      expect(restored.toMap(), legacy.toMap());
      await AppDatabase.instance.saveInventoryGroup([
        InventoryItem(
          id: 'group-dry',
          name: '干巢',
          groupName: '5 元蚁巢',
          purchased: false,
          createdAt: DateTime(2026, 9, 29),
        ),
      ]);
      expect(
        (await AppDatabase.instance.listInventory()).where(
          (item) => item.name == '干巢',
        ),
        hasLength(2),
      );
    },
  );
}
