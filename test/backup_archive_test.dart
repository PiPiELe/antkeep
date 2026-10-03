import 'dart:typed_data';

import 'package:antkeep/data/backup_archive.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export rejects an oversized manifest before encoding', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'manifest.json',
          BackupArchive.maxManifestBytes + 1,
          const [],
        ),
      );
    expect(() => BackupArchive.encode(archive), throwsFormatException);
  });

  test('export rejects oversized media before encoding', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'media/large.jpg',
          BackupArchive.maxSingleFileBytes + 1,
          const [],
        ),
      );
    expect(() => BackupArchive.encode(archive), throwsFormatException);
  });

  test('export rejects excessive total uncompressed size', () {
    final archive = Archive();
    final fileCount =
        BackupArchive.maxTotalUncompressedBytes ~/
        BackupArchive.maxSingleFileBytes;
    for (var i = 0; i <= fileCount; i++) {
      archive.addFile(
        ArchiveFile('media/$i.jpg', BackupArchive.maxSingleFileBytes, const []),
      );
    }
    expect(() => BackupArchive.encode(archive), throwsFormatException);
  });

  test('accepts a normal archive before reading its contents', () {
    final archive = Archive()
      ..add(ArchiveFile('manifest.json', 2, [123, 125]))
      ..add(ArchiveFile('media/a.jpg', 1, [1]));

    final decoded = BackupArchive.decode(
      Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );

    expect(decoded.files.where((file) => file.isFile), hasLength(2));
  });

  test('round trips files larger than the former limits', () {
    final manifest = Uint8List(2 * 1024 * 1024)..last = 125;
    final media = Uint8List(25 * 1024 * 1024)..last = 42;
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('manifest.json', manifest))
      ..addFile(ArchiveFile.bytes('media/large.jpg', media));

    final decoded = BackupArchive.decode(BackupArchive.encode(archive));
    expect(decoded.findFile('manifest.json')!.readBytes(), manifest);
    expect(decoded.findFile('media/large.jpg')!.readBytes(), media);
  });

  test('accepts exact size limits and rejects one extra byte', () {
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', 8 * 1024 * 1024, const []));
    for (var i = 0; i < 11; i++) {
      archive.addFile(ArchiveFile('media/$i.jpg', 64 * 1024 * 1024, const []));
    }
    final lastFile = ArchiveFile('media/last.jpg', 56 * 1024 * 1024, const []);
    archive.addFile(lastFile);

    expect(() => BackupArchive.validateArchive(archive), returnsNormally);
    lastFile.size++;
    expect(() => BackupArchive.encode(archive), throwsFormatException);
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
