import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'groups persist, purchase independently, restore and save atomically',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-groups-',
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
      final db = AppDatabase.instance;
      await db.open();
      InventoryItem item(String id, String name, {String? group = '5 元蚁巢'}) =>
          InventoryItem(
            id: id,
            name: name,
            groupName: group,
            purchased: false,
            createdAt: DateTime(2026, 9, 29),
            expiryType: InventoryExpiryType.shelfLife,
            shelfLifeMonths: 3,
          );
      await db.saveInventoryGroup([
        item('dry', '干巢'),
        item('wet', '湿巢'),
        item('area', '中活动区'),
      ]);
      await db.saveInventoryGroup([item('other-dry', '干巢', group: '另一款蚁巢')]);
      await db.saveInventoryItem(item('standalone', '干巢', group: null));
      await db.purchaseInventoryItems(
        ['dry'],
        details: {'dry': (quantity: 2, purchasePriceCents: 500)},
      );
      final items = await db.listInventory();
      final dry = items.singleWhere((item) => item.id == 'dry');
      expect(dry.groupName, '5 元蚁巢');
      expect(dry.fullName, '5 元蚁巢 · 干巢');
      expect(dry.quantity, 2);
      expect(dry.purchasePriceCents, 500);
      expect(dry.effectiveExpiryDate(), isNotNull);
      expect(items.singleWhere((item) => item.id == 'wet').purchased, isFalse);
      final snapshot = await db.snapshot();
      await db.replaceAll(snapshot);
      expect(
        (await db.listInventory())
            .singleWhere((item) => item.id == 'dry')
            .toMap(),
        dry.toMap(),
      );
      await expectLater(
        db.saveInventoryGroup([item('new', '连接管'), item('duplicate', '干巢')]),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.listInventory()).any((item) => item.id == 'new'),
        isFalse,
      );
      // Old backups contain no group metadata and remain readable.
      final oldSnapshot = await db.snapshot();
      oldSnapshot['inventory_items'] = [
        item('legacy', '旧物品', group: null).toMap()..remove('group_name'),
      ];
      await db.replaceAll(oldSnapshot);
      expect((await db.listInventory()).single.groupName, isNull);
    },
  );
}
