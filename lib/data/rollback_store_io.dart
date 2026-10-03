import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class RollbackStore {
  RollbackStore._();
  static final instance = RollbackStore._();

  Future<void> save(Uint8List bytes) async {
    final destination = await file();
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
  }

  Future<void> saveFile(File source) async {
    final destination = await file();
    final temporary = File('${destination.path}.tmp');
    try {
      await source.copy(temporary.path);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Uint8List?> read() async {
    final source = await file();
    return await source.exists() ? source.readAsBytes() : null;
  }

  Future<bool> exists() async => (await file()).exists();

  Future<File> file() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'antkeep'));
    await directory.create(recursive: true);
    return File(path.join(directory.path, 'restore-rollback.zip'));
  }
}
