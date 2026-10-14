import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/backup_data.dart';
import 'package:antkeep/data/database_path.dart';
import 'package:antkeep/domain/milestone.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'version 29 milestone rows survive the nullable colony upgrade',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'antkeep-milestone-v29-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      addTearDown(() async {
        await AppDatabase.instance.close();
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        await directory.delete(recursive: true);
      });
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final app = AppDatabase.instance;
      final date = DateTime(2026, 10, 12);
      await app.open();
      await app.saveColony(
        Colony(id: 'colony', name: '旧蚁群', createdAt: date, updatedAt: date),
      );
      await app.saveMilestone(
        Milestone(
          id: 'old',
          colonyId: 'colony',
          title: '旧版里程碑',
          occurredAt: date,
          createdAt: date,
        ),
      );
      await app.close();

      final path = await applicationDatabasePath();
      final old = await openDatabase(path);
      await old.execute('''CREATE TABLE milestones_v29 (
      id TEXT PRIMARY KEY, colony_id TEXT NOT NULL, title TEXT NOT NULL,
      occurred_at TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL,
      FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE CASCADE
    )''');
      await old.execute(
        '''INSERT INTO milestones_v29
      SELECT id, colony_id, title, occurred_at, note, created_at FROM milestones''',
      );
      await old.execute('DROP TABLE milestones');
      await old.execute('ALTER TABLE milestones_v29 RENAME TO milestones');
      await old.setVersion(29);
      await old.close();

      await app.open();
      expect((await app.listMilestones('colony')).single.title, '旧版里程碑');
      await app.saveMilestone(
        Milestone(id: 'new', title: '独立里程碑', occurredAt: date, createdAt: date),
      );
      final snapshot = await app.snapshot();
      BackupData.validate(snapshot);
      expect((await app.listAllMilestones()).length, 2);
      await app.close();
      final upgraded = await openDatabase(path);
      expect(await upgraded.getVersion(), 30);
      expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await upgraded.close();
    },
  );
}
