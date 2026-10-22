import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/data/auto_backup_runtime.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = <String, String>{
    'onboarding_completed': 'true',
    'app_edition': 'offline',
  };
  late Directory directory;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-consent-test-');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (call) async {
        switch (call.method) {
          case 'openDatabase':
            return {'id': 1};
          case 'execute':
            return {'transactionId': 1};
          case 'batch':
            return null;
          case 'update':
            return 0;
          case 'query':
            final sql = call.arguments['sql'] as String;
            if (sql == 'PRAGMA user_version') {
              return [
                {'user_version': 34},
              ];
            }
            if (!sql.contains('app_settings')) return [];
            return [
              for (final entry in settings.entries)
                {'setting_key': entry.key, 'setting_value': entry.value},
            ];
          case 'insert':
            final values = call.arguments['arguments'] as List<dynamic>;
            settings[values[0] as String] = values[1] as String;
            return 1;
          case 'closeDatabase':
            return null;
          default:
            throw UnsupportedError(call.method);
        }
      },
    );
    databaseFactory = databaseFactorySqflitePlugin;
    await AppDatabase.instance.open();
    await themeController.load();
    await autoBackupController.load();
  });
  tearDownAll(() async {
    await AppDatabase.instance.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'upgraded app asks on first home entry, declining persists across app recreation',
    (tester) async {
      await tester.pumpWidget(const AntKeepApp());
      await tester.pumpAndSettle();
      expect(find.text('开启自动本地备份？'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(autoBackupController.enabled, isFalse);
      await tester.tap(find.text('暂不开启'));
      await tester.pumpAndSettle();
      expect(settings['auto_backup_consent_v1'], 'true');
      expect(settings['auto_backup_enabled'], 'false');
      expect(find.byTooltip('扫描蚁群标签'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const AntKeepApp());
      await tester.pumpAndSettle();
      expect(find.text('开启自动本地备份？'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
