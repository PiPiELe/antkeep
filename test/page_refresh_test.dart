import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/diary_preferences.dart';
import 'package:antkeep/diary_settings_page.dart';
import 'package:antkeep/population_analysis_page.dart';
import 'package:antkeep/colony_growth_page.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/memorial.dart';
import 'package:antkeep/domain/share_card_data.dart';
import 'package:antkeep/share_content_page.dart';
import 'package:antkeep/share_cards_page.dart';
import 'package:antkeep/memorial_share_page.dart';
import 'package:antkeep/widgets/share_card_poster.dart';
import 'package:antkeep/species_encyclopedia_page.dart';
import 'package:antkeep/husbandry_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

Future<void> revealSetting(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> openStatisticsSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.text('统计设置'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('统计设置'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tables = <String, List<Map<String, Object?>>>{
    'app_settings': [],
    'feeder_records': [],
    'colonies': [],
    'care_records': [],
    'inventory_items': [],
    'memorials': [],
  };
  final records = tables['feeder_records']!;
  late Directory directory;
  bool failColonyDeletion = false;
  bool failOrderWrite = false;
  bool failShareRead = false;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-feeder-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (
          call,
        ) async {
          switch (call.method) {
            case 'openDatabase':
              return {'id': 1};
            case 'execute':
              return {'transactionId': 1};
            case 'batch':
              return null;
            case 'query':
              final sql = call.arguments['sql'] as String;
              if (sql == 'PRAGMA user_version') {
                return [
                  {'user_version': 8},
                ];
              }
              final arguments =
                  (call.arguments['arguments'] as List<dynamic>?) ?? [];
              final table = RegExp(r'FROM (\w+)').firstMatch(sql)!.group(1)!;
              if (failShareRead && table == 'memorials') {
                throw PlatformException(code: 'read_failed');
              }
              final filter = RegExp(r'WHERE (\w+) = \?')
                  .firstMatch(sql)
                  ?.group(1);
              return tables[table]!
                  .where(
                    (row) => filter == null || row[filter] == arguments.first,
                  )
                  .take(sql.contains('LIMIT 1') ? 1 : tables[table]!.length)
                  .toList();
            case 'update':
              final sql = call.arguments['sql'] as String;
              final values = call.arguments['arguments'] as List<dynamic>;
              if (sql == 'DELETE FROM colonies WHERE id = ?') {
                if (failColonyDeletion) {
                  throw PlatformException(code: 'delete_failed');
                }
                final count = tables['colonies']!.length;
                tables['colonies']!.removeWhere(
                  (row) => row['id'] == values.single,
                );
                tables['care_records']!.removeWhere(
                  (row) => row['colony_id'] == values.single,
                );
                return count - tables['colonies']!.length;
              }
              final table = RegExp(r'UPDATE(?: OR IGNORE)? (\w+)')
                  .firstMatch(sql)!
                  .group(1)!;
              final columns = RegExp(
                r'(\w+) = (\?|NULL)',
                caseSensitive: false,
              ).allMatches(sql.split('WHERE').first).toList();
              final matching = tables[table]!.where(
                (row) => row['id'] == values.last,
              );
              if (matching.isEmpty) return 0;
              final row = matching.single;
              var valueIndex = 0;
              for (final column in columns) {
                row[column.group(1)!] = column.group(2) == '?'
                    ? values[valueIndex++]
                    : null;
              }
              return 1;
            case 'insert':
              final sql = call.arguments['sql'] as String;
              final table = RegExp(r'INTO (\w+)').firstMatch(sql)!.group(1)!;
              if (table == 'app_settings' && failOrderWrite) {
                throw PlatformException(code: 'storage_unavailable');
              }
              final records = tables[table]!;
              final columns = sql
                  .substring(sql.indexOf('(') + 1, sql.indexOf(')'))
                  .split(',')
                  .map((column) => column.trim())
                  .toList();
              final values = call.arguments['arguments'] as List<dynamic>;
              if (table == 'app_settings') {
                records.removeWhere(
                  (row) => row['setting_key'] == values.first,
                );
              }
              final placeholders = sql
                  .substring(sql.lastIndexOf('(') + 1, sql.lastIndexOf(')'))
                  .split(',');
              var valueIndex = 0;
              records.insert(0, {
                for (var index = 0; index < columns.length; index++)
                  columns[index]: placeholders[index].trim() == '?'
                      ? values[valueIndex++]
                      : null,
              });
              return records.length;
            default:
              throw UnsupportedError(
                'Unexpected database call: ${call.method}',
              );
          }
        });
    databaseFactory = databaseFactorySqflitePlugin;
    await AppDatabase.instance.open();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.tekartik.sqflite'),
          null,
        );
    await directory.delete(recursive: true);
  });

  setUp(() async {
    themeController.simpleMode = false;
    failColonyDeletion = false;
    failOrderWrite = false;
    failShareRead = false;
    for (final rows in tables.values) {
      rows.clear();
    }
    await themeController.load();
  });

  tearDown(() {
    themeController.simpleMode = false;
  });

  for (final archived in [false, true]) {
    testWidgets(
      'diary presets preserve records and allow full detail, archived=$archived',
      (tester) async {
        final now = DateTime.now();
        final colony = Colony(
          id: 'display',
          name: '展示测试',
          createdAt: now,
          updatedAt: now,
          archived: archived,
          initialWorkerCount: 12,
          targetTemperature: 25,
          showSpecialized: true,
          specializedCount: 2,
        );
        tables['colonies']!.add(colony.toMap());
        tables['care_records']!.add(
          CareRecord(
            id: 'display-record',
            colonyId: colony.id,
            type: CareRecordType.observation,
            occurredAt: now,
            createdAt: now,
            eggCount: 9,
            workerMortalityCount: 1,
            temperature: 28,
            note: '观察备注',
          ).toMap(),
        );
        final before = Map<String, Object?>.from(
          tables['care_records']!.single,
        );
        final colonyBefore = Map<String, Object?>.from(
          tables['colonies']!.single,
        );
        await tester.pumpWidget(
          const MaterialApp(home: ColonyDetailPage(colonyId: 'display')),
        );
        await tester.pumpAndSettle();
        final menu = find.byKey(const ValueKey('diary-settings-menu'));
        await tester.scrollUntilVisible(
          menu,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, '紧凑'));
        await tester.pumpAndSettle();
        expect(themeController.diary.preset, DiaryPreset.compact);
        expect(themeController.diary.incremental, isTrue);
        await tester.scrollUntilVisible(
          find.text('查看详情'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('卵 9'), findsNothing);
        expect(find.textContaining('工蚁死亡 1'), findsOneWidget);
        expect(find.textContaining('高于预设上限'), findsOneWidget);
        await tester.tap(find.text('查看详情'));
        await tester.pumpAndSettle();
        expect(find.textContaining('卵 9'), findsOneWidget);
        expect(find.byType(RecordFormPage), findsNothing);
        expect(tables['care_records']!.single, before);
        expect(tables['colonies']!.single, colonyBefore);
        await themeController.load();
        expect(themeController.diary.preset, DiaryPreset.compact);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'quantity-only diary keeps a summary and presets do not change population',
    (tester) async {
      final now = DateTime.now();
      final colony = Colony(
        id: 'quantity-only',
        name: '数量记录',
        createdAt: now,
        updatedAt: now,
        initialWorkerCount: 12,
      );
      tables['colonies']!.add(colony.toMap());
      final record = CareRecord(
        id: 'count',
        colonyId: colony.id,
        type: CareRecordType.observation,
        occurredAt: now,
        createdAt: now,
        eggCount: 9,
      );
      tables['care_records']!.add(record.toMap());
      final population = colony.currentPopulation([record]);
      await themeController.setDiary(
        themeController.diary.select(DiaryPreset.daily),
      );
      await tester.pumpWidget(
        const MaterialApp(home: ColonyDetailPage(colonyId: 'quantity-only')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('已记录种群数量'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('卵 9'), findsNothing);
      expect(find.text('已记录种群数量'), findsOneWidget);
      await tester.ensureVisible(find.text('查看详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.text('卵 9'), findsOneWidget);
      final after = colony.currentPopulation(
        tables['care_records']!.map(CareRecord.fromMap),
      );
      expect(after.eggs, population.eggs);
      expect(after.workers, population.workers);
    },
  );

  testWidgets(
    'unified settings include colony rules and preserve incremental default on history edits',
    (tester) async {
      final now = DateTime.now();
      final colony = Colony(
        id: 'entry-settings',
        name: '录入设置',
        createdAt: now,
        updatedAt: now,
      );
      tables['colonies']!.add(colony.toMap());
      await tester.pumpWidget(
        MaterialApp(
          home: RecordFormPage(
            colony: colony,
            record: CareRecord(
              id: 'old',
              colonyId: colony.id,
              type: CareRecordType.observation,
              occurredAt: DateTime(2026, 10, 1, 12, 30),
              createdAt: now,
              workerCount: 12,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('日记设置'));
      await tester.pumpAndSettle();
      expect(find.byType(DiarySettingsPage), findsOneWidget);
      final toggle = find.widgetWithText(SwitchListTile, '增量');
      await revealSetting(tester, toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      final specific = find.widgetWithText(CheckboxListTile, '记录具体时间');
      await revealSetting(tester, specific);
      expect(tester.widget<CheckboxListTile>(specific).value, isTrue);
      await tester.tap(specific);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(specific).value, isFalse);
      await tester.tap(specific);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(specific).value, isFalse);
      await revealSetting(tester, find.text('特化'));
      await tester.tap(find.text('特化'));
      await tester.pumpAndSettle();
      expect(find.byType(ColonyFormPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('仅记录日期'), findsOneWidget);
      expect(themeController.diary.incremental, isTrue);
    },
  );

  testWidgets('home share stays available across tabs and simple mode', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('分享'), findsOneWidget);
    await tester.tap(find.text('英灵殿').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('分享'), findsOneWidget);
    await tester.tap(find.byTooltip('分享'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareContentPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    themeController.simpleMode = true;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('分享'), findsOneWidget);
    expect(find.text('分析'), findsNothing);
    await tester.tap(find.byTooltip('分享'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareContentPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('share selection handles empty data and retries failed loading', (
    tester,
  ) async {
    failShareRead = true;
    await tester.pumpWidget(const MaterialApp(home: ShareContentPage()));
    await tester.pumpAndSettle();
    expect(find.text('加载失败，点击重试'), findsOneWidget);
    failShareRead = false;
    await tester.tap(find.text('加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有蚁群，请先添加蚁群'), findsOneWidget);
    await tester.tap(find.text('纪念分享图'));
    await tester.pumpAndSettle();
    expect(find.text('还没有纪念，请先在英灵殿添加'), findsOneWidget);
  });

  testWidgets(
    'share selection routes selected colony and template or memorial',
    (tester) async {
      final now = DateTime.now();
      for (final id in ['a', 'b']) {
        tables['colonies']!.add(
          Colony(id: id, name: '蚁群$id', createdAt: now, updatedAt: now).toMap(),
        );
        tables['care_records']!.add(
          CareRecord(
            id: 'record-$id',
            colonyId: id,
            type: CareRecordType.observation,
            occurredAt: now,
            createdAt: now,
            note: '日记$id',
          ).toMap(),
        );
      }
      final memorial = Memorial(
        id: 'm',
        kind: MemorialKind.queen,
        name: '纪念测试',
        createdAt: now,
      );
      tables['memorials']!.add(memorial.toMap());
      await tester.pumpWidget(const MaterialApp(home: ShareContentPage()));
      await tester.pumpAndSettle();
      for (final kind in ShareCardKind.values) {
        await tester.tap(find.widgetWithText(ChoiceChip, kind.label));
        await tester.pumpAndSettle();
        await tester.tap(find.text('蚁群b'));
        await tester.pumpAndSettle();
        final page = tester.widget<ShareCardsPage>(find.byType(ShareCardsPage));
        expect(page.colony.id, 'b');
        expect(page.records.map((r) => r.colonyId), ['b']);
        expect(
          tester.widget<ShareCardPoster>(find.byType(ShareCardPoster)).kind,
          kind,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('纪念分享图'));
      await tester.pumpAndSettle();
      expect(find.text('蚁群b'), findsNothing);
      await tester.tap(find.text('纪念测试'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<MemorialSharePage>(find.byType(MemorialSharePage))
            .memorial
            .id,
        'm',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> tapSave(WidgetTester tester, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final isDiaryRecord =
        label == '保存记录' && find.byType(RecordFormPage).evaluate().isNotEmpty;
    if (isDiaryRecord) {
      await tester.tap(find.byTooltip('保存记录'));
    } else {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }
    await tester.pumpAndSettle();
    if (label == '保存蚁群' &&
        find.byType(ColonyGrowthPage).evaluate().isNotEmpty) {
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
  }

  Future<void> showSortableColonies(WidgetTester tester) async {
    final now = DateTime(2026, 10, 2);
    for (final id in ['c', 'b', 'a']) {
      await AppDatabase.instance.saveColony(
        Colony(id: id, name: id, createdAt: now, updatedAt: now),
      );
    }
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
  }

  Future<void> dragColony(WidgetTester tester, String from, String to) async {
    final start = tester.getCenter(find.text(from));
    final target = tester.getRect(find.byKey(ValueKey(to)));
    final end = Offset(
      start.dx,
      target.center.dy > start.dy ? target.bottom + 1 : target.top - 1,
    );
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(Offset.lerp(start, end, step / 12)!);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('long press sorts both ways and retains order after reload', (
    tester,
  ) async {
    await showSortableColonies(tester);
    await dragColony(tester, 'a', 'c');
    expect(themeController.colonyOrder, ['b', 'c', 'a']);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('a'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const ValueKey('c'))).dy),
    );
    await dragColony(tester, 'a', 'b');
    expect(themeController.colonyOrder, ['a', 'b', 'c']);
    await themeController.load();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    expect(themeController.colonyOrder, ['a', 'b', 'c']);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('a'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('b'))).dy),
    );
    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ColonyDetailPage>(find.byType(ColonyDetailPage)).colonyId,
      'b',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed ordering write restores the visible and saved order', (
    tester,
  ) async {
    await showSortableColonies(tester);
    failOrderWrite = true;
    await dragColony(tester, 'a', 'c');
    expect(themeController.colonyOrder, isEmpty);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('a'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('b'))).dy),
    );
    expect(find.text('保存顺序失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved order ignores deleted IDs and appends new colonies', (
    tester,
  ) async {
    await themeController.setColonyOrder(['deleted', 'b', 'a']);
    await showSortableColonies(tester);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('b'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('a'))).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('a'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('c'))).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('growth settings validate counts and persist period and path', (
    tester,
  ) async {
    final now = DateTime.now();
    final colony = Colony(
      id: 'growth-ui',
      name: '扩充测试',
      createdAt: now,
      updatedAt: now,
      initialEggCount: 10,
      initialLarvaCount: 10,
      developmentPath: GrowthPath.eggToCocoonToWorker,
      initialCocoonCount: 5,
      initialWorkerCount: 20,
    );
    tables['colonies']!.add(colony.toMap());
    await tester.pumpWidget(
      MaterialApp(home: ColonyGrowthPage(colony: colony)),
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<GrowthFrequency>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每月').last);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<GrowthPath>), findsNothing);
    expect(find.textContaining('卵 → 幼 → 茧 → 工'), findsOneWidget);
    for (final item in [('卵净增长', '2'), ('茧净增长', '3'), ('工净增长', '1')]) {
      final field = find.widgetWithText(TextFormField, item.$1);
      await tester.ensureVisible(field);
      await tester.enterText(field, item.$2);
    }
    await tapSave(tester, '保存设置');
    final growth = Colony.fromMap(tables['colonies']!.single).growth!;
    expect(growth.frequency, GrowthFrequency.monthly);
    expect(growth.path, GrowthPath.eggToCocoonToWorker);
    expect(growth.eggs, 2);
    expect(growth.cocoons, 3);
    expect(growth.workers, 1);
    expect(growth.completedCycles, 0);
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('reopened-growth-app'),
        home: ColonyGrowthPage(
          key: const ValueKey('reopen'),
          colony: Colony.fromMap(tables['colonies']!.single),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tapSave(tester, '保存设置');
    expect(Colony.fromMap(tables['colonies']!.single).growth, isNull);
  });

  for (final analysis in [true, false]) {
    testWidgets(
      '${analysis ? 'analysis' : 'detail'} forecast opens setup and refreshes after saving',
      (tester) async {
        final now = DateTime.now();
        tables['colonies']!.add(
          Colony(
            id: 'setup-forecast',
            name: '设置预测',
            createdAt: now,
            updatedAt: now,
            initialWorkerCount: 20,
            initialEggCount: 10,
            initialLarvaCount: 100,
            initialCocoonCount: 5,
          ).toMap(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: analysis
                ? const PopulationAnalysisPage()
                : const ColonyDetailPage(colonyId: 'setup-forecast'),
          ),
        );
        await tester.pumpAndSettle();
        if (analysis) {
          await tester.tap(find.byKey(const ValueKey('analysis-subject')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('蚁群 · 设置预测').last);
        } else {
          final populationCard = find.ancestor(
            of: find.text('种群数量'),
            matching: find.byType(Card),
          );
          expect(
            find.descendant(of: populationCard, matching: find.text('自动扩充')),
            findsOneWidget,
          );
          await tester.tap(find.text('自动扩充'));
          await tester.pumpAndSettle();
          expect(find.byType(ColonyGrowthPage), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byTooltip('展开种群数量'));
          await tester.tap(find.byTooltip('展开种群数量'));
        }
        await tester.pumpAndSettle();
        if (!analysis) await openStatisticsSettings(tester);
        final setup = find.byKey(const ValueKey('population-forecast-setup'));
        await revealSetting(tester, setup);
        await tester.tap(find.text('增长预测'));
        await tester.pumpAndSettle();
        expect(find.byType(ColonyGrowthPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(setup, findsOneWidget);
        expect(Colony.fromMap(tables['colonies']!.single).growth, isNull);

        await tester.ensureVisible(find.text('设置规则'));
        await tester.tap(find.text('设置规则'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(SwitchListTile, '开启自动扩充'));
        await tester.pumpAndSettle();
        final workers = find.widgetWithText(TextFormField, '工净增长');
        await tester.ensureVisible(workers);
        await tester.enterText(workers, '1');
        await tapSave(tester, '保存设置');
        expect(find.byType(ColonyGrowthPage), findsNothing);
        expect(setup, findsNothing);
        final toggle = find.byKey(const ValueKey('population-forecast-toggle'));
        await tester.ensureVisible(toggle);
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        expect(find.text('7 天'), findsOneWidget);
        if (!analysis) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(const ValueKey('population-forecast-summary')),
          findsOneWidget,
        );
        expect(tables['care_records'], isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'detail chart forecasts without adding records and keeps brood filtering',
    (tester) async {
      final now = DateTime.now();
      tables['colonies']!.add(
        Colony(
          id: 'detail-forecast',
          name: '详情预测',
          createdAt: now,
          updatedAt: now,
          queenCount: 1,
          initialWorkerCount: 20,
          initialEggCount: 0,
          initialLarvaCount: 100,
          initialCocoonCount: 5,
          growth: ColonyGrowth(
            frequency: GrowthFrequency.daily,
            path: GrowthPath.eggToWorker,
            startedAt: now,
            workers: 1,
          ),
        ).toMap(),
      );
      await tester.pumpWidget(
        const MaterialApp(home: ColonyDetailPage(colonyId: 'detail-forecast')),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('population-forecast-toggle'));
      await tester.ensureVisible(find.byTooltip('展开种群数量'));
      await tester.tap(find.byTooltip('展开种群数量'));
      await tester.pumpAndSettle();
      await openStatisticsSettings(tester);
      await revealSetting(tester, toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('7 天'));
      await tester.tap(find.text('7 天'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final summary = find.byKey(const ValueKey('population-forecast-summary'));
      await tester.ensureVisible(summary);
      expect(find.textContaining('28 只（估算）'), findsOneWidget);
      await openStatisticsSettings(tester);
      await revealSetting(tester, find.text('带卵幼'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('带卵幼'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('126 只（估算）'), findsOneWidget);
      expect(tables['care_records'], isEmpty);
      await openStatisticsSettings(tester);
      await revealSetting(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(summary, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> fillRequiredColonyCounts(WidgetTester tester) async {
    for (final field in ['蚁后 *', '工蚁 *']) {
      final input = find.widgetWithText(TextFormField, field);
      await tester.ensureVisible(input);
      await tester.enterText(input, '0');
    }
  }

  testWidgets('colony deletion requires confirmation and refreshes the list', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 30);
    for (final id in ['待删除', '保留']) {
      tables['colonies']!.add(
        Colony(id: id, name: id, createdAt: now, updatedAt: now).toMap(),
      );
      tables['care_records']!.add(
        CareRecord(
          id: '$id-record',
          colonyId: id,
          type: CareRecordType.observation,
          occurredAt: now,
          createdAt: now,
        ).toMap(),
      );
    }
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除蚁群'));
    await tester.pumpAndSettle();
    expect(find.text('删除蚁群？'), findsOneWidget);
    expect(find.textContaining('「待删除」'), findsOneWidget);
    expect(tables['colonies'], hasLength(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(ColonyDetailPage), findsOneWidget);
    expect(tables['colonies'], hasLength(2));
    expect(tables['care_records'], hasLength(2));

    // Dismissing the dialog is also cancellation.
    await tester.tap(find.byTooltip('删除蚁群'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tables['colonies'], hasLength(2));

    failColonyDeletion = true;
    await tester.tap(find.byTooltip('删除蚁群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(find.byType(ColonyDetailPage), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tables['colonies'], hasLength(2));
    expect(tables['care_records'], hasLength(2));

    failColonyDeletion = false;
    await tester.tap(find.byTooltip('删除蚁群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(find.byType(ColonyDetailPage), findsNothing);
    expect(find.text('待删除'), findsNothing);
    expect(find.text('保留'), findsOneWidget);
    expect(tables['colonies']!.single['id'], '保留');
    expect(tables['care_records']!.single['colony_id'], '保留');

    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除蚁群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(find.text('还没有蚁群'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('husbandry duration appears in the list and colony detail', (
    tester,
  ) async {
    final now = DateTime.now();
    final arrival = DateTime(now.year, now.month, now.day - 36);
    tables['colonies']!.add(
      Colony(
        id: 'duration',
        name: '到家计时',
        acquiredOn: arrival,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    expect(find.text('已养殖 36 天', findRichText: true), findsOneWidget);
    await tester.tap(find.text('到家计时'));
    await tester.pumpAndSettle();
    expect(find.text('已养殖 36 天', findRichText: true), findsOneWidget);
    expect(
      find.text('${arrival.year}.${arrival.month}.${arrival.day}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('360px detail keeps duration above readable metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final arrival = DateTime(now.year, now.month, now.day - 36);
    tables['colonies']!.add(
      Colony(
        id: 'narrow-duration',
        name: '窄屏布局',
        species: '黑金弓背蚁',
        acquiredOn: arrival,
        source: '本地合成测试数据（非真实饲养记录）',
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('窄屏布局'));
    await tester.pumpAndSettle();

    final date = find.text('${arrival.year}.${arrival.month}.${arrival.day}');
    final source = find.text('本地合成测试数据（非真实饲养记录）');
    final days = find.text('已养殖 36 天', findRichText: true);
    expect(tester.getTopLeft(days).dy, lessThan(tester.getTopLeft(date).dy));
    expect(tester.getTopLeft(date).dy, lessThan(tester.getTopLeft(source).dy));
    expect(tester.getSize(source).width, greaterThan(180));
    expect(tester.getSize(days).height, lessThan(64));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone detail keeps the cover beside duration and actions usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final now = DateTime.now();
      final acquiredOn = DateTime(now.year, now.month, now.day - 16);
      tables['colonies']!.add(
        Colony(
          id: 'responsive-detail',
          name: '猎镰猛蚁蚁群',
          species: '猎镰猛蚁',
          acquiredOn: acquiredOn,
          source: '网购-蚂蚁牧场',
          queenCount: 5,
          initialWorkerCount: 55,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      await AppDatabase.instance.saveRecord(
        CareRecord(
          id: 'responsive-detail-record',
          colonyId: 'responsive-detail',
          type: CareRecordType.observation,
          occurredAt: now,
          createdAt: now,
          note: '布局验收日记',
        ),
      );
      for (final width in [320.0, 360.0, 440.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          const MaterialApp(
            home: ColonyDetailPage(colonyId: 'responsive-detail'),
          ),
        );
        await tester.pumpAndSettle();
        final cover = find.byWidgetPredicate(
          (widget) => widget is Image && widget.semanticLabel == '默认蚂蚁封面',
        );
        expect(
          tester.getRect(find.byType(HusbandryDuration)).left,
          greaterThan(tester.getRect(cover).right),
        );
        expect(
          tester
              .getRect(
                find.text(
                  '${acquiredOn.year}.${acquiredOn.month}.${acquiredOn.day}',
                ),
              )
              .top,
          greaterThan(tester.getRect(cover).bottom),
        );
        expect(find.text('网购-蚂蚁牧场'), findsOneWidget);
        final recordCard = find.ancestor(
          of: find.text('布局验收日记'),
          matching: find.byType(Card),
        );
        await tester.ensureVisible(recordCard);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(recordCard).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.widgetWithText(FilledButton, '添加记录')).top,
          ),
        );
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(360, 800);
      await tester.pump();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除蚁群'));
      await tester.pumpAndSettle();
      expect(find.text('删除蚁群？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tables['colonies'], hasLength(1));
    },
  );

  testWidgets(
    'simple mode keeps colony and diary creation and restores detail',
    (tester) async {
      themeController.simpleMode = true;
      await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FloatingActionButton, '蚁群'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('colony-name')), '简化测试');
      await fillRequiredColonyCounts(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存蚁群'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存蚁群'));
      await tester.pumpAndSettle();
      expect(find.byType(ColonyGrowthPage), findsNothing);
      expect(find.byType(ColonyFormPage), findsNothing);
      expect(find.text('简化测试'), findsOneWidget);
      await tester.tap(find.text('简化测试'));
      await tester.pumpAndSettle();
      expect(find.text('自动扩充'), findsNothing);
      expect(find.text('种群数量'), findsOneWidget);
      expect(find.text('百科'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('养蚁日记'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('养蚁日记'), findsOneWidget);
      await tester.tap(find.text('添加记录'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '备注'), '简化模式的记录');
      await tapSave(tester, '保存记录');
      await tester.scrollUntilVisible(
        find.text('简化模式的记录'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('简化模式的记录'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      themeController.simpleMode = false;
      await tester.tap(find.text('简化测试'));
      await tester.pumpAndSettle();
      expect(find.text('自动扩充'), findsOneWidget);
      expect(find.text('种群数量'), findsOneWidget);
      expect(tables['colonies'], hasLength(1));
      expect(tables['care_records'], hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new colonies appear on returning home without reopening', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    expect(find.text('还没有蚁群'), findsOneWidget);
    for (final name in ['测试蚁群一', '测试蚁群二']) {
      await tester.tap(find.widgetWithText(FloatingActionButton, '蚁群'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('colony-name')), name);
      await fillRequiredColonyCounts(tester);
      await tapSave(tester, '保存蚁群');
      expect(find.byType(ColonyFormPage), findsNothing);
      expect(find.text(name), findsOneWidget);
      expect(find.text('还没有蚁群'), findsNothing);
    }
    expect(find.text('测试蚁群一'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, '蚁群'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tables['colonies'], hasLength(2));
    expect(find.text('测试蚁群二'), findsOneWidget);
  });

  testWidgets('colony purchase prices validate, save, edit and clear', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, '蚁群'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('colony-name')), '购入价测试');
    await fillRequiredColonyCounts(tester);
    final price = find.widgetWithText(TextFormField, '购入价（可选）');
    await tester.scrollUntilVisible(
      price,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(price, '-1');
    await tapSave(tester, '保存蚁群');
    expect(tables['colonies'], isEmpty);
    expect(find.text('请输入有效的非负金额，最多两位小数'), findsOneWidget);
    await tester.ensureVisible(price);
    await tester.enterText(price, '19.99');
    await tapSave(tester, '保存蚁群');
    expect(tables['colonies']!.single['purchase_price_cents'], 1999);
    await tester.tap(find.text('购入价测试'));
    await tester.pumpAndSettle();
    expect(find.text('¥19.99'), findsOneWidget);
    for (final value in ['0', '']) {
      await tester.tap(find.byTooltip('编辑蚁群'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        price,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextFormField>(price).controller!.text,
        value == '0' ? '19.99' : '0.00',
      );
      await tester.enterText(price, value);
      await tapSave(tester, '保存蚁群');
      expect(
        tables['colonies']!.single['purchase_price_cents'],
        value.isEmpty ? null : 0,
      );
      expect(find.text('¥0.00'), value.isEmpty ? findsNothing : findsOneWidget);
    }
  });

  testWidgets('colony alert bounds validate and persist', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('colony-name')), '范围测试');
    await fillRequiredColonyCounts(tester);
    final temperatureLower = find.widgetWithText(TextFormField, '温度下限 °C');
    final temperatureUpper = find.widgetWithText(TextFormField, '温度上限 °C');
    await tester.scrollUntilVisible(
      temperatureLower,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(temperatureLower, '30');
    await tester.enterText(temperatureUpper, '20');
    await tapSave(tester, '保存蚁群');
    expect(tables['colonies'], isEmpty);
    expect(find.text('下限不能高于上限'), findsOneWidget);

    await tester.ensureVisible(temperatureLower);
    await tester.enterText(temperatureLower, '20');
    final humidityLower = find.widgetWithText(TextFormField, '湿度下限 %');
    final humidityUpper = find.widgetWithText(TextFormField, '湿度上限 %');
    await tester.enterText(humidityLower, '45');
    await tester.enterText(humidityUpper, '65');
    await tapSave(tester, '保存蚁群');
    final saved = tables['colonies']!.single;
    expect(saved['target_temperature_lower'], 20.0);
    expect(saved['target_temperature'], 20.0);
    expect(saved['target_humidity_lower'], 45.0);
    expect(saved['target_humidity'], 65.0);
  });

  for (final feeder in FeederType.values) {
    testWidgets('${feeder.name} purchase price is saved and displayed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: FeederDetailPage(feeder: feeder)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加记录'));
      await tester.pumpAndSettle();
      final price = find.widgetWithText(TextFormField, '购入价（可选）');
      await tester.ensureVisible(price);
      await tester.enterText(price, '1.234');
      await tapSave(tester, '保存记录');
      expect(tables['feeder_records'], isEmpty);
      await tester.ensureVisible(price);
      await tester.enterText(price, '0.29');
      await tapSave(tester, '保存记录');
      expect(tables['feeder_records']!.single['purchase_price_cents'], 29);
      expect(find.text('购入价 ¥0.29'), findsOneWidget);
    });
  }

  for (final (category, scientificName, name) in [
    ('收获蚁', 'Messor ebeninus', '乌檀收获蚁'),
    ('牛蚁', 'Myrmecia pilosula', '多毛牛蚁'),
    ('牛蚁', 'Myrmecia sp.17', 'SP17牛蚁（未定种）'),
    ('真猛蚁', 'Euponera pilosior', '多毛真猛蚁（Euponera pilosior）'),
  ]) {
    testWidgets('imported $scientificName can be searched, saved and edited', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextFormField, '品种分类/细分种类'));
      await tester.pumpAndSettle();
      Finder search() => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(search(), category);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, category).first);
      await tester.pumpAndSettle();
      await tester.enterText(search(), ' ${scientificName.toUpperCase()} ');
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      await fillRequiredColonyCounts(tester);
      await tapSave(tester, '保存蚁群');
      final saved = (await AppDatabase.instance.listColonies()).single;
      expect(saved.species, name);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('edit-$name'),
          home: ColonyFormPage(colony: saved),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('$category / $name'), findsOneWidget);
      final field = find.widgetWithText(TextFormField, '品种分类/细分种类');
      expect(tester.widget<TextFormField>(field).enabled, isTrue);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(search(), name);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, name), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (query, category, species, nickname) in [
    ('乌檀', '收获蚁', '乌檀收获蚁', '乌檀收获蚁'),
    (' MYRMECIA PILOSULA ', '牛蚁', '多毛牛蚁', '多毛牛蚁'),
    ('费事弓背蚁', '弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
    ('黑金', '弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
    ('红金', '弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
    ('黑斑', '弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
    ('子弹蚁', '子弹蚁', '子弹蚁', '子弹蚁'),
  ]) {
    testWidgets('top-level search selects and saves $query directly', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, '品种分类/细分种类');
      await tester.tap(field);
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      final result = find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title as Text).data == species &&
            widget.subtitle is Text &&
            (widget.subtitle as Text).data == category,
      );
      expect(result, findsOneWidget);
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('$category / $species'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('colony-name')))
            .controller!
            .text,
        nickname,
      );
      await fillRequiredColonyCounts(tester);
      await tapSave(tester, '保存蚁群');
      expect(
        (await AppDatabase.instance.listColonies()).single.species,
        species,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'clearing top-level search restores categories without changing selection',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, '品种分类/细分种类');
      await tester.tap(field);
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      expect(find.text('工匠收获蚁'), findsNothing);
      await tester.enterText(search, '不存在的品种');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配项'), findsOneWidget);
      await tester.enterText(search, '   ');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, '收获蚁'), findsOneWidget);
      expect(find.text('工匠收获蚁'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field).initialValue, isEmpty);
    },
  );

  testWidgets('species selection cascades and updates the name with an alias', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
    await tester.pumpAndSettle();
    final familyField = find.widgetWithText(TextFormField, '品种分类/细分种类');
    final nameField = find.byKey(const ValueKey('colony-name'));
    expect(familyField, findsOneWidget);
    expect(find.widgetWithText(TextFormField, '细分品种'), findsNothing);
    expect(
      tester.getTopLeft(familyField).dy,
      lessThan(tester.getTopLeft(nameField).dy),
    );
    await tester.tap(familyField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收获蚁'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('工匠收获蚁'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.widget<TextFormField>(nameField).controller!.text, '工匠收获蚁');
    await tester.enterText(nameField, '我的蚁群');
    await tester.tap(familyField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收获蚁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('野蛮收获蚁（原生收获蚁）'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(nameField).controller!.text, '原生收获蚁');
    await tester.enterText(nameField, '   ');
    await tester.tap(familyField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收获蚁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('红胸收获蚁'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(nameField).controller!.text, '红胸收获蚁');
    // Cancelling the automatic second picker leaves the name intact.
    await tester.tap(familyField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('弓背蚁'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(nameField).controller!.text, '红胸收获蚁');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual species dialog confirms and cancels without close errors',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextFormField, '品种分类/细分种类'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收获蚁'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('未收录？手动填写品种'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '学名 / 正式名'),
        '测试品种',
      );
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('测试品种'), findsNWidgets(2));
      await tester.tap(find.text('未收录？手动填写品种'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('测试品种'), findsNWidgets(2));
    },
  );

  for (final (formal, common) in [
    ('Camponotus fedtschenkoi', '黑金弓背蚁'),
    ('费氏弓背蚁', '黑金弓背蚁'),
    ('费氏弓背蚁', '红金弓背蚁'),
    ('费氏弓背蚁', '黑斑弓背蚁'),
  ]) {
    testWidgets(
      'formal and common species names save and reopen: $formal $common',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FloatingActionButton, '蚁群'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('未收录？手动填写品种'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认'));
        await tester.pumpAndSettle();
        expect(find.text('请至少填写一个名称'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, '学名 / 正式名'),
          ' $formal ',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, '通用名（可选）'),
          ' $common ',
        );
        await tester.tap(find.text('确认'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('colony-name')),
          '双名称蚁群',
        );
        await fillRequiredColonyCounts(tester);
        await tapSave(tester, '保存蚁群');
        final saved = (await AppDatabase.instance.listColonies()).single;
        expect(saved.species, '$formal（$common）');
        expect(Colony.fromMap(saved.toMap()).species, saved.species);
        await tester.tap(find.text('双名称蚁群'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('编辑蚁群'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('未收录？手动填写品种'));
        await tester.pumpAndSettle();
        expect(find.text(formal), findsOneWidget);
        expect(find.text(common), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, '通用名（可选）'),
          '取消的名称',
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tapSave(tester, '保存蚁群');
        expect(
          (await AppDatabase.instance.findColony(saved.id))!.species,
          saved.species,
        );
      },
    );
  }

  testWidgets('manual species accepts a common name without a formal name', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未收录？手动填写品种'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '通用名（可选）'),
      '自定义通用名',
    );
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('自定义通用名'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy species names retain their category and both names search',
    (tester) async {
      final date = DateTime(2026, 9, 1);
      for (final (oldName, formalName, combinedName, nickname) in [
        ('黑金弓背蚁', '费氏弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
        ('红金弓背蚁', '费氏弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
        ('黑斑弓背蚁', '费氏弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
        ('费氏弓背蚁（黑金弓背蚁）', '费氏弓背蚁', '费氏弓背蚁', '费氏弓背蚁'),
        ('原生收获蚁', '野蛮收获蚁', '野蛮收获蚁（原生收获蚁）', '原生收获蚁'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: ColonyFormPage(
              key: ValueKey(oldName),
              colony: Colony(
                id: oldName,
                name: '已有昵称',
                species: oldName,
                createdAt: date,
                updatedAt: date,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.widgetWithText(TextFormField, '品种分类/细分种类');
        expect(tester.widget<TextFormField>(field).enabled, isTrue);
        expect(find.textContaining(' / $oldName'), findsOneWidget);
        if (formalName == '费氏弓背蚁') {
          await tester.tap(find.text('未收录？手动填写品种'));
          await tester.pumpAndSettle();
          final commonField = tester.widget<TextFormField>(
            find.widgetWithText(TextFormField, '通用名（可选）'),
          );
          expect(
            commonField.initialValue,
            oldName.contains('（') ? '黑金弓背蚁' : oldName,
          );
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(find.textContaining(' / $oldName'), findsOneWidget);
        }
        await tester.tap(field);
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        );
        for (final query in [oldName, formalName]) {
          await tester.enterText(search, query);
          await tester.pumpAndSettle();
          expect(find.widgetWithText(ListTile, combinedName), findsOneWidget);
        }
        await tester.tap(find.widgetWithText(ListTile, combinedName));
        await tester.pumpAndSettle();
        expect(find.textContaining(' / $combinedName'), findsOneWidget);
        expect(find.text(nickname), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final fromList in [false, true]) {
    testWidgets(
      'colony duration opens date input and persists only on save (list: $fromList)',
      (tester) async {
        final createdAt = DateTime(2026, 9, 1);
        final colony = Colony(
          id: 'duration-colony',
          name: '入手日期测试',
          species: '收获蚁',
          queenCount: 1,
          initialWorkerCount: 20,
          purchasePriceCents: 10000,
          createdAt: createdAt,
          updatedAt: createdAt,
        );
        await AppDatabase.instance.saveColony(colony);
        await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
        await tester.pumpAndSettle();
        if (!fromList) {
          await tester.tap(find.text(colony.name));
          await tester.pumpAndSettle();
        }

        final hint = fromList
            ? find.byIcon(Icons.calendar_today_outlined)
            : find.text('入手日期待补充').hitTestable();
        await tester.tap(hint);
        await tester.pumpAndSettle();
        expect(find.text('填写入手日期'), findsOneWidget);
        if (fromList) expect(find.byType(ColonyDetailPage), findsNothing);
        expect(find.byType(InputDatePickerFormField), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          (await AppDatabase.instance.findColony(colony.id))!.toMap(),
          colony.toMap(),
        );

        await tester.tap(hint);
        await tester.pumpAndSettle();
        final selectedDate = DateUtils.dateOnly(DateTime.now())
            .subtract(const Duration(days: 5));
        final localizations = MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)),
        );
        await tester.enterText(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextFormField),
          ),
          localizations.formatCompactDate(selectedDate),
        );
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();

        final saved = (await AppDatabase.instance.findColony(colony.id))!;
        expect(saved.acquiredOn, selectedDate);
        expect(saved.toMap(), {
          ...colony.toMap(),
          'acquired_on': selectedDate.toIso8601String(),
          'updated_at': saved.updatedAt.toIso8601String(),
        });
        expect(
          find.text('已养殖 5 天', findRichText: true).hitTestable(),
          findsOneWidget,
        );
        expect(hint, findsNothing);
        if (!fromList) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(colony.name));
        await tester.pumpAndSettle();
        expect(
          find.text('已养殖 5 天', findRichText: true).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'colony summaries separate brood with record and archive fallback',
    (tester) async {
      final date = DateTime(2026, 9, 1);
      await AppDatabase.instance.saveColony(
        Colony(
          id: 'summary-colony',
          name: '数量摘要',
          queenCount: 1,
          initialWorkerCount: 0,
          initialEggCount: 5,
          initialCocoonCount: 2,
          createdAt: date,
          updatedAt: date,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
      await tester.pumpAndSettle();
      for (final text in ['1 蚁后', '0 工蚁', '5 卵', '2 茧']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('新后群'), findsOneWidget);
      expect(find.textContaining('幼虫'), findsNothing);
      expect(find.textContaining('卵幼茧'), findsNothing);

      // A newer feeding entry has no counts; use the latest quantity entry.
      await AppDatabase.instance.saveRecord(
        CareRecord(
          id: 'feeding',
          colonyId: 'summary-colony',
          type: CareRecordType.observation,
          occurredAt: date.add(const Duration(days: 2)),
          createdAt: date,
        ),
      );
      await AppDatabase.instance.saveRecord(
        CareRecord(
          id: 'counts',
          colonyId: 'summary-colony',
          type: CareRecordType.observation,
          occurredAt: date.add(const Duration(days: 1)),
          createdAt: date,
          eggCount: 0,
          larvaCount: 3,
          workerCount: 8,
        ),
      );
      await AppDatabase.instance.saveRecord(
        CareRecord(
          id: 'other-colony-counts',
          colonyId: 'other-colony',
          type: CareRecordType.observation,
          occurredAt: date,
          createdAt: date,
          eggCount: 100,
        ),
      );
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await tester.pumpAndSettle();
      // Explicit zero overrides the archive; missing pupae fall back to 2.
      for (final text in ['1 蚁后', '8 工蚁', '0 卵', '3 幼虫', '2 茧']) {
        expect(find.text(text), findsOneWidget);
      }
      final quantity =
          tester.widget<Text>(find.text('1 蚁后')).textSpan! as TextSpan;
      expect(
        (quantity.children!.first as TextSpan).style!.fontWeight,
        FontWeight.w700,
      );
      expect((quantity.children!.last as TextSpan).style, isNull);
      await tester.tap(find.text('数量摘要'));
      await tester.pumpAndSettle();
      for (final text in ['1 蚁后', '8 工蚁', '0 卵', '3 幼虫', '2 茧']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.textContaining('卵幼茧'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const ColoniesPage(),
        ),
      );
      await tester.pumpAndSettle();
      for (final text in ['1 蚁后', '8 工蚁', '0 卵', '3 幼虫', '2 茧']) {
        expect(find.text(text).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in {
    0: '小群',
    20: '小群',
    101: '中群',
    500: '大群',
    10000: '超大群',
  }.entries) {
    testWidgets(
      'new queen and ${entry.value} labels coexist at ${entry.key} workers',
      (tester) async {
        final date = DateTime(2026, 9, 1);
        await AppDatabase.instance.saveColony(
          Colony(
            id: 'queen-tags',
            name: '从新后养起',
            initialWorkerCount: 0,
            createdAt: date,
            updatedAt: date,
          ),
        );
        await AppDatabase.instance.saveRecord(
          CareRecord(
            id: 'current-workers',
            colonyId: 'queen-tags',
            type: CareRecordType.observation,
            occurredAt: date.add(const Duration(days: 1)),
            createdAt: date,
            workerCount: entry.key,
          ),
        );
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
        await tester.pumpAndSettle();
        expect(find.text('新后群'), findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('${entry.key} 工蚁'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('从新后养起'));
        await tester.pumpAndSettle();
        final profileCard = find.ancestor(
          of: find.textContaining('蚂蚁品种：'),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: profileCard, matching: find.text('新后群')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: profileCard, matching: find.text(entry.value)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: profileCard,
            matching: find.text('${entry.key} 工蚁'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('specialized counts are shown only after opting in and persist', (
    tester,
  ) async {
    final date = DateTime(2026, 9, 1);
    await AppDatabase.instance.saveColony(
      Colony(
        id: 'specialized-colony',
        name: '特化展示',
        queenCount: 1,
        initialWorkerCount: 10,
        initialEggCount: 5,
        initialCocoonCount: 2,
        createdAt: date,
        updatedAt: date,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    for (final text in ['1 蚁后', '10 工蚁', '5 卵', '2 茧']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('3 特化'), findsNothing);

    Future<void> edit() async {
      await tester.tap(find.text('特化展示'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑蚁群'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -340));
      await tester.pumpAndSettle();
    }

    await edit();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(find.widgetWithText(TextFormField, '特化数量'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    final specialized = find.widgetWithText(TextFormField, '特化数量');
    expect(tester.getTopLeft(specialized).dx, greaterThan(100));
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.enterText(specialized, '3');
    await tapSave(tester, '保存蚁群');
    expect(find.text('3 特化'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    for (final text in ['1 蚁后', '3 特化', '10 工蚁', '5 卵', '2 茧']) {
      expect(find.text(text), findsOneWidget);
    }

    await edit();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '特化数量'))
          .controller!
          .text,
      '3',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tapSave(tester, '保存蚁群');
    expect(find.text('3 特化'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    for (final text in ['1 蚁后', '10 工蚁', '5 卵', '2 茧']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('3 特化'), findsNothing);
    final saved = (await AppDatabase.instance.findColony(
      'specialized-colony',
    ))!;
    expect(saved.showSpecialized, isFalse);
    expect(saved.specializedCount, 3);
  });

  testWidgets('editing a colony refreshes both pages and preserves records', (
    tester,
  ) async {
    final createdAt = DateTime(2026, 9, 1);
    final colony = Colony(
      id: 'edit-colony',
      name: '编辑前',
      species: '自定义品种',
      queenCount: 1,
      initialWorkerCount: 0,
      nestType: '试管巢',
      source: '网购（蚁友商店，订单备注及完整来源说明）',
      acquiredOn: createdAt,
      initialEggCount: 5,
      initialCocoonCount: 2,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await AppDatabase.instance.saveColony(colony);
    await AppDatabase.instance.saveRecord(
      CareRecord(
        id: 'existing-record',
        colonyId: colony.id,
        type: CareRecordType.observation,
        occurredAt: createdAt,
        createdAt: createdAt,
        note: '已有记录',
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑前'));
    await tester.pumpAndSettle();
    final profileCard = find.ancestor(
      of: find.textContaining('蚂蚁品种：'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: profileCard, matching: find.text('新后群')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: profileCard, matching: find.text('1 蚁后')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: profileCard, matching: find.text('试管巢')),
      findsOneWidget,
    );
    expect(find.text('网购-蚁友商店，订单备注及完整来源说明'), findsOneWidget);
    expect(
      find.descendant(
        of: profileCard,
        matching: find.text('网购-蚁友商店，订单备注及完整来源说明'),
      ),
      findsOneWidget,
    );
    expect(find.text('种群数量'), findsOneWidget);
    expect(find.text('5 卵'), findsOneWidget);
    expect(find.text('2 茧'), findsOneWidget);
    expect(find.textContaining('幼虫'), findsNothing);
    expect(find.byKey(const ValueKey('colony-population-chart')), findsNothing);
    expect(find.byTooltip('展开种群数量'), findsOneWidget);
    final collapsedPopulation = find.ancestor(
      of: find.text('种群数量'),
      matching: find.byType(Card),
    );
    expect(tester.getSize(collapsedPopulation).height, lessThanOrEqualTo(56));
    await tester.ensureVisible(find.byTooltip('展开种群数量'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('展开种群数量'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('colony-population-chart')),
      findsOneWidget,
    );
    await openStatisticsSettings(tester);
    await revealSetting(tester, find.text('带卵幼'));
    await tester.tap(find.text('带卵幼'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('colony-population-chart')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('编辑蚁群'));
    await tester.pumpAndSettle();
    expect(find.text('自定义品种'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('colony-name')), '编辑后');
    await tester.enterText(find.widgetWithText(TextFormField, '工蚁 *'), '1000');
    final sourceField = find.widgetWithText(TextFormField, '来源（可选）');
    await tester.scrollUntilVisible(
      sourceField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<TextFormField>(sourceField).controller!.text,
      '蚁友商店，订单备注及完整来源说明',
    );
    expect(find.text('网购'), findsOneWidget);
    await tester.enterText(sourceField, '新店铺');
    await tapSave(tester, '保存蚁群');
    expect(find.text('网购-新店铺'), findsOneWidget);
    expect(find.text('编辑后'), findsOneWidget);
    expect(find.text('大群'), findsOneWidget);
    final saved = (await AppDatabase.instance.findColony(colony.id))!;
    expect(saved.createdAt, createdAt);
    expect(saved.species, colony.species);
    expect(saved.source, '网购（新店铺）');
    expect(saved.acquiredOn, colony.acquiredOn);
    expect(saved.initialEggCount, 5);
    expect(saved.initialCocoonCount, 2);
    expect(saved.nestType, colony.nestType);
    expect(tables['colonies'], hasLength(1));
    expect(
      (await AppDatabase.instance.listRecords(colony.id)).single.id,
      'existing-record',
    );
    // Cancel a second edit without changing persisted data.
    await tester.tap(find.byTooltip('编辑蚁群'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      sourceField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextFormField>(sourceField).controller!.text, '新店铺');
    expect(find.text('网购'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('colony-name')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('colony-name')), '取消编辑');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('编辑后'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('编辑后'), findsOneWidget);
    expect(find.text('取消编辑'), findsNothing);
    expect(find.text('大群'), findsOneWidget);
  });

  for (final example in [
    (detail: '蚂蚁商户 A', type: '网购'),
    (detail: '云丘山', type: '野采'),
    (detail: '=哥', type: '蚁友赠送'),
  ]) {
    testWidgets('colony source keeps detail separate from ${example.type}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final colony = Colony(
        id: 'source-colony',
        name: '来源测试',
        queenCount: 1,
        initialWorkerCount: 0,
        createdAt: now,
        updatedAt: now,
      );
      await tester.pumpWidget(
        MaterialApp(home: ColonyFormPage(colony: colony)),
      );
      final sourceField = find.widgetWithText(TextFormField, '来源（可选）');
      await tester.scrollUntilVisible(
        sourceField,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(sourceField, example.detail);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      for (final type in ['野采', '网购', example.type]) {
        await tester.tap(find.byTooltip('选择来源'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(PopupMenuItem<String>, type));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(sourceField).controller!.text,
          example.detail,
        );
      }
      final input = find.descendant(
        of: sourceField,
        matching: find.byType(EditableText),
      );
      final selector = find.byTooltip('选择来源');
      expect(
        tester.getSize(input).width,
        greaterThan(tester.getSize(selector).width),
      );
      expect(tester.takeException(), isNull);
      await tapSave(tester, '保存蚁群');
      final saved = (await AppDatabase.instance.findColony(colony.id))!;
      expect(saved.source, '${example.type}（${example.detail}）');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MaterialApp(home: ColonyFormPage(colony: saved)));
      await tester.scrollUntilVisible(
        sourceField,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextFormField>(sourceField).controller!.text,
        example.detail,
      );
      expect(find.text(example.type), findsOneWidget);
    });
  }

  for (final source in ['网购 蚂蚁商户', '野采', '自定义来源', null]) {
    testWidgets('colony source preserves unchanged legacy value $source', (
      tester,
    ) async {
      final now = DateTime.now();
      final colony = Colony(
        id: 'legacy-source',
        name: '旧来源',
        queenCount: 1,
        initialWorkerCount: 0,
        source: source,
        createdAt: now,
        updatedAt: now,
      );
      await tester.pumpWidget(
        MaterialApp(home: ColonyFormPage(colony: colony)),
      );
      await tapSave(tester, '保存蚁群');
      expect(
        (await AppDatabase.instance.findColony(colony.id))!.source,
        source,
      );
    });
  }

  for (final species in ['黑金弓背蚁', '费氏弓背蚁（黑金弓背蚁）', '无恶齿收获蚁', null]) {
    testWidgets('colony encyclopedia entry resolves $species', (tester) async {
      final now = DateTime.now();
      await AppDatabase.instance.saveColony(
        Colony(
          id: 'encyclopedia-colony',
          name: '百科跳转测试',
          species: species,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: ColonyDetailPage(colonyId: 'encyclopedia-colony'),
        ),
      );
      await tester.pumpAndSettle();
      if (species == null) {
        expect(find.text('百科'), findsNothing);
        return;
      }
      await tester.ensureVisible(find.text('百科'));
      await tester.tap(find.text('百科'));
      await tester.pumpAndSettle();
      if (species != '无恶齿收获蚁') {
        expect(find.byType(SpeciesDetailPage), findsOneWidget);
        expect(
          tester
              .widget<SpeciesDetailPage>(find.byType(SpeciesDetailPage))
              .profile
              .name,
          '费氏弓背蚁',
        );
      } else {
        expect(find.byType(SpeciesEncyclopediaPage), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '无颚齿收获蚁',
        );
        expect(find.text('暂无匹配的物种'), findsOneWidget);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('百科跳转测试'), findsOneWidget);
      expect(
        (await AppDatabase.instance.findColony('encyclopedia-colony'))!.species,
        species,
      );
    });
  }

  testWidgets('new and edited colonies control the shared development path', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
    final selector = find.byType(DropdownButtonFormField<GrowthPath>);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('卵 → 幼 → 工').last);
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('colony-name'));
    await tester.scrollUntilVisible(
      name,
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(name, '模式测试');
    for (final entry in [('蚁后 *', '1'), ('工蚁 *', '2'), ('幼虫', '3')]) {
      final field = find.widgetWithText(TextFormField, entry.$1);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.$2);
    }
    await tapSave(tester, '保存蚁群');
    var colony = Colony.fromMap(tables['colonies']!.single);
    expect(colony.developmentPath, GrowthPath.eggToWorker);
    expect(colony.initialLarvaCount, 3);
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('edit-mode'),
        home: ColonyFormPage(colony: colony),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('卵 → 幼 → 茧 → 工').last);
    await tester.pumpAndSettle();
    await tapSave(tester, '保存蚁群');
    colony = Colony.fromMap(tables['colonies']!.single);
    expect(colony.developmentPath, GrowthPath.eggToCocoonToWorker);
    expect(colony.initialLarvaCount, 3);
  });

  testWidgets('record increments default on and can be switched to totals', (
    tester,
  ) async {
    final now = DateTime.now();
    final colony = Colony(
      id: 'increment-ui',
      name: '增量测试',
      createdAt: now,
      updatedAt: now,
      initialEggCount: 10,
      initialLarvaCount: 5,
      initialCocoonCount: 3,
      initialWorkerCount: 20,
    );
    tables['colonies']!.add(colony.toMap());
    await tester.pumpWidget(
      const MaterialApp(home: ColonyDetailPage(colonyId: 'increment-ui')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, '增量');
    await tester.tap(find.byTooltip('日记设置'));
    await tester.pumpAndSettle();
    await revealSetting(tester, toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, '幼虫数');
    await tester.scrollUntilVisible(
      field,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, '2');
    await tapSave(tester, '保存记录');
    var saved = CareRecord.fromMap(tables['care_records']!.single);
    expect([saved.eggCount, saved.larvaCount], [8, 7]);
    await tester.ensureVisible(find.text('添加记录'));
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('日记设置'));
    await tester.pumpAndSettle();
    await revealSetting(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      field,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, '4');
    await tapSave(tester, '保存记录');
    saved = CareRecord.fromMap(tables['care_records']!.first);
    expect(saved.larvaCount, 4);
    expect(saved.eggCount, isNull);
    expect(find.text('8 卵'), findsOneWidget);
    expect(find.text('4 幼虫'), findsOneWidget);
    expect(find.text('3 茧'), findsOneWidget);
  });

  testWidgets('new care records immediately refresh the colony detail', (
    tester,
  ) async {
    final now = DateTime.now();
    await AppDatabase.instance.saveColony(
      Colony(id: 'test-colony', name: '测试蚁群', createdAt: now, updatedAt: now),
    );
    await tester.pumpWidget(
      const MaterialApp(home: ColonyDetailPage(colonyId: 'test-colony')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '备注'), '测试观察记录');
    await tapSave(tester, '保存记录');
    expect(find.byType(RecordFormPage), findsNothing);
    await tester.scrollUntilVisible(
      find.text('测试观察记录'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('测试观察记录'), findsOneWidget);
    expect(find.text('还没有记录'), findsNothing);
  });

  testWidgets(
    'new inventory items appear immediately and cancellation adds nothing',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: InventoryPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增物品'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '物品名称'), '测试新增物品');
      await tester.tap(
        find.byType(DropdownButtonFormField<InventoryExpiryType>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('按购入后保质期').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '保质期（月）'), '6');
      await tester.tap(find.text('新增'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('测试新增物品'), findsOneWidget);
      await tester.tap(find.text('新增物品'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '物品名称'), '取消的物品');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('取消的物品'), findsNothing);
      expect(tables['inventory_items'], hasLength(1));
      expect(tables['inventory_items']!.single['shelf_life_months'], 6);
    },
  );

  testWidgets('aggregate items expand and purchase children independently', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: InventoryPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增物品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聚合物品'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '一级物品名称'), '5 元蚁巢');
    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    expect(find.text('请至少填写一个子物品'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, '子物品（每行一个）'),
      '干巢\n干巢',
    );
    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    expect(find.text('子物品名称不能重复'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, '子物品（每行一个）'),
      '干巢\n湿巢\n中活动区',
    );
    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tables['inventory_items'], hasLength(3));
    expect(
      tables['inventory_items']!.every((row) => row['group_name'] == '5 元蚁巢'),
      isTrue,
    );
    expect(find.text('推荐 (1)'), findsOneWidget);
    await tester.tap(find.text('5 元蚁巢'));
    await tester.pumpAndSettle();
    expect(find.text('干巢'), findsOneWidget);
    expect(find.text('湿巢'), findsOneWidget);
    expect(find.text('中活动区'), findsOneWidget);
    await tester.tap(find.text('干巢'));
    await tester.pumpAndSettle();
    expect(find.text('5 元蚁巢 · 干巢'), findsOneWidget);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(
      tables['inventory_items']!
          .where((row) => row['purchased'] == 1)
          .single['name'],
      '干巢',
    );
    expect(find.text('已购 (1)'), findsOneWidget);
    expect(find.text('5 元蚁巢 · 已购入'), findsOneWidget);
  });

  testWidgets('inventory purchase changes refresh immediately', (tester) async {
    await AppDatabase.instance.saveInventoryItem(
      InventoryItem(
        id: 'test-item',
        name: '测试物品',
        purchased: false,
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: InventoryPage()));
    await tester.pumpAndSettle();
    expect(find.text('点击添加'), findsOneWidget);
    await tester.tap(find.text('测试物品'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '数量（选填）'), '5');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('已购 (1)'), findsOneWidget);
    expect(find.text('推荐 (1)'), findsOneWidget);
    expect(find.text('测试物品'), findsOneWidget);
    expect(find.text('已购入'), findsOneWidget);
    expect(find.text('暂时没有推荐的物品。'), findsNothing);
    await tester.tap(find.text('已购 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('已购入'), findsOneWidget);
    expect(find.textContaining('数量：'), findsNothing);
  });

  testWidgets(
    'saved feeder records appear immediately and update the summary',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DlcPage())),
      );
      await tester.pumpAndSettle();
      for (final label in ['杜比亚', '樱桃蟑螂', '面包虫', '蛐蛐']) {
        expect(tester.getSize(find.text(label)).height, lessThan(30));
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('杜比亚'));
      await tester.pumpAndSettle();
      expect(find.text('还没有杜比亚记录'), findsOneWidget);

      for (final count in ['100', '90']) {
        await tester.tap(find.text('添加记录'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '幼体/若虫数量'),
          count,
        );
        await tester.enterText(find.widgetWithText(TextField, '成体数量'), '20');
        await tester.scrollUntilVisible(
          find.text('保存记录'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('保存记录'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join('\n'),
        );
        expect(find.byType(FeederRecordFormPage), findsNothing);
        expect(find.text('幼体/若虫 $count · 成体 20'), findsOneWidget);
      }
      expect(find.text('幼体/若虫 100 · 成体 20'), findsOneWidget);
      expect(records, hasLength(2));

      await tester.tap(find.text('添加记录'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(records, hasLength(2));
      expect(find.text('幼体/若虫 90 · 成体 20'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('110 只'), findsOneWidget);
      expect(find.text('暂未记录'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
}
