import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/backup_logic.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/nest_entry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase.instance;
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-nests-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await database.open();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // SQLite can retain the file handle until the test process exits on Windows.
    }
  });

  final now = DateTime(2026, 10, 11);
  Map<String, dynamic> oldSnapshot() => {
    'colonies': [
      Colony(
        id: 'colony',
        name: '测试蚁群',
        nestType: '试管巢',
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    ],
    'care_records': <Map<String, Object?>>[],
    'memorials': <Map<String, Object?>>[],
  };

  setUp(() async => database.replaceAll(oldSnapshot()));

  test(
    'old data keeps a current nest without inventing its start date',
    () async {
      final entries = await database.listNestEntries('colony');
      expect(entries, hasLength(1));
      expect(entries.single.nestType, '试管巢');
      expect(entries.single.startedOn, isNull);
      expect(entries.single.isCurrent, isTrue);
    },
  );

  test(
    'editing current nest updates profile; deleting it clears current type',
    () async {
      final old = (await database.listNestEntries('colony')).single;
      final newNest = NestEntry(
        id: 'new-nest',
        colonyId: 'colony',
        nestType: '石膏巢',
        name: '主巢',
        startedOn: now,
        createdAt: now,
        isCurrent: true,
      );
      await database.saveNestEntry(newNest);
      expect((await database.findColony('colony'))!.nestType, '石膏巢');
      expect(
        (await database.listNestEntries('colony'))
            .where((entry) => entry.isCurrent)
            .single
            .id,
        'new-nest',
      );
      await database.deleteNestEntry(newNest);
      expect((await database.findColony('colony'))!.nestType, isNull);
      expect((await database.listNestEntries('colony')).single.id, old.id);
    },
  );

  test('editing the colony nest type adds a history entry', () async {
    final original = (await database.listNestEntries('colony')).single;
    await database.saveColony(
      Colony(
        id: 'colony',
        name: '测试蚁群',
        nestType: '石膏巢',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final entries = await database.listNestEntries('colony');
    expect(entries, hasLength(2));
    expect(entries.where((entry) => entry.isCurrent).single.nestType, '石膏巢');
    expect(
      entries.singleWhere((entry) => entry.id == original.id).isCurrent,
      isFalse,
    );
  });

  test(
    'nest history survives snapshot restore and validates references',
    () async {
      await database.saveNestEntry(
        NestEntry(
          id: 'older',
          colonyId: 'colony',
          nestType: '亚克力巢',
          startedOn: DateTime(2025, 2, 1),
          createdAt: now,
        ),
      );
      final saved = await database.snapshot();
      BackupData.validate(saved);
      await database.replaceAll(oldSnapshot());
      await database.replaceAll(saved);
      expect((await database.listNestEntries('colony')).length, 2);

      final invalid = Map<String, dynamic>.from(saved);
      invalid['nest_entries'] = [
        {
          ...(saved['nest_entries'] as List).first as Map,
          'colony_id': 'missing',
        },
      ];
      expect(() => BackupData.validate(invalid), throwsFormatException);
    },
  );

  test(
    'incremental restore keeps the local current nest and imports history',
    () async {
      final current = await database.snapshot();
      final local = (current['nest_entries'] as List).single as Map;
      final incoming = Map<String, dynamic>.from(current);
      incoming['colonies'] = [
        Colony(
          id: 'colony',
          name: '测试蚁群',
          nestType: '石膏巢',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      ];
      incoming['nest_entries'] = [
        NestEntry(
          id: 'imported-current',
          colonyId: 'colony',
          nestType: '石膏巢',
          createdAt: now,
          isCurrent: true,
        ).toMap(),
      ];
      final probe = _BackupProbe();
      final (merged, _) = probe.mergeMissing<Object>(current, incoming, {});
      BackupData.validate(merged);
      await database.replaceAll(merged);
      final entries = await database.listNestEntries('colony');
      expect(entries, hasLength(2));
      expect(entries.singleWhere((entry) => entry.isCurrent).id, local['id']);
      expect(
        entries
            .singleWhere((entry) => entry.id == 'imported-current')
            .isCurrent,
        isFalse,
      );
      expect((await database.findColony('colony'))!.nestType, '试管巢');

      final (again, _) = probe.mergeMissing<Object>(merged, incoming, {});
      expect(again['nest_entries'], hasLength(2));
    },
  );

  test(
    'incremental restore preserves the current nest of a new colony',
    () async {
      final current = await database.snapshot();
      final incoming = Map<String, dynamic>.from(current);
      incoming['colonies'] = [
        Colony(
          id: 'imported-colony',
          name: '导入蚁群',
          nestType: '石膏巢',
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      ];
      incoming['nest_entries'] = [
        NestEntry(
          id: 'imported-current',
          colonyId: 'imported-colony',
          nestType: '石膏巢',
          createdAt: now,
          isCurrent: true,
        ).toMap(),
      ];
      final (merged, _) = _BackupProbe().mergeMissing<Object>(
        current,
        incoming,
        {},
      );
      BackupData.validate(merged);
      await database.replaceAll(merged);
      expect(
        (await database.listNestEntries('imported-colony')).single.isCurrent,
        isTrue,
      );
    },
  );
}

class _BackupProbe with BackupLogic {
  @override
  AppDatabase get database => AppDatabase.instance;
}
