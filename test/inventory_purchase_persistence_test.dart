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
    'v11 inventory migrates, checkout rolls back, prices survive restore',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-cart-db-',
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
      final old = await openDatabase(
        path,
        version: 11,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
        purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
        expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
        purchased_at TEXT, expires_at TEXT, quantity INTEGER
      )''');
          for (final table in ['colonies', 'care_records', 'feeder_records']) {
            await db.execute('CREATE TABLE $table (id TEXT PRIMARY KEY)');
          }
          await db.insert('inventory_items', {
            'id': 'old-item',
            'name': '旧物品',
            'purchased': 1,
            'created_at': '2026-09-01T00:00:00.000',
            'purchased_at': '2026-09-02T00:00:00.000',
            'quantity': 7,
          });
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
      final legacy = items.singleWhere((item) => item.id == 'old-item');
      expect(legacy.quantity, 7);
      expect(legacy.purchasePriceCents, isNull);
      expect(legacy.purchasedAt, DateTime(2026, 9, 2));
      final selected = items.where((item) => !item.purchased).take(2).toList();
      final details = {
        selected.first.id: (quantity: 2, purchasePriceCents: 1299),
        selected.last.id: (quantity: null, purchasePriceCents: 0),
      };
      await db.execute(
        '''CREATE TRIGGER fail_checkout BEFORE UPDATE ON inventory_items
      WHEN NEW.id = '${selected.last.id}'
      BEGIN SELECT RAISE(ABORT, 'test checkout failure'); END''',
      );
      await expectLater(
        AppDatabase.instance.purchaseInventoryItems(
          details.keys,
          details: details,
        ),
        throwsA(isA<DatabaseException>()),
      );
      final failed = await AppDatabase.instance.listInventory();
      expect(
        failed
            .where((item) => details.containsKey(item.id))
            .every(
              (item) => !item.purchased && item.purchasePriceCents == null,
            ),
        isTrue,
      );
      await db.execute('DROP TRIGGER fail_checkout');
      await AppDatabase.instance.purchaseInventoryItems(
        details.keys,
        details: details,
      );
      final snapshot = await AppDatabase.instance.snapshot();
      await AppDatabase.instance.replaceAll(snapshot);
      final restored = await AppDatabase.instance.listInventory();
      final priced = restored.singleWhere(
        (item) => item.id == selected.first.id,
      );
      expect(priced.quantity, 2);
      expect(priced.purchasePriceCents, 1299);
      expect(priced.purchasePriceText, '12.99');
      expect(priced.purchased, isTrue);
      final free = restored.singleWhere((item) => item.id == selected.last.id);
      expect(free.purchasePriceCents, 0);
      expect(free.quantity, isNull);
      expect(free.purchasedAt, priced.purchasedAt);
      await AppDatabase.instance.purchaseInventoryItems(details.keys);
      expect(
        (await AppDatabase.instance.listInventory())
            .singleWhere((item) => item.id == priced.id)
            .purchasePriceCents,
        1299,
      );
      final legacyMap = legacy.toMap()..remove('purchase_price_cents');
      expect(InventoryItem.fromMap(legacyMap).purchasePriceCents, isNull);
    },
  );
}
