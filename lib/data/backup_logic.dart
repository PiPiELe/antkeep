import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'backup_archive.dart';
import 'backup_data.dart';

enum BackupRestoreMode { incremental, overwrite }

const backupVersion = 2;

mixin BackupLogic {
  AppDatabase get database;

  Uint8List encodeManifest(Map<String, dynamic> data, Iterable<String> media) {
    BackupData.validate(data);
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
      final additions = <Map<String, Object?>>[];
      for (final entry in incoming[table] as List? ?? const []) {
        final row = Map<String, Object?>.from(entry as Map);
        if (ids.contains(row['id'])) continue;
        if (table == 'inventory_items' &&
            names.contains((row['group_name'] ?? '', row['name']))) {
          continue;
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
        (manifest['version'] != 1 && manifest['version'] != backupVersion) ||
        data is! Map<String, dynamic> ||
        data['colonies'] is! List ||
        data['care_records'] is! List ||
        (manifest['version'] == 2 && data['memorials'] is! List) ||
        (data['feeder_records'] != null && data['feeder_records'] is! List) ||
        (data['inventory_items'] != null && data['inventory_items'] is! List) ||
        manifest['media'] is! List ||
        !(manifest['media'] as List).every((path) => path is String)) {
      throw const FormatException('备份格式、版本或数据不完整。');
    }
  }
}
