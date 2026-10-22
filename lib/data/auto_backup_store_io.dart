import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'auto_backup_model.dart';
import 'backup_service_io.dart';
import 'backup_logic.dart';
import 'local_media_store.dart';

AutoBackupStorage createAutoBackupStorage() => LocalAutoBackupStorage(
  BackupService(AppDatabase.instance, LocalMediaStore.instance),
);

class LocalAutoBackupStorage implements AutoBackupStorage {
  LocalAutoBackupStorage(this.service, {this.directory});
  final BackupService service;
  final Directory? directory;
  static const keepCount = 3;
  static final _name = RegExp(r'^antkeep-auto-([0-9]{16,17})\.zip$');

  @override
  bool get supported => true;

  Future<Directory> _root() async {
    final root =
        directory ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'antkeep',
            'auto-backups',
          ),
        );
    await root.create(recursive: true);
    return root;
  }

  @override
  Future<List<LocalBackupEntry>> list() async {
    final result = <LocalBackupEntry>[];
    await for (final entity in (await _root()).list(followLinks: false)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      final match = _name.firstMatch(name);
      if (match == null) continue;
      final time = int.tryParse(match[1]!);
      if (time == null) continue;
      result.add(
        LocalBackupEntry(
          name,
          DateTime.fromMicrosecondsSinceEpoch(time),
          await entity.length(),
        ),
      );
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<File> _file(LocalBackupEntry entry) async {
    if (!_name.hasMatch(entry.name)) throw const FormatException('自动备份文件名无效');
    final file = File(path.join((await _root()).path, entry.name));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('备份文件不存在');
    }
    return file;
  }

  @override
  Future<void> create(DateTime now) async {
    final root = await _root();
    final file = File(
      path.join(root.path, 'antkeep-auto-${now.microsecondsSinceEpoch}.zip'),
    );
    await service.writeBackupFile(file);
    // Rotation follows successful publication; unrelated/manual files are ignored.
    final entries = await list();
    final older = entries.where(
      (entry) => entry.name != path.basename(file.path),
    );
    for (final stale in older.skip(keepCount - 1)) {
      try {
        await (await _file(stale)).delete();
      } on FileSystemException {
        // A retention failure does not invalidate the new recoverable backup.
      }
    }
  }

  @override
  Future<bool> export(LocalBackupEntry entry) async =>
      service.exportExistingFile(await _file(entry), entry.name);

  @override
  Future<void> restore(
    LocalBackupEntry entry, {
    required bool incremental,
  }) async => service.restoreFile(
    await _file(entry),
    mode: incremental
        ? BackupRestoreMode.incremental
        : BackupRestoreMode.overwrite,
  );
}
