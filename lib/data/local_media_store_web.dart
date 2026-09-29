import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

class LocalMediaStore {
  LocalMediaStore._();
  static final instance = LocalMediaStore._();
  static const _prefix = 'antkeep-media:';
  final _uuid = const Uuid();

  Future<void> initialize() async {}

  Future<String> copyImage(XFile image) async {
    final extension = path.extension(image.name).toLowerCase();
    final relativePath =
        '${_uuid.v4()}${extension.isEmpty ? '.jpg' : extension}';
    web.window.localStorage.setItem(
      '$_prefix$relativePath',
      base64Encode(await image.readAsBytes()),
    );
    return relativePath;
  }

  Future<Uint8List> readImage(String relativePath) async =>
      Uint8List.fromList(base64Decode(_read(relativePath)));

  Future<Map<String, List<int>>> readFiles(
    Iterable<String> relativePaths,
  ) async => {
    for (final path in relativePaths) path: base64Decode(_read(path)),
  };

  Future<void> restoreFiles(Map<String, List<int>> files) async {
    for (final entry in files.entries) {
      _validate(entry.key);
      web.window.localStorage.setItem(
        '$_prefix${entry.key}',
        base64Encode(entry.value),
      );
    }
  }

  Future<MediaRestore> replaceFilesWithRollback(
    Map<String, List<int>> files,
  ) async {
    final previous = <String, String?>{};
    try {
      for (final entry in files.entries) {
        _validate(entry.key);
        final key = '$_prefix${entry.key}';
        previous[entry.key] = web.window.localStorage.getItem(key);
        web.window.localStorage.setItem(key, base64Encode(entry.value));
      }
    } catch (_) {
      await _restorePrevious(previous);
      rethrow;
    }
    return MediaRestore._(this, previous);
  }

  String _read(String relativePath) {
    _validate(relativePath);
    final encoded = web.window.localStorage.getItem('$_prefix$relativePath');
    if (encoded == null) throw StateError('备份无法创建：缺少照片 $relativePath');
    return encoded;
  }

  void _validate(String relativePath) {
    if (relativePath.isEmpty ||
        path.isAbsolute(relativePath) ||
        relativePath.contains('..') ||
        relativePath.contains('/')) {
      throw const FormatException('Invalid media path.');
    }
  }

  Future<void> _restorePrevious(Map<String, String?> previous) async {
    for (final entry in previous.entries) {
      final key = '$_prefix${entry.key}';
      if (entry.value == null) {
        web.window.localStorage.removeItem(key);
      } else {
        web.window.localStorage.setItem(key, entry.value!);
      }
    }
  }
}

class MediaRestore {
  MediaRestore._(this._store, this._previous);
  final LocalMediaStore _store;
  final Map<String, String?> _previous;

  Future<void> rollback() => _store._restorePrevious(_previous);
}
