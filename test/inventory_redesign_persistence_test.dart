import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = AppDatabase.instance;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('inventory-redesign-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  InventoryBatch batch(
    String id, {
    int? quantity = 2,
    int? cost = 1250,
    DateTime? expiry,
  }) => InventoryBatch(
    id: id,
    quantity: quantity,
    costCents: cost,
    acquiredAt: DateTime(2026, 10, 18),
    expiresAt: expiry,
  );

  test('batches persist independently; aggregate cost, unknown quantity and backup remain compatible', () async {
    final item = (await db.listInventory()).singleWhere((i) => i.name == '营养液');
    await db.saveInventoryBatch(
      item.id,
      batch('a', expiry: DateTime(2026, 10, 20)),
    );
    await db.saveInventoryBatch(
      item.id,
      batch('b', quantity: 4, cost: 1900, expiry: DateTime(2026, 11, 20)),
    );
    var saved = (await db.listInventory()).singleWhere((i) => i.id == item.id);
    expect(saved.quantity, 6);
    expect(saved.purchasePriceCents, 3150);
    expect(saved.records.map((r) => r.expiresAt), [
      DateTime(2026, 10, 20),
      DateTime(2026, 11, 20),
    ]);
    expect((await db.loadSpendingSummary()).inventoryCents, 3150);
    await db.saveInventoryBatch(
      item.id,
      batch('a', quantity: 0, expiry: DateTime(2026, 10, 20)),
    );
    saved = (await db.listInventory()).singleWhere((i) => i.id == item.id);
    expect(saved.effectiveExpiryDate(), DateTime(2026, 11, 20));
    expect(saved.purchasePriceCents, 3150);
    final snapshot = await db.snapshot();
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    await db.close();
    await db.open();
    expect(
      (await db.listInventory()).singleWhere((i) => i.id == item.id).records,
      hasLength(2),
    );
    await db.deleteInventoryBatch(item.id, 'a');
    saved = (await db.listInventory()).singleWhere((i) => i.id == item.id);
    expect(saved.quantity, 4);
    expect(saved.purchasePriceCents, 1900);
    await db.saveInventoryBatch(
      item.id,
      batch('unknown', quantity: null, cost: null),
    );
    expect(
      (await db.listInventory()).singleWhere((i) => i.id == item.id).quantity,
      isNull,
    );
    await db.deleteInventoryBatch(item.id, 'b');
    await db.deleteInventoryBatch(item.id, 'unknown');
    saved = (await db.listInventory()).singleWhere((i) => i.id == item.id);
    expect(saved.purchased, false);
    expect(saved.allowsExpiry, true);
  });

  test('catalog edits preserve legacy records and adding specs does not acquire them', () async {
    final item = (await db.listInventory()).singleWhere((i) => i.name == '营养液');
    await db.setInventoryPurchased(
      item,
      true,
      quantity: 3,
      purchasePriceCents: 500,
    );
    final legacy = (await db.listInventory()).singleWhere(
      (i) => i.id == item.id,
    );
    final expiry = legacy.effectiveExpiryDate();
    final edited = InventoryItem.fromMap({
      ...legacy.toMap(),
      'supports_expiry': 0,
      'purpose': '养蚁补给',
      'category': '喂食',
    });
    await db.saveInventoryCatalog([edited]);
    var saved = (await db.listInventory()).singleWhere((i) => i.id == item.id);
    expect(saved.records.single.expiresAt, expiry);
    expect(saved.allowsExpiry, false);
    final spec = InventoryItem(
      id: 'new-spec',
      name: '100ml',
      groupName: '营养液',
      purchased: false,
      createdAt: DateTime.now(),
      category: '喂食',
    );
    await db.saveInventoryCatalog([spec]);
    saved = (await db.listInventory()).singleWhere((i) => i.id == spec.id);
    expect(saved.records, isEmpty);
    await db.saveInventoryBatch(spec.id, batch('spec-batch'));
    await expectLater(db.deleteInventorySpec(spec.id), throwsStateError);
    expect(
      (await db.listInventory())
          .singleWhere((i) => i.id == item.id)
          .records
          .single
          .quantity,
      3,
    );
  });

  test('catalog duplicate failure rolls back all edits', () async {
    final items = await db.listInventory();
    final a = items.firstWhere((i) => i.groupLabel == null);
    final b = items.firstWhere((i) => i.groupLabel == null && i.id != a.id);
    await expectLater(
      db.saveInventoryCatalog([
        InventoryItem.fromMap({...a.toMap(), 'purpose': '不能落库'}),
        InventoryItem.fromMap({...b.toMap(), 'name': a.name}),
      ]),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      (await db.listInventory()).singleWhere((i) => i.id == a.id).purpose,
      a.purpose,
    );
  });

  test('version 33 upgrades existing records and deleted bundled specs stay deleted', () async {
    final item = (await db.listInventory()).singleWhere((i) => i.name == '营养液');
    await db.setInventoryPurchased(
      item,
      true,
      quantity: 8,
      purchasePriceCents: 2300,
    );
    await db.close();
    final old = await openDatabase(await applicationDatabasePath());
    for (final column in [
      'category',
      'icon_key',
      'supports_expiry',
      'spec_note',
      'batches_json',
      'hidden',
    ]) {
      await old.execute('ALTER TABLE inventory_items DROP COLUMN $column');
    }
    await old.execute('ALTER TABLE care_records DROP COLUMN feeding_category');
    for (final column in ['last_fed_at', 'removal_hours', 'removal_due_at']) {
      await old.execute('ALTER TABLE care_tasks DROP COLUMN $column');
    }
    await old.execute('PRAGMA user_version = 33');
    await old.close();
    await db.open();
    final upgraded = (await db.listInventory()).singleWhere(
      (i) => i.id == item.id,
    );
    expect(upgraded.records.single.quantity, 8);
    expect(upgraded.records.single.costCents, 2300);
    expect(upgraded.records.single.expiresAt, isNotNull);
    final spec = (await db.listInventory()).firstWhere(
      (i) => i.groupLabel == '试管',
    );
    await db.deleteInventorySpec(spec.id);
    await db.close();
    await db.open();
    expect((await db.listInventory()).any((i) => i.id == spec.id), false);
    final snapshot = await db.snapshot();
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    await db.close();
    await db.open();
    expect((await db.listInventory()).any((i) => i.id == spec.id), false);
  });

  test('expiry is date-only, excludes unknown dates and depleted batches', () {
    final now = DateTime(2026, 10, 18, 23, 59);
    expect(batch('a', expiry: DateTime(2026, 10, 18)).isExpired(now), false);
    expect(batch('b', expiry: DateTime(2026, 10, 25)).isExpiring(now), true);
    expect(batch('c', expiry: DateTime(2026, 10, 26)).isExpiring(now), false);
    expect(batch('d').isExpired(now), false);
    expect(
      batch('e', quantity: 0, expiry: DateTime(2026, 10, 17)).isExpired(now),
      false,
    );
    expect(batch('f', expiry: DateTime(2026, 10, 17)).isExpired(now), true);
    expect(inventoryMatches('泡箱', ['EPP 泡沫箱']), true);
    expect(inventoryMatches('试20', ['试管', '20cm']), false);
  });
}
