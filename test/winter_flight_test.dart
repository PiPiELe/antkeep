import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/backup_logic.dart';
import 'package:antkeep/domain/flight_observation.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/winter_cycle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.instance;
  late Directory directory;
  final now = DateTime(2026, 10, 11);

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-winter-flight-');
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
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // SQLite may hold the database file until the test process exits on Windows.
    }
  });

  setUp(
    () async => db.replaceAll({
      'colonies': [
        Colony(id: 'c', name: '测试蚁群', createdAt: now, updatedAt: now).toMap(),
      ],
      'care_records': <Map<String, Object?>>[],
      'memorials': <Map<String, Object?>>[],
    }),
  );

  test(
    'only one active winter cycle; ending it preserves history and allows next',
    () async {
      final first = WinterCycle(
        id: 'w1',
        colonyId: 'c',
        startedOn: DateTime(2026, 1),
        plannedEndOn: DateTime(2026, 3),
        createdAt: now,
      );
      await db.saveWinterCycle(first);
      final second = WinterCycle(
        id: 'w2',
        colonyId: 'c',
        startedOn: DateTime(2026, 10),
        createdAt: now,
      );
      await expectLater(db.saveWinterCycle(second), throwsA(isA<Exception>()));
      await db.saveWinterCycle(
        WinterCycle(
          id: 'w1',
          colonyId: 'c',
          startedOn: first.startedOn,
          plannedEndOn: first.plannedEndOn,
          endedOn: DateTime(2026, 3, 15),
          createdAt: now,
        ),
      );
      await db.saveWinterCycle(second);
      expect(await db.listWinterCycles('c'), hasLength(2));
    },
  );

  test(
    'winter and flight records survive snapshot restore and validate',
    () async {
      await db.saveWinterCycle(
        WinterCycle(id: 'w', colonyId: 'c', startedOn: now, createdAt: now),
      );
      await db.saveFlightObservation(
        FlightObservation(
          id: 'f',
          observedAt: now,
          place: '北京',
          species: '弓背蚁',
          count: 2,
          createdAt: now,
        ),
      );
      final snapshot = await db.snapshot();
      BackupData.validate(snapshot);
      await db.replaceAll(snapshot);
      expect((await db.listWinterCycles('c')).single.id, 'w');
      expect((await db.listFlightObservations()).single.place, '北京');
      final invalid = Map<String, dynamic>.from(snapshot);
      invalid['winter_cycles'] = [
        ...snapshot['winter_cycles'] as List,
        {...(snapshot['winter_cycles'] as List).single as Map, 'id': 'other'},
      ];
      expect(() => BackupData.validate(invalid), throwsFormatException);
    },
  );

  test(
    'version 3 imports without new tables; version 4 requires them',
    () async {
      final data = await db.snapshot();
      data.remove('winter_cycles');
      data.remove('flight_observations');
      final probe = _BackupProbe();
      final manifest = <String, dynamic>{
        'format': 'antkeep',
        'version': 3,
        'data': data,
        'media': <String>[],
      };
      probe.validateManifestMap(manifest);
      expect(
        () => probe.validateManifestMap({...manifest, 'version': 4}),
        throwsFormatException,
      );
    },
  );

  test('incremental restore keeps the existing active winter cycle', () async {
    await db.saveWinterCycle(
      WinterCycle(id: 'local', colonyId: 'c', startedOn: now, createdAt: now),
    );
    final current = await db.snapshot();
    final incoming = Map<String, dynamic>.from(current);
    incoming['winter_cycles'] = [
      WinterCycle(
        id: 'remote',
        colonyId: 'c',
        startedOn: now,
        createdAt: now,
      ).toMap(),
    ];
    final (merged, _) = _BackupProbe().mergeMissing<Object>(
      current,
      incoming,
      {},
    );
    expect((merged['winter_cycles'] as List).single['id'], 'local');
  });
}

class _BackupProbe with BackupLogic {
  @override
  AppDatabase get database => AppDatabase.instance;
}
