import 'package:flutter/services.dart';

/// Runtime hints, never a promise that system memory can be reserved by this app.
class BackupResources {
  const BackupResources({
    this.availableMemory,
    this.freeDisk,
    this.lowMemory = false,
  });
  static const channel = MethodChannel('com.pipiele.antkeep/backup');
  final int? availableMemory;
  final int? freeDisk;
  final bool lowMemory;

  int get bufferBytes {
    final memory = availableMemory;
    if (lowMemory || (memory != null && memory < 256 * 1024 * 1024)) {
      return 64 * 1024;
    }
    if (memory != null && memory >= 1024 * 1024 * 1024) return 1024 * 1024;
    return 256 * 1024;
  }

  void requireDisk(int bytes) {
    // Leave room for SQLite journals and unrelated app writes.
    if (freeDisk != null && freeDisk! < bytes + 32 * 1024 * 1024) {
      throw StateError('可用存储空间不足，请清理空间后重试备份操作。');
    }
  }

  static Future<BackupResources> read(String directory) async {
    try {
      final values = await channel.invokeMapMethod<String, dynamic>(
        'resources',
        {'path': directory},
      );
      return BackupResources(
        availableMemory: values?['availableMemory'] as int?,
        freeDisk: values?['freeDisk'] as int?,
        lowMemory: values?['lowMemory'] == true,
      );
    } on MissingPluginException {
      return const BackupResources();
    } on PlatformException {
      // Desktop/tests or unavailable native metrics use bounded, serial I/O.
      return const BackupResources();
    }
  }
}

/// Retain disk recovery material if rollback itself cannot complete.
class BackupRecoveryFailure implements Exception {
  BackupRecoveryFailure(this.directory);
  final String directory;
  @override
  String toString() => '恢复未完成，回退资料已保留在 $directory，请勿清理应用数据。';
}
