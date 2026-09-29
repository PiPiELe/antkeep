import 'dart:typed_data';

import 'package:antkeep/data/backup_archive.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a normal archive before reading its contents', () {
    final archive = Archive()
      ..add(ArchiveFile('manifest.json', 2, [123, 125]))
      ..add(ArchiveFile('media/a.jpg', 1, [1]));

    final decoded = BackupArchive.decode(
      Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );

    expect(decoded.files.where((file) => file.isFile), hasLength(2));
  });

  test('rejects archive entries that exceed the media size limit', () {
    final archive = Archive()
      ..add(
        ArchiveFile(
          'media/large.jpg',
          BackupArchive.maxSingleFileBytes + 1,
          const [],
        ),
      );

    expect(
      () => BackupArchive.validateArchive(archive),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects undeclared archive entries', () {
    final files = <String, ArchiveFile>{
      'manifest.json': ArchiveFile('manifest.json', 0, const []),
      'media/a.jpg': ArchiveFile('media/a.jpg', 0, const []),
      'media/unreferenced.jpg': ArchiveFile(
        'media/unreferenced.jpg',
        0,
        const [],
      ),
    };

    expect(
      () => BackupArchive.validateFiles(files, {'a.jpg'}),
      throwsA(isA<FormatException>()),
    );
  });
}
