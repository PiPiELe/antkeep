import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/domain/memorial.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('version 18 preserves memorials, links and unique endings and accepts brood', () async {
    final directory = await Directory.systemTemp.createTemp('antkeep-v18-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await directory.delete(recursive: true);
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final now = DateTime(2026, 10, 2);
    final legacy = [
      for (final kind in [
        MemorialKind.queen,
        MemorialKind.worker,
        MemorialKind.colony,
      ])
        Memorial(
          id: kind.name,
          kind: kind,
          name: '旧纪念 ${kind.name}',
          colonyId: 'legacy',
          species: '收获蚁',
          diedOn: now,
          farewell: '再见',
          cause: '未知',
          observation: '最后观察',
          lesson: '经验',
          createdAt: now,
        ).toMap(),
    ];
    final path = await applicationDatabasePath();
    final old = await openDatabase(
      path,
      version: 18,
      onCreate: (db, _) async {
        // Version 20 adds a column to this pre-existing diary table.
        await db.execute('CREATE TABLE care_records (id TEXT PRIMARY KEY)');
        await db.execute('''CREATE TABLE colonies (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, archived INTEGER NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )''');
        await db.execute('''CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, group_name TEXT,
        purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
        expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
        purchased_at TEXT, expires_at TEXT, quantity INTEGER, purchase_price_cents INTEGER
      )''');
        await db.execute('''CREATE TABLE memorials (
        id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('queen', 'worker', 'colony')),
        name TEXT NOT NULL, colony_id TEXT, species TEXT, died_on TEXT,
        farewell TEXT, cause TEXT, observation TEXT, lesson TEXT, created_at TEXT NOT NULL,
        FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE SET NULL
      )''');
        await db.execute(
          "CREATE UNIQUE INDEX memorial_colony_end ON memorials(colony_id) WHERE kind = 'colony'",
        );
        await db.insert('colonies', {
          'id': 'legacy',
          'name': '旧蚁群',
          'archived': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        for (final row in legacy) {
          await db.insert('memorials', row);
        }
      },
    );
    await old.close();

    final repository = AppDatabase.instance;
    await repository.open();
    final saved = await repository.listMemorials();
    for (final row in legacy) {
      expect(saved.singleWhere((m) => m.id == row['id']).toMap(), row);
    }
    await repository.saveMemorial(
      Memorial(
        id: 'brood',
        kind: MemorialKind.brood,
        name: '未羽化的小生命',
        colonyId: 'legacy',
        createdAt: now,
      ),
    );
    final database = await openDatabase(
      path,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    try {
      expect(await database.getVersion(), 21);
      expect(await database.query('memorials'), hasLength(4));
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(
        database.insert('memorials', {
          ...legacy.last,
          'id': 'duplicate-ending',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('memorials', {
          ...legacy.first,
          'id': 'invalid-type',
          'kind': 'invalid',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await database.delete('colonies', where: 'id = ?', whereArgs: ['legacy']);
      expect(
        (await database.query('memorials'))
            .every((row) => row['colony_id'] == null),
        isTrue,
      );
    } finally {
      await database.close();
    }
  });
}
