import 'dart:async';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/data/auto_backup_controller.dart';
import 'package:antkeep/data/auto_backup_model.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryBackupSettings implements AppSettingsStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<Map<String, String>> readSettings() async => Map.of(values);
  @override
  Future<void> writeSettings(Map<String, String> updates) async {
    if (fail) throw StateError('disk full');
    values.addAll(updates);
  }
}

class FakeBackupStorage implements AutoBackupStorage {
  int creates = 0;
  bool fail = false;
  Completer<void>? pending;
  final entries = <LocalBackupEntry>[];
  @override
  bool get supported => true;
  @override
  Future<void> create(DateTime now) async {
    creates++;
    if (pending != null) await pending!.future;
    if (fail) throw StateError('disk full');
    entries.add(LocalBackupEntry('backup.zip', now, 1024));
  }

  @override
  Future<List<LocalBackupEntry>> list() async => entries;
  @override
  Future<bool> export(LocalBackupEntry entry) async => true;
  @override
  Future<void> restore(
    LocalBackupEntry entry, {
    required bool incremental,
  }) async {}
}

void main() {
  test(
    'upgrade prompts once, never creates without explicit consent',
    () async {
      final settings = MemoryBackupSettings();
      final storage = FakeBackupStorage();
      final controller = AutoBackupController(settings, storage);
      await controller.load();
      expect(controller.needsConsent, isTrue);
      await controller.run();
      expect(storage.creates, 0);
      await controller.setEnabled(false);
      final restart = AutoBackupController(settings, storage);
      await restart.load();
      expect(restart.needsConsent, isFalse);
      await restart.run();
      expect(storage.creates, 0);
      await restart.setEnabled(true);
      await restart.run();
      expect(storage.creates, 1);
    },
  );

  test(
    'failed consent persistence leaves prompt pending and feature disabled',
    () async {
      final settings = MemoryBackupSettings()..fail = true;
      final controller = AutoBackupController(settings, FakeBackupStorage());
      await controller.load();
      await expectLater(controller.setEnabled(true), throwsStateError);
      expect(controller.needsConsent, isTrue);
      expect(controller.enabled, isFalse);
    },
  );

  test(
    'once per day survives restart and clock rollback; force refresh works',
    () async {
      final settings = MemoryBackupSettings();
      final storage = FakeBackupStorage();
      var now = DateTime(2026, 10, 21, 9);
      final controller = AutoBackupController(
        settings,
        storage,
        now: () => now,
      );
      await controller.load();
      await controller.setEnabled(true);
      await controller.run();
      await controller.run();
      expect(storage.creates, 1);
      final restart = AutoBackupController(settings, storage, now: () => now);
      await restart.load();
      await restart.run();
      expect(storage.creates, 1);
      now = now.add(const Duration(days: 1));
      await restart.run();
      expect(storage.creates, 2);
      await restart.run(force: true);
      expect(storage.creates, 3);
      now = now.subtract(const Duration(days: 2));
      await restart.run();
      expect(storage.creates, 4);
    },
  );

  test('failure retains last success, persists error and retries', () async {
    final settings = MemoryBackupSettings();
    final storage = FakeBackupStorage();
    var now = DateTime(2026, 10, 21);
    final controller = AutoBackupController(settings, storage, now: () => now);
    await controller.load();
    await controller.setEnabled(true);
    await controller.run();
    final previous = controller.lastSuccess;
    now = now.add(const Duration(days: 1));
    storage.fail = true;
    await controller.run();
    expect(controller.lastSuccess, previous);
    expect(controller.error, isNotNull);
    final restart = AutoBackupController(settings, storage, now: () => now);
    await restart.load();
    expect(restart.error, isNotNull);
    storage.fail = false;
    await restart.run();
    expect(restart.lastSuccess, now);
    expect(restart.error, isNull);
  });

  test(
    'overlapping triggers and export/restore do not run concurrently',
    () async {
      final settings = MemoryBackupSettings();
      final storage = FakeBackupStorage()..pending = Completer<void>();
      final controller = AutoBackupController(settings, storage);
      await controller.load();
      await controller.setEnabled(true);
      final first = controller.run();
      await controller.run();
      expect(storage.creates, 1);
      await expectLater(controller.withBackup(() async {}), throwsStateError);
      storage.pending!.complete();
      await first;
      expect(controller.busy, isFalse);
      await controller.setEnabled(false);
      await controller.run(force: true);
      expect(storage.creates, 1);
    },
  );
}
