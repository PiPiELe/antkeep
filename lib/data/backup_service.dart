import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import 'app_database.dart';
import 'local_media_store.dart';

class BackupService {
  BackupService(this._database, this._mediaStore);
  static const _version = 1;
  final AppDatabase _database;
  final LocalMediaStore _mediaStore;

  Future<void> exportBackup() async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await FilePicker.saveFile(
      dialogTitle: '导出蚁记备份',
      fileName: 'antkeep-$timestamp.zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: await createBackupBytes(),
    );
  }

  Future<Uint8List> createBackupBytes() async {
    final data = await _database.snapshot();
    final media = await _mediaStore.readFiles(_database.photoPaths(data));
    final archive = Archive();
    final manifestBytes = utf8.encode(
      jsonEncode({
        'format': 'antkeep',
        'version': _version,
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
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  Future<void> restoreBackup() async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (selection.isEmpty) return;
    await restoreBytes(await selection.single.readAsBytes());
  }

  Future<void> restoreBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final files = {
      for (final file in archive.files.where((file) => file.isFile))
        file.name: file,
    };
    final manifestFile = files['manifest.json'];
    if (manifestFile == null) throw const FormatException('不是有效的蚁记备份。');
    final manifestBytes = manifestFile.readBytes();
    if (manifestBytes == null) throw const FormatException('备份清单无法读取。');
    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    _validate(manifest);
    final data = manifest['data'] as Map<String, dynamic>;
    final declaredMedia = (manifest['media'] as List).cast<String>().toSet();
    final referencedMedia = _database.photoPaths(data);
    if (!declaredMedia.containsAll(referencedMedia)) {
      throw const FormatException('备份中有照片记录，但缺少对应的照片文件。');
    }
    final media = <String, List<int>>{};
    for (final relativePath in declaredMedia) {
      final file = files['media/$relativePath'];
      if (file == null) throw FormatException('备份缺少照片：$relativePath');
      final content = file.readBytes();
      if (content == null) throw FormatException('备份照片无法读取：$relativePath');
      media[relativePath] = content;
    }
    final mediaRestore = await _mediaStore.replaceFilesWithRollback(media);
    try {
      await _database.replaceAll(data);
    } catch (_) {
      await mediaRestore.rollback();
      rethrow;
    }
  }

  void _validate(Map<String, dynamic> manifest) {
    final data = manifest['data'];
    if (manifest['format'] != 'antkeep' ||
        manifest['version'] != _version ||
        data is! Map<String, dynamic> ||
        data['colonies'] is! List ||
        data['care_records'] is! List ||
        manifest['media'] is! List ||
        !(manifest['media'] as List).every((path) => path is String)) {
      throw const FormatException('备份格式、版本或数据不完整。');
    }
  }
}
