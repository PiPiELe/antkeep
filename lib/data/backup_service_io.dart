import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'backup_archive.dart';
import 'backup_logic.dart';
import 'backup_resources.dart';
import 'backup_zip_io.dart';
import 'local_media_store.dart';
import 'rollback_store.dart';

class BackupService with BackupLogic {
  BackupService(this.database, this._mediaStore);
  @override
  final AppDatabase database;
  final LocalMediaStore _mediaStore;
  static bool _busy = false;

  Future<T> _operation<T>(Future<T> Function(Directory) action) async {
    if (_busy) throw StateError('正在处理备份，请等待当前操作完成。');
    _busy = true;
    Directory? temporary;
    var preserveRecovery = false;
    try {
      final root = await getApplicationSupportDirectory();
      final parent = Directory(path.join(root.path, 'antkeep', 'backup-work'));
      await parent.create(recursive: true);
      temporary = await parent.createTemp('operation-');
      return await action(temporary);
    } on BackupRecoveryFailure {
      preserveRecovery = true;
      rethrow;
    } finally {
      try {
        if (temporary != null && !preserveRecovery) {
          await temporary.delete(recursive: true);
        }
      } on FileSystemException {
        // Cleanup failure must not turn a completed database restore into an error.
      }
      _busy = false;
    }
  }

  Future<File> _encode(
    Directory temporary,
    String name,
    Map<String, dynamic> data,
    Map<String, String> media,
  ) async {
    final manifest = encodeManifest(data, media.keys);
    var expanded = manifest.length;
    for (final source in media.values) {
      final size = await File(source).length();
      if (size > BackupArchive.maxSingleFileBytes) {
        throw const FormatException('备份中存在超出大小限制的文件。');
      }
      expanded += size;
    }
    if (expanded > BackupArchive.maxTotalUncompressedBytes) {
      throw const FormatException('备份解压后的内容超过导入上限。');
    }
    final resources = await BackupResources.read(temporary.path);
    // Deflate may slightly grow incompressible files; include headers and margin.
    resources.requireDisk(expanded + expanded ~/ 100 + 1024 * 1024);
    final output = File(path.join(temporary.path, name));
    final buffer = resources.bufferBytes;
    await Isolate.run(() => BackupZip.write(output, manifest, media, buffer));
    return output;
  }

  Future<File> _snapshot(Directory temporary, String name) async {
    final data = await database.snapshot();
    final names = database.photoPaths(data);
    encodeManifest(
      data,
      names,
    ); // Reject entry/manifest limits before opening attachments.
    return _encode(temporary, name, data, await _mediaStore.filePaths(names));
  }

  Future<bool> exportBackup() => _operation((temporary) async {
    final file = await _snapshot(temporary, 'export.zip');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    if (Platform.isAndroid || Platform.isIOS) {
      return await BackupResources.channel.invokeMethod<bool>('saveBackup', {
            'path': file.path,
            'name': 'antkeep-$timestamp.zip',
          }) ??
          false;
    }
    // The app targets phones; retain the desktop preview's existing save API.
    return await FilePicker.saveFile(
          fileName: 'antkeep-$timestamp.zip',
          bytes: await file.readAsBytes(),
          mimeType: 'application/zip',
        ) !=
        null;
  });

  /// Byte APIs remain for callers/tests. The mobile UI uses file APIs exclusively.
  Future<Uint8List> createBackupBytes() => _operation(
    (temporary) async =>
        (await _snapshot(temporary, 'export.zip')).readAsBytes(),
  );

  Future<void> writeBackupFile(File destination) =>
      _operation((temporary) async {
        final source = await _snapshot(temporary, 'export.zip');
        final staging = File('${destination.path}.tmp');
        try {
          await source.copy(staging.path);
          await staging.rename(destination.path);
        } finally {
          if (await staging.exists()) await staging.delete();
        }
      });

  Future<bool> restoreBackup({required BackupRestoreMode mode}) => _operation((
    temporary,
  ) async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (selection.isEmpty) return false;
    // Native file_picker materializes the selected document as a local file.
    final selected = selection.single;
    if (selected.uri.scheme != 'file') throw StateError('无法读取所选备份，请先将文件保存到手机。');
    await _restore(File.fromUri(selected.uri), temporary, mode);
    return true;
  });

  Future<bool> hasRollback() => RollbackStore.instance.exists();

  Future<void> undoLastRestore() => _operation((temporary) async {
    final file = await RollbackStore.instance.file();
    if (!await file.exists()) throw StateError('没有可撤销的恢复操作。');
    await _restore(file, temporary, BackupRestoreMode.overwrite);
  });

  Future<void> restoreBytes(
    Uint8List bytes, {
    BackupRestoreMode mode = BackupRestoreMode.overwrite,
  }) => _operation((temporary) async {
    if (bytes.length > BackupArchive.maxInputBytes) {
      throw const FormatException('备份文件超过 512 MB 的大小上限。');
    }
    final file = File(path.join(temporary.path, 'input.zip'));
    await file.writeAsBytes(bytes, flush: true);
    await _restore(file, temporary, mode);
  });

  Future<void> restoreFile(
    File file, {
    BackupRestoreMode mode = BackupRestoreMode.overwrite,
  }) => _operation((temporary) => _restore(file, temporary, mode));

  Future<void> _restore(
    File input,
    Directory temporary,
    BackupRestoreMode mode,
  ) async {
    final entries = await BackupZip.inspect(input);
    final manifestEntry = entries
        .where((entry) => entry.name == 'manifest.json')
        .firstOrNull;
    if (manifestEntry == null) throw const FormatException('不是有效的蚁记备份。');
    final resources = await BackupResources.read(temporary.path);
    final expanded = entries.fold(0, (sum, entry) => sum + entry.size);
    resources.requireDisk(expanded);
    final manifestFile = File(path.join(temporary.path, 'manifest.json'));
    final buffer = resources.bufferBytes;
    await Isolate.run(
      () => BackupZip.extract(input, manifestEntry, manifestFile, buffer),
    );
    var (data, declared) = parseManifest(
      await manifestFile.readAsBytes(),
      entries.map((e) => e.name).toSet(),
    );
    final extracted = Directory(path.join(temporary.path, 'incoming'));
    await extracted.create();
    final extractedPath = extracted.path;
    await Isolate.run(() async {
      for (final entry in entries) {
        if (entry.name == 'manifest.json') continue;
        await BackupZip.extract(
          input,
          entry,
          File(path.join(extractedPath, entry.name.substring(6))),
          buffer,
        );
      }
    });
    var media = {
      for (final name in declared) name: path.join(extracted.path, name),
    };
    if (mode == BackupRestoreMode.incremental) {
      (data, media) = mergeMissing(await database.snapshot(), data, media);
      final existing = await _mediaStore.filePaths(
        database.photoPaths(data).difference(media.keys.toSet()),
      );
      // Verify the merged state remains exportable (including compressed ZIP size).
      final merged = await _encode(temporary, 'merged.zip', data, {
        ...existing,
        ...media,
      });
      await merged.delete();
    }
    final rollback = await _snapshot(temporary, 'rollback.zip');
    final rollbackStore = RollbackStore.instance;
    final destination = await rollbackStore.file();
    final previousSize = await destination.exists()
        ? await destination.length()
        : 0;
    final undoSize = await _mediaStore.overwrittenBytes(media.keys);
    // Stage the incoming files, old media and previous rollback on disk before
    // changing SQLite. Native free-space values are refreshed at each stage.
    final latestResources = await BackupResources.read(temporary.path);
    var incomingSize = 0;
    for (final source in media.values) {
      incomingSize += await File(source).length();
    }
    latestResources.requireDisk(
      incomingSize + undoSize + previousSize + await rollback.length(),
    );
    final previous = await destination.exists()
        ? await destination.copy(
            path.join(temporary.path, 'previous-rollback.zip'),
          )
        : null;
    final change = await _mediaStore.installFiles(
      media,
      Directory(path.join(temporary.path, 'undo-media')),
    );
    var rollbackSaved = false;
    try {
      await rollbackStore.saveFile(rollback);
      rollbackSaved = true;
      await database.replaceAll(data);
    } catch (_) {
      Object? recoveryError;
      try {
        await change.rollback();
      } catch (error) {
        recoveryError = error;
      }
      try {
        if (rollbackSaved) {
          if (previous != null) {
            await rollbackStore.saveFile(previous);
          } else if (await destination.exists()) {
            await destination.delete();
          }
        }
      } catch (error) {
        recoveryError = error;
      }
      if (recoveryError != null) throw BackupRecoveryFailure(temporary.path);
      rethrow;
    }
  }
}
