import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tables = <String, List<Map<String, Object?>>>{
    'feeder_records': [],
    'colonies': [],
    'care_records': [],
    'inventory_items': [],
  };
  final records = tables['feeder_records']!;
  late Directory directory;

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
              final table = RegExp(r'UPDATE (\w+)').firstMatch(sql)!.group(1)!;
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
              final records = tables[table]!;
              final columns = sql
                  .substring(sql.indexOf('(') + 1, sql.indexOf(')'))
                  .split(',')
                  .map((column) => column.trim())
                  .toList();
              final values = call.arguments['arguments'] as List<dynamic>;
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

  setUp(() {
    for (final rows in tables.values) {
      rows.clear();
    }
  });

  Future<void> tapSave(WidgetTester tester, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(label),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
  }

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
    expect(find.textContaining('入手日期：'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new colonies appear on returning home without reopening', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    expect(find.text('还没有蚁群'), findsOneWidget);
    for (final name in ['测试蚁群一', '测试蚁群二']) {
      await tester.tap(find.text('新入手蚁群'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '蚁群昵称 *'),
        name,
      );
      await tapSave(tester, '保存蚁群');
      expect(find.byType(ColonyFormPage), findsNothing);
      expect(find.text(name), findsOneWidget);
      expect(find.text('还没有蚁群'), findsNothing);
    }
    expect(find.text('测试蚁群一'), findsOneWidget);
    await tester.tap(find.text('新入手蚁群'));
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
    await tester.tap(find.text('新入手蚁群'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '蚁群昵称 *'),
      '购入价测试',
    );
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
    expect(find.text('购入价 ¥19.99'), findsOneWidget);
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
      expect(
        find.text('购入价 ¥0.00'),
        value.isEmpty ? findsNothing : findsOneWidget,
      );
    }
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

  testWidgets('species selection cascades and only fills an empty name', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
    await tester.pumpAndSettle();
    final familyField = find.widgetWithText(TextFormField, '品种分类');
    final speciesField = find.widgetWithText(TextFormField, '细分品种');
    final nameField = find.widgetWithText(TextFormField, '蚁群昵称 *');
    expect(
      tester.getTopLeft(familyField).dy,
      lessThan(tester.getTopLeft(speciesField).dy),
    );
    expect(
      tester.getTopLeft(speciesField).dy,
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
    await tester.tap(speciesField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('野蛮收获蚁（原生收获蚁）'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(nameField).controller!.text, '我的蚁群');
    await tester.enterText(nameField, '   ');
    await tester.tap(speciesField);
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
      await tester.tap(find.widgetWithText(TextFormField, '品种分类'));
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

  testWidgets('formal and common species names save and reopen together', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColoniesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新入手蚁群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未收录？手动填写品种'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('请至少填写一个名称'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, '学名 / 正式名'),
      ' Camponotus fedtschenkoi ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '通用名（可选）'),
      ' 黑金弓背蚁 ',
    );
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '蚁群昵称 *'),
      '双名称蚁群',
    );
    await tapSave(tester, '保存蚁群');
    final saved = (await AppDatabase.instance.listColonies()).single;
    expect(saved.species, 'Camponotus fedtschenkoi（黑金弓背蚁）');
    expect(Colony.fromMap(saved.toMap()).species, saved.species);
    await tester.tap(find.text('双名称蚁群'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑蚁群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未收录？手动填写品种'));
    await tester.pumpAndSettle();
    expect(find.text('Camponotus fedtschenkoi'), findsOneWidget);
    expect(find.text('黑金弓背蚁'), findsOneWidget);
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
  });

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
      for (final (oldName, formalName, combinedName) in [
        ('黑金弓背蚁', '费氏弓背蚁', '费氏弓背蚁（黑金弓背蚁）'),
        ('原生收获蚁', '野蛮收获蚁', '野蛮收获蚁（原生收获蚁）'),
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
        final field = find.widgetWithText(TextFormField, '细分品种');
        expect(tester.widget<TextFormField>(field).enabled, isTrue);
        expect(find.text(oldName), findsOneWidget);
        await tester.tap(field);
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        );
        for (final query in [oldName, formalName]) {
          await tester.enterText(search, query);
          await tester.pumpAndSettle();
          expect(find.text(combinedName), findsOneWidget);
        }
        await tester.tap(find.text(combinedName));
        await tester.pumpAndSettle();
        expect(find.text(combinedName), findsOneWidget);
        expect(find.text('已有昵称'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'colony summaries combine brood with record and archive fallback',
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
      expect(find.text('1 只蚁后 · 0 只工蚁 · 7 只卵幼茧'), findsOneWidget);
      expect(find.text('新后群'), findsOneWidget);

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
      final summary = find.text('1 只蚁后 · 8 只工蚁 · 5 只卵幼茧');
      expect(summary, findsOneWidget);
      final spans =
          (tester.widget<Text>(summary).textSpan! as TextSpan).children!;
      final quantity = spans.first as TextSpan;
      expect(
        (quantity.children!.first as TextSpan).style!.fontWeight,
        FontWeight.w700,
      );
      expect((quantity.children!.last as TextSpan).style, isNull);
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
        expect(find.text('${entry.key} 只工蚁'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('从新后养起'));
        await tester.pumpAndSettle();
        final scaleCard = find.ancestor(
          of: find.text('群规模'),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: scaleCard, matching: find.text('新后群')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: scaleCard, matching: find.text(entry.value)),
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
    expect(find.text('1 只蚁后 · 10 只工蚁 · 7 只卵幼茧'), findsOneWidget);

    Future<void> edit() async {
      await tester.tap(find.text('特化展示'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑蚁群'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('显示特化'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    await edit();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(find.widgetWithText(TextFormField, '特化数量'), findsNothing);
    await tester.tap(find.text('显示特化'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '特化数量'), '3');
    await tapSave(tester, '保存蚁群');
    expect(find.text('3 只特化'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 只蚁后 · 3 只特化 · 10 只工蚁 · 7 只卵幼茧'), findsOneWidget);

    await edit();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '特化数量'))
          .controller!
          .text,
      '3',
    );
    await tester.tap(find.text('显示特化'));
    await tester.pumpAndSettle();
    await tapSave(tester, '保存蚁群');
    expect(find.text('3 只特化'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 只蚁后 · 10 只工蚁 · 7 只卵幼茧'), findsOneWidget);
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
      source: '蚁友赠送',
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
    final scaleCard = find.ancestor(
      of: find.text('群规模'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: scaleCard, matching: find.text('新后群')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: scaleCard, matching: find.text('1 只蚁后')),
      findsNothing,
    );
    final infoCard = find.ancestor(
      of: find.text('试管巢'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: infoCard, matching: find.text('1 只蚁后')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: infoCard, matching: find.text('0 只工蚁')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('编辑蚁群'));
    await tester.pumpAndSettle();
    expect(find.text('自定义品种'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '蚁群昵称 *'), '编辑后');
    await tester.enterText(
      find.widgetWithText(TextFormField, '初始工蚁数量'),
      '1000',
    );
    await tapSave(tester, '保存蚁群');
    expect(find.text('编辑后'), findsOneWidget);
    expect(find.text('大群'), findsOneWidget);
    final saved = (await AppDatabase.instance.findColony(colony.id))!;
    expect(saved.createdAt, createdAt);
    expect(saved.species, colony.species);
    expect(saved.source, colony.source);
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
    await tester.enterText(
      find.widgetWithText(TextFormField, '蚁群昵称 *'),
      '取消编辑',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('编辑后'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('编辑后'), findsOneWidget);
    expect(find.text('取消编辑'), findsNothing);
    expect(find.text('大群'), findsOneWidget);
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
    await tester.tap(find.text('购买'));
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
    expect(find.text('点击购买'), findsOneWidget);
    await tester.tap(find.text('测试物品'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '数量（选填）'), '5');
    await tester.tap(find.text('购买'));
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
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DlcPage())),
      );
      await tester.pumpAndSettle();
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
