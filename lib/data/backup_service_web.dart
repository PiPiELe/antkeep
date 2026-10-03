import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import 'app_database.dart';
import 'backup_archive.dart';
import 'backup_data.dart';
import 'backup_logic.dart';
import 'local_media_store.dart';
import 'rollback_store.dart';

class BackupService with BackupLogic {
  BackupService(this._database, this._mediaStore);
  @override
  AppDatabase get database => _database;
  final AppDatabase _database;
  final LocalMediaStore _mediaStore;

  Future<bool> exportBackup() async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final destination = await FilePicker.saveFile(
      dialogTitle: '导出蚁记备份',
      fileName: 'antkeep-$timestamp.zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: await createBackupBytes(),
    );
    return destination != null;
  }

  Future<Uint8List> createBackupBytes() async {
    final data = await _database.snapshot();
    BackupData.validate(data);
    final paths = _database.photoPaths(data);
    if (paths.length + 1 > BackupArchive.maxEntries) {
      throw FormatException(
        '备份最多支持 ${BackupArchive.maxEntries - 1} 张照片，当前照片数量超出上限。',
      );
    }
    for (final path in paths) {
      BackupArchive.validateMediaPath(path);
    }
    final media = await _mediaStore.readFiles(paths);
    return _encodeBackup(data, media);
  }

  Uint8List _encodeBackup(
    Map<String, dynamic> data,
    Map<String, List<int>> media,
  ) {
    final archive = Archive();
    final manifestBytes = utf8.encode(
      jsonEncode({
        'format': 'antkeep',
        'version': backupVersion,
        'created_at': DateTime.now().toIso8601String(),
        'data': data,
        'media': media.keys.toList()..sort(),
      }),
    );
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    for (final entry in media.entries) {
      archive.addFile(
        ArchiveFile('media/${entry.key}', entry.value.length, entry.value),
      );
    }
    return BackupArchive.encode(archive);
  }

  Future<bool> restoreBackup({required BackupRestoreMode mode}) async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (selection.isEmpty) return false;
    await restoreBytes(await selection.single.readAsBytes(), mode: mode);
    return true;
  }

  Future<bool> hasRollback() => RollbackStore.instance.exists();

  Future<void> undoLastRestore() async {
    final bytes = await RollbackStore.instance.read();
    if (bytes == null) throw StateError('没有可撤销的恢复操作。');
    await restoreBytes(bytes);
  }

  Future<void> restoreBytes(
    Uint8List bytes, {
    BackupRestoreMode mode = BackupRestoreMode.overwrite,
  }) async {
    final archive = BackupArchive.decode(bytes);
    final files = {
      for (final file in archive.files.where((file) => file.isFile))
        file.name: file,
    };
    final manifestFile = files['manifest.json'];
    if (manifestFile == null) throw const FormatException('不是有效的蚁记备份。');
    final manifestBytes = manifestFile.readBytes();
    if (manifestBytes == null) throw const FormatException('备份清单无法读取。');
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('备份清单格式无效。');
    }
    validateManifestMap(manifest);
    var data = manifest['data'] as Map<String, dynamic>;
    BackupData.validate(data);
    final declaredMedia = (manifest['media'] as List).cast<String>().toSet();
    final referencedMedia = _database.photoPaths(data);
    if (!declaredMedia.containsAll(referencedMedia) ||
        !referencedMedia.containsAll(declaredMedia)) {
      throw const FormatException('备份中有照片记录，但缺少对应的照片文件。');
    }
    for (final relativePath in declaredMedia) {
      BackupArchive.validateMediaPath(relativePath);
    }
    BackupArchive.validateFiles(files, declaredMedia);
    var media = <String, List<int>>{};
    for (final relativePath in declaredMedia) {
      final file = files['media/$relativePath'];
      if (file == null) throw FormatException('备份缺少照片：$relativePath');
      final content = file.readBytes();
      if (content == null) throw FormatException('备份照片无法读取：$relativePath');
      media[relativePath] = content;
    }
    if (mode == BackupRestoreMode.incremental) {
      (data, media) = mergeMissing(await _database.snapshot(), data, media);
      BackupData.validate(data);
      // Keep the merged state exportable so a subsequent undo can also save it.
      final combinedMedia = await _mediaStore.readFiles(
        _database.photoPaths(data).difference(media.keys.toSet()),
      );
      _encodeBackup(data, {...combinedMedia, ...media});
    }
    final rollbackBytes = await createBackupBytes();
    await RollbackStore.instance.save(rollbackBytes);
    final mediaRestore = await _mediaStore.replaceFilesWithRollback(media);
    try {
      await _database.replaceAll(data);
    } catch (_) {
      await mediaRestore.rollback();
      rethrow;
    }
  }
}
