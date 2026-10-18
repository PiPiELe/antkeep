import 'dart:io';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/inventory_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = AppDatabase.instance;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('inventory-ui-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
    final snapshot = await db.snapshot();
    snapshot['inventory_items'] = [
      InventoryItem(
        id: 'box',
        name: 'EPP 泡沫箱',
        purpose: '运输与保温',
        category: '环境',
        purchased: false,
        createdAt: DateTime.now(),
      ).toMap(),
      InventoryItem(
        id: 'food',
        name: '营养液',
        category: '喂食',
        supportsExpiry: true,
        purchased: false,
        createdAt: DateTime.now(),
      ).toMap(),
    ];
    await db.replaceAll(snapshot);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    double width = 393,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: antKeepTheme(ThemeColor.mistBlue, dark: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const InventoryPage(),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await Scrollable.ensureVisible(
      tester.element(find.text(label).last),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  Future<void> enter(WidgetTester tester, String hint, String value) async {
    final finder = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );
    await tester.enterText(finder, value);
    await settle(tester);
  }

  testWidgets(
    'no-spec card can add and edit specs without acquiring, and still acquire directly',
    (tester) async {
      await open(tester);
      await tap(tester, 'EPP 泡沫箱');
      expect(find.text('还没有设置规格'), findsOneWidget);
      await tap(tester, '添加规格');
      await enter(tester, '例如：20cm、30cm、加厚型', '20cm');
      await tap(tester, '保存规格');
      expect(find.text('20cm'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await settle(tester);
      expect(find.text('筛选').hitTestable(), findsOneWidget);
      var items = (await tester.runAsync(db.listInventory))!;
      expect(items.every((i) => i.records.isEmpty), true);
      await tap(tester, '不区分规格，直接记录入手');
      expect(find.text('设置有效期（可选）'), findsNothing);
      await tap(tester, '保存记录');
      items = (await tester.runAsync(db.listInventory))!;
      expect(
        items.singleWhere((i) => i.id == 'box').records.single.quantity,
        1,
      );
      expect(
        items.singleWhere((i) => i.groupLabel == 'EPP 泡沫箱').records,
        isEmpty,
      );
      await tap(tester, '已入手 (1)');
      expect(find.text('数量 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'optional expiry is per acquisition and repeated acquisition creates separate records',
    (tester) async {
      await open(tester);
      await tap(tester, '营养液');
      await tap(tester, '直接记录入手');
      expect(find.text('设置有效期（可选）'), findsOneWidget);
      expect(find.text('有效期至 *'), findsNothing);
      await tap(tester, '保存记录');
      await tap(tester, '直接记录入手');
      await tester.tap(find.byType(Switch));
      await settle(tester);
      await tap(tester, '保存记录');
      expect(find.text('请选择有效期截止日期'), findsOneWidget);
      final dates = find.widgetWithIcon(
        OutlinedButton,
        Icons.calendar_today_outlined,
      );
      await tester.ensureVisible(dates.last);
      await tester.tap(dates.last);
      await settle(tester);
      await tap(tester, 'OK');
      await tap(tester, '保存记录');
      final item = (await tester.runAsync(db.listInventory))!
          .singleWhere((i) => i.id == 'food');
      expect(item.records, hasLength(2));
      expect(item.records.first.expiresAt, isNull);
      expect(item.records.last.expiresAt, isNotNull);
      await tap(tester, '已入手 (1)');
      expect(find.textContaining('需要关注'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search, categories and filter cancel preserve correct results', (
    tester,
  ) async {
    await open(tester);
    await enter(tester, '搜索名称、用途或规格', '泡箱');
    expect(find.text('EPP 泡沫箱'), findsOneWidget);
    expect(find.text('营养液'), findsNothing);
    await tester.tap(find.byTooltip('清空搜索'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '喂食'));
    await settle(tester);
    expect(find.text('营养液'), findsOneWidget);
    expect(find.text('EPP 泡沫箱'), findsNothing);
    await tap(tester, '全部');
    await tap(tester, '筛选');
    await tap(tester, '已入手');
    await tester.tap(find.byTooltip('关闭'));
    await settle(tester);
    expect(find.text('EPP 泡沫箱'), findsOneWidget);
    await tap(tester, '筛选');
    await tap(tester, '已入手');
    await tap(tester, '应用筛选');
    expect(find.text('没有找到匹配物品'), findsOneWidget);
  });

  testWidgets(
    'new item drawer saves category, optional specs, icon and purpose on a narrow screen',
    (tester) async {
      await open(tester, width: 320);
      await tap(tester, '新增物品');
      await enter(tester, '例如：EPP 泡沫箱', '旅行收纳盒');
      await tap(tester, '生活');
      await enter(tester, '例如：运输时保温', '外出收纳');
      await tap(tester, '添加规格');
      await enter(tester, '例如：20cm、30cm、加厚型', '加厚款');
      await tap(tester, '保存规格');
      await tap(tester, '保存物品');
      final items = (await tester.runAsync(db.listInventory))!
          .where((i) => i.productName == '旅行收纳盒')
          .toList();
      expect(items, hasLength(2));
      expect(
        items.every(
          (i) =>
              i.categoryLabel == '生活' && i.purpose == '外出收纳' && !i.allowsExpiry,
        ),
        true,
      );
      expect(find.text('旅行收纳盒'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'record editing preserves zero quantity and deletion needs confirmation',
    (tester) async {
      await tester.runAsync(
        () => db.saveInventoryBatch(
          'box',
          InventoryBatch(
            id: 'one',
            quantity: 3,
            acquiredAt: DateTime(2026, 10, 18),
            costCents: 500,
          ),
        ),
      );
      await open(tester);
      await tap(tester, '已入手 (1)');
      await tap(tester, 'EPP 泡沫箱');
      await tester.enterText(find.byType(TextFormField).first, '0');
      await tap(tester, '保存修改');
      expect(find.text('已用完'), findsOneWidget);
      await tap(tester, 'EPP 泡沫箱');
      await tester.tap(find.byTooltip('删除'));
      await settle(tester);
      await tap(tester, '取消');
      expect(find.text('编辑入手记录'), findsOneWidget);
      await tester.tap(find.byTooltip('删除'));
      await settle(tester);
      await tap(tester, '确认删除');
      expect(find.text('已入手 (0)'), findsOneWidget);
      expect(
        (await tester.runAsync(db.listInventory))!
            .singleWhere((i) => i.id == 'box')
            .records,
        isEmpty,
      );
    },
  );

  testWidgets(
    'large text and keyboard keep the sheet scrollable and its save action reachable',
    (tester) async {
      await open(tester, width: 320, scale: 1.4);
      await tap(tester, '新增物品');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.text('保存物品').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
