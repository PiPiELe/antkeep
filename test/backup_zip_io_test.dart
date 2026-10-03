import 'dart:io';
import 'dart:typed_data';

import 'package:antkeep/data/backup_archive.dart';
import 'package:antkeep/data/backup_resources.dart';
import 'package:antkeep/data/backup_zip_io.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-stream-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<File> legacyArchive({
    CompressionType compression = CompressionType.deflate,
  }) async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('manifest.json', [123, 125]))
      ..addFile(
        ArchiveFile.bytes(
          'media/photo.jpg',
          List<int>.generate(8192, (i) => i % 256),
        )..compression = compression,
      );
    return File('${directory.path}/legacy.zip')
        .writeAsBytes(ZipEncoder().encodeBytes(archive));
  }

  test(
    'file writer interoperates with archive decoder and streamed reader',
    () async {
      final source = await File('${directory.path}/photo.jpg')
          .writeAsBytes(List<int>.generate(1024 * 1024, (i) => i % 251));
      final output = File('${directory.path}/backup.zip');
      await BackupZip.write(output, Uint8List.fromList([123, 125]), {
        '照片.jpg': source.path,
      }, 64 * 1024);
      final decoded = BackupArchive.decode(await output.readAsBytes());
      expect(
        decoded.findFile('media/照片.jpg')!.readBytes(),
        await source.readAsBytes(),
      );
      final entries = await BackupZip.inspect(output);
      final extracted = File('${directory.path}/extracted.jpg');
      await BackupZip.extract(output, entries.last, extracted, 64 * 1024);
      expect(await extracted.readAsBytes(), await source.readAsBytes());
    },
  );

  for (final compression in [CompressionType.none, CompressionType.deflate]) {
    test('reads legacy $compression archives with CRC verification', () async {
      final zip = await legacyArchive(compression: compression);
      final entries = await BackupZip.inspect(zip);
      final extracted = File('${directory.path}/extracted.jpg');
      await BackupZip.extract(zip, entries.last, extracted, 64 * 1024);
      expect(await extracted.length(), 8192);
    });
  }

  test(
    'checks ZIP size from file length without reading a huge file',
    () async {
      final file = File('${directory.path}/too-large.zip');
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(BackupArchive.maxInputBytes + 1);
      await handle.close();
      await expectLater(BackupZip.inspect(file), throwsFormatException);
    },
  );

  test('rejects CRC damage and truncated file content', () async {
    final zip = await legacyArchive(compression: CompressionType.none);
    final entries = await BackupZip.inspect(zip);
    final handle = await zip.open(mode: FileMode.append);
    await handle.setPosition(entries.last.offset);
    await handle.writeByte(254);
    await handle.close();
    await expectLater(
      BackupZip.extract(
        zip,
        entries.last,
        File('${directory.path}/out'),
        65536,
      ),
      throwsFormatException,
    );
  });

  test(
    'enforces actual expanded size even if ZIP metadata understates it',
    () async {
      final zip = await legacyArchive();
      final entry = (await BackupZip.inspect(zip)).last;
      final forged = BackupZipEntry(
        entry.name,
        1,
        entry.compressedSize,
        entry.crc,
        entry.method,
        entry.offset,
      );
      final output = File('${directory.path}/out');
      await expectLater(
        BackupZip.extract(zip, forged, output, 65536),
        throwsFormatException,
      );
      expect(await output.length(), lessThanOrEqualTo(1));
    },
  );

  test('rejects inconsistent local headers before extracting', () async {
    final zip = await legacyArchive();
    final bytes = await zip.readAsBytes();
    bytes[14] ^= 1; // Local CRC no longer matches the central directory.
    await zip.writeAsBytes(bytes);
    await expectLater(BackupZip.inspect(zip), throwsFormatException);
  });

  test('rejects duplicate entry names and unsafe media paths', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('manifest.json', [123, 125]))
      ..addFile(ArchiveFile.bytes('media/a.jpg', [1]))
      ..addFile(ArchiveFile.bytes('media/b.jpg', [2]));
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    final pattern = 'media/b.jpg'.codeUnits;
    for (var i = 0; i <= bytes.length - pattern.length; i++) {
      if (List.generate(
        pattern.length,
        (j) => bytes[i + j] == pattern[j],
      ).every((v) => v)) {
        bytes[i + 6] = 'a'.codeUnitAt(0);
      }
    }
    final duplicate = await File('${directory.path}/duplicate.zip')
        .writeAsBytes(bytes);
    await expectLater(BackupZip.inspect(duplicate), throwsFormatException);
    final unsafe = Archive()
      ..addFile(ArchiveFile.bytes('media/../escape', [1]));
    final unsafeZip = await File('${directory.path}/unsafe.zip')
        .writeAsBytes(ZipEncoder().encodeBytes(unsafe));
    await expectLater(BackupZip.inspect(unsafeZip), throwsFormatException);
  });

  test('rejects an oversized source before creating a ZIP', () async {
    final source = File('${directory.path}/photo.jpg');
    final handle = await source.open(mode: FileMode.write);
    await handle.truncate(BackupArchive.maxSingleFileBytes + 1);
    await handle.close();
    final output = File('${directory.path}/out.zip');
    await expectLater(
      BackupZip.write(output, Uint8List(0), {'photo.jpg': source.path}, 65536),
      throwsFormatException,
    );
    expect(await output.exists(), isFalse);
  });

  test('uses current memory hints with conservative fallback', () async {
    expect(const BackupResources().bufferBytes, 256 * 1024);
    expect(
      const BackupResources(availableMemory: 128 * 1024 * 1024).bufferBytes,
      64 * 1024,
    );
    expect(
      const BackupResources(availableMemory: 2 * 1024 * 1024 * 1024)
          .bufferBytes,
      1024 * 1024,
    );
    expect(
      const BackupResources(
        availableMemory: 2 * 1024 * 1024 * 1024,
        lowMemory: true,
      ).bufferBytes,
      64 * 1024,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      BackupResources.channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    expect(
      (await BackupResources.read(directory.path)).bufferBytes,
      256 * 1024,
    );
    messenger.setMockMethodCallHandler(BackupResources.channel, null);
  });

  test('disk-space guard includes reserve', () {
    expect(
      () =>
          const BackupResources(freeDisk: 64 * 1024 * 1024)
              .requireDisk(40 * 1024 * 1024),
      throwsStateError,
    );
    expect(
      () =>
          const BackupResources(freeDisk: 64 * 1024 * 1024)
              .requireDisk(16 * 1024 * 1024),
      returnsNormally,
    );
  });
}
