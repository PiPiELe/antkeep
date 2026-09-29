import 'dart:typed_data';

import 'package:archive/archive.dart';

class BackupArchive {
  BackupArchive._();

  static const maxInputBytes = 128 * 1024 * 1024;
  static const maxEntries = 500;
  static const maxTotalUncompressedBytes = 192 * 1024 * 1024;
  static const maxSingleFileBytes = 24 * 1024 * 1024;
  static const maxManifestBytes = 1024 * 1024;

  static Uint8List encode(Archive archive) {
    validateArchive(archive);
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    _validateInputSize(bytes);
    return bytes;
  }

  static void _validateInputSize(Uint8List bytes) {
    if (bytes.length > maxInputBytes) {
      throw const FormatException('备份文件超过 128 MB 的大小上限。');
    }
  }

  static Archive decode(Uint8List bytes) {
    _validateInputSize(bytes);
    _preflightZip(bytes);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    validateArchive(archive);
    return archive;
  }

  static void _preflightZip(Uint8List bytes) {
    const endOfCentralDirectory = 0x06054b50;
    const centralDirectoryHeader = 0x02014b50;
    final data = ByteData.sublistView(bytes);
    final firstEndOfCentralDirectory = bytes.length - 22 - 0xffff;
    var endOffset = -1;
    for (
      var offset = bytes.length - 22;
      offset >=
          (firstEndOfCentralDirectory < 0 ? 0 : firstEndOfCentralDirectory);
      offset--
    ) {
      if (data.getUint32(offset, Endian.little) == endOfCentralDirectory) {
        endOffset = offset;
        break;
      }
    }
    if (endOffset < 0 || endOffset + 22 > bytes.length) {
      throw const FormatException('不是有效的 ZIP 备份。');
    }

    final entriesOnDisk = data.getUint16(endOffset + 8, Endian.little);
    final entryCount = data.getUint16(endOffset + 10, Endian.little);
    final directorySize = data.getUint32(endOffset + 12, Endian.little);
    final directoryOffset = data.getUint32(endOffset + 16, Endian.little);
    if (entriesOnDisk != entryCount || entryCount > maxEntries) {
      throw const FormatException('备份包含的文件过多或跨磁盘 ZIP。');
    }
    final directoryEnd = directoryOffset + directorySize;
    if (directoryEnd > endOffset || directoryEnd < directoryOffset) {
      throw const FormatException('备份目录无效。');
    }

    var cursor = directoryOffset;
    var totalSize = 0;
    for (var index = 0; index < entryCount; index++) {
      if (cursor + 46 > directoryEnd ||
          data.getUint32(cursor, Endian.little) != centralDirectoryHeader) {
        throw const FormatException('备份目录无效。');
      }
      final compressedSize = data.getUint32(cursor + 20, Endian.little);
      final uncompressedSize = data.getUint32(cursor + 24, Endian.little);
      final fileNameLength = data.getUint16(cursor + 28, Endian.little);
      final extraLength = data.getUint16(cursor + 30, Endian.little);
      final commentLength = data.getUint16(cursor + 32, Endian.little);
      final externalAttributes = data.getUint32(cursor + 38, Endian.little);
      final localHeaderOffset = data.getUint32(cursor + 42, Endian.little);
      final fileType = (externalAttributes >> 16) & 0xf000;
      if (compressedSize == 0xffffffff ||
          uncompressedSize == 0xffffffff ||
          localHeaderOffset == 0xffffffff ||
          fileType == 0xa000) {
        throw const FormatException('备份包含不支持的 ZIP 条目。');
      }
      if (uncompressedSize > maxSingleFileBytes) {
        throw const FormatException('备份中存在超出大小限制的文件。');
      }
      totalSize += uncompressedSize;
      if (totalSize > maxTotalUncompressedBytes) {
        throw const FormatException('备份解压后的内容超过导入上限。');
      }
      cursor += 46 + fileNameLength + extraLength + commentLength;
    }
    if (cursor != directoryEnd) {
      throw const FormatException('备份目录无效。');
    }
  }

  static void validateArchive(Archive archive) {
    final files = archive.files.where((file) => file.isFile).toList();
    if (files.length > maxEntries) {
      throw const FormatException('备份包含的文件过多。');
    }
    var totalSize = 0;
    for (final file in files) {
      if (file.isSymbolicLink || file.size < 0) {
        throw const FormatException('备份包含不支持的文件。');
      }
      final limit = file.name == 'manifest.json'
          ? maxManifestBytes
          : maxSingleFileBytes;
      if (file.size > limit) {
        throw const FormatException('备份中存在超出大小限制的文件。');
      }
      totalSize += file.size;
      if (totalSize > maxTotalUncompressedBytes) {
        throw const FormatException('备份解压后的内容超过导入上限。');
      }
    }
  }

  static void validateFiles(
    Map<String, ArchiveFile> files,
    Set<String> declaredMedia,
  ) {
    final expectedFiles = <String>{
      'manifest.json',
      ...declaredMedia.map((relativePath) => 'media/$relativePath'),
    };
    if (files.length != expectedFiles.length ||
        !files.keys.every(expectedFiles.contains)) {
      throw const FormatException('备份包含未声明的文件。');
    }
  }

  static void validateMediaPath(String relativePath) {
    if (relativePath.isEmpty ||
        relativePath.contains('..') ||
        relativePath.contains('/') ||
        relativePath.contains('\\')) {
      throw const FormatException('备份中的照片路径无效。');
    }
  }
}
