import 'dart:io';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final settings = <String, String>{};
  var failWrites = false;
  late Directory directory;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-settings-');
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
          case 'query':
            if (call.arguments['sql'] == 'PRAGMA user_version') {
              return [
                {'user_version': 13},
              ];
            }
            return [
              for (final entry in settings.entries)
                {'setting_key': entry.key, 'setting_value': entry.value},
            ];
          case 'insert':
            if (failWrites) {
              throw PlatformException(code: 'storage_unavailable');
            }
            final values = call.arguments['arguments'] as List<dynamic>;
            settings[values[0] as String] = values[1] as String;
            return 1;
          default:
            throw UnsupportedError('Unexpected database call: ${call.method}');
        }
      },
    );
    databaseFactory = databaseFactorySqflitePlugin;
    await AppDatabase.instance.open();
  });

  setUp(() async {
    settings.clear();
    failWrites = false;
    await themeController.load();
  });

  tearDownAll(() async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      null,
    );
    await directory.delete(recursive: true);
  });

  Widget app({bool dark = false}) => MaterialApp(
    theme: antKeepTheme(ThemeColor.forest, dark: dark),
    home: const Scaffold(body: SettingsPage()),
  );

  bool selected(WidgetTester tester, String label) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
      .selected;

  testWidgets(
    'online materials can be selected without update or account entrypoints',
    (tester) async {
      await tester.pumpWidget(app());
      expect(selected(tester, '离线版'), isTrue);
      expect(find.text('应用已是最新版本'), findsNothing);
      expect(find.text('个人中心与签到'), findsNothing);
      await tester.tap(find.text('在线版'));
      await tester.pumpAndSettle();
      expect(selected(tester, '离线版'), isFalse);
      expect(selected(tester, '在线版'), isTrue);
      expect(find.text('个人中心与签到'), findsNothing);
      expect(find.text('检查更新'), findsNothing);
      expect(find.text('去更新'), findsNothing);
      final restarted = AppPreferences(AppDatabase.instance);
      await restarted.load();
      expect(restarted.edition, AppEdition.online);
    },
  );

  testWidgets('failed online edition change keeps the existing preference', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    failWrites = true;
    await tester.tap(find.text('在线版'));
    await tester.pumpAndSettle();
    expect(selected(tester, '离线版'), isTrue);
    expect(selected(tester, '在线版'), isFalse);
    expect(find.textContaining('操作未完成'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'settings scrolls on small screen with large text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(app(dark: dark));
        for (final label in ['在线版', '薰衣草紫', '深色', '本地养护提醒', '撤销上一次恢复']) {
          await tester.scrollUntilVisible(
            find.text(label),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
