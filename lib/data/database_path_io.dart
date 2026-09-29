import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<String> applicationDatabasePath() async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory(path.join(root.path, 'antkeep'));
  await directory.create(recursive: true);
  return path.join(directory.path, 'antkeep.sqlite');
}
