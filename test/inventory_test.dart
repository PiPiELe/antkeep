import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
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
        '棉花团',
        '恒温箱',
        'EPP 泡沫箱',
      ]),
    );
    expect(items.first.quantity, isNull);
  });

  testWidgets(
    'grouped sizes can be purchased, edited, cancelled and returned to recommendations',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: InventoryPage()));
      await tester.pumpAndSettle();
      expect(find.text('离心管'), findsOneWidget);
      expect(find.text('离心管 50ml'), findsNothing);
      await tester.tap(find.text('离心管'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('离心管 50ml'));
      await tester.tap(find.text('离心管 50ml'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '-2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入非负整数'), findsWidgets);
      expect(
        rows.singleWhere((row) => row['name'] == '离心管 50ml')['purchased'],
        0,
      );
      await tester.enterText(find.byType(TextFormField), '12');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('离心管 · 已购入'));
      await tester.tap(find.text('离心管 · 已购入'));
      await tester.pumpAndSettle();
      expect(find.text('离心管 50ml'), findsOneWidget);
      expect(find.text('已购入'), findsOneWidget);
      expect(find.text('数量：12'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('离心管 · 已购入')).dy,
        greaterThan(tester.getTopLeft(find.text('离心管')).dy),
      );
      await tester.tap(find.text('已购 (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('离心管 · 已购入'));
      await tester.pumpAndSettle();
      expect(find.text('数量：12'), findsOneWidget);
      final purchasedAt = rows.singleWhere(
        (row) => row['name'] == '离心管 50ml',
      )['purchased_at'];
      await tester.tap(find.text('离心管 50ml'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '8');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('数量：8'), findsOneWidget);
      expect(
        rows.singleWhere((row) => row['name'] == '离心管 50ml')['purchased_at'],
        purchasedAt,
      );
      final snapshot = await AppDatabase.instance.snapshot();
      final saved = (snapshot['inventory_items'] as List)
          .cast<Map<String, Object?>>();
      expect(
        InventoryItem.fromMap(
          saved.singleWhere((row) => row['name'] == '离心管 50ml'),
        ).toMap()['quantity'],
        8,
      );
      await tester.tap(find.text('离心管 50ml'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '99');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('数量：8'), findsOneWidget);
      await tester.tap(find.text('离心管 50ml'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('还没有已购的物品。'), findsOneWidget);
      final row = rows.singleWhere((row) => row['name'] == '离心管 50ml');
      expect(row['quantity'], isNull);
      expect(row['purchased_at'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('batch purchase selects sizes, cancels and saves once', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: InventoryPage()));
    await tester.pumpAndSettle();
    final before = rows.map((row) => Map<String, Object?>.from(row)).toList();
    await tester.tap(find.text('批量购入'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认购入 (0)'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('确认购入 (${rows.length})'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('确认购入 (0)'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rows, before);

    await tester.tap(find.text('批量购入'));
    await tester.pumpAndSettle();
    for (final name in ['离心管 50ml', 'EPP 泡沫箱']) {
      final checkbox = find.widgetWithText(CheckboxListTile, name);
      await tester.scrollUntilVisible(
        checkbox,
        150,
        scrollable: find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('确认购入 (2)'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final purchased = rows.where((row) => row['purchased'] == 1).toList();
    expect(
      purchased.map((row) => row['name']),
      unorderedEquals(['离心管 50ml', 'EPP 泡沫箱']),
    );
    expect(
      purchased.every(
        (row) => row['purchased_at'] != null && row['quantity'] == null,
      ),
      isTrue,
    );
    expect(purchased.map((row) => row['purchased_at']).toSet(), hasLength(1));
    expect(find.text('已购 (2)'), findsOneWidget);
    await tester.tap(find.text('批量购入'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'EPP 泡沫箱'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, '离心管 50ml'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final item = InventoryItem.fromMap(purchased.first);
    await AppDatabase.instance.setInventoryPurchased(item, true, quantity: 7);
    final existing = Map<String, Object?>.from(purchased.first);
    await AppDatabase.instance.purchaseInventoryItems([item.id]);
    expect(purchased.first, existing);
  });
}
