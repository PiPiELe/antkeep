import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class RollbackStore {
  RollbackStore._();
  static final instance = RollbackStore._();

  Future<void> save(Uint8List bytes) async {
    final destination = await _file();
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
  }

  Future<Uint8List?> read() async {
    final file = await _file();
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<bool> exists() async => (await _file()).exists();

  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'antkeep'));
    await directory.create(recursive: true);
    return File(path.join(directory.path, 'restore-rollback.zip'));
  }
}
