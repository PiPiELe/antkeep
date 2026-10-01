import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('spending includes archived colonies and all DLC, excludes unbought items, and counts prices once', () async {
    final directory = await Directory.systemTemp.createTemp(
      'antkeep-spending-db-',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final repository = AppDatabase.instance;
    await repository.open();
    final db = await openDatabase(await applicationDatabasePath());
    addTearDown(() async {
      await db.close();
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await directory.delete(recursive: true);
    });
    final empty = await repository.loadSpendingSummary();
    expect(empty.totalCents, 0);
    expect(empty.topEntries, isEmpty);
    final date = DateTime(2026, 9, 1);
    for (final entry in {
      'active': 10001,
      'archived': 29,
      'unknown': null,
    }.entries) {
      await repository.saveColony(
        Colony(
          id: entry.key,
          name: entry.key,
          createdAt: date,
          updatedAt: date,
          purchasePriceCents: entry.value,
        ),
      );
    }
    await db.update(
      'colonies',
      {'archived': 1},
      where: 'id = ?',
      whereArgs: ['archived'],
    );
    for (final entry in {
      'paid': 5000,
      'free': 0,
      'unknown': null,
      'unbought': 99999,
    }.entries) {
      await repository.saveInventoryItem(
        InventoryItem(
          id: entry.key,
          name: entry.key,
          purchased: entry.key != 'unbought',
          createdAt: date,
          purchasePriceCents: entry.value,
          quantity: 10,
        ),
      );
    }
    for (final feeder in FeederType.values) {
      await repository.saveFeederRecord(
        FeederRecord(
          id: feeder.name,
          feeder: feeder,
          type: FeederRecordType.observation,
          occurredAt: date,
          createdAt: date,
          purchasePriceCents: 25,
        ),
      );
    }
    var summary = await repository.loadSpendingSummary();
    expect(summary.coloniesCents, 10030);
    expect(summary.inventoryCents, 5000);
    expect(summary.feedersCents, 25 * FeederType.values.length);
    expect(summary.totalCents, 15030 + 25 * FeederType.values.length);
    expect(summary.topEntries.map((entry) => entry.cents), [
      10001,
      5000,
      29,
      25,
      25,
    ]);
    expect(summary.topEntries.map((entry) => entry.name), [
      'active',
      'paid',
      'archived',
      '樱桃蟑螂 · 观察',
      '蛐蛐 · 观察',
    ]);
    expect(summary.topEntries.map((entry) => entry.category), [
      '蚁群',
      '已购物品',
      '蚁群',
      'DLC 养殖',
      'DLC 养殖',
    ]);
    expect(summary.topEntries.last.occurredAt, date);
    await db.update(
      'feeder_records',
      {'purchase_price_cents': 20001},
      where: 'id = ?',
      whereArgs: [FeederType.dubia.name],
    );
    summary = await repository.loadSpendingSummary();
    expect(summary.topEntries.first.name, '杜比亚 · 观察');
    expect(summary.topEntries.first.cents, 20001);
    final paid = (await repository.listInventory()).singleWhere(
      (item) => item.id == 'paid',
    );
    await repository.setInventoryPurchased(paid, false);
    summary = await repository.loadSpendingSummary();
    expect(summary.inventoryCents, 0);
    expect(
      summary.topEntries.map((entry) => entry.name),
      isNot(contains('paid')),
    );

    await db.update('feeder_records', {'purchase_price_cents': null});
    summary = await repository.loadSpendingSummary();
    expect(summary.topEntries.map((entry) => entry.name), [
      'active',
      'archived',
    ]);
    expect(summary.topEntries.map((entry) => entry.cents), [10001, 29]);
  });
}
