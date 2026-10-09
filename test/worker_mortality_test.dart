import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = AppDatabase.instance;
  final at = DateTime(2026, 1, 1);
  final colony = Colony(
    id: 'colony',
    name: '测试',
    createdAt: at,
    updatedAt: at,
    queenCount: 1,
    initialWorkerCount: 100,
  );
  CareRecord record(int? deaths) => CareRecord(
    id: 'record',
    colonyId: colony.id,
    type: CareRecordType.mortality,
    occurredAt: at,
    createdAt: at,
    workerMortalityCount: deaths,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-mortality-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await Directory('${directory.path}/antkeep').create();
    final legacy = await openDatabase(
      '${directory.path}/antkeep/antkeep.sqlite',
      version: 16,
      onCreate: (database, _) async {
        for (final sql in _version16Tables) {
          await database.execute(sql);
        }
      },
    );
    await legacy.insert('colonies', colony.toMap());
    await legacy.insert(
      'care_records',
      record(null).toMap()
        ..remove('worker_mortality_count')
        ..remove('auto_growth_rule_json')
        ..remove('feeding_food')
        ..remove('feeding_amount')
        ..remove('feeding_response')
        ..remove('feeding_leftovers'),
    );
    await legacy.close();
    await db.open();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test(
    'v16 upgrade preserves diary; counts and old backups survive restore',
    () async {
      expect(
        (await db.listRecords(colony.id)).single.workerMortalityCount,
        isNull,
      );
      for (final count in [0, 3, 1000000, null]) {
        await db.updateRecord(record(count));
        expect(
          (await db.listRecords(colony.id)).single.workerMortalityCount,
          count,
        );
        final snapshot = await db.snapshot();
        BackupData.validate(snapshot);
        await db.replaceAll(snapshot);
        expect(
          (await db.listRecords(colony.id)).single.workerMortalityCount,
          count,
        );
      }
      final old = await db.snapshot();
      old['care_records'] = [
        Map<String, Object?>.from((old['care_records'] as List).single as Map)
          ..remove('worker_mortality_count'),
      ];
      BackupData.validate(old);
      await db.replaceAll(old);
      expect(
        (await db.listRecords(colony.id)).single.workerMortalityCount,
        isNull,
      );
      for (final invalid in [-1, 1000001, 1.5, '3']) {
        final snapshot = await db.snapshot();
        snapshot['care_records'] = [
          Map<String, Object?>.from(
            (snapshot['care_records'] as List).single as Map,
          )..['worker_mortality_count'] = invalid,
        ];
        expect(() => BackupData.validate(snapshot), throwsFormatException);
      }
      await db.deleteRecord(record(null));
      await db.saveRecord(record(7), incremental: true);
      expect((await db.listRecords(colony.id)).single.workerMortalityCount, 7);
      expect((await db.listRecords(colony.id)).single.workerCount, isNull);
    },
  );

  test('death counts replay after database edit, restore, type change and deletion', () async {
    final known = Colony.fromMap({
      ...colony.toMap(),
      'id': 'known-population',
      'initial_worker_count': 100,
    });
    await db.saveColony(known);
    CareRecord event(int deaths) => CareRecord.fromMap({
      ...record(deaths).toMap(),
      'id': 'known-death',
      'colony_id': known.id,
    });
    Future<int?> workers() async =>
        known.currentWorkerCount(await db.listRecords(known.id));
    await db.saveRecord(event(3), incremental: true);
    expect(await workers(), 97);
    await db.updateRecord(event(5));
    expect(await workers(), 95);
    final snapshot = await db.snapshot();
    BackupData.validate(snapshot);
    await db.replaceAll(snapshot);
    expect(await workers(), 95);
    await db.updateRecord(
      CareRecord.fromMap({
        ...event(5).toMap(),
        'record_type': CareRecordType.observation.storageValue,
        'worker_mortality_count': null,
      }),
    );
    expect(await workers(), 100);
    await db.updateRecord(event(5));
    await db.deleteRecord(event(5));
    expect(await workers(), 100);
    await db.deleteColony(known.id);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byTooltip('保存记录'));
    await settle(tester);
  }

  final deaths = find.widgetWithText(TextField, '工蚁死亡数量');

  testWidgets('new diary defaults to date only and keeps top save fixed', (
    tester,
  ) async {
    await tester.runAsync(() => db.deleteRecord(record(null)));
    await tester.pumpWidget(MaterialApp(home: RecordFormPage(colony: colony)));

    expect(find.textContaining('发生日期：'), findsOneWidget);
    expect(find.text('仅记录日期'), findsOneWidget);
    expect(find.byTooltip('日记设置'), findsOneWidget);
    expect(find.text('具体时间：'), findsNothing);
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    expect(find.byTooltip('保存记录'), findsOneWidget);

    await tester.tap(find.byTooltip('保存记录'));
    await settle(tester);

    final saved = await tester.runAsync(() => db.listRecords(colony.id));
    expect(saved!.single.occurredAt.hour, 0);
    expect(saved.single.occurredAt.minute, 0);
    await tester.runAsync(() => db.deleteRecord(saved.single));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden by default, death input validates and saves', (
    tester,
  ) async {
    await tester.runAsync(() => db.deleteRecord(record(null)));
    await tester.pumpWidget(MaterialApp(home: RecordFormPage(colony: colony)));
    expect(deaths, findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '死亡'));
    await tester.pumpAndSettle();
    expect(deaths, findsOneWidget);
    await tester.enterText(deaths, '-1');
    await save(tester);
    expect(find.textContaining('数量请输入 0～1000000 的整数'), findsOneWidget);
    expect(await tester.runAsync(() => db.listRecords(colony.id)), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      deaths,
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(deaths, '3');
    await save(tester);
    final saved = await tester.runAsync(() => db.listRecords(colony.id));
    expect(saved!.single.workerMortalityCount, 3);
    expect(colony.currentWorkerCount(saved), 97);
    expect(saved.single.type, CareRecordType.mortality);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('edit fills death count and changing type clears it on save', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db.deleteColony(colony.id);
      await db.saveColony(colony);
      await db.saveRecord(record(3));
    });
    final saved = (await tester.runAsync(() => db.listRecords(colony.id)))!
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordFormPage(colony: colony, record: saved),
      ),
    );
    expect(tester.widget<TextField>(deaths).controller!.text, '3');
    await tester.enterText(deaths, '5');
    await save(tester);
    expect(
      (await tester.runAsync(() => db.listRecords(colony.id)))!
          .single
          .workerMortalityCount,
      5,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    final edited = (await tester.runAsync(() => db.listRecords(colony.id)))!
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordFormPage(colony: colony, record: edited),
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '观察'));
    await tester.pumpAndSettle();
    expect(deaths, findsNothing);
    await save(tester);
    final changed = (await tester.runAsync(() => db.listRecords(colony.id)))!
        .single;
    expect(changed.type, CareRecordType.observation);
    expect(changed.workerMortalityCount, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'colony detail shows death chart and refreshes after diary edits and deletion',
    (tester) async {
      final today = DateTime.now();
      final earlier = DateTime(today.year, today.month, today.day - 10);
      final recent = DateTime(today.year, today.month, today.day - 1);
      await tester.runAsync(() async {
        await db.deleteColony(colony.id);
        await db.saveColony(colony);
        await db.saveRecord(
          CareRecord.fromMap({
            ...record(1).toMap(),
            'id': 'earlier',
            'occurred_at': earlier.toIso8601String(),
          }),
        );
        await db.saveRecord(
          CareRecord.fromMap({
            ...record(3).toMap(),
            'occurred_at': recent.toIso8601String(),
          }),
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: ColonyDetailPage(colonyId: colony.id)),
      );
      await settle(tester);
      final card = find.byKey(const ValueKey('colony-mortality-analysis'));
      Future<void> showCard(int workers) async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await settle(tester);
        expect(find.text('$workers 工蚁'), findsOneWidget);
        await tester.scrollUntilVisible(
          card,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await settle(tester);
      }

      await showCard(96);
      expect(
        find.descendant(of: card, matching: find.text('每日工蚁死亡数量')),
        findsNothing,
      );
      expect(tester.getSize(card).height, lessThanOrEqualTo(56));
      await tester.ensureVisible(find.byTooltip('展开死亡分析'));
      await settle(tester);
      await tester.tap(find.byTooltip('展开死亡分析'));
      await settle(tester);
      expect(
        find.descendant(of: card, matching: find.text('每日工蚁死亡数量')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('已记录死亡量上升')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('最近 7 日 · 3 只 · 已记录 1/7 天'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('折叠死亡分析'));
      await settle(tester);
      await tester.tap(find.byTooltip('折叠死亡分析'));
      await settle(tester);
      expect(
        find.descendant(of: card, matching: find.text('每日工蚁死亡数量')),
        findsNothing,
      );
      expect(tester.getSize(card).height, lessThanOrEqualTo(56));
      await tester.ensureVisible(find.byTooltip('展开死亡分析'));
      await settle(tester);
      await tester.tap(find.byTooltip('展开死亡分析'));
      await settle(tester);
      expect(
        find.descendant(of: card, matching: find.text('每日工蚁死亡数量')),
        findsOneWidget,
      );
      final diary = find.byKey(const ValueKey('record'));
      await tester.scrollUntilVisible(
        diary,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(diary);
      await settle(tester);
      await tester.enterText(deaths, '5');
      await save(tester);
      await showCard(94);
      expect(
        find.descendant(
          of: card,
          matching: find.text('最近 7 日 · 5 只 · 已记录 1/7 天'),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        diary,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.drag(diary, const Offset(-180, 0));
      await settle(tester);
      await tester.tap(find.text('删除'));
      await settle(tester);
      await tester.tap(find.text('确认删除'));
      await settle(tester);
      await showCard(99);
      expect(
        find.descendant(of: card, matching: find.text('数据不足，暂无法比较')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('最近 7 日 · 0 只 · 已记录 0/7 天'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

// Frozen schema fixture for upgrading an existing v16 database.
const _version16Tables = [
  '''CREATE TABLE colonies (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, species TEXT, acquired_on TEXT,
      source TEXT, queen_count INTEGER, initial_worker_count INTEGER,
      purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0),
      specialized_count INTEGER, show_specialized INTEGER NOT NULL DEFAULT 0,
      initial_egg_count INTEGER, initial_cocoon_count INTEGER, auto_growth_json TEXT,
      initial_larva_count INTEGER, development_path TEXT,
      nest_type TEXT, target_temperature_lower REAL, target_temperature REAL,
      target_humidity_lower REAL, target_humidity REAL, cover_photo_path TEXT,
      archived INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''',
  '''CREATE TABLE care_records (
      id TEXT PRIMARY KEY, colony_id TEXT NOT NULL, record_type TEXT NOT NULL,
      occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
      egg_count INTEGER, larva_count INTEGER, pupa_count INTEGER, worker_count INTEGER,
      photos_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL,
      FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE CASCADE
    )''',
  '''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )''',
  '''CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, group_name TEXT,
        purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
        expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
        purchased_at TEXT, expires_at TEXT,
        quantity INTEGER CHECK (quantity >= 0),
        purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0)
      )''',
  '''CREATE TABLE feeder_records (
      id TEXT PRIMARY KEY, feeder_type TEXT NOT NULL, record_type TEXT NOT NULL,
      occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
      juvenile_count INTEGER, adult_count INTEGER, mortality_count INTEGER,
      purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0),
      created_at TEXT NOT NULL
    )''',
];
