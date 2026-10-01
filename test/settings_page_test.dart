import 'dart:io';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/online/app_update.dart';
import 'package:antkeep/online/runtime.dart';
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
            if (!(call.arguments['sql'] as String).contains('app_settings')) {
              return [];
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

  testWidgets('offline startup shows a dismissible update only once', (
    tester,
  ) async {
    await appUpdateController.setOnline(false);
    appUpdateController.policy = AppUpdatePolicy(
      version: 1,
      latestVersion: const AppVersion(1, 1, 0),
      minimumVersion: const AppVersion(1, 1, 0),
      downloadUrl: Uri.parse('https://downloads.example.test/antkeep'),
      releaseNotes: '修复已知问题。',
    );
    appUpdateController.availability = AppUpdateAvailability.optional;
    addTearDown(() => appUpdateController.setOnline(false));
    await tester.pumpWidget(const AntKeepApp());
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 1.1.0'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('在线版需要更新'), findsNothing);
    await tester.tap(find.text('稍后更新'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await themeController.setThemeColor(ThemeColor.forest);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(themeController.edition, AppEdition.offline);
  });

  testWidgets('simple mode persists and restores all navigation entries', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(themeController.simpleMode, isFalse);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('分析'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简化模式'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(2));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('分析'), findsNothing);
    final restarted = AppPreferences(AppDatabase.instance);
    await restarted.load();
    expect(restarted.simpleMode, isTrue);
    await tester.tap(find.widgetWithText(NavigationDestination, '蚁群'));
    await tester.pumpAndSettle();
    expect(find.byType(ColoniesPage), findsOneWidget);
    expect(find.text('还没有蚁群'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简化模式'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('分析'), findsOneWidget);
    await restarted.load();
    expect(restarted.simpleMode, isFalse);
  });

  testWidgets('failed simple mode change preserves full mode', (tester) async {
    await tester.pumpWidget(app());
    failWrites = true;
    await tester.tap(find.text('简化模式'));
    await tester.pumpAndSettle();
    expect(themeController.simpleMode, isFalse);
    expect(find.textContaining('操作未完成'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '简化模式'))
          .value,
      isFalse,
    );
  });

  testWidgets('online edition can be selected and persists the choice', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(selected(tester, '离线版'), isTrue);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('应用已是最新版本'), findsNothing);
    expect(find.text('个人中心与签到'), findsNothing);
    await tester.tap(find.text('在线版'));
    await tester.pumpAndSettle();
    expect(selected(tester, '离线版'), isFalse);
    expect(selected(tester, '在线版'), isTrue);
    expect(find.text('个人中心与签到'), findsOneWidget);
    final restarted = AppPreferences(AppDatabase.instance);
    await restarted.load();
    expect(restarted.edition, AppEdition.online);
  });

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
