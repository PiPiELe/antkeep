import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'backup_resources.dart';

class LocalMediaStore {
  LocalMediaStore._();
  static final instance = LocalMediaStore._();
  static const _channel = MethodChannel('com.pipiele.antkeep/storage');
  final _uuid = const Uuid();
  Directory? _directory;

  Future<void> initialize() async {
    if (_directory != null) return;
    final root = await getApplicationSupportDirectory();
    _directory = Directory(path.join(root.path, 'antkeep', 'media'));
    await _directory!.create(recursive: true);
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod<void>('excludeFromCloudBackup', {
          'path': _directory!.parent.path,
        });
      } on PlatformException {
        // The app remains usable if the operating system rejects the marker.
      }
    }
  }

  Directory get _mediaDirectory =>
      _directory ?? (throw StateError('Media store has not been initialized.'));

  Future<String> copyImage(XFile image) async {
    final extension = path.extension(image.name).toLowerCase();
    final relativePath =
        '${_uuid.v4()}${extension.isEmpty ? '.jpg' : extension}';
    await File(image.path).copy(path.join(_mediaDirectory.path, relativePath));
    return relativePath;
  }

  Future<Uint8List> readImage(String relativePath) =>
      _fileFor(relativePath).then((file) => file.readAsBytes());

  Future<Map<String, List<int>>> readFiles(
    Iterable<String> relativePaths,
  ) async {
    final files = <String, List<int>>{};
    for (final relativePath in relativePaths) {
      final file = await _fileFor(relativePath);
      if (!await file.exists()) throw StateError('备份无法创建：缺少照片 $relativePath');
      files[relativePath] = await file.readAsBytes();
    }
    return files;
  }

  Future<Map<String, String>> filePaths(Iterable<String> names) async {
    final files = <String, String>{};
    for (final name in names) {
      final file = await _fileFor(name);
      if (!await file.exists()) throw StateError('备份无法创建：缺少照片 $name');
      files[name] = file.path;
    }
    return files;
  }

  Future<int> overwrittenBytes(Iterable<String> names) async {
    var size = 0;
    for (final name in names) {
      final file = await _fileFor(name);
      if (await file.exists()) size += await file.length();
    }
    return size;
  }

  Future<DiskMediaRestore> installFiles(
    Map<String, String> files,
    Directory undo,
  ) async {
    await undo.create(recursive: true);
    final previous = <String, String?>{};
    final change = DiskMediaRestore._(this, previous);
    try {
      for (final entry in files.entries) {
        final destination = await _fileFor(entry.key);
        if (await destination.exists()) {
          final saved = await destination.copy(path.join(undo.path, entry.key));
          previous[entry.key] = saved.path;
        } else {
          previous[entry.key] = null;
        }
        await File(entry.value).copy(destination.path);
      }
      return change;
    } catch (_) {
      try {
        await change.rollback();
      } catch (_) {
        throw BackupRecoveryFailure(undo.parent.path);
      }
      rethrow;
    }
  }

  Future<void> restoreFiles(Map<String, List<int>> files) async {
    for (final entry in files.entries) {
      final file = await _fileFor(entry.key);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value, flush: true);
    }
  }

  Future<MediaRestore> replaceFilesWithRollback(
    Map<String, List<int>> files,
  ) async {
    final previous = <String, List<int>>{};
    final created = <String>{};
    try {
      for (final entry in files.entries) {
        final file = await _fileFor(entry.key);
        if (await file.exists()) {
          previous[entry.key] = await file.readAsBytes();
        } else {
          created.add(entry.key);
        }
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
    } catch (_) {
      await _restorePrevious(previous, created);
      rethrow;
    }
    return MediaRestore._(this, previous, created);
  }

  Future<File> _fileFor(String relativePath) async {
    if (relativePath.isEmpty ||
        path.isAbsolute(relativePath) ||
        relativePath.contains('..') ||
        relativePath.contains('/')) {
      throw const FormatException('Invalid media path.');
    }
    return File(path.join(_mediaDirectory.path, relativePath));
  }

  Future<void> _restorePrevious(
    Map<String, List<int>> previous,
    Set<String> created,
  ) async {
    await restoreFiles(previous);
    for (final relativePath in created) {
      final file = await _fileFor(relativePath);
      if (await file.exists()) await file.delete();
    }
  }
}

class MediaRestore {
  MediaRestore._(this._store, this._previous, this._created);
  final LocalMediaStore _store;
  final Map<String, List<int>> _previous;
  final Set<String> _created;

  Future<void> rollback() => _store._restorePrevious(_previous, _created);
}

class DiskMediaRestore {
  DiskMediaRestore._(this._store, this._previous);
  final LocalMediaStore _store;
  final Map<String, String?> _previous;

  Future<void> rollback() async {
    for (final entry in _previous.entries) {
      final destination = await _store._fileFor(entry.key);
      if (entry.value != null) {
        await File(entry.value!).copy(destination.path);
      } else if (await destination.exists()) {
        await destination.delete();
      }
    }
  }
}
