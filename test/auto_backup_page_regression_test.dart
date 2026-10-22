import 'dart:async';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/auto_backup_page.dart';
import 'package:antkeep/data/auto_backup_controller.dart';
import 'package:antkeep/data/auto_backup_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auto_backup_controller_test.dart' show MemoryBackupSettings;
import 'offline_tools_ui_test.dart' show capture;

class _Storage implements AutoBackupStorage {
  final entries = <LocalBackupEntry>[];
  final restoring = Completer<void>();
  Completer<List<LocalBackupEntry>>? nextList;
  bool? restoreIncremental;

  @override
  bool get supported => true;
  @override
  Future<List<LocalBackupEntry>> list() async {
    final delayed = nextList;
    nextList = null;
    return delayed == null ? List.of(entries) : delayed.future;
  }

  @override
  Future<void> create(DateTime at) async {
    entries.insert(0, LocalBackupEntry('$at.zip', at, 1024));
    if (entries.length > 3) entries.removeLast();
  }

  @override
  Future<bool> export(LocalBackupEntry entry) async => true;
  @override
  Future<void> restore(LocalBackupEntry entry, {required bool incremental}) {
    restoreIncremental = incremental;
    return restoring.future;
  }
}

class _RetrySettings extends MemoryBackupSettings {
  bool failRead = true;
  @override
  Future<Map<String, String>> readSettings() async {
    if (failRead) throw StateError('settings unavailable');
    return super.readSettings();
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'background backup refreshes the empty list and removes rotated entries',
    (tester) async {
      final storage = _Storage();
      var at = DateTime(2026, 10, 22, 9);
      final controller = AutoBackupController(
        MemoryBackupSettings(),
        storage,
        now: () => at,
      );
      await controller.load();
      await controller.setEnabled(true);
      await tester.pumpWidget(
        MaterialApp(home: AutoBackupPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有自动备份。开启后将生成第一份。'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await controller.run();
        await tester.pumpAndSettle();
        at = at.add(const Duration(days: 1));
      }
      expect(find.text('还没有自动备份。开启后将生成第一份。'), findsNothing);
      expect(find.text('2026-10-22 09:00'), findsNothing);
      expect(find.text('2026-10-25 09:00'), findsOneWidget);
      expect(find.text('导出到应用外'), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('retry reloads preferences after an initial settings failure', (
    tester,
  ) async {
    final settings = _RetrySettings()
      ..values.addAll({
        'auto_backup_consent_v1': 'true',
        'auto_backup_enabled': 'true',
      });
    final controller = AutoBackupController(settings, _Storage());
    await tester.pumpWidget(
      MaterialApp(home: AutoBackupPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法读取本地备份，请重试。'), findsOneWidget);
    settings.failRead = false;
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(controller.loaded, isTrue);
    expect(controller.enabled, isTrue);
    expect(find.text('无法读取本地备份，请重试。'), findsNothing);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  for (final fail in [false, true]) {
    testWidgets(
      'an older list ${fail ? 'failure' : 'result'} cannot overwrite a refreshed list',
      (tester) async {
        final storage = _Storage();
        final controller = AutoBackupController(
          MemoryBackupSettings(),
          storage,
          now: () => DateTime(2026, 10, 22, 9),
        );
        await controller.load();
        await tester.pumpWidget(
          MaterialApp(home: AutoBackupPage(controller: controller)),
        );
        await tester.pumpAndSettle();
        final oldRead = Completer<List<LocalBackupEntry>>();
        storage.nextList = oldRead;
        await controller.setEnabled(true);
        await controller.run();
        await tester.pumpAndSettle();
        expect(find.text('2026-10-22 09:00'), findsOneWidget);
        if (fail) {
          oldRead.completeError(StateError('old read failed'));
        } else {
          oldRead.complete([]);
        }
        await tester.pumpAndSettle();
        expect(find.text('2026-10-22 09:00'), findsOneWidget);
        expect(find.text('无法读取本地备份，请重试。'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }

  for (final incremental in [false, true]) {
    for (final fail in [false, true]) {
      testWidgets(
        '${incremental ? 'incremental' : 'overwrite'} restore blocks back and taps until ${fail ? 'failure' : 'success'}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final storage = _Storage();
          await storage.create(DateTime(2026, 10, 22));
          final controller = AutoBackupController(
            MemoryBackupSettings(),
            storage,
          );
          await controller.load();
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: antKeepTheme(ThemeColor.forest),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AutoBackupPage(controller: controller),
                        ),
                      ),
                      child: const Text('打开备份'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开备份'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('恢复'));
          await tester.tap(find.text('恢复'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(incremental ? '增量恢复' : '覆盖恢复'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(controller.busy, isTrue);
          expect(storage.restoreIncremental, incremental);
          expect(find.text('正在恢复备份，请稍候…'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.tapAt(const Offset(4, 4));
          await tester.tap(find.byType(BackButton), warnIfMissed: false);
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(AutoBackupPage), findsOneWidget);
          expect(find.text('正在恢复备份，请稍候…'), findsOneWidget);
          expect(controller.busy, isTrue);
          if (!incremental && !fail) {
            await capture(tester, key, 'backup-restore-busy-320');
          }
          if (fail) {
            storage.restoring.completeError(StateError('restore failed'));
          } else {
            storage.restoring.complete();
          }
          await tester.pumpAndSettle();
          expect(controller.busy, isFalse);
          expect(find.text('正在恢复备份，请稍候…'), findsNothing);
          expect(
            find.text(fail ? '操作未完成，请检查存储空间或稍后重试。' : '恢复完成，可在数据管理中撤销。'),
            findsOneWidget,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(AutoBackupPage), findsNothing);
          expect(find.text('打开备份'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        },
      );
    }
  }
}
