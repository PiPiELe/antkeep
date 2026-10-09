import 'dart:convert';
import 'dart:async';

import '../domain/memorial.dart';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/colony_growth.dart';
import '../domain/record_increment.dart';
import '../domain/spending_analysis.dart';
import '../app_preferences.dart';
import 'database_factory.dart';
import 'database_path.dart';

abstract class AntKeepRepository {
  Future<List<Colony>> listColonies();
  Future<Colony?> findColony(String id);
  Future<void> saveColony(Colony colony);
  Future<void> deleteColony(String id);
  Future<List<CareRecord>> listRecords(String colonyId);
  Future<List<CareRecord>> listRecentRecords();
  Future<void> saveRecord(CareRecord record, {bool incremental = false});
  Future<void> updateRecord(CareRecord record);
  Future<void> deleteRecord(CareRecord record);
}

class AppDatabase implements AntKeepRepository, AppSettingsStore {
  AppDatabase._();
  static final instance = AppDatabase._();
  Database? _database;
  final _memorialChanges = StreamController<void>.broadcast();
  Stream<void> get memorialChanges => _memorialChanges.stream;

  Future<void> open() async {
    if (_database != null) return;
    initializeDatabaseFactory();
    _database = await openDatabase(
      await applicationDatabasePath(),
      version: 20,
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
      purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0),
      specialized_count INTEGER, show_specialized INTEGER NOT NULL DEFAULT 0,
      initial_egg_count INTEGER, initial_cocoon_count INTEGER, auto_growth_json TEXT,
      initial_larva_count INTEGER, development_path TEXT,
      nest_type TEXT, target_temperature_lower REAL, target_temperature REAL,
      target_humidity_lower REAL, target_humidity REAL, cover_photo_path TEXT,
      archived INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
    await database.execute('''CREATE TABLE care_records (
      id TEXT PRIMARY KEY, colony_id TEXT NOT NULL, record_type TEXT NOT NULL,
      occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
      egg_count INTEGER, larva_count INTEGER, pupa_count INTEGER, worker_count INTEGER,
      worker_mortality_count INTEGER CHECK (worker_mortality_count BETWEEN 0 AND 1000000),
      auto_growth_rule_json TEXT,
      photos_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL,
      FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE CASCADE
    )''');
    await database.execute(
      'CREATE INDEX records_by_colony_time ON care_records(colony_id, occurred_at DESC)',
    );
    await _createMemorialTable(database);
    await _createSettingsTable(database);
    await _createInventoryTable(database);
    await _createFeederRecordsTable(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 20) {
      await database.execute(
        'ALTER TABLE care_records ADD COLUMN auto_growth_rule_json TEXT',
      );
    }
    if (oldVersion < 18) await _createMemorialTable(database);
    if (oldVersion == 18) {
      // Rebuild the CHECK constraint while retaining all existing memorials.
      await database.execute('ALTER TABLE memorials RENAME TO memorials_old');
      await database.execute('DROP INDEX memorial_colony_end');
      await _createMemorialTable(database);
      await database.execute('''INSERT INTO memorials
        (id, kind, name, colony_id, species, died_on, farewell, cause,
         observation, lesson, created_at)
        SELECT id, kind, name, colony_id, species, died_on, farewell, cause,
         observation, lesson, created_at FROM memorials_old''');
      await database.execute('DROP TABLE memorials_old');
    }
    if (oldVersion < 17) {
      await database.execute(
        'ALTER TABLE care_records ADD COLUMN worker_mortality_count INTEGER '
        'CHECK (worker_mortality_count BETWEEN 0 AND 1000000)',
      );
    }
    if (oldVersion < 16) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN initial_larva_count INTEGER',
      );
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN development_path TEXT',
      );
    }
    if (oldVersion < 15) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN auto_growth_json TEXT',
      );
    }
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
    if (oldVersion >= 5 && oldVersion < 8) {
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
    if (oldVersion >= 5 && oldVersion < 9) {
      await database.execute(
        'ALTER TABLE inventory_items ADD COLUMN quantity INTEGER CHECK (quantity >= 0)',
      );
    }
    if (oldVersion < 10) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN specialized_count INTEGER',
      );
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN show_specialized INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 11) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0)',
      );
      if (oldVersion >= 6) {
        await database.execute(
          'ALTER TABLE feeder_records ADD COLUMN purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0)',
        );
      }
    }
    if (oldVersion >= 5 && oldVersion < 12) {
      await database.execute(
        'ALTER TABLE inventory_items ADD COLUMN purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0)',
      );
    }
    if (oldVersion >= 5 && oldVersion < 13) {
      // Replace the global name constraint with uniqueness within each group.
      await database.execute(
        'ALTER TABLE inventory_items RENAME TO inventory_items_old',
      );
      await _createInventoryTable(database);
      await database.execute('''INSERT INTO inventory_items
        (id, name, purchased, created_at, expiry_type, shelf_life_months,
         purchased_at, expires_at, quantity, purchase_price_cents)
        SELECT id, name, purchased, created_at, expiry_type, shelf_life_months,
         purchased_at, expires_at, quantity, purchase_price_cents
        FROM inventory_items_old''');
      await database.execute('DROP TABLE inventory_items_old');
    }
    if (oldVersion < 14) {
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN target_temperature_lower REAL',
      );
      await database.execute(
        'ALTER TABLE colonies ADD COLUMN target_humidity_lower REAL',
      );
    }
  }

  static Future<void> _createMemorialTable(DatabaseExecutor db) async {
    await db.execute("""CREATE TABLE memorials (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('queen', 'worker', 'brood', 'colony')),
      name TEXT NOT NULL, colony_id TEXT, species TEXT, died_on TEXT,
      farewell TEXT, cause TEXT, observation TEXT, lesson TEXT, created_at TEXT NOT NULL,
      FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE SET NULL
    )""");
    await db.execute(
      "CREATE UNIQUE INDEX memorial_colony_end ON memorials(colony_id) WHERE kind = 'colony'",
    );
  }

  Future<List<Memorial>> listMemorials() async => (await _db.query(
    'memorials',
    orderBy: 'COALESCE(died_on, created_at) DESC, created_at DESC',
  )).map(Memorial.fromMap).toList();

  Future<void> saveMemorial(Memorial memorial) async {
    memorial.validate();
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'memorials',
        where: 'id = ?',
        whereArgs: [memorial.id],
      );
      if (existing.isNotEmpty) {
        final original = Memorial.fromMap(existing.single);
        if (original.kind != memorial.kind ||
            (original.kind == MemorialKind.colony &&
                original.colonyId != memorial.colonyId)) {
          throw const FormatException('纪念类型及整群纪念的关联蚁群不能更改。');
        }
      }
      if (memorial.colonyId != null) {
        final colonies = await txn.query(
          'colonies',
          where: 'id = ?',
          whereArgs: [memorial.colonyId],
        );
        if (colonies.isEmpty) throw StateError('关联蚁群已不存在');
        if (memorial.kind == MemorialKind.colony && existing.isEmpty) {
          if (colonies.single['archived'] == 1) throw StateError('该蚁群已移入英灵殿');
          // Keep history untouched. Restoring requires opting into growth again,
          // otherwise it would generate estimates for the time spent archived.
          await txn.update(
            'colonies',
            {
              'archived': 1,
              'development_path': Colony.fromMap(colonies.single)
                  .developmentPath
                  .name,
              'auto_growth_json': null,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [memorial.colonyId],
          );
        }
      } else if (memorial.kind == MemorialKind.colony && existing.isEmpty) {
        throw const FormatException('整群移入需要选择蚁群。');
      }
      if (existing.isEmpty) {
        await txn.insert('memorials', memorial.toMap());
      } else {
        await txn.update(
          'memorials',
          memorial.toMap()..remove('created_at'),
          where: 'id = ?',
          whereArgs: [memorial.id],
        );
      }
    });
    _memorialChanges.add(null);
  }

  Future<void> restoreMemorialColony(String memorialId) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'memorials',
        where: 'id = ? AND kind = ?',
        whereArgs: [memorialId, 'colony'],
      );
      if (rows.isEmpty || rows.single['colony_id'] == null) {
        throw StateError('关联蚁群已不存在');
      }
      await txn.update(
        'colonies',
        {'archived': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [rows.single['colony_id']],
      );
      await txn.delete('memorials', where: 'id = ?', whereArgs: [memorialId]);
    });
    _memorialChanges.add(null);
  }

  Future<void> deleteMemorial(String id) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'memorials',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isNotEmpty &&
          rows.single['kind'] == 'colony' &&
          rows.single['colony_id'] != null) {
        throw StateError('请先恢复蚁群，避免丢失整群纪念入口');
      }
      await txn.delete('memorials', where: 'id = ?', whereArgs: [id]);
    });
    _memorialChanges.add(null);
  }

  static Future<void> _createSettingsTable(DatabaseExecutor executor) =>
      executor.execute('''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )''');

  static Future<void> _createInventoryTable(DatabaseExecutor executor) async {
    await executor.execute('''CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, group_name TEXT,
        purchased INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
        expiry_type TEXT NOT NULL DEFAULT 'none', shelf_life_months INTEGER,
        purchased_at TEXT, expires_at TEXT,
        quantity INTEGER CHECK (quantity >= 0),
        purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0)
      )''');
    await executor.execute('''CREATE UNIQUE INDEX inventory_name_in_group
        ON inventory_items(COALESCE(group_name, ''), name)''');
  }

  static Future<void> _createFeederRecordsTable(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''CREATE TABLE feeder_records (
      id TEXT PRIMARY KEY, feeder_type TEXT NOT NULL, record_type TEXT NOT NULL,
      occurred_at TEXT NOT NULL, note TEXT, temperature REAL, humidity REAL,
      juvenile_count INTEGER, adult_count INTEGER, mortality_count INTEGER,
      purchase_price_cents INTEGER CHECK (purchase_price_cents >= 0),
      created_at TEXT NOT NULL
    )''');
    await executor.execute(
      'CREATE INDEX feeder_records_by_type_time ON feeder_records(feeder_type, occurred_at DESC)',
    );
  }

  @override
  Future<List<Colony>> listColonies() async {
    await applyColonyGrowth();
    return (await _db.query(
      'colonies',
      where: 'archived = 0',
      orderBy: 'CASE WHEN initial_worker_count = 0 THEN 0 ELSE 1 END, updated_at DESC',
    )).map(Colony.fromMap).toList();
  }

  @override
  Future<Colony?> findColony(String id) async {
    await applyColonyGrowth(colonyId: id);
    final rows = await _db.query('colonies', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Colony.fromMap(rows.single);
  }

  @override
  Future<void> saveColony(Colony colony) =>
      _db.transaction((transaction) async {
        await _applyGrowth(transaction, DateTime.now(), colony.id);
        final updated = await transaction.update(
          'colonies',
          colony.toMap()..remove('auto_growth_json'),
          where: 'id = ?',
          whereArgs: [colony.id],
        );
        if (updated == 0) {
          await transaction.insert('colonies', colony.toMap());
        }
      });

  Future<Colony> updateColonyDiaryRules(
    String id, {
    bool? showSpecialized,
    int? specializedCount,
    GrowthPath? developmentPath,
  }) async {
    if (specializedCount != null &&
        (specializedCount < 0 || specializedCount > 1000000)) {
      throw const FormatException('特化数量须为 0～1000000 的整数');
    }
    final at = DateTime.now();
    await _db.transaction((txn) async {
      await _applyGrowth(txn, at, id);
      final rows = await txn.query(
        'colonies',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('蚁群已不存在');
      if ((rows.single['archived'] as int? ?? 0) == 1) {
        throw StateError('已归档蚁群不能修改养殖规则');
      }
      final changes = <String, Object?>{'updated_at': at.toIso8601String()};
      if (showSpecialized != null) {
        changes['show_specialized'] = showSpecialized ? 1 : 0;
      }
      if (specializedCount != null) {
        changes['specialized_count'] = specializedCount;
      }
      if (developmentPath != null) {
        changes['development_path'] = developmentPath.name;
      }
      await txn.update('colonies', changes, where: 'id = ?', whereArgs: [id]);
    });
    return (await findColony(id))!;
  }

  Future<void> configureColonyGrowth(
    String id,
    ColonyGrowth? growth, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    await _db.transaction((txn) async {
      await _applyGrowth(txn, at, id);
      final rows = await txn.query(
        'colonies',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('蚁群已不存在');
      final colony = Colony.fromMap(rows.single);
      final current = colony.growth;
      final effective = growth != null && current?.startedAt == growth.startedAt
          ? current
          : growth;
      await txn.update(
        'colonies',
        {
          // Keep legacy paths independent of the optional growth configuration.
          'development_path':
              rows.single['development_path'] ??
              effective?.path.name ??
              colony.developmentPath.name,
          'auto_growth_json': effective?.encode(),
          'updated_at': at.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> applyColonyGrowth({DateTime? now, String? colonyId}) => _db
      .transaction((txn) => _applyGrowth(txn, now ?? DateTime.now(), colonyId));

  Future<void> _applyGrowth(
    Transaction txn,
    DateTime now,
    String? colonyId,
  ) async {
    final rows = await txn.query(
      'colonies',
      where:
          'archived = 0 AND auto_growth_json IS NOT NULL'
          '${colonyId == null ? '' : ' AND id = ?'}',
      whereArgs: colonyId == null ? null : [colonyId],
    );
    for (final row in rows) {
      final colony = Colony.fromMap(row);
      final growth = colony.growth;
      if (growth == null || colony.archived) continue;
      var cycle = growth.completedCycles;
      if (growth.dueAt(cycle + 1).isAfter(now)) continue;
      final records = (await txn.query(
        'care_records',
        where: 'colony_id = ?',
        whereArgs: [colony.id],
        orderBy: 'occurred_at ASC, created_at ASC, id ASC',
      )).map(CareRecord.fromMap).toList();
      final recordIds = records.map((record) => record.id).toSet();
      var population = GrowthPopulation(
        eggs: colony.initialEggCount,
        larvae: colony.initialLarvaCount,
        cocoons: colony.initialCocoonCount,
        workers: colony.initialWorkerCount,
      );
      var cursor = 0;
      while (!growth.dueAt(cycle + 1).isAfter(now)) {
        final due = growth.dueAt(++cycle);
        while (cursor < records.length &&
            !records[cursor].occurredAt.isAfter(due)) {
          final record = records[cursor++];
          population = GrowthPopulation(
            eggs: record.eggCount ?? population.eggs,
            larvae: record.larvaCount ?? population.larvae,
            cocoons: record.pupaCount ?? population.cocoons,
            workers: record.workerCountAfter(population.workers),
          );
        }
        final recordId =
            'growth:${colony.id}:${growth.startedAt.toIso8601String()}:$cycle';
        // Incremental restore can import settled cycles while retaining an
        // older local watermark. Keep their snapshots without applying twice.
        if (recordIds.contains(recordId)) continue;
        population = growth.advance(population);
        await txn.insert(
          'care_records',
          CareRecord(
            id: recordId,
            colonyId: colony.id,
            type: CareRecordType.observation,
            occurredAt: due,
            createdAt: now,
            note: '自动扩充（估算） · ${growth.frequency.label} · ${growth.path.label}',
            eggCount: population.eggs,
            larvaCount: population.larvae,
            pupaCount: population.cocoons,
            workerCount: population.workers,
            growthRule: growth,
          ).toMap(),
        );
      }
      await txn.update(
        'colonies',
        {
          'auto_growth_json': growth.completed(cycle).encode(),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [colony.id],
      );
    }
  }

  @override
  Future<void> deleteColony(String id) async {
    // Foreign keys cascade the deletion to this colony's care records.
    await _db.delete('colonies', where: 'id = ?', whereArgs: [id]);
    _memorialChanges.add(null);
  }

  @override
  Future<List<CareRecord>> listRecords(String colonyId) async {
    await applyColonyGrowth(colonyId: colonyId);
    return (await _db.query(
      'care_records',
      where: 'colony_id = ?',
      whereArgs: [colonyId],
      orderBy: 'occurred_at DESC',
    )).map(CareRecord.fromMap).toList();
  }

  @override
  Future<List<CareRecord>> listRecentRecords() async {
    await applyColonyGrowth();
    return (await _db.query(
      'care_records',
      orderBy: 'occurred_at DESC',
      limit: 50,
    )).map(CareRecord.fromMap).toList();
  }

  @override
  Future<void> saveRecord(
    CareRecord record, {
    bool incremental = false,
    bool recalculateAllGrowth = false,
  }) => _db.transaction((transaction) async {
    await _applyGrowth(transaction, DateTime.now(), record.colonyId);
    final before = await _growthReplayRecords(transaction, record.colonyId);
    _requireGrowthConfirmation(before, [
      record.occurredAt,
    ], recalculateAllGrowth);
    var resolved = record;
    if (incremental) {
      final rows = await transaction.query(
        'colonies',
        where: 'id = ?',
        whereArgs: [record.colonyId],
      );
      if (rows.isEmpty) throw StateError('蚁群已不存在');
      final history = await transaction.query(
        'care_records',
        where: 'colony_id = ?',
        whereArgs: [record.colonyId],
      );
      resolved = resolveRecordIncrement(
        Colony.fromMap(rows.single),
        history.map(CareRecord.fromMap),
        record,
      );
    }
    await transaction.insert('care_records', resolved.toMap());
    await _recalculateGrowthEstimates(
      transaction,
      record.colonyId,
      before,
      recalculateAll: recalculateAllGrowth,
    );
    await transaction.update(
      'colonies',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [record.colonyId],
    );
  });

  @override
  Future<void> updateRecord(
    CareRecord record, {
    bool recalculateAllGrowth = false,
  }) => _db.transaction((transaction) async {
    await _applyGrowth(transaction, DateTime.now(), record.colonyId);
    final before = await _growthReplayRecords(transaction, record.colonyId);
    final original = before.where((item) => item.id == record.id).firstOrNull;
    _requireGrowthConfirmation(before, [
      if (original != null) original.occurredAt,
      record.occurredAt,
    ], recalculateAllGrowth);
    final values = record.toMap()
      ..remove('id')
      ..remove('colony_id')
      ..remove('created_at');
    if (original != null && _isGeneratedGrowth(original)) {
      // Editing an estimate turns it into an explicit correction. Keep its ID
      // and timestamp, but do not silently recalculate the user's new total.
      values['auto_growth_rule_json'] = null;
      if ((values['note'] as String?)?.startsWith('自动扩充（估算）') ?? false) {
        values['note'] = '手动校正 · ${values['note']}';
      }
    }
    final count = await transaction.update(
      'care_records',
      values,
      where: 'id = ? AND colony_id = ?',
      whereArgs: [record.id, record.colonyId],
    );
    if (count != 1) throw StateError('日记已不存在，请返回刷新');
    await _recalculateGrowthEstimates(
      transaction,
      record.colonyId,
      before,
      recalculateAll: recalculateAllGrowth,
      correctedId: record.id,
    );
    await transaction.update(
      'colonies',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [record.colonyId],
    );
  });

  @override
  Future<void> deleteRecord(
    CareRecord record, {
    bool recalculateAllGrowth = false,
  }) => _db.transaction((transaction) async {
    await _applyGrowth(transaction, DateTime.now(), record.colonyId);
    final before = await _growthReplayRecords(transaction, record.colonyId);
    _requireGrowthConfirmation(before, [
      record.occurredAt,
    ], recalculateAllGrowth);
    await transaction.delete(
      'care_records',
      where: 'id = ? AND colony_id = ?',
      whereArgs: [record.id, record.colonyId],
    );
    await _recalculateGrowthEstimates(
      transaction,
      record.colonyId,
      before,
      recalculateAll: recalculateAllGrowth,
    );
    await transaction.update(
      'colonies',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [record.colonyId],
    );
  });

  /// Local calendar boundary for the routinely replayed growth estimates.
  static DateTime growthReplayBoundary([DateTime? now]) {
    final date = now ?? DateTime.now();
    return DateTime(date.year, date.month, date.day - 30);
  }

  Future<bool> needsGlobalGrowthRecalculation(
    String colonyId,
    Iterable<DateTime> changedDates,
  ) async {
    final changed = changedDates.toList();
    if (!changed.any((date) => date.isBefore(growthReplayBoundary()))) {
      return false;
    }
    final records = await _growthReplayRecords(_db, colonyId);
    if (_needsGlobalGrowthRecalculation(records, changed)) return true;
    // Inspect unsettled cycles without writing. The expensive settlement and
    // replay then run under the progress dialog after confirmation.
    final colonyRows = await _db.query(
      'colonies',
      where: 'id = ?',
      whereArgs: [colonyId],
    );
    final colony = colonyRows.isEmpty ? null : Colony.fromMap(colonyRows.single);
    final growth = colony?.archived == false ? colony?.growth : null;
    if (growth == null) return false;
    final nextDue = growth.dueAt(growth.completedCycles + 1);
    return !nextDue.isAfter(DateTime.now());
  }

  Future<List<CareRecord>> _growthReplayRecords(
    DatabaseExecutor db,
    String colonyId,
  ) async => (await db.query(
    'care_records',
    where: 'colony_id = ?',
    whereArgs: [colonyId],
    orderBy: 'occurred_at ASC, created_at ASC, id ASC',
  )).map(CareRecord.fromMap).toList();

  bool _needsGlobalGrowthRecalculation(
    List<CareRecord> records,
    Iterable<DateTime> changedDates,
  ) {
    final changed = changedDates.toList();
    if (changed.isEmpty ||
        !changed.any((date) => date.isBefore(growthReplayBoundary()))) {
      return false;
    }
    return records.any(
      (record) =>
          record.id.startsWith('growth:') &&
          changed.any((date) => !record.occurredAt.isBefore(date)),
    );
  }

  void _requireGrowthConfirmation(
    List<CareRecord> records,
    Iterable<DateTime> changedDates,
    bool confirmed,
  ) {
    if (!confirmed && _needsGlobalGrowthRecalculation(records, changedDates)) {
      throw StateError('这条日记早于 30 天界碑，请确认全局更新后重试。');
    }
  }

  Future<void> _recalculateGrowthEstimates(
    Transaction transaction,
    String colonyId,
    List<CareRecord> before, {
    required bool recalculateAll,
    String? correctedId,
  }) async {
    if (!before.any((record) => record.id.startsWith('growth:'))) return;
    final colonyRows = await transaction.query(
      'colonies',
      where: 'id = ?',
      whereArgs: [colonyId],
    );
    if (colonyRows.isEmpty) return;
    final colony = Colony.fromMap(colonyRows.single);
    final after = await _growthReplayRecords(transaction, colonyId);
    before.sort(CareRecord.comparePopulationOrder);
    after.sort(CareRecord.comparePopulationOrder);
    final boundary = recalculateAll
        ? null
        : before
              .where(
                (record) =>
                    record.id.startsWith('growth:') &&
                    record.occurredAt.isBefore(growthReplayBoundary()),
              )
              .lastOrNull;
    final initial = boundary == null
        ? GrowthPopulation(
            eggs: colony.initialEggCount,
            larvae: colony.initialLarvaCount,
            cocoons: colony.initialCocoonCount,
            workers: colony.initialWorkerCount,
          )
        : GrowthPopulation(
            eggs: boundary.eggCount,
            larvae: boundary.larvaCount,
            cocoons: boundary.pupaCount,
            workers: boundary.workerCount,
          );
    bool afterBoundary(CareRecord record) =>
        boundary == null ||
        CareRecord.comparePopulationOrder(record, boundary) > 0;
    final oldRecords = before.where(afterBoundary);
    final newRecords = after.where(afterBoundary);
    final oldBefore = <String, GrowthPopulation>{};
    var oldPopulation = initial;
    for (final record in oldRecords) {
      oldBefore[record.id] = oldPopulation;
      oldPopulation = _applyPopulationRecord(oldPopulation, record);
    }
    var population = initial;
    for (final record in newRecords) {
      if (record.id != correctedId && _isGeneratedGrowth(record)) {
        final rule = _growthRuleFor(record, colony);
        if (rule == null) {
          final previous = oldBefore[record.id];
          if (previous != null && !_samePopulation(population, previous)) {
            throw StateError(
              '旧自动扩充日记缺少当时的增长规则，无法可靠重算。请先手动校正 ${record.occurredAt.year}-${record.occurredAt.month}-${record.occurredAt.day} 的界碑数量，再重试。',
            );
          }
          population = _applyPopulationRecord(population, record);
          continue;
        }
        final recalculated = rule.advance(population);
        final values = {
          'egg_count': recalculated.eggs,
          'larva_count': recalculated.larvae,
          'pupa_count': recalculated.cocoons,
          'worker_count': recalculated.workers,
          'auto_growth_rule_json': rule.encode(),
        };
        await transaction.update(
          'care_records',
          values,
          where: 'id = ?',
          whereArgs: [record.id],
        );
        population = recalculated;
      } else {
        population = _applyPopulationRecord(population, record);
      }
    }
  }

  bool _isGeneratedGrowth(CareRecord record) =>
      record.isAutomaticGrowthEstimate;

  ColonyGrowth? _growthRuleFor(CareRecord record, Colony colony) {
    if (record.growthRule case final stored?) return stored;
    final current = colony.growth;
    if (current == null ||
        !record.id.startsWith(
          'growth:${colony.id}:${current.startedAt.toIso8601String()}:',
        ) ||
        record.note !=
            '自动扩充（估算） · ${current.frequency.label} · ${current.path.label}') {
      return null;
    }
    return current;
  }

  bool _samePopulation(GrowthPopulation a, GrowthPopulation b) =>
      a.eggs == b.eggs &&
      a.larvae == b.larvae &&
      a.cocoons == b.cocoons &&
      a.workers == b.workers;

  GrowthPopulation _applyPopulationRecord(
    GrowthPopulation population,
    CareRecord record,
  ) => GrowthPopulation(
    eggs: record.eggCount ?? population.eggs,
    larvae: record.larvaCount ?? population.larvae,
    cocoons: record.pupaCount ?? population.cocoons,
    workers: record.workerCountAfter(population.workers),
  );

  @override
  Future<Map<String, String>> readSettings() async => {
    for (final row in await _db.query('app_settings'))
      row['setting_key'] as String: row['setting_value'] as String,
  };

  @override
  Future<void> writeSettings(Map<String, String> values) =>
      _db.transaction((transaction) async {
        for (final entry in values.entries) {
          await transaction.insert('app_settings', {
            'setting_key': entry.key,
            'setting_value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<SpendingSummary> loadSpendingSummary() => _db.transaction((
    transaction,
  ) async {
    Future<int> sum(String table, {String? where}) async {
      final rows = await transaction.query(
        table,
        columns: ['COALESCE(SUM(purchase_price_cents), 0) AS total'],
        where: where,
      );
      return rows.single['total'] as int;
    }

    final topRows = await transaction.rawQuery('''
          SELECT id, name, '蚁群' AS category, purchase_price_cents AS cents,
                 NULL AS record_type, NULL AS occurred_at
          FROM colonies WHERE purchase_price_cents > 0
          UNION ALL
          SELECT id,
                 CASE WHEN group_name IS NULL OR group_name = '' THEN name
                      ELSE group_name || ' · ' || name END,
                 '已购物品', purchase_price_cents, NULL, NULL
          FROM inventory_items WHERE purchased = 1 AND purchase_price_cents > 0
          UNION ALL
          SELECT id, feeder_type, 'DLC 养殖', purchase_price_cents,
                 record_type, occurred_at
          FROM feeder_records WHERE purchase_price_cents > 0
          ORDER BY cents DESC, category ASC, id ASC
          LIMIT 5
        ''');
    return SpendingSummary(
      // Archived colonies still represent money already spent.
      coloniesCents: await sum('colonies'),
      inventoryCents: await sum('inventory_items', where: 'purchased = 1'),
      feedersCents: await sum('feeder_records'),
      topEntries: topRows.map((row) {
        final isFeeder = row['record_type'] != null;
        return SpendingEntry(
          name: isFeeder
              ? '${FeederType.fromStorage(row['name'] as String).label} · '
                    '${FeederRecordType.fromStorage(row['record_type'] as String).label}'
              : row['name'] as String,
          category: row['category'] as String,
          cents: row['cents'] as int,
          occurredAt: isFeeder
              ? DateTime.parse(row['occurred_at'] as String)
              : null,
        );
      }).toList(),
    );
  });

  Future<List<InventoryItem>> listInventory() async => (await _db.query(
    'inventory_items',
    orderBy: 'purchased ASC, name COLLATE NOCASE ASC',
  )).map(InventoryItem.fromMap).toList();

  Future<void> saveInventoryItem(InventoryItem item) => _db.insert(
    'inventory_items',
    item.toMap(),
    conflictAlgorithm: ConflictAlgorithm.abort,
  );

  Future<void> saveInventoryGroup(List<InventoryItem> items) async {
    if (items.isEmpty ||
        items.first.groupName == null ||
        items.first.groupName!.trim().isEmpty ||
        items.any(
          (item) =>
              item.groupName != items.first.groupName ||
              item.name.trim().isEmpty,
        )) {
      throw ArgumentError('请填写聚合名称和至少一个子物品');
    }
    await _db.transaction((transaction) async {
      for (final item in items) {
        await transaction.insert('inventory_items', item.toMap());
      }
    });
  }

  Future<void> setInventoryPurchased(
    InventoryItem item,
    bool purchased, {
    int? quantity,
    int? purchasePriceCents,
  }) async {
    if (quantity != null && quantity < 0) {
      throw ArgumentError.value(quantity, 'quantity', '数量不能小于零');
    }
    if (purchasePriceCents != null && purchasePriceCents < 0) {
      throw ArgumentError.value(
        purchasePriceCents,
        'purchasePriceCents',
        '购入价不能小于零',
      );
    }
    await _db.update(
      'inventory_items',
      {
        'purchased': purchased ? 1 : 0,
        'purchased_at': purchased
            ? (item.purchased ? item.purchasedAt : DateTime.now())
                  ?.toIso8601String()
            : null,
        'quantity': purchased ? quantity : null,
        'purchase_price_cents': purchased ? purchasePriceCents : null,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> purchaseInventoryItems(
    Iterable<String> itemIds, {
    Map<String, ({int? quantity, int? purchasePriceCents})> details = const {},
  }) async {
    final ids = itemIds.toSet();
    if (ids.isEmpty) return;
    for (final id in ids) {
      final detail = details[id];
      if ((detail?.quantity ?? 0) < 0 ||
          (detail?.purchasePriceCents ?? 0) < 0) {
        throw ArgumentError('数量和购入价不能小于零');
      }
    }
    final purchasedAt = DateTime.now().toIso8601String();
    await _db.transaction((transaction) async {
      for (final id in ids) {
        await transaction.update(
          'inventory_items',
          {
            'purchased': 1,
            'purchased_at': purchasedAt,
            'quantity': details[id]?.quantity,
            'purchase_price_cents': details[id]?.purchasePriceCents,
          },
          where: 'purchased = 0 AND id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<List<FeederRecord>> listFeederRecords(FeederType feeder) async =>
      (await _db.query(
        'feeder_records',
        where: 'feeder_type = ?',
        whereArgs: [feeder.storageValue],
        orderBy: 'occurred_at DESC',
      )).map(FeederRecord.fromMap).toList();

  Future<void> saveFeederRecord(FeederRecord record) =>
      _db.insert('feeder_records', record.toMap());

  Future<FeederRecord?> latestFeederCountRecord(FeederType feeder) async {
    final rows = await _db.query(
      'feeder_records',
      where: 'feeder_type = ? AND (juvenile_count IS NOT NULL OR adult_count IS NOT NULL)',
      whereArgs: [feeder.storageValue],
      orderBy: 'occurred_at DESC, created_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : FeederRecord.fromMap(rows.single);
  }

  Future<void> _seedInventory() async {
    // Rename only the bundled item, preserving purchases and custom items.
    await _db.update(
      'inventory_items',
      {'name': '脱脂棉球'},
      where: 'id = ? AND name = ? AND group_name IS NULL',
      whereArgs: ['default-17', '棉花团'],
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // Positions are persisted as IDs. Append new defaults; do not reorder.
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
      (name: '试管 15cm', expiryType: InventoryExpiryType.none, months: null),
      (name: '试管 18cm', expiryType: InventoryExpiryType.none, months: null),
      (name: '试管 20cm', expiryType: InventoryExpiryType.none, months: null),
      (name: '白菜巢', expiryType: InventoryExpiryType.none, months: null),
      (name: '堵水海绵', expiryType: InventoryExpiryType.none, months: null),
      (name: '蚂蚁吸尘器', expiryType: InventoryExpiryType.none, months: null),
      (name: '脱脂棉球', expiryType: InventoryExpiryType.none, months: null),
      (name: '恒温箱', expiryType: InventoryExpiryType.none, months: null),
      (name: 'EPP 泡沫箱', expiryType: InventoryExpiryType.none, months: null),
      (name: '尖头画笔（勾线笔）', expiryType: InventoryExpiryType.none, months: null),
      (name: '图钉吸铁石', expiryType: InventoryExpiryType.none, months: null),
      (name: '平头注射器', expiryType: InventoryExpiryType.none, months: null),
      (name: '小剪刀', expiryType: InventoryExpiryType.none, months: null),
      (name: 'LED 小灯', expiryType: InventoryExpiryType.none, months: null),
      (name: '平头画笔', expiryType: InventoryExpiryType.none, months: null),
      (name: '营养果冻', expiryType: InventoryExpiryType.shelfLife, months: 3),
      (name: '蚂蚁喂水器', expiryType: InventoryExpiryType.none, months: null),
      (
        name: '10mm 软管（蚂蚁平稳换巢）',
        expiryType: InventoryExpiryType.none,
        months: null,
      ),
      (name: '滴管', expiryType: InventoryExpiryType.none, months: null),
      (name: '手工玻璃纸', expiryType: InventoryExpiryType.none, months: null),
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
    for (final item in const [
      (id: 'default-feeding-tray-aluminum', name: '铝制喂食盘'),
      (id: 'default-feeding-tray-personalized', name: '个性喂食盘'),
    ]) {
      batch.insert('inventory_items', {
        'id': item.id,
        'name': item.name,
        'group_name': '喂食盘',
        'purchased': 0,
        'created_at': now,
        'expiry_type': InventoryExpiryType.none.storageValue,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>> snapshot() => _db.transaction(
    (txn) async => {
      'memorials': await txn.query('memorials'),
      'colonies': await txn.query('colonies'),
      'care_records': await txn.query('care_records'),
      'feeder_records': await txn.query('feeder_records'),
      'inventory_items': await txn.query('inventory_items'),
    },
  );

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
      await transaction.delete('memorials');
      await transaction.delete('care_records');
      await transaction.delete('colonies');
      for (final colony in colonies) {
        await transaction.insert('colonies', colony);
      }
      for (final row in snapshot['memorials'] as List? ?? const []) {
        await transaction.insert(
          'memorials',
          Map<String, Object?>.from(row as Map),
        );
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
    _memorialChanges.add(null);
  }
}
