import 'dart:io';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/care_tasks_section.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/care_task.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'offline_tools_ui_test.dart' show capture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
  final at = DateTime(2026, 1, 1);
  late Directory root;
  late Colony colony;
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('antkeep-feeding-ui-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
    await LocalMediaStore.instance.initialize();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDownAll(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  setUp(() async {
    colony = Colony(id: 'c', name: '收获蚁', createdAt: at, updatedAt: at);
    await db.replaceAll({
      'colonies': [colony.toMap()],
      'care_records': [],
      'care_tasks': [],
      'memorials': [],
      'feeder_records': [],
      'inventory_items': [],
    });
  });
  testWidgets(
    'split switch, per-food reminder and quick feeding work at 320px with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: antKeepTheme(ThemeColor.forest),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CareTasksSection(
                  colony: colony,
                  compact: true,
                  onRecord: (_) async => false,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('细分食物投喂'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await settle(tester);
      expect(find.text('蛋白'), findsOneWidget);
      expect(find.text('糖类'), findsOneWidget);
      expect(find.text('种子'), findsOneWidget);
      await tester.tap(find.text('蛋白'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤食提醒'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '投喂后几小时撤食'),
        '8',
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'feeding-reminder-320');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('保存'));
      await settle(tester);
      final tasks = (await tester.runAsync(() => db.listCareTasks()))!;
      expect(
        tasks.singleWhere((t) => t.type == CareTaskType.protein).removalHours,
        8,
      );
      expect(
        tasks.singleWhere((t) => t.type == CareTaskType.sugar).removalHours,
        isNull,
      );
      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);
      await tester.pump(const Duration(seconds: 5));
      await capture(tester, key, 'feeding-split-320');
      final fed = (await tester.runAsync(() => db.listCareTasks()))!;
      expect(fed.where((t) => t.lastFedAt != null).length, 1);
      expect(
        fed.singleWhere((t) => t.type == CareTaskType.protein).removalDueAt,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ordinary diary can select one food plan and update only its timer',
    (tester) async {
      await tester.runAsync(() => db.setSplitFeeding('c', true));
      await tester.pumpWidget(
        MaterialApp(home: RecordFormPage(colony: colony)),
      );
      await settle(tester);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '投喂'));
      await tester.tap(find.widgetWithText(ChoiceChip, '投喂'));
      await tester.pumpAndSettle();
      final select = find.widgetWithText(
        DropdownButtonFormField<String>,
        '食物分类与计时',
      );
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('糖类 · 更新计时').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('保存记录'));
      await settle(tester);
      final records = (await tester.runAsync(() => db.listRecords('c')))!;
      expect(records.single.feedingCategory, CareTaskType.sugar.storageValue);
      final tasks = (await tester.runAsync(() => db.listCareTasks()))!;
      expect(
        tasks.singleWhere((t) => t.type == CareTaskType.sugar).lastFedAt,
        records.single.occurredAt,
      );
      expect(tasks.where((t) => t.lastFedAt != null).length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
