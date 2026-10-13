import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/backup_logic.dart';
import 'package:antkeep/domain/wild_catch_record.dart';
import 'package:antkeep/wild_catch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
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

  testWidgets('add, edit, and delete a wild catch', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
    await _settleDatabase(tester);
    await tester.tap(find.text('记录战果'));
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

  testWidgets('phone location is optional and requires confirmation', (
    tester,
  ) async {
    final original = GeolocatorPlatform.instance;
    final location = _FakeGeolocator();
    GeolocatorPlatform.instance = location;
    addTearDown(() => GeolocatorPlatform.instance = original);

    await tester.pumpWidget(const MaterialApp(home: WildCatchPage()));
    await _settleDatabase(tester);
    await tester.tap(find.text('记录战果'));
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

  test('version 26 records survive the location column upgrade', () async {
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(
      await applicationDatabasePath(),
    );
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
