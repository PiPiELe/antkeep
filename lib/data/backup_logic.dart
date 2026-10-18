import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'backup_archive.dart';
import 'backup_data.dart';

enum BackupRestoreMode { incremental, overwrite }

const backupVersion = 14;

mixin BackupLogic {
  AppDatabase get database;

  Uint8List encodeManifest(Map<String, dynamic> data, Iterable<String> media) {
    BackupData.validate(data);
    if (data['nest_entries'] is! List ||
        data['winter_cycles'] is! List ||
        data['flight_observations'] is! List ||
        data['wild_catch_records'] is! List ||
        data['milestones'] is! List) {
      throw const FormatException('当前备份缺少巢体、越冬、婚飞、野采或里程碑记录表。');
    }
    if (media.length + 1 > BackupArchive.maxEntries) {
      throw FormatException(
        '备份最多支持 ${BackupArchive.maxEntries - 1} 张照片，当前照片数量超出上限。',
      );
    }
    for (final name in media) {
      BackupArchive.validateMediaPath(name);
    }
    final bytes = utf8.encode(
      jsonEncode({
        'format': 'antkeep',
        'version': backupVersion,
        'created_at': DateTime.now().toIso8601String(),
        'data': data,
        'media': media.toList()..sort(),
      }),
    );
    if (bytes.length > BackupArchive.maxManifestBytes) {
      throw const FormatException('备份清单超过 8 MB 的大小上限。');
    }
    return bytes;
  }

  (Map<String, dynamic>, Set<String>) parseManifest(
    Uint8List bytes,
    Set<String> files,
  ) {
    final manifest = jsonDecode(utf8.decode(bytes));
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('备份清单格式无效。');
    }
    validateManifestMap(manifest);
    final data = manifest['data'] as Map<String, dynamic>;
    BackupData.validate(data);
    final declared = (manifest['media'] as List).cast<String>().toSet();
    final referenced = database.photoPaths(data);
    if (!declared.containsAll(referenced) ||
        !referenced.containsAll(declared)) {
      throw const FormatException('备份中有照片记录，但缺少对应的照片文件。');
    }
    for (final name in declared) {
      BackupArchive.validateMediaPath(name);
    }
    final expected = {
      'manifest.json',
      ...declared.map((name) => 'media/$name'),
    };
    if (expected.length != files.length || !files.containsAll(expected)) {
      throw const FormatException('备份包含缺失或未声明的文件。');
    }
    return (data, declared);
  }

  (Map<String, dynamic>, Map<String, T>) mergeMissing<T extends Object>(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
    Map<String, T> incomingMedia,
  ) {
    final merged = <String, dynamic>{};
    final added = <String, dynamic>{};
    final localColonies = {
      for (final row in current['colonies'] as List) row['id']: row,
    };
    final endedColonies = {
      for (final row in current['memorials'] as List)
        if (row['kind'] == 'colony' && row['colony_id'] != null)
          row['colony_id'],
    };
    for (final table in current.keys) {
      final existing = (current[table] as List).cast<Map>();
      final ids = existing.map((row) => row['id']).toSet();
      final names = {
        for (final row in existing)
          if (table == 'inventory_items')
            (row['group_name'] ?? '', row['name']),
      };
      final taskTypes = {
        for (final row in existing)
          if (table == 'care_tasks') (row['colony_id'], row['task_type']),
      };
      final activeWinterColonies = {
        for (final row in existing)
          if (table == 'winter_cycles' && row['ended_on'] == null)
            row['colony_id'],
      };
      final additions = <Map<String, Object?>>[];
      for (final entry in incoming[table] as List? ?? const []) {
        final row = Map<String, Object?>.from(entry as Map);
        if (ids.contains(row['id'])) continue;
        if (table == 'inventory_items' &&
            names.contains((row['group_name'] ?? '', row['name']))) {
          continue;
        }
        if (table == 'care_tasks' &&
            !taskTypes.add((row['colony_id'], row['task_type']))) {
          continue;
        }
        if (table == 'winter_cycles' &&
            row['ended_on'] == null &&
            !activeWinterColonies.add(row['colony_id'])) {
          continue;
        }
        if (table == 'nest_entries' &&
            row['is_current'] == 1 &&
            localColonies.containsKey(row['colony_id'])) {
          // The local colony profile decides which nest is current. Keep the
          // imported entry as history, even when it has a different ID.
          row['is_current'] = 0;
        }
        if (table == 'memorials' &&
            row['kind'] == 'colony' &&
            row['colony_id'] != null) {
          // Keep local colony state and at most one ending per colony,
          // including when a later local ending has a different memorial ID.
          final localColony = localColonies[row['colony_id']];
          if ((localColony != null && localColony['archived'] != 1) ||
              !endedColonies.add(row['colony_id'])) {
            continue;
          }
        }
        additions.add(row);
      }
      added[table] = additions;
      merged[table] = [...existing, ...additions];
    }
    // Imported photos get private names, including when a backup reuses a
    // local filename with different bytes. Skipped records import no photos.
    final renamed = {
      for (final source in database.photoPaths(added))
        source: '${const Uuid().v4()}${path.extension(source)}',
    };
    for (final row in added['colonies'] as List) {
      final cover = row['cover_photo_path'];
      if (renamed.containsKey(cover)) row['cover_photo_path'] = renamed[cover];
    }
    for (final row in added['care_records'] as List) {
      final photos = row['photos_json'];
      if (photos is String && photos.isNotEmpty) {
        row['photos_json'] = jsonEncode([
          for (final source in jsonDecode(photos) as List) renamed[source]!,
        ]);
      }
    }
    for (final row in added['wild_catch_records'] as List) {
      final photos = row['photos_json'];
      if (photos is String && photos.isNotEmpty) {
        row['photos_json'] = jsonEncode([
          for (final source in jsonDecode(photos) as List) renamed[source]!,
        ]);
      }
      final events = row['events_json'];
      if (events is String && events.isNotEmpty) {
        row['events_json'] = jsonEncode([
          for (final event in jsonDecode(events) as List)
            {
              ...event as Map,
              'photo_paths': [
                for (final source in event['photo_paths'] as List? ?? const [])
                  renamed[source] ?? source,
              ],
            },
        ]);
      }
    }
    for (final row in added['milestones'] as List? ?? const []) {
      final photo = row['photo_path'];
      if (renamed.containsKey(photo)) row['photo_path'] = renamed[photo];
    }
    return (
      merged,
      {
        for (final entry in renamed.entries)
          entry.value: incomingMedia[entry.key]!,
      },
    );
  }

  void validateManifestMap(Map<String, dynamic> manifest) {
    final data = manifest['data'];
    if (manifest['format'] != 'antkeep' ||
        (manifest['version'] != 1 &&
            manifest['version'] != 2 &&
            manifest['version'] != 3 &&
            manifest['version'] != 4 &&
            manifest['version'] != 5 &&
            manifest['version'] != 6 &&
            manifest['version'] != 7 &&
            manifest['version'] != 8 &&
            manifest['version'] != 9 &&
            manifest['version'] != 10 &&
            manifest['version'] != 11 &&
            manifest['version'] != 12 &&
            manifest['version'] != 13 &&
            manifest['version'] != backupVersion) ||
        data is! Map<String, dynamic> ||
        data['colonies'] is! List ||
        data['care_records'] is! List ||
        (manifest['version'] >= 2 && data['memorials'] is! List) ||
        (manifest['version'] >= 3 && data['nest_entries'] is! List) ||
        (manifest['version'] >= 4 && data['winter_cycles'] is! List) ||
        (manifest['version'] >= 4 && data['flight_observations'] is! List) ||
        (manifest['version'] >= 5 && data['milestones'] is! List) ||
        (manifest['version'] >= 6 && data['wild_catch_records'] is! List) ||
        (data['feeder_records'] != null && data['feeder_records'] is! List) ||
        (data['care_tasks'] != null && data['care_tasks'] is! List) ||
        (data['inventory_items'] != null && data['inventory_items'] is! List) ||
        manifest['media'] is! List ||
        !(manifest['media'] as List).every((path) => path is String)) {
      throw const FormatException('备份格式、版本或数据不完整。');
    }
  }
}
