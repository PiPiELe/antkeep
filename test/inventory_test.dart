import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rows = <Map<String, Object?>>[];
  final migrations = <String>[];
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-inventory-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (call) async {
        final args = call.arguments as Map;
        switch (call.method) {
          case 'openDatabase':
            return {'id': 1};
          case 'execute':
            migrations.add(args['sql'] as String);
            return null;
          case 'batch':
            for (final operation in args['operations'] as List) {
              final sql = operation['sql'] as String;
              final columns = sql
                  .substring(sql.indexOf('(') + 1, sql.indexOf(')'))
                  .split(',')
                  .map((column) => column.trim())
                  .toList();
              final values = operation['arguments'] as List;
              final placeholders = sql
                  .substring(sql.lastIndexOf('(') + 1, sql.lastIndexOf(')'))
                  .split(',');
              var valueIndex = 0;
              rows.add({
                for (var i = 0; i < columns.length; i++)
                  columns[i]: placeholders[i].trim() == '?'
                      ? values[valueIndex++]
                      : null,
              });
            }
            return null;
          case 'query':
            final sql = args['sql'] as String;
            if (sql == 'PRAGMA user_version') {
              return [
                {'user_version': 8},
              ];
            }
            if (sql.contains('inventory_items')) return rows;
            return <Map<String, Object?>>[];
          case 'update':
            final values = args['arguments'] as List;
            final sql = args['sql'] as String;
            final assignments = sql
                .split(' SET ')[1]
                .split(' WHERE ')[0]
                .split(',');
            final ids = values.skip(
              assignments
                  .where((assignment) => assignment.contains('?'))
                  .length,
            );
            final matching = rows
                .where(
                  (row) =>
                      ids.contains(row['id']) &&
                      (!sql.contains('purchased = 0') || row['purchased'] == 0),
                )
                .toList();
            for (final row in matching) {
              var valueIndex = 0;
              for (final assignment in assignments) {
                final parts = assignment.split('=');
                row[parts.first.trim()] = parts.last.trim() == '?'
                    ? values[valueIndex++]
                    : null;
              }
            }
            return matching.length;
          default:
            throw UnsupportedError(call.method);
        }
      },
    );
    databaseFactory = databaseFactorySqflitePlugin;
    await AppDatabase.instance.open();
  });

  tearDownAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      null,
    );
    await directory.delete(recursive: true);
  });

  test('version 8 upgrades and all requested defaults are seeded', () async {
    expect(
      migrations,
      contains(
        'ALTER TABLE inventory_items ADD COLUMN quantity INTEGER CHECK (quantity >= 0)',
      ),
    );
    expect(
      migrations,
      contains(
        'ALTER TABLE inventory_items ADD COLUMN purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0)',
      ),
    );
    final items = await AppDatabase.instance.listInventory();
    expect(
      items.map((item) => item.name),
      containsAll([
        '试管 15cm',
        '试管 18cm',
        '试管 20cm',
        '白菜巢',
        '堵水海绵',
        '蚂蚁吸尘器',
        '脱脂棉球',
        '恒温箱',
        'EPP 泡沫箱',
        '尖头画笔（勾线笔）',
        '图钉吸铁石',
        '平头注射器',
        '小剪刀',
        'LED 小灯',
        '平头画笔',
        '营养果冻',
        '蚂蚁喂水器',
        '10mm 软管',
        '滴管',
        '手工玻璃纸',
        '铝制喂食盘',
        '个性喂食盘',
      ]),
    );
    expect(items.first.quantity, isNull);
    expect(
      items.singleWhere((item) => item.id == 'default-28').purpose,
      '蚂蚁平稳换巢',
    );
    expect(items.where((item) => item.name == '防逃液'), hasLength(1));
    expect(items.where((item) => item.name == '棉花团'), isEmpty);
    final jelly = items.singleWhere((item) => item.name == '营养果冻');
    expect(jelly.expiryType, InventoryExpiryType.shelfLife);
    expect(jelly.shelfLifeMonths, 3);
    expect(
      items
          .where((item) => item.groupLabel == '喂食盘')
          .map((item) => item.childLabel),
      unorderedEquals(['铝制喂食盘', '个性喂食盘']),
    );
  });
}
