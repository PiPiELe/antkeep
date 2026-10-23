import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'version 22 nest type becomes a current entry with unknown start',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-nest-v22-',
      );
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
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // SQLite can retain the file handle until process exit on Windows.
        }
      });
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final old = await openDatabase(
        await applicationDatabasePath(),
        version: 22,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE care_records (id TEXT PRIMARY KEY)');
          await db.execute('''CREATE TABLE care_tasks (
            id TEXT PRIMARY KEY, colony_id TEXT NOT NULL, task_type TEXT NOT NULL,
            interval_days INTEGER NOT NULL, next_due_on TEXT NOT NULL,
            last_completed_on TEXT
          )''');
          await db.execute('''CREATE TABLE colonies (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, nest_type TEXT,
          archived INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )''');
          await db.execute('''CREATE TABLE inventory_items (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, group_name TEXT,
          purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
          expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
          purchased_at TEXT, expires_at TEXT, quantity INTEGER,
          purchase_price_cents INTEGER
        )''');
          await db.execute('''CREATE UNIQUE INDEX inventory_name_in_group
          ON inventory_items(COALESCE(group_name, ''), name)''');
          await db.insert('colonies', {
            'id': 'legacy',
            'name': '旧蚁群',
            'nest_type': '试管巢',
            'created_at': '2026-09-01T00:00:00.000',
            'updated_at': '2026-09-01T00:00:00.000',
          });
        },
      );
      await old.close();

      await AppDatabase.instance.open();
      final entries = await AppDatabase.instance.listNestEntries('legacy');
      expect(entries, hasLength(1));
      expect(entries.single.nestType, '试管巢');
      expect(entries.single.isCurrent, isTrue);
      expect(entries.single.startedOn, isNull);
    },
  );
}
