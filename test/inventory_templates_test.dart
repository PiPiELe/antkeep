import 'dart:convert';
import 'dart:io';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/inventory_page.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:antkeep/online/online_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Store implements OnlineStore {
  String? content;
  @override
  Future<String?> readContent() async => content;
  @override
  Future<void> writeContent(String value) async => content = value;
  @override
  Future<String?> readSeenAnnouncement() async => null;
  @override
  Future<void> writeSeenAnnouncement(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
  late Directory directory;
  late OnlineController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('inventory-templates-');
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
        id: 'existing',
        name: '原物品',
        purchased: false,
        category: '生活',
        createdAt: DateTime(2026),
      ).toMap(),
    ];
    await db.replaceAll(snapshot);
    controller = OnlineController(
      api: OnlineApi(
        baseUrl: 'https://api.example.test',
        clientFactory: () => MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 'publication',
                'version': 1,
                'publishedAt': '2026-10-18T00:00:00Z',
                'itemTemplates': [
                  for (final (id, name, category, enabled, months) in [
                    ('food', '模板糖水', '喂食', true, 3),
                    ('other', '模板容器', '自定义分类', true, null),
                    ('hidden', '停用模板', '工具', false, null),
                  ])
                    {
                      'id': id,
                      'name': name,
                      'category': category,
                      'enabled': enabled,
                      'defaultUnit': '瓶',
                      'expiry': months == null
                          ? {'type': 'none'}
                          : {'type': 'shelfLife', 'months': months},
                    },
                ],
                'onboarding': {
                  'title': '指南',
                  'summary': '内容',
                  'steps': [
                    {'id': 'first', 'title': '开始', 'body': '正文'},
                  ],
                },
              }),
            ),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
      store: _Store(),
    );
    await controller.setEnabled(true);
  });
  tearDown(() async {
    controller.dispose();
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
        home: InventoryPage(controller: controller),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  testWidgets(
    'published template is opt-in and defaults survive repeated acquisitions and backup',
    (tester) async {
      await open(tester);
      await tap(tester, '新增物品');
      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '例如：EPP 泡沫箱',
      );
      expect(tester.widget<TextField>(nameField).controller!.text, isEmpty);
      await tap(tester, '从模板填写');
      expect(find.text('停用模板'), findsNothing);
      await tap(tester, '模板糖水');
      expect(tester.widget<TextField>(nameField).controller!.text, '模板糖水');
      await tap(tester, '保存物品');
      var items = (await tester.runAsync(db.listInventory))!;
      final added = items.where((i) => i.productName == '模板糖水');
      expect(added, hasLength(2));
      expect(
        added.every(
          (i) =>
              i.categoryLabel == '喂食' &&
              i.allowsExpiry &&
              i.shelfLifeMonths == 3 &&
              i.records.isEmpty,
        ),
        isTrue,
      );
      expect(added.singleWhere((i) => i.groupLabel != null).childLabel, '瓶');
      expect(items.singleWhere((i) => i.id == 'existing').categoryLabel, '生活');
      await tap(tester, '不区分规格，直接记录入手');
      expect(find.text('有效期至 *'), findsOneWidget);
      await tap(tester, '保存记录');
      await tap(tester, '不区分规格，直接记录入手');
      expect(find.text('有效期至 *'), findsOneWidget);
      await tap(tester, '保存记录');
      items = (await tester.runAsync(db.listInventory))!;
      final item = items.singleWhere((i) => i.name == '模板糖水');
      expect(item.records, hasLength(2));
      expect(item.shelfLifeMonths, 3);
      expect(
        item.records.every(
          (r) => r.expiresAt == item.suggestedExpiryDate(r.acquiredAt!),
        ),
        isTrue,
      );
      final saved = (await tester.runAsync(db.snapshot))!;
      BackupData.validate(saved);
      await tester.runAsync(() => db.replaceAll(saved));
      final restored = (await tester.runAsync(db.listInventory))!
          .singleWhere((i) => i.id == item.id);
      expect(restored.shelfLifeMonths, 3);
      expect(
        restored.records.map((r) => r.toMap()),
        item.records.map((r) => r.toMap()),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow large-text picker can cancel and does not overwrite an existing item',
    (tester) async {
      await open(tester, width: 320, scale: 1.3);
      await tap(tester, '新增物品');
      await tap(tester, '从模板填写');
      await tap(tester, '取消');
      await tap(tester, '从模板填写');
      await tap(tester, '模板容器');
      await tap(tester, '保存物品');
      final items = (await tester.runAsync(db.listInventory))!;
      expect(
        items
            .where((i) => i.productName == '模板容器')
            .every((i) => !i.allowsExpiry && i.categoryLabel == '工具'),
        isTrue,
      );
      await tap(tester, '原物品');
      await tap(tester, '编辑物品资料');
      expect(find.text('从模板填写'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline templates work locally and duplicate names keep the existing item',
    (tester) async {
      await controller.setEnabled(false);
      await open(tester);
      await tap(tester, '新增物品');
      await tap(tester, '从模板填写');
      expect(find.text('模板糖水'), findsNothing);
      await tap(tester, '营养液');
      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '例如：EPP 泡沫箱',
      );
      await tester.enterText(nameField, '原物品');
      await tap(tester, '保存物品');
      expect(find.textContaining('该物品已存在'), findsOneWidget);
      final existing = (await tester.runAsync(db.listInventory))!;
      expect(existing, hasLength(1));
      expect(existing.single.categoryLabel, '生活');
      expect(existing.single.allowsExpiry, isFalse);
      expect(existing.single.shelfLifeMonths, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'template month defaults clamp month ends and respect disabled expiry',
    () {
      final item = InventoryItem(
        id: 'template',
        name: '物品',
        purchased: false,
        createdAt: DateTime(2026),
        supportsExpiry: true,
        shelfLifeMonths: 1,
      );
      expect(
        item.suggestedExpiryDate(DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28),
      );
      final disabled = InventoryItem.fromMap({
        ...item.toMap(),
        'supports_expiry': 0,
      });
      expect(disabled.suggestedExpiryDate(DateTime(2026, 1, 31)), isNull);
    },
  );
}
