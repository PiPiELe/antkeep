import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/backup_logic.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/wild_catch_record.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/live_wild_catch_page.dart';
import 'package:antkeep/main.dart' show ColonyFormPage;
import 'package:antkeep/wild_catch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
  final media = LocalMediaStore.instance;
  late Directory directory;
  final now = DateTime(2026, 10, 13);

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-wild-catch-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await db.open();
    await media.initialize();
  });

  tearDownAll(() async {
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  setUp(
    () async => db.replaceAll({
      'colonies': <Map<String, Object?>>[],
      'care_records': <Map<String, Object?>>[],
    }),
  );

  test(
    'wild catches survive backup and old version 5 remains importable',
    () async {
      final record = WildCatchRecord(
        id: 'catch-1',
        caughtAt: now,
        place: '山脚',
        latitude: 31.23456,
        longitude: 121.45678,
        species: const [
          WildCatchSpecies(
            name: '弓背蚁',
            colonies: [
              WildCatchColony(queenCount: 2, workerCount: 0),
              WildCatchColony(queenCount: 1, note: '岩石下'),
            ],
          ),
          WildCatchSpecies(
            name: '收获蚁',
            colonies: [WildCatchColony(queenCount: 1)],
          ),
        ],
        note: '雨后',
        createdAt: now,
      );
      await db.saveWildCatchRecord(record);
      final snapshot = await db.snapshot();
      BackupData.validate(snapshot);
      await db.replaceAll(snapshot);
      expect((await db.listWildCatchRecords()).single.toMap(), record.toMap());

      final probe = _BackupProbe();
      final manifest = <String, dynamic>{
        'format': 'antkeep',
        'version': 6,
        'data': snapshot,
        'media': <String>[],
      };
      probe.validateManifestMap(manifest);
      probe.validateManifestMap({...manifest, 'version': 7});
      final legacyRecord = Map<String, Object?>.from(record.toMap())
        ..remove('latitude')
        ..remove('longitude');
      final legacySnapshot = Map<String, dynamic>.from(snapshot)
        ..['wild_catch_records'] = [legacyRecord];
      BackupData.validate(legacySnapshot);
      await db.replaceAll(legacySnapshot);
      expect((await db.listWildCatchRecords()).single.latitude, isNull);
      final previous = Map<String, dynamic>.from(snapshot)
        ..remove('wild_catch_records');
      probe.validateManifestMap({...manifest, 'version': 5, 'data': previous});
      expect(
        () => probe.validateManifestMap({...manifest, 'data': previous}),
        throwsFormatException,
      );
      final invalid = Map<String, dynamic>.from(snapshot)
        ..['wild_catch_records'] = [
          {
            ...record.toMap(),
            'species_json': '[{"name":"弓背蚁","colonies":[{"queen_count":-1}]}]',
          },
        ];
      expect(() => BackupData.validate(invalid), throwsFormatException);
    },
  );

  test(
    'converted and linked results survive backup with wild catch tags',
    () async {
      final record = WildCatchRecord(
        id: 'catch-linked',
        caughtAt: now,
        place: '山脚',
        species: const [
          WildCatchSpecies(
            name: '弓背蚁',
            colonies: [
              WildCatchColony(queenCount: 1, workerCount: 3),
              WildCatchColony(queenCount: 2),
            ],
          ),
        ],
        createdAt: now,
      );
      final converted = Colony(
        id: 'converted',
        name: '山脚弓背蚁',
        species: '弓背蚁',
        acquiredOn: now,
        source: '野采（山脚）',
        queenCount: 1,
        initialWorkerCount: 3,
        createdAt: now,
        updatedAt: now,
      );
      final existing = Colony(
        id: 'existing',
        name: '已有蚁群',
        source: '蚁友赠送',
        createdAt: now,
        updatedAt: now,
      );
      await db.saveWildCatchRecord(record);
      await db.saveColony(existing);
      await db.linkWildCatchColony(
        recordId: record.id,
        speciesIndex: 0,
        colonyIndex: 0,
        colonyId: converted.id,
        newColony: converted,
      );
      await db.linkWildCatchColony(
        recordId: record.id,
        speciesIndex: 0,
        colonyIndex: 1,
        colonyId: existing.id,
      );
      expect((await db.findColony(converted.id))!.isWildCatch, isTrue);
      expect((await db.findColony(existing.id))!.isWildCatch, isTrue);
      expect((await db.findColony(existing.id))!.source, '蚁友赠送');
      final snapshot = await db.snapshot();
      BackupData.validate(snapshot);
      await db.replaceAll(snapshot);
      expect(
        (await db.listWildCatchRecords()).single.species.single.colonies.map(
          (result) => result.colonyId,
        ),
        [converted.id, existing.id],
      );
      expect((await db.findColony(existing.id))!.isWildCatch, isTrue);
      await expectLater(
        db.linkWildCatchColony(
          recordId: record.id,
          speciesIndex: 0,
          colonyIndex: 0,
          colonyId: existing.id,
        ),
        throwsStateError,
      );
      await db.deleteColony(existing.id);
      final afterDeletion = (await db.listWildCatchRecords()).single;
      expect(
        afterDeletion.species.single.colonies.first.colonyId,
        converted.id,
      );
      expect(afterDeletion.species.single.colonies.last.colonyId, isNull);
    },
  );

  testWidgets(
    'wild catch results can be converted or linked from the summary',
    (tester) async {
      final record = WildCatchRecord(
        id: 'catch-ui',
        caughtAt: now,
        place: '河边',
        species: const [
          WildCatchSpecies(
            name: '收获蚁',
            colonies: [
              WildCatchColony(queenCount: 1, workerCount: 4),
              WildCatchColony(queenCount: 2),
            ],
          ),
        ],
        createdAt: now,
      );
      await tester.runAsync(() async {
        await db.saveWildCatchRecord(record);
        await db.saveColony(
          Colony(
            id: 'existing-ui',
            name: '已有蚁群',
            source: '蚁友赠送',
            createdAt: now,
            updatedAt: now,
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: WildCatchResultsPage(record: record)),
      );
      await tester.tap(find.byTooltip('关联蚁群').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('转换为新蚁群'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建蚁群'));
      await _settleDatabase(tester);
      final linked = (await tester.runAsync(db.listWildCatchRecords))!
          .single
          .species
          .single
          .colonies
          .first
          .colonyId;
      expect(linked, isNotNull);
      final colony = await tester.runAsync(() => db.findColony(linked!));
      expect(colony!.species, '收获蚁');
      expect(colony.queenCount, 1);
      expect(colony.initialWorkerCount, 4);
      expect(colony.isWildCatch, isTrue);
      expect(find.textContaining('已关联蚁群'), findsOneWidget);
      await tester.tap(find.byTooltip('关联蚁群'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关联已有蚁群'));
      await _settleDatabase(tester);
      await tester.tap(find.text('已有蚁群'));
      await _settleDatabase(tester);
      final results = (await tester.runAsync(db.listWildCatchRecords))!
          .single
          .species
          .single
          .colonies;
      expect(results.last.colonyId, 'existing-ui');
      final existing = await tester.runAsync(
        () => db.findColony('existing-ui'),
      );
      expect(existing!.source, '蚁友赠送');
      expect(existing.isWildCatch, isTrue);
      expect(find.textContaining('已关联蚁群'), findsNWidgets(2));
    },
  );

  testWidgets('existing colony can link a wild catch result while editing', (
    tester,
  ) async {
    final colony = Colony(
      id: 'edited-colony',
      name: '已有蚁群',
      createdAt: now,
      updatedAt: now,
    );
    final record = WildCatchRecord(
      id: 'catch-from-edit',
      caughtAt: now,
      place: '河岸',
      species: const [
        WildCatchSpecies(
          name: '弓背蚁',
          colonies: [WildCatchColony(queenCount: 1)],
        ),
      ],
      createdAt: now,
    );
    await tester.runAsync(() async {
      await db.saveColony(colony);
      await db.saveWildCatchRecord(record);
    });
    await tester.pumpWidget(MaterialApp(home: ColonyFormPage(colony: colony)));
    await _settleDatabase(tester);
    await tester.scrollUntilVisible(
      find.text('关联野采战果（可选）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wild-catch-link-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('河岸 · 弓背蚁 · 第 1 群').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存蚁群'));
    await _settleDatabase(tester);
    final saved = (await tester.runAsync(db.listWildCatchRecords))!.single;
    expect(saved.species.single.colonies.single.colonyId, colony.id);
    final edited = (await tester.runAsync(() => db.findColony(colony.id)))!;
    expect(edited.isWildCatch, isTrue);
    expect(edited.queenCount, isNull);
    expect(edited.initialWorkerCount, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: ColonyFormPage(colony: edited)));
    await _settleDatabase(tester);
    await tester.scrollUntilVisible(
      find.textContaining('已关联野采战果：河岸 · 弓背蚁 · 第 1 群'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('关联野采战果（可选）'), findsNothing);
  });

  test('failed wild catch link rolls back the colony edit', () async {
    final colony = Colony(
      id: 'rollback-colony',
      name: '原名',
      createdAt: now,
      updatedAt: now,
    );
    await db.saveColony(colony);
    await db.saveWildCatchRecord(
      WildCatchRecord(
        id: 'already-linked',
        caughtAt: now,
        place: '河岸',
        species: const [
          WildCatchSpecies(
            name: '弓背蚁',
            colonies: [WildCatchColony(colonyId: 'another-colony')],
          ),
        ],
        createdAt: now,
      ),
    );
    await expectLater(
      db.saveColony(
        Colony(id: colony.id, name: '新名', createdAt: now, updatedAt: now),
        wildCatchResult: (
          recordId: 'already-linked',
          speciesIndex: 0,
          colonyIndex: 0,
        ),
      ),
      throwsStateError,
    );
    expect((await db.findColony(colony.id))!.name, '原名');
  });

  testWidgets('add, edit, and delete a wild catch', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
    await _settleDatabase(tester);
    await tester.tap(find.text('补记野采'));
    await tester.pumpAndSettle();
    expect(find.text('记录具体时间'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '野采地点 *'), '山脚');
    await tester.tap(find.text('添加蚁种'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '蚁种名称 *'), '弓背蚁');
    await tester.enterText(find.widgetWithText(TextFormField, '蚁后数量'), '2');
    await tester.ensureVisible(find.text('添加蚁群'));
    await tester.tap(find.text('添加蚁群'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '蚁后数量').at(1),
      '1',
    );
    await tester.ensureVisible(find.text('添加蚁种'));
    await tester.tap(find.text('添加蚁种'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '蚁种名称 *').at(1),
      '收获蚁',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '蚁后数量').at(2),
      '1',
    );
    await tester.tap(find.text('保存记录'));
    await _settleDatabase(tester);
    expect(find.text('山脚'), findsOneWidget);
    expect(find.text('弓背蚁 · 2 群'), findsOneWidget);
    expect(find.text('收获蚁 · 1 群'), findsOneWidget);
    expect(
      (await tester.runAsync(db.listWildCatchRecords))!.single.species
          .map((entry) => entry.colonies.length),
      [2, 1],
    );

    await tester.tap(find.text('山脚'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '蚁后数量').at(1),
      '3',
    );
    await tester.tap(find.text('保存记录'));
    await _settleDatabase(tester);
    expect(
      (await tester.runAsync(db.listWildCatchRecords))!
          .single
          .species
          .first
          .colonies[1]
          .queenCount,
      3,
    );

    await tester.tap(find.byTooltip('删除野采记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await _settleDatabase(tester);
    expect(await tester.runAsync(db.listWildCatchRecords), isEmpty);
  });

  testWidgets('wild catch card keeps long details out of the narrow summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = WildCatchRecord(
      id: 'narrow-card',
      caughtAt: now,
      place: '公司楼下',
      hasSpecificTime: true,
      startedAt: now,
      endedAt: now.add(const Duration(hours: 1)),
      species: const [
        WildCatchSpecies(
          name: '石头蚁群',
          colonies: [WildCatchColony(queenCount: 1, workerCount: 50)],
        ),
      ],
      note: '跟随蚂蚁来到一棵树下，看到入口后又观察了很久，记录附近的环境和路线。',
      latitude: 40.04197,
      longitude: 116.29888,
      createdAt: now,
    );
    await tester.runAsync(() => db.saveWildCatchRecord(record));

    await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
    await _settleDatabase(tester);
    expect(find.text('石头蚁群 · 1 群'), findsOneWidget);
    expect(find.textContaining('第 1 群：'), findsNothing);
    expect(find.byTooltip('管理野采战果'), findsOneWidget);
    expect(find.byTooltip('编辑野采记录'), findsOneWidget);
    expect(find.byTooltip('删除野采记录'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 群：蚁后 1 只'), findsOneWidget);
    expect(find.textContaining('纬度 40.04197'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'start, record events, resume, finish, and view wild catch data',
    (tester) async {
      final image = File('${directory.path}/live-catch.jpg');
      await tester.runAsync(() => image.writeAsBytes([1, 2, 3]));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (_) async => [image.path],
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/image_picker'),
              null,
            ),
      );

      await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
      await _settleDatabase(tester);
      await tester.tap(find.text('开始野采'));
      await tester.pumpAndSettle();
      expect(find.text('野采开始'), findsOneWidget);
      expect(find.byTooltip('获取手机定位（可选）'), findsOneWidget);
      expect(await tester.runAsync(db.listWildCatchRecords), isEmpty);
      await tester.enterText(find.widgetWithText(TextField, '野采地点 *'), '溪边');
      await tester.tap(find.text('确认地点并开始野采'));
      await _settleDatabase(tester);
      var record = (await tester.runAsync(db.listWildCatchRecords))!.single;
      expect(record.isActive, isTrue);
      expect(record.place, '溪边');
      expect(record.events.map((event) => event.action), ['开始']);
      expect(find.text('野采进行中'), findsOneWidget);
      expect(find.widgetWithText(TextField, '野采地点 *'), findsNothing);
      expect(find.text('地点：溪边'), findsWidgets);

      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从图库选择'));
      await _settleDatabase(tester);
      record = (await tester.runAsync(db.listWildCatchRecords))!.single;
      expect(record.photos, hasLength(1));
      expect(record.events.last.photoPaths, record.photos);

      await tester.tap(find.text('记战果'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '蚁种名称（可选）'), '弓背蚁');
      await tester.enterText(find.widgetWithText(TextField, '蚁后数量（可选）'), '1');
      await tester.tap(find.text('记录').last);
      await _settleDatabase(tester);
      record = (await tester.runAsync(db.listWildCatchRecords))!.single;
      expect(record.species.single.name, '弓背蚁');
      expect(record.events.last.action, '战果');

      await tester.tap(find.text('记事件'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '记录此刻发生的事'), '雨停了');
      await tester.tap(find.text('记录').last);
      await _settleDatabase(tester);
      record = (await tester.runAsync(db.listWildCatchRecords))!.single;
      expect(record.events.last.detail, '雨停了');
      expect(find.text('雨停了'), findsOneWidget);

      await tester.tap(find.text('查看当前战果汇总'));
      await tester.pumpAndSettle();
      expect(find.text('野采战果汇总'), findsOneWidget);
      expect(find.text('弓背蚁 · 1 群'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await _settleDatabase(tester);
      await tester.tap(find.text('溪边'));
      await _settleDatabase(tester);
      expect(find.text('野采进行中'), findsOneWidget);
      expect(find.text('地点：溪边'), findsWidgets);

      await tester.tap(find.text('结束野采'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('结束野采').last);
      await _settleDatabase(tester);
      record = (await tester.runAsync(db.listWildCatchRecords))!.single;
      expect(record.endedAt, isNotNull);
      expect(record.events.map((event) => event.action), [
        '开始',
        '照片',
        '战果',
        '备注',
        '结束',
      ]);
      expect(find.text('野采结束'), findsOneWidget);
      await tester.tap(find.text('查看本次野采数据'));
      await tester.pumpAndSettle();
      expect(find.text('野采数据'), findsOneWidget);
      expect(find.text('记录时间线'), findsOneWidget);

      final snapshot = (await tester.runAsync(db.snapshot))!;
      BackupData.validate(snapshot);
      await tester.runAsync(() => db.replaceAll(snapshot));
      expect(
        (await tester.runAsync(db.listWildCatchRecords))!.single.events.length,
        5,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await _settleDatabase(tester);
      await tester.tap(find.byTooltip('编辑野采记录'));
      await tester.pumpAndSettle();
      expect(find.text('野采日期'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, '野采地点 *'),
        '新溪边',
      );
      await tester.tap(find.text('保存记录'));
      await _settleDatabase(tester);
      final revised = (await tester.runAsync(db.listWildCatchRecords))!.single;
      expect(revised.startedAt, record.startedAt);
      expect(revised.endedAt, record.endedAt);
      expect(revised.events.last.action, '修订');
    },
  );

  testWidgets('live catch can save without species or select one', (
    tester,
  ) async {
    final started = DateTime.now().subtract(const Duration(minutes: 1));
    final record = WildCatchRecord(
      id: 'optional-species',
      caughtAt: started,
      place: '溪边',
      species: const [],
      startedAt: started,
      createdAt: started,
    );
    await tester.pumpWidget(
      MaterialApp(home: LiveWildCatchPage(initialRecord: record)),
    );

    await tester.tap(find.text('记战果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录').last);
    await _settleDatabase(tester);
    var saved = (await tester.runAsync(db.listWildCatchRecords))!.single;
    expect(saved.species.single.name, isEmpty);
    expect(saved.species.single.displayName, '未填写品种');
    expect(WildCatchRecord.fromMap(saved.toMap()).species.single.name, isEmpty);
    expect(find.text('未填写品种'), findsOneWidget);

    await tester.tap(find.text('记战果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从品种库选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('弓背蚁').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '尼科巴弓背蚁');
    await tester.pumpAndSettle();
    await tester.tap(find.text('尼科巴弓背蚁').last);
    await tester.pumpAndSettle();
    expect(find.text('尼科巴弓背蚁'), findsOneWidget);
    await tester.tap(find.text('记录').last);
    await _settleDatabase(tester);
    saved = (await tester.runAsync(db.listWildCatchRecords))!.single;
    expect(saved.species.map((entry) => entry.name), ['', '尼科巴弓背蚁']);
    expect(find.text('尼科巴弓背蚁'), findsOneWidget);
    expect(find.text('采获 1 群'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('尼科巴弓背蚁')).dx,
      greaterThan(tester.getTopRight(find.text('战果').first).dx),
    );
    expect(find.textContaining('采获 尼科巴弓背蚁'), findsNothing);
  });

  testWidgets('live photo can be removed from preview after confirmation', (
    tester,
  ) async {
    const photoPath = 'live-photo.png';
    final started = DateTime.now().subtract(const Duration(minutes: 5));
    final record = WildCatchRecord(
      id: 'live-photo',
      caughtAt: started,
      hasSpecificTime: true,
      place: '溪边',
      species: const [],
      photos: const [photoPath],
      startedAt: started,
      createdAt: started,
      events: [
        WildCatchEvent(at: started, action: '开始', detail: '地点：溪边'),
        WildCatchEvent(
          at: started.add(const Duration(minutes: 1)),
          action: '照片',
          detail: '添加 1 张野采照片',
          photoPaths: const [photoPath],
        ),
      ],
    );
    await tester.runAsync(() async {
      final bytes = await File('assets/images/default-ant-cover.png')
          .readAsBytes();
      await File('${directory.path}/antkeep/media/$photoPath')
          .writeAsBytes(bytes);
      await db.saveWildCatchRecord(record);
    });

    await tester.pumpWidget(
      MaterialApp(home: LiveWildCatchPage(initialRecord: record)),
    );
    await _settleDatabase(tester);
    expect(find.byTooltip('移除野采照片'), findsNothing);
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('野采照片'), findsOneWidget);
    await tester.tap(find.text('删除照片'));
    await tester.pumpAndSettle();
    expect(find.text('删除这张照片？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(db.listWildCatchRecords))!.single.photos, [
      photoPath,
    ]);

    await tester.tap(find.text('删除照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await _settleDatabase(tester);
    expect(
      (await tester.runAsync(db.listWildCatchRecords))!.single.photos,
      isEmpty,
    );
  });

  testWidgets('phone location is optional and requires confirmation', (
    tester,
  ) async {
    final original = GeolocatorPlatform.instance;
    final location = _FakeGeolocator();
    GeolocatorPlatform.instance = location;
    addTearDown(() => GeolocatorPlatform.instance = original);

    await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
    await _settleDatabase(tester);
    await tester.tap(find.text('补记野采'));
    await tester.pumpAndSettle();
    expect(location.requests, 0);
    await tester.enterText(find.widgetWithText(TextFormField, '野采地点 *'), '河边');
    await tester.tap(find.text('获取手机定位（可选）'));
    await tester.pump();
    await tester.pump();
    expect(find.text('确认当前位置'), findsOneWidget);
    expect(location.requests, 1);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除定位'), findsNothing);

    await tester.tap(find.text('获取手机定位（可选）'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('使用此定位'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除定位'), findsOneWidget);
    await tester.tap(find.text('保存记录'));
    await _settleDatabase(tester);
    final record = (await tester.runAsync(db.listWildCatchRecords))!.single;
    expect(record.place, '河边');
    expect(record.latitude, 31.23456);
    expect(record.longitude, 121.45678);

    await tester.tap(find.text('河边'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除定位'));
    await tester.tap(find.text('保存记录'));
    await _settleDatabase(tester);
    expect(
      (await tester.runAsync(db.listWildCatchRecords))!.single.latitude,
      isNull,
    );
  });

  testWidgets('live catch confirms optional location before the clock starts', (
    tester,
  ) async {
    final original = GeolocatorPlatform.instance;
    final location = _FakeGeolocator();
    GeolocatorPlatform.instance = location;
    addTearDown(() => GeolocatorPlatform.instance = original);

    await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
    await _settleDatabase(tester);
    await tester.tap(find.text('开始野采'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(db.listWildCatchRecords), isEmpty);
    await tester.enterText(find.widgetWithText(TextField, '野采地点 *'), '河岸');
    await tester.tap(find.byTooltip('获取手机定位（可选）'));
    await tester.pump();
    await tester.pump();
    expect(find.text('确认当前位置'), findsOneWidget);
    await tester.tap(find.text('使用此定位'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已确认位置'), findsOneWidget);
    await tester.tap(find.text('确认地点并开始野采'));
    await _settleDatabase(tester);
    final record = (await tester.runAsync(db.listWildCatchRecords))!.single;
    expect(record.place, '河岸');
    expect(record.latitude, 31.23456);
    expect(record.longitude, 121.45678);
    expect(record.startedAt, isNotNull);
    expect(find.widgetWithText(TextField, '野采地点 *'), findsNothing);
  });

  testWidgets('photos belong to the wild catch without a species', (
    tester,
  ) async {
    final first = File('${directory.path}/wild-first.jpg');
    final second = File('${directory.path}/wild-second.jpg');
    await tester.runAsync(() async {
      await first.writeAsBytes([1, 2, 3]);
      await second.writeAsBytes([4, 5, 6]);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (call) async => [first.path, second.path],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            null,
          ),
    );

    await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
    await _settleDatabase(tester);
    await tester.tap(find.text('补记野采'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '野采地点 *'), '河岸');
    await tester.ensureVisible(find.text('添加野采照片'));
    await tester.tap(find.text('添加野采照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从图库选择'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除野采照片'), findsNWidgets(2));
    await tester.tap(find.text('保存记录'));
    await _settleDatabase(tester);

    final saved = (await tester.runAsync(db.listWildCatchRecords))!.single;
    expect(saved.species, isEmpty);
    expect(saved.photos, hasLength(2));
    expect(saved.photos.first, isNot(first.path));
    expect(await tester.runAsync(() => media.readImage(saved.photos.first)), [
      1,
      2,
      3,
    ]);
    expect(find.text('2 张野采照片'), findsOneWidget);

    await tester.tap(find.text('河岸'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除野采照片').first);
    await tester.tap(find.text('保存记录'));
    await _settleDatabase(tester);
    final edited = (await tester.runAsync(db.listWildCatchRecords))!.single;
    expect(edited.photos, [saved.photos.last]);
    await tester.runAsync(() async {
      await expectLater(
        media.readImage(saved.photos.first),
        throwsA(isA<FileSystemException>()),
      );
    });
    expect(await tester.runAsync(() => media.readImage(saved.photos.last)), [
      4,
      5,
      6,
    ]);

    await tester.tap(find.byTooltip('删除野采记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await _settleDatabase(tester);
    expect(await tester.runAsync(db.listWildCatchRecords), isEmpty);
    await tester.runAsync(() async {
      await expectLater(
        media.readImage(saved.photos.last),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  test('version 26 records survive the location column upgrade', () async {
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(
      await applicationDatabasePath(),
    );
    await raw.execute('ALTER TABLE inventory_items DROP COLUMN purpose');
    await raw.execute('ALTER TABLE milestones DROP COLUMN artwork');
    await raw.execute('DROP TABLE wild_catch_records');
    await raw.execute('''CREATE TABLE wild_catch_records (
      id TEXT PRIMARY KEY, caught_at TEXT NOT NULL,
      has_specific_time INTEGER NOT NULL DEFAULT 0,
      place TEXT NOT NULL, species_json TEXT NOT NULL DEFAULT '[]',
      note TEXT, created_at TEXT NOT NULL
    )''');
    await raw.insert('wild_catch_records', {
      'id': 'old-catch',
      'caught_at': now.toIso8601String(),
      'place': '旧地点',
      'created_at': now.toIso8601String(),
    });
    await raw.execute('PRAGMA user_version = 26');
    await raw.close();

    await db.open();
    final record = (await db.listWildCatchRecords()).single;
    expect(record.place, '旧地点');
    expect(record.latitude, isNull);
    await db.saveWildCatchRecord(
      WildCatchRecord(
        id: record.id,
        caughtAt: record.caughtAt,
        place: record.place,
        species: record.species,
        latitude: 31.23456,
        longitude: 121.45678,
        createdAt: record.createdAt,
      ),
    );
    expect((await db.listWildCatchRecords()).single.latitude, 31.23456);
  });

  test('version 27 records gain an empty photo list', () async {
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(
      await applicationDatabasePath(),
    );
    await raw.execute('ALTER TABLE inventory_items DROP COLUMN purpose');
    await raw.execute('ALTER TABLE milestones DROP COLUMN artwork');
    await raw.execute('DROP TABLE wild_catch_records');
    await raw.execute('''CREATE TABLE wild_catch_records (
      id TEXT PRIMARY KEY, caught_at TEXT NOT NULL,
      has_specific_time INTEGER NOT NULL DEFAULT 0,
      place TEXT NOT NULL, species_json TEXT NOT NULL DEFAULT '[]',
      note TEXT, latitude REAL, longitude REAL, created_at TEXT NOT NULL
    )''');
    await raw.insert('wild_catch_records', {
      'id': 'location-catch',
      'caught_at': now.toIso8601String(),
      'place': '旧地点',
      'latitude': 31.23456,
      'longitude': 121.45678,
      'created_at': now.toIso8601String(),
    });
    await raw.execute('PRAGMA user_version = 27');
    await raw.close();

    await db.open();
    final record = (await db.listWildCatchRecords()).single;
    expect(record.latitude, 31.23456);
    expect(record.photos, isEmpty);
  });

  test('version 28 records gain empty live timeline fields', () async {
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(
      await applicationDatabasePath(),
    );
    await raw.execute('ALTER TABLE inventory_items DROP COLUMN purpose');
    await raw.execute('ALTER TABLE milestones DROP COLUMN artwork');
    await raw.execute('DROP TABLE wild_catch_records');
    await raw.execute('''CREATE TABLE wild_catch_records (
      id TEXT PRIMARY KEY, caught_at TEXT NOT NULL,
      has_specific_time INTEGER NOT NULL DEFAULT 0,
      place TEXT NOT NULL, species_json TEXT NOT NULL DEFAULT '[]',
      note TEXT, latitude REAL, longitude REAL,
      photos_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL
    )''');
    await raw.insert('wild_catch_records', {
      'id': 'photo-catch',
      'caught_at': now.toIso8601String(),
      'place': '旧地点',
      'created_at': now.toIso8601String(),
    });
    await raw.execute('PRAGMA user_version = 28');
    await raw.close();

    await db.open();
    final record = (await db.listWildCatchRecords()).single;
    expect(record.isLive, isFalse);
    expect(record.events, isEmpty);
    expect(record.endedAt, isNull);
  });
}

Future<void> _settleDatabase(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
}

class _BackupProbe with BackupLogic {
  @override
  AppDatabase get database => AppDatabase.instance;
}

class _FakeGeolocator extends GeolocatorPlatform {
  int requests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return LocationPermission.whileInUse;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    longitude: 121.45678,
    latitude: 31.23456,
    timestamp: DateTime.now(),
    accuracy: 12,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
