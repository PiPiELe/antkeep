import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'version 31 inventory gains purpose without losing purchase data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-purpose-v31-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      addTearDown(() async {
        await AppDatabase.instance.close();
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        await directory.delete(recursive: true);
      });
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final path = await applicationDatabasePath();
      final old = await openDatabase(
        path,
        version: 31,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE milestones (id TEXT PRIMARY KEY)');
          await db.execute('''CREATE TABLE inventory_items (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, group_name TEXT,
          purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
          expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
          purchased_at TEXT, expires_at TEXT, quantity INTEGER,
          purchase_price_cents INTEGER
        )''');
          await db.insert('inventory_items', {
            'id': 'custom',
            'name': '自定义物品',
            'purchased': 1,
            'created_at': '2026-10-01T10:00:00.000',
            'purchased_at': '2026-10-02T10:00:00.000',
            'quantity': 3,
            'purchase_price_cents': 1250,
          });
        },
      );
      await old.close();

      await AppDatabase.instance.open();
      final item = (await AppDatabase.instance.listInventory()).singleWhere(
        (item) => item.id == 'custom',
      );
      expect(item.purpose, isNull);
      expect(item.quantity, 3);
      expect(item.purchasePriceCents, 1250);
      final purchasedAt = item.purchasedAt;
      await AppDatabase.instance.setInventoryPurchased(
        item,
        true,
        quantity: 3,
        purchasePriceCents: 1250,
        purpose: '临时保温',
        updatePurpose: true,
      );
      await AppDatabase.instance.close();
      await AppDatabase.instance.open();
      final restored = (await AppDatabase.instance.listInventory()).singleWhere(
        (item) => item.id == 'custom',
      );
      expect(restored.purpose, '临时保温');
      expect(restored.purchasedAt, purchasedAt);
      expect(restored.quantity, 3);
    },
  );
}
