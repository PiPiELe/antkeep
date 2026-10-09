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
    'refreshing defaults preserves existing purchases and custom items',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-defaults-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final path = await applicationDatabasePath();
      final cotton = InventoryItem(
        id: 'default-17',
        name: '棉花团',
        purchased: true,
        createdAt: DateTime(2026, 8, 1),
        purchasedAt: DateTime(2026, 8, 2),
        quantity: 12,
        purchasePriceCents: 800,
        expiryType: InventoryExpiryType.fixedDate,
        expiresAt: DateTime(2027, 8, 2),
      );
      final custom = InventoryItem(
        id: 'custom-cotton',
        name: '棉花团',
        groupName: '自定义耗材',
        purchased: true,
        createdAt: DateTime(2026, 8, 3),
        quantity: 5,
      );
      final old = await openDatabase(
        path,
        version: 17,
        onCreate: (db, _) async {
          // Version 20 adds a column to this pre-existing diary table.
          await db.execute('CREATE TABLE care_records (id TEXT PRIMARY KEY)');
          await db.execute('''CREATE TABLE inventory_items (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, group_name TEXT,
          purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
          expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
          purchased_at TEXT, expires_at TEXT, quantity INTEGER,
          purchase_price_cents INTEGER
        )''');
          await db.execute('''CREATE UNIQUE INDEX inventory_name_in_group
          ON inventory_items(COALESCE(group_name, ''), name)''');
          await db.insert('inventory_items', cotton.toMap());
          await db.insert('inventory_items', custom.toMap());
        },
      );
      await old.close();
      await AppDatabase.instance.open();
      final db = await openDatabase(path);
      addTearDown(() async {
        await db.close();
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        await directory.delete(recursive: true);
      });

      final items = await AppDatabase.instance.listInventory();
      expect(
        items.singleWhere((item) => item.id == cotton.id).toMap(),
        cotton.toMap()..['name'] = '脱脂棉球',
      );
      expect(
        items.singleWhere((item) => item.id == custom.id).toMap(),
        custom.toMap(),
      );
      expect(items.where((item) => item.name == '防逃液'), hasLength(1));
      expect(items.singleWhere((item) => item.id == 'default-18').name, '恒温箱');
      expect(
        items.singleWhere((item) => item.id == 'default-19').name,
        'EPP 泡沫箱',
      );
      final trays = items.where((item) => item.groupName == '喂食盘').toList();
      expect(
        trays.map((item) => item.name),
        unorderedEquals(['铝制喂食盘', '个性喂食盘']),
      );
      await AppDatabase.instance.purchaseInventoryItems([trays.first.id]);
      final purchased = await AppDatabase.instance.listInventory();
      expect(
        purchased.singleWhere((item) => item.id == trays.first.id).purchased,
        isTrue,
      );
      expect(
        purchased.singleWhere((item) => item.id == trays.last.id).purchased,
        isFalse,
      );
      final jelly = items.singleWhere((item) => item.name == '营养果冻');
      await db.update(
        'inventory_items',
        {
          'purchased': 1,
          'purchased_at': DateTime(2026, 1, 31).toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [jelly.id],
      );
      expect(
        (await AppDatabase.instance.listInventory())
            .singleWhere((item) => item.id == jelly.id)
            .effectiveExpiryDate(),
        DateTime(2026, 4, 30),
      );
    },
  );
}
