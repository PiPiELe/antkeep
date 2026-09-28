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
      version: 8,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    await _seedInventory();
  }

  Database get _db =>
      _database ?? (throw StateError('Database has not been opened.'));

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''CREATE TABLE colonies (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, species TEXT, acquired_on TEXT,
      source TEXT, queen_count INTEGER, initial_worker_count INTEGER,
      initial_egg_count INTEGER, initial_cocoon_count INTEGER,
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
    await _createInventoryTable(database);
    await _createFeederRecordsTable(database);
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
    if (oldVersion < 5) await _createInventoryTable(database);
    if (oldVersion < 6) await _createFeederRecordsTable(database);
    if (oldVersion < 7) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN initial_egg_count INTEGER',
      );
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN initial_cocoon_count INTEGER',
      );
    }
    if (oldVersion < 8) {
      await database.execute(
        "ALTER TABLE inventory_items ADD COLUMN expiry_type TEXT NOT NULL DEFAULT 'none'",
      );
      await database.execute(
        'ALTER TABLE inventory_items ADD COLUMN shelf_life_months INTEGER',
      );
      await database.execute(
        'ALTER TABLE inventory_items ADD COLUMN purchased_at TEXT',
      );
      await database.execute(
        'ALTER TABLE inventory_items ADD COLUMN expires_at TEXT',
      );
    }
  }

  static Future<void> _createSettingsTable(DatabaseExecutor executor) =>
      executor.execute('''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )''');

  static Future<void> _createInventoryTable(DatabaseExecutor executor) =>
      executor.execute('''CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
        purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
        expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
        purchased_at TEXT, expires_at TEXT
      )''');

  static Future<void> _createFeederRecordsTable(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''CREATE TABLE feeder_records (
      id TEXT PRIMARY KEY, feeder_type TEXT NOT NULL, record_type TEXT NOT NULL,
      occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
      juvenile_count INTEGER, adult_count INTEGER, mortality_count INTEGER,
      created_at TEXT NOT NULL
    )''');
    await executor.execute(
      'CREATE INDEX feeder_records_by_type_time ON feeder_records(feeder_type, occurred_at DESC)',
    );
  }

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

  Future<List<InventoryItem>> listInventory() async => (await _db.query(
    'inventory_items',
    orderBy: 'purchased ASC, name COLLATE NOCASE ASC',
  )).map(InventoryItem.fromMap).toList();

  Future<void> saveInventoryItem(InventoryItem item) => _db.insert(
    'inventory_items',
    item.toMap(),
    conflictAlgorithm: ConflictAlgorithm.abort,
  );

  Future<void> setInventoryPurchased(InventoryItem item, bool purchased) =>
      _db.update(
        'inventory_items',
        {
          'purchased': purchased ? 1 : 0,
          'purchased_at': purchased ? DateTime.now().toIso8601String() : null,
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );

  Future<List<FeederRecord>> listFeederRecords(FeederType feeder) async =>
      (await _db.query(
        'feeder_records',
        where: 'feeder_type = ?',
        whereArgs: [feeder.storageValue],
        orderBy: 'occurred_at DESC',
      )).map(FeederRecord.fromMap).toList();

  Future<void> saveFeederRecord(FeederRecord record) =>
      _db.insert('feeder_records', record.toMap());

  Future<void> _seedInventory() async {
    const items = [
      (name: '防逃液', expiryType: InventoryExpiryType.none, months: null),
      (name: '镊子', expiryType: InventoryExpiryType.none, months: null),
      (name: '双钩针', expiryType: InventoryExpiryType.none, months: null),
      (name: '离心管 50ml', expiryType: InventoryExpiryType.none, months: null),
      (name: '离心管 20ml', expiryType: InventoryExpiryType.none, months: null),
      (name: '离心管 5ml', expiryType: InventoryExpiryType.none, months: null),
      (name: '离心管 2ml', expiryType: InventoryExpiryType.none, months: null),
      (name: '3D 打印机', expiryType: InventoryExpiryType.none, months: null),
      (name: '微距摄像头', expiryType: InventoryExpiryType.none, months: null),
      (name: '可食用色素', expiryType: InventoryExpiryType.none, months: null),
      (name: '营养液', expiryType: InventoryExpiryType.shelfLife, months: 3),
    ];
    final now = DateTime.now().toIso8601String();
    final batch = _db.batch();
    for (var index = 0; index < items.length; index++) {
      batch.insert('inventory_items', {
        'id': 'default-$index',
        'name': items[index].name,
        'purchased': 0,
        'created_at': now,
        'expiry_type': items[index].expiryType.storageValue,
        'shelf_life_months': items[index].months,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>> snapshot() async => {
    'colonies': await _db.query('colonies'),
    'care_records': await _db.query('care_records'),
    'feeder_records': await _db.query('feeder_records'),
    'inventory_items': await _db.query('inventory_items'),
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
    final feederRecords = (snapshot['feeder_records'] as List? ?? const [])
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    final inventoryItems = (snapshot['inventory_items'] as List?)
        ?.map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    await _db.transaction((transaction) async {
      if (inventoryItems != null) await transaction.delete('inventory_items');
      await transaction.delete('feeder_records');
      await transaction.delete('care_records');
      await transaction.delete('colonies');
      for (final colony in colonies) {
        await transaction.insert('colonies', colony);
      }
      for (final record in records) {
        await transaction.insert('care_records', record);
      }
      for (final record in feederRecords) {
        await transaction.insert('feeder_records', record);
      }
      if (inventoryItems != null) {
        for (final item in inventoryItems) {
          await transaction.insert('inventory_items', item);
        }
      }
    });
  }
}
