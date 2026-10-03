import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

import 'backup_archive.dart';

class BackupZipEntry {
  const BackupZipEntry(
    this.name,
    this.size,
    this.compressedSize,
    this.crc,
    this.method,
    this.offset,
  );
  final String name;
  final int size, compressedSize, crc, method, offset;
}

/// ZIP32 store/deflate with bounded, backpressured disk I/O. No archive-sized
/// byte arrays; CRC and actual expanded lengths are checked while extracting.
class BackupZip {
  static Future<List<BackupZipEntry>> inspect(File file) async {
    final input = await file.open();
    try {
      final length = await input.length();
      if (length > BackupArchive.maxInputBytes) {
        throw const FormatException('备份文件超过 512 MB 的大小上限。');
      }
      if (length < 22) throw const FormatException('不是有效的 ZIP 备份。');
      final tailOffset = max(0, length - 22 - 0xffff);
      final tail = await _read(input, tailOffset, length - tailOffset);
      var end = -1;
      for (var i = tail.lengthInBytes - 22; i >= 0; i--) {
        if (tail.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + tail.getUint16(i + 20, Endian.little) ==
                tail.lengthInBytes) {
          end = i;
          break;
        }
      }
      if (end < 0) throw const FormatException('备份目录无效。');
      final count = tail.getUint16(end + 10, Endian.little);
      final directorySize = tail.getUint32(end + 12, Endian.little);
      final directoryOffset = tail.getUint32(end + 16, Endian.little);
      if (count > BackupArchive.maxEntries ||
          tail.getUint16(end + 4, Endian.little) != 0 ||
          tail.getUint16(end + 6, Endian.little) != 0 ||
          tail.getUint16(end + 8, Endian.little) != count ||
          directoryOffset + directorySize != tailOffset + end) {
        throw const FormatException('备份文件过多或 ZIP 目录不受支持。');
      }
      final entries = <BackupZipEntry>[];
      final names = <String>{};
      final ranges = <(int, int)>[];
      var cursor = directoryOffset;
      var total = 0;
      for (var i = 0; i < count; i++) {
        if (cursor + 46 > directoryOffset + directorySize) {
          throw const FormatException('备份目录无效。');
        }
        final header = await _read(input, cursor, 46);
        final flags = header.getUint16(8, Endian.little);
        final method = header.getUint16(10, Endian.little);
        final crc = header.getUint32(16, Endian.little);
        final compressed = header.getUint32(20, Endian.little);
        final size = header.getUint32(24, Endian.little);
        final nameLength = header.getUint16(28, Endian.little);
        final extraLength = header.getUint16(30, Endian.little);
        final commentLength = header.getUint16(32, Endian.little);
        final attrs = header.getUint32(38, Endian.little);
        final local = header.getUint32(42, Endian.little);
        if (header.getUint32(0, Endian.little) != 0x02014b50 ||
            flags & 0x41 != 0 ||
            (method != 0 && method != 8) ||
            compressed == 0xffffffff ||
            local == 0xffffffff ||
            header.getUint16(34, Endian.little) != 0 ||
            (attrs >> 16) & 0xf000 == 0xa000 ||
            nameLength > 4096 ||
            cursor + 46 + nameLength + extraLength + commentLength >
                directoryOffset + directorySize) {
          throw const FormatException('备份包含不支持的 ZIP 条目。');
        }
        final nameData = await _read(input, cursor + 46, nameLength);
        final nameBytes = nameData.buffer.asUint8List();
        final name = utf8.decode(nameBytes);
        if (!names.add(name)) throw const FormatException('备份包含重复文件。');
        if (name != 'manifest.json' && name != 'media/') {
          if (!name.startsWith('media/')) {
            throw const FormatException('备份包含未声明的文件。');
          }
          BackupArchive.validateMediaPath(name.substring(6));
        }
        final limit = name == 'manifest.json'
            ? BackupArchive.maxManifestBytes
            : BackupArchive.maxSingleFileBytes;
        if (size > limit || (name == 'media/' && size != 0)) {
          throw const FormatException('备份中存在超出大小限制的文件。');
        }
        total += size;
        if (total > BackupArchive.maxTotalUncompressedBytes) {
          throw const FormatException('备份解压后的内容超过导入上限。');
        }
        if (local + 30 > directoryOffset) {
          throw const FormatException('备份文件头无效。');
        }
        final localHeader = await _read(input, local, 30);
        final localNameLength = localHeader.getUint16(26, Endian.little);
        final dataOffset =
            local +
            30 +
            localNameLength +
            localHeader.getUint16(28, Endian.little);
        if (localHeader.getUint32(0, Endian.little) != 0x04034b50 ||
            localHeader.getUint16(6, Endian.little) != flags ||
            localHeader.getUint16(8, Endian.little) != method ||
            localNameLength != nameLength ||
            dataOffset + compressed > directoryOffset ||
            (flags & 8 == 0 &&
                (localHeader.getUint32(14, Endian.little) != crc ||
                    localHeader.getUint32(18, Endian.little) != compressed ||
                    localHeader.getUint32(22, Endian.little) != size))) {
          throw const FormatException('备份文件头与目录不一致。');
        }
        final localName = await _read(input, local + 30, localNameLength);
        if (utf8.decode(localName.buffer.asUint8List()) != name) {
          throw const FormatException('备份文件名不一致。');
        }
        ranges.add((local, dataOffset + compressed));
        if (name != 'media/') {
          entries.add(
            BackupZipEntry(name, size, compressed, crc, method, dataOffset),
          );
        }
        cursor += 46 + nameLength + extraLength + commentLength;
      }
      ranges.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < ranges.length; i++) {
        if (ranges[i].$1 < ranges[i - 1].$2) {
          throw const FormatException('备份文件内容重叠。');
        }
      }
      if (cursor != directoryOffset + directorySize) {
        throw const FormatException('备份目录无效。');
      }
      return entries;
    } finally {
      await input.close();
    }
  }

  static Future<ByteData> _read(
    RandomAccessFile file,
    int offset,
    int count,
  ) async {
    await file.setPosition(offset);
    final bytes = await file.read(count);
    if (bytes.length != count) throw const FormatException('备份文件不完整。');
    return ByteData.sublistView(bytes);
  }

  static Future<void> extract(
    File zip,
    BackupZipEntry entry,
    File destination,
    int bufferBytes,
  ) async {
    final output = await destination.open(mode: FileMode.write);
    var size = 0;
    var crc = 0;
    try {
      Stream<List<int>> stream = _chunks(
        zip,
        entry.offset,
        entry.compressedSize,
        // A single deflate input chunk can expand many times before the stream
        // pauses. Bound it separately from the adaptive file-copy buffer.
        entry.method == 8 ? min(bufferBytes, 8 * 1024) : bufferBytes,
      );
      if (entry.method == 8) stream = stream.transform(ZLibDecoder(raw: true));
      await for (final bytes in stream) {
        size += bytes.length;
        if (size > entry.size) throw const FormatException('备份实际解压大小超过声明。');
        crc = getCrc32(bytes, crc);
        await output.writeFrom(bytes);
      }
      if (size != entry.size || crc != entry.crc) {
        throw const FormatException('备份文件损坏或校验失败。');
      }
      await output.flush();
    } finally {
      await output.close();
    }
  }

  static Stream<List<int>> _chunks(
    File file,
    int offset,
    int size,
    int bufferBytes,
  ) async* {
    final input = await file.open();
    try {
      await input.setPosition(offset);
      while (size > 0) {
        final bytes = await input.read(min(size, bufferBytes));
        if (bytes.isEmpty) throw const FormatException('备份文件不完整。');
        size -= bytes.length;
        yield bytes;
      }
    } finally {
      await input.close();
    }
  }

  static Future<void> write(
    File destination,
    Uint8List manifest,
    Map<String, String> media,
    int bufferBytes,
  ) async {
    final sizes = <String, int>{'manifest.json': manifest.length};
    for (final entry in media.entries) {
      BackupArchive.validateMediaPath(entry.key);
      sizes['media/${entry.key}'] = await File(entry.value).length();
    }
    if (sizes.length > BackupArchive.maxEntries) {
      throw const FormatException('备份照片数量超过上限。');
    }
    var total = 0;
    for (final entry in sizes.entries) {
      final limit = entry.key == 'manifest.json'
          ? BackupArchive.maxManifestBytes
          : BackupArchive.maxSingleFileBytes;
      if (entry.value > limit) throw const FormatException('备份中存在超出大小限制的文件。');
      total += entry.value;
    }
    if (total > BackupArchive.maxTotalUncompressedBytes) {
      throw const FormatException('备份解压后的内容超过导入上限。');
    }
    final output = await destination.open(mode: FileMode.write);
    var position = 0;
    final directory = <Uint8List>[];
    Future<void> append(List<int> bytes) async {
      if (position + bytes.length > BackupArchive.maxInputBytes) {
        throw const FormatException('备份文件超过 512 MB 的大小上限。');
      }
      await output.writeFrom(bytes);
      position += bytes.length;
    }

    try {
      for (final entry in sizes.entries) {
        final name = utf8.encode(entry.key);
        final localOffset = position;
        final local = ByteData(30)
          ..setUint32(0, 0x04034b50, Endian.little)
          ..setUint16(4, 20, Endian.little)
          ..setUint16(6, 0x808, Endian.little)
          ..setUint16(8, 8, Endian.little)
          ..setUint16(12, 33, Endian.little)
          ..setUint16(26, name.length, Endian.little);
        await append(local.buffer.asUint8List());
        await append(name);
        final start = position;
        var crc = 0;
        var actual = 0;
        final source = entry.key == 'manifest.json'
            ? Stream<List<int>>.value(manifest)
            : _chunks(
                File(media[entry.key.substring(6)]!),
                0,
                entry.value,
                bufferBytes,
              );
        final compressed = source
            .map((bytes) {
              actual += bytes.length;
              crc = getCrc32(bytes, crc);
              return bytes;
            })
            .transform(ZLibEncoder(raw: true));
        await for (final bytes in compressed) {
          await append(bytes);
        }
        if (actual != entry.value) {
          throw const FormatException('备份源文件发生变化，请重试。');
        }
        final compressedSize = position - start;
        final descriptor = ByteData(16)
          ..setUint32(0, 0x08074b50, Endian.little)
          ..setUint32(4, crc, Endian.little)
          ..setUint32(8, compressedSize, Endian.little)
          ..setUint32(12, actual, Endian.little);
        await append(descriptor.buffer.asUint8List());
        final central = ByteData(46 + name.length)
          ..setUint32(0, 0x02014b50, Endian.little)
          ..setUint16(4, 20, Endian.little)
          ..setUint16(6, 20, Endian.little)
          ..setUint16(8, 0x808, Endian.little)
          ..setUint16(10, 8, Endian.little)
          ..setUint16(14, 33, Endian.little)
          ..setUint32(16, crc, Endian.little)
          ..setUint32(20, compressedSize, Endian.little)
          ..setUint32(24, actual, Endian.little)
          ..setUint16(28, name.length, Endian.little)
          ..setUint32(42, localOffset, Endian.little);
        central.buffer.asUint8List().setRange(46, 46 + name.length, name);
        directory.add(central.buffer.asUint8List());
      }
      final directoryOffset = position;
      for (final bytes in directory) {
        await append(bytes);
      }
      final end = ByteData(22)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint16(8, sizes.length, Endian.little)
        ..setUint16(10, sizes.length, Endian.little)
        ..setUint32(12, position - directoryOffset, Endian.little)
        ..setUint32(16, directoryOffset, Endian.little);
      await append(end.buffer.asUint8List());
      await output.flush();
    } finally {
      await output.close();
    }
  }
}
