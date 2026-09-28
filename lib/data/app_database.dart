import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

abstract class AntKeepRepository {
  Future<List<Colony>> listColonies();
  Future<Colony?> findColony(String id);
  Future<void> saveColony(Colony colony);
  Future<List<CareRecord>> listRecords(String colonyId);
  Future<List<CareRecord>> listRecentRecords();
  Future<void> saveRecord(CareRecord record);
}

class AppDatabase implements AntKeepRepository {
  AppDatabase._();
  static final instance = AppDatabase._();
  Database? _database;

  Future<void> open() async {
    if (_database != null) return;
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'antkeep'));
    await directory.create(recursive: true);
    _database = await openDatabase(
      path.join(directory.path, 'antkeep.sqlite'),
      version: 4,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  Database get _db =>
      _database ?? (throw StateError('Database has not been opened.'));

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''CREATE TABLE colonies (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, species TEXT, acquired_on TEXT,
      source TEXT, queen_count INTEGER, initial_worker_count INTEGER,
      nest_type TEXT, target_temperature REAL, target_humidity REAL, cover_photo_path TEXT,
      archived INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
    await database.execute('''CREATE TABLE care_records (
      id TEXT PRIMARY KEY, colony_id TEXT NOT NULL, record_type TEXT NOT NULL,
      occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
      egg_count INTEGER, larva_count INTEGER, pupa_count INTEGER, worker_count INTEGER,
      photos_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL,
      FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE CASCADE
    )''');
    await database.execute(
      'CREATE INDEX records_by_colony_time ON care_records(colony_id, occurred_at DESC)',
    );
    await _createSettingsTable(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createSettingsTable(database);
    }
    if (oldVersion < 3) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN initial_worker_count INTEGER',
      );
    }
    if (oldVersion < 4) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN target_temperature REAL',
      );
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN target_humidity REAL',
      );
    }
  }

  static Future<void> _createSettingsTable(DatabaseExecutor executor) =>
      executor.execute('''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )''');

  @override
  Future<List<Colony>> listColonies() async => (await _db.query(
    'colonies',
    where: 'archived = 0',
    orderBy: 'updated_at DESC',
  )).map(Colony.fromMap).toList();

  @override
  Future<Colony?> findColony(String id) async {
    final rows = await _db.query('colonies', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Colony.fromMap(rows.single);
  }

  @override
  Future<void> saveColony(Colony colony) => _db.insert(
    'colonies',
    colony.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<List<CareRecord>> listRecords(String colonyId) async =>
      (await _db.query(
        'care_records',
        where: 'colony_id = ?',
        whereArgs: [colonyId],
        orderBy: 'occurred_at DESC',
      )).map(CareRecord.fromMap).toList();

  @override
  Future<List<CareRecord>> listRecentRecords() async => (await _db.query(
    'care_records',
    orderBy: 'occurred_at DESC',
    limit: 50,
  )).map(CareRecord.fromMap).toList();

  @override
  Future<void> saveRecord(CareRecord record) =>
      _db.transaction((transaction) async {
        await transaction.insert('care_records', record.toMap());
        await transaction.update(
          'colonies',
          {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [record.colonyId],
        );
      });

  Future<bool> isDarkThemeEnabled() async {
    final rows = await _db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['dark_theme'],
    );
    return rows.isNotEmpty && rows.single['setting_value'] == 'true';
  }

  Future<void> setDarkThemeEnabled(bool enabled) => _db.insert('app_settings', {
    'setting_key': 'dark_theme',
    'setting_value': '$enabled',
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, dynamic>> snapshot() async => {
    'colonies': await _db.query('colonies'),
    'care_records': await _db.query('care_records'),
  };

  Set<String> photoPaths(Map<String, dynamic> snapshot) {
    final paths = <String>{};
    for (final entry in snapshot['colonies'] as List<dynamic>) {
      final cover = (entry as Map)['cover_photo_path'];
      if (cover is String && cover.isNotEmpty) paths.add(cover);
    }
    for (final entry in snapshot['care_records'] as List<dynamic>) {
      final photos = (entry as Map)['photos_json'];
      if (photos is String && photos.isNotEmpty) {
        paths.addAll((jsonDecode(photos) as List<dynamic>).cast<String>());
      }
    }
    return paths;
  }

  Future<void> replaceAll(Map<String, dynamic> snapshot) async {
    final colonies = (snapshot['colonies'] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    final records = (snapshot['care_records'] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    await _db.transaction((transaction) async {
      await transaction.delete('care_records');
      await transaction.delete('colonies');
      for (final colony in colonies) {
        await transaction.insert('colonies', colony);
      }
      for (final record in records) {
        await transaction.insert('care_records', record);
      }
    });
  }
}
