import 'dart:io';
import 'dart:ui' as ui;

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/care_tasks_section.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/diary_preferences.dart';
import 'package:antkeep/diary_settings_page.dart';
import 'package:antkeep/domain/care_task.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
  late Directory directory;
  final today = DateUtils.dateOnly(DateTime.now());
  const captureKey = ValueKey('ux-capture');

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> page(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    bool dark = false,
    double scale = 1,
  }) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, width > 768 ? 936 : 900);
    final font = FontLoader('UXPreview');
    const fontPath = String.fromEnvironment('UX_PREVIEW_FONT');
    await tester.runAsync(() async {
      if (fontPath.isEmpty) {
        font.addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'));
      } else {
        font.addFont(
          Future.value(
            ByteData.sublistView(await File(fontPath).readAsBytes()),
          ),
        );
      }
      await font.load();
    });
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(icons.load);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: antKeepTheme(ThemeColor.forest, dark: dark).copyWith(
          textTheme: antKeepTheme(
            ThemeColor.forest,
            dark: dark,
          ).textTheme.apply(fontFamily: 'UXPreview'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: captureKey,
            child: InterfaceStyleScope(
              style: InterfaceStyle.current,
              child: child!,
            ),
          ),
        ),
        home: child,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const output = String.fromEnvironment('UX_PREVIEW_DIR');
    if (output.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-ux-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
    await LocalMediaStore.instance.initialize();
    final snapshot = await db.snapshot();
    snapshot['colonies'] = [
      for (var i = 0; i < 4; i++)
        Colony(
          id: 'demo-$i',
          name: ['尼科巴一号', '收获蚁', '新后观察', '红头弓背蚁'][i],
          species: i == 1 ? '收获蚁' : '尼科巴弓背蚁',
          queenCount: 1,
          initialWorkerCount: [20, 128, 0, 76][i],
          acquiredOn: i == 0
              ? null
              : today.subtract(Duration(days: 18 + i * 20)),
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
          updatedAt: today,
        ).toMap(),
    ];
    snapshot['care_records'] = [
      CareRecord(
        id: 'demo-death',
        colonyId: 'demo-0',
        type: CareRecordType.mortality,
        occurredAt: today,
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
        workerMortalityCount: 2,
        note: '工蚁死亡 2 只，已检查巢内情况',
      ).toMap(),
    ];
    snapshot['care_tasks'] = [
      CareTask(
        id: 'due',
        colonyId: 'demo-0',
        type: CareTaskType.feeding,
        intervalDays: 7,
        nextDueOn: today,
      ).toMap(),
      CareTask(
        id: 'future',
        colonyId: 'demo-0',
        type: CareTaskType.watering,
        intervalDays: 3,
        nextDueOn: today.add(const Duration(days: 2)),
      ).toMap(),
    ];
    snapshot['inventory_items'] = [
      InventoryItem(
        id: 'plate',
        name: '喂食盘',
        purchased: false,
        category: '喂食',
        createdAt: today,
      ).toMap(),
    ];
    await db.replaceAll(snapshot);
    await themeController.load();
    await themeController.setInterfaceStyle(InterfaceStyle.current);
    await themeController.setColonyDisplayStyle(ColonyDisplayStyle.dense);
    await themeController.setDiary(const DiaryPreferences());
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'all four densities retain search and clear combined filters in one action',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await page(tester, const ColoniesPage());
      await tester.enterText(find.byType(TextField).first, '尼科巴一号');
      await settle(tester);
      for (final style in ColonyDisplayStyle.values) {
        await tester.runAsync(
          () => themeController.setColonyDisplayStyle(style),
        );
        await settle(tester);
        expect(find.byKey(const ValueKey('demo-0')), findsOneWidget);
        expect(find.text('收获蚁'), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '尼科巴一号',
        );
        expect(find.byTooltip('新增蚁群'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextField).first, '不存在');
      await settle(tester);
      await tester.tap(find.text('显示全部').last);
      await settle(tester);
      expect(find.byKey(const ValueKey('demo-1')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'future tasks have no checkbox and record completion refreshes latest feeding',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await page(tester, const ColonyDetailPage(colonyId: 'demo-0'));
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.text('完成并记录'), findsOneWidget);
      await tester.tap(find.text('完成并记录'));
      await settle(tester);
      await tester.tap(find.byTooltip('保存记录'));
      await settle(tester);
      final records = (await tester.runAsync(() => db.listRecords('demo-0')))!;
      expect(
        records.where((record) => record.type == CareRecordType.feeding),
        hasLength(1),
      );
      final tasks = (await tester.runAsync(
        () => db.listCareTasks(colonyId: 'demo-0'),
      ))!;
      expect(
        tasks.firstWhere((task) => task.id == 'due').nextDueOn,
        today.add(const Duration(days: 7)),
      );
      expect(
        tasks.firstWhere((task) => task.id == 'future').nextDueOn,
        today.add(const Duration(days: 2)),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'quantity preview refreshes after settings and uses persisted total mode',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final colony = (await tester.runAsync(() => db.findColony('demo-0')))!;
      await page(tester, RecordFormPage(colony: colony));
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, '当前总数'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '当前总数'));
      await settle(tester);
      expect(themeController.diary.incremental, isFalse);
      final workers = find.widgetWithText(TextField, '当前工蚁总数');
      await tester.ensureVisible(workers);
      await tester.enterText(workers, '7');
      await settle(tester);
      expect(find.text('工蚁 18 → 7'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await tester.tap(find.byTooltip('日记设置'));
      await settle(tester);
      expect(find.byType(DiarySettingsPage), findsOneWidget);
      await tester.runAsync(
        () => db.saveRecord(
          CareRecord(
            id: 'preview-correction',
            colonyId: colony.id,
            type: CareRecordType.observation,
            occurredAt: today,
            createdAt: DateTime.now(),
            workerCount: 25,
          ),
        ),
      );
      Navigator.of(tester.element(find.byType(DiarySettingsPage))).pop();
      await settle(tester);
      expect(find.text('工蚁 25 → 7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    for (final width in [360.0, 390.0, 430.0, 768.0, 1366.0]) {
      testWidgets('real pages fit $width dark=$dark', (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final suffix = '${width.toInt()}-${dark ? 'dark' : 'light'}';
        final save = width == 390 || width == 1366;
        await page(tester, const HomePage(), width: width, dark: dark);
        if (save) await capture(tester, 'list-$suffix');
        await tester.tap(find.text('尼科巴一号'));
        await settle(tester);
        expect(find.text('补充蚁群档案'), findsOneWidget);
        if (save) await capture(tester, 'detail-$suffix');
        await tester.scrollUntilVisible(
          find.byTooltip('展开种群数量'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await settle(tester);
        expect(find.textContaining('当前已知合计 19'), findsOneWidget);
        expect(find.byTooltip('展开种群数量'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await page(tester, const InventoryPage(), width: width, dark: dark);
        await tester.tap(find.text('喂食盘'));
        await settle(tester);
        await tester.ensureVisible(find.text('直接记录入手'));
        await tester.tap(find.text('直接记录入手'));
        await settle(tester);
        expect(find.text('设置有效期（可选）'), findsNothing);
        final cost = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '未填写',
        );
        await tester.enterText(cost, '18');
        await tester.tap(find.byTooltip('增加数量'));
        await settle(tester);
        expect(find.textContaining('¥9.00'), findsOneWidget);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        if (save) await capture(tester, 'inventory-$suffix');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('保存记录'));
        await settle(tester);
        final items = (await tester.runAsync(db.listInventory))!;
        expect(items.single.records.single.costCents, 1800);
        expect(items.single.records.single.quantity, 2);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'large fonts keep help and completion actions readable at 360px',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final colony = (await tester.runAsync(() => db.findColony('demo-0')))!;
      await page(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: CareTasksSection(
              colony: colony,
              compact: true,
              onRecord: (_) async => false,
            ),
          ),
        ),
        width: 360,
        scale: 1.3,
      );
      expect(find.text('完成并记录'), findsOneWidget);
      await tester.tap(find.text('添加'));
      await settle(tester);
      expect(find.text('1～365 天；完成后从完成当天重新计算'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
