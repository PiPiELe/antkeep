import 'dart:io';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/colony_dense_layout.dart';
import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/milestones_overview_page.dart';
import 'package:antkeep/onboarding.dart';
import 'package:antkeep/online/app_update.dart';
import 'package:antkeep/online/runtime.dart';
import 'package:antkeep/widgets/fading_horizontal_scroll.dart';
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
          case 'update':
            return 0;
          case 'query':
            if (call.arguments['sql'] == 'PRAGMA user_version') {
              return [
                {'user_version': 17},
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

  testWidgets('theme and font pickers apply, persist and report failed saves', (
    tester,
  ) async {
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => MaterialApp(
          theme: antKeepTheme(
            themeController.themeColor,
            fontColor: themeController.fontColor,
          ),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与展示'));
    await tester.pumpAndSettle();
    Future<void> choose(String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text(label)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
    }

    await choose('雾蓝');
    expect(settings['theme_color'], 'mistBlue');
    await choose('深蓝 #243B53');
    expect(settings['font_color'], 'navy');
    expect(
      Theme.of(tester.element(find.text('字体颜色'))).textTheme.bodyMedium!.color,
      FontColor.navy.color,
    );
    await choose('纯白');
    expect(settings['theme_color'], 'white');
    expect(themeController.fontColor, FontColor.navy);
    failWrites = true;
    await choose('墨绿 #285943');
    expect(themeController.fontColor, FontColor.navy);
    expect(find.byType(SnackBar), findsOneWidget);
    failWrites = false;
    await choose('跟随主题');
    expect(settings['font_color'], 'theme');
    expect(tester.takeException(), isNull);
  });

  bool selected(WidgetTester tester, String label) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
      .selected;

  Future<void> openCategory(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('appearance colors use one and two horizontal rows', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openCategory(tester, '外观与展示');

    final themePicker = find.byType(ThemeColorPicker);
    final fontPicker = find.byType(FontColorPicker);
    expect(
      find.descendant(
        of: themePicker,
        matching: find.byType(FadingHorizontalScroll),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: fontPicker,
        matching: find.byType(FadingHorizontalScroll),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.widgetWithText(ChoiceChip, '森林绿')).dy,
      tester.getTopLeft(find.widgetWithText(ChoiceChip, '纯白')).dy,
    );
    expect(
      tester.getTopLeft(find.widgetWithText(ChoiceChip, '跟随主题')).dy,
      tester.getTopLeft(find.widgetWithText(ChoiceChip, '石墨灰 #424242')).dy,
    );
    expect(
      tester.getTopLeft(find.widgetWithText(ChoiceChip, '跟随主题')).dy,
      isNot(
        tester.getTopLeft(find.widgetWithText(ChoiceChip, '墨黑 #000000')).dy,
      ),
    );
  });

  testWidgets('appearance setting controls colony overview card', (
    tester,
  ) async {
    await themeController.setInterfaceStyle(InterfaceStyle.current);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openCategory(tester, '外观与展示');
    final overview = find.widgetWithText(SwitchListTile, '蚁群总览卡片');
    expect(tester.widget<SwitchListTile>(overview).value, isTrue);
    await tester.tap(overview);
    await tester.pumpAndSettle();
    expect(themeController.showColonyOverview, isFalse);
    expect(settings['show_colony_overview'], 'false');
  });

  testWidgets(
    'appearance setting shows four list styles without interface choices',
    (tester) async {
      expect(themeController.interfaceStyle, InterfaceStyle.classic);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openCategory(tester, '外观与展示');
      expect(find.text('界面样式'), findsNothing);
      expect(find.text('新版界面'), findsNothing);
      expect(find.text('经典界面'), findsNothing);
      for (final style in ColonyDisplayStyle.values) {
        await tester.scrollUntilVisible(
          find.text(style.label),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(style.label), findsOneWidget);
      }
      await Scrollable.ensureVisible(
        tester.element(find.text('经典')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('经典'));
      await tester.pumpAndSettle();
      expect(themeController.interfaceStyle, InterfaceStyle.current);
      expect(themeController.colonyDisplayStyle, ColonyDisplayStyle.classic);
      expect(settings['interface_style'], 'current');
      expect(settings['colony_display_style'], 'classic');
    },
  );

  testWidgets('appearance setting switches and saves colony list style', (
    tester,
  ) async {
    await themeController.setInterfaceStyle(InterfaceStyle.current);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openCategory(tester, '外观与展示');
    await tester.scrollUntilVisible(
      find.text('紧凑'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('紧凑'));
    await tester.pumpAndSettle();
    expect(themeController.colonyDisplayStyle, ColonyDisplayStyle.compact);
    expect(settings['colony_display_style'], 'compact');
    await tester.ensureVisible(find.text('密集型'));
    await tester.tap(find.text('密集型'));
    await tester.pumpAndSettle();
    expect(themeController.colonyDisplayStyle, ColonyDisplayStyle.dense);
    expect(settings['colony_display_style'], 'dense');
  });

  testWidgets(
    'settings home groups controls and data actions into five destinations',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      for (final category in SettingsCategory.values) {
        expect(
          find.text(category.title),
          category == SettingsCategory.reminders
              ? findsNothing
              : findsOneWidget,
        );
      }
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('恢复备份'), findsNothing);
      expect(find.text('数据推送'), findsNothing);
      await openCategory(tester, '数据管理');
      expect(find.text('数据推送'), findsOneWidget);
      expect(find.text('备份上传'), findsOneWidget);
      expect(find.text('导出备份'), findsOneWidget);
      await tester.tap(find.text('备份上传'));
      await tester.pumpAndSettle();
      expect(find.text('请先开启在线模式并登录账号。'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复备份'));
      await tester.pumpAndSettle();
      expect(find.text('选择恢复方式'), findsOneWidget);
      expect(find.text('恢复图片'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('数据推送'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请先在设置中切换到在线版'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('导出备份'), findsOneWidget);
      await tester.tap(find.text('导出备份'));
      await tester.pumpAndSettle();
      expect(find.text('选择导出格式'), findsOneWidget);
      expect(find.text('ZIP 完整备份'), findsOneWidget);
      expect(find.text('Excel 数据表'), findsOneWidget);
      expect(find.text('Excel + 原图（ZIP）'), findsOneWidget);
      expect(find.text('可恢复记录；不含照片文件'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('外观与展示'), findsOneWidget);
    },
  );

  testWidgets(
    'help and version details remain reachable from secondary pages',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openCategory(tester, '帮助与反馈');
      expect(find.text('使用指南'), findsOneWidget);
      expect(find.text('交流群二维码'), findsOneWidget);
      expect(find.text('检查更新'), findsNothing);
      await tester.tap(find.text('使用指南'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openCategory(tester, '关于与更新');
      expect(find.text('当前 App 版本'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.text('使用指南'), findsNothing);
    },
  );

  testWidgets('offline startup shows a dismissible update only once', (
    tester,
  ) async {
    await appUpdateController.setOnline(false);
    appUpdateController.policy = AppUpdatePolicy(
      version: 1,
      latestVersion: const AppVersion(1, 1, 0),
      minimumVersion: const AppVersion(1, 1, 0),
      downloadUrl: Uri.parse('https://downloads.example.test/antkeep'),
      releaseNotes: '新增离线更新提示。\n修复记录展示问题。',
      apk: const AppUpdateApk(filename: '蚁记-1.1.0.apk', sizeBytes: 52428800),
    );
    appUpdateController.availability = AppUpdateAvailability.optional;
    addTearDown(() => appUpdateController.setOnline(false));
    await tester.pumpWidget(const AntKeepApp());
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 1.1.0'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('更新说明'), findsOneWidget);
    expect(find.text('新增离线更新提示。\n修复记录展示问题。'), findsOneWidget);
    expect(find.text('蚁记-1.1.0.apk'), findsOneWidget);
    expect(find.text('文件大小：50.0 MB'), findsOneWidget);
    expect(find.text('在线版需要更新'), findsNothing);
    await tester.tap(find.text('稍后更新'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await themeController.setThemeColor(ThemeColor.forest);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(themeController.edition, AppEdition.offline);
  });

  testWidgets(
    'long required-update notes scroll on a small screen without APK metadata',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final notes = List.generate(60, (i) => '${i + 1}. 后台配置的更新说明。').join('\n');
      appUpdateController.policy = AppUpdatePolicy(
        version: 2,
        latestVersion: const AppVersion(1, 2, 0),
        minimumVersion: const AppVersion(1, 1, 0),
        downloadUrl: Uri.parse('https://downloads.example.test/antkeep'),
        releaseNotes: notes,
      );
      appUpdateController.availability = AppUpdateAvailability.required;
      addTearDown(() => appUpdateController.setOnline(false));
      await tester.pumpWidget(const AntKeepApp());
      await tester.pumpAndSettle();
      expect(find.text('在线版需要更新'), findsOneWidget);
      expect(find.text(notes), findsOneWidget);
      expect(find.text('安装包'), findsNothing);
      final scrollable = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
      );
      expect(find.text('立即更新').hitTestable(), findsOneWidget);
      expect(find.text('使用离线版').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
    await openCategory(tester, '外观与展示');
    await tester.tap(find.text('简化模式'));
    await tester.pumpAndSettle();
    await tester.pageBack();
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
    await openCategory(tester, '外观与展示');
    await tester.tap(find.text('简化模式'));
    await tester.pumpAndSettle();
    await tester.pageBack();
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
    await openCategory(tester, '外观与展示');
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

  testWidgets('ultra simple switches update navigation and colony tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await openCategory(tester, '外观与展示');
    await tester.tap(find.text('超极简模式'));
    await tester.pumpAndSettle();
    expect(themeController.ultraSimpleMode, isTrue);
    expect(themeController.simpleMode, isFalse);
    expect(themeController.interfaceStyle, InterfaceStyle.current);
    expect(themeController.colonyDisplayStyle, ColonyDisplayStyle.dense);
    expect(settings['colony_display_style'], 'dense');
    expect(find.text('自选显示内容'), findsOneWidget);
    expect(find.byKey(const ValueKey('ultra-inventory')), findsNothing);
    await tester.tap(find.text('自选显示内容'));
    await tester.pumpAndSettle();
    for (final feature in UltraSimpleFeature.values) {
      expect(find.byKey(ValueKey('ultra-${feature.name}')), findsOneWidget);
    }
    await tester.tap(find.text('自选显示内容'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ultra-inventory')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    await openCategory(tester, '外观与展示');
    await tester.tap(find.text('自选显示内容'));
    await tester.pumpAndSettle();
    final inventory = find.byKey(const ValueKey('ultra-inventory'));
    await tester.ensureVisible(inventory);
    await tester.tap(inventory);
    await tester.pumpAndSettle();
    expect(themeController.showFeature(UltraSimpleFeature.inventory), isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(2));

    await themeController.setUltraFeature(UltraSimpleFeature.memorial, true);
    await themeController.setUltraFeature(UltraSimpleFeature.milestones, true);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '蚁群'));
    await tester.pumpAndSettle();
    final denseTabs = find.byType(ColonyDenseTabs);
    expect(
      find.descendant(of: denseTabs, matching: find.text('英灵殿')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: denseTabs, matching: find.text('里程碑')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: denseTabs, matching: find.text('英灵殿')),
    );
    await tester.pumpAndSettle();
    await themeController.setUltraFeature(UltraSimpleFeature.memorial, false);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: denseTabs, matching: find.text('英灵殿')),
      findsNothing,
    );
    expect(
      find.descendant(of: denseTabs, matching: find.text('里程碑')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final restarted = AppPreferences(AppDatabase.instance);
    await restarted.load();
    expect(restarted.ultraSimpleMode, isTrue);
    expect(restarted.showFeature(UltraSimpleFeature.inventory), isFalse);
    expect(restarted.showFeature(UltraSimpleFeature.memorial), isFalse);
    expect(restarted.showFeature(UltraSimpleFeature.milestones), isTrue);
  });

  testWidgets('ultra simple controls remain reachable on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await themeController.setUltraSimpleMode(true);
    await tester.pumpWidget(app());
    await openCategory(tester, '外观与展示');
    await tester.ensureVisible(find.text('自选显示内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自选显示内容'));
    await tester.pumpAndSettle();
    for (final feature in UltraSimpleFeature.values) {
      await tester.ensureVisible(find.byKey(ValueKey('ultra-${feature.name}')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('dense milestone rename uses the visible tab identity', (
    tester,
  ) async {
    await themeController.setUltraSimpleMode(true);
    await themeController.setUltraFeature(UltraSimpleFeature.milestones, true);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final milestone = find.descendant(
      of: find.byType(ColonyDenseTabs),
      matching: find.text('里程碑'),
    );
    await tester.longPress(milestone);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '成长大事记');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(themeController.colonyTabName(ColonyTab.milestones), '成长大事记');
    expect(themeController.colonyTabName(ColonyTab.memorial), '英灵殿');
    expect(tester.takeException(), isNull);
  });

  testWidgets('colony tab names persist, validate, cancel and reset', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    for (final entry in {
      ColonyTab.colonies: '蚂蚁之家',
      ColonyTab.memorial: '星光纪念馆',
      ColonyTab.milestones: '成长大事记',
    }.entries) {
      await tester.longPress(find.text(entry.key.defaultName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '  ${entry.value}  ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(entry.value), findsOneWidget);
    }
    final restarted = AppPreferences(AppDatabase.instance);
    await restarted.load();
    expect(restarted.colonyTabName(ColonyTab.colonies), '蚂蚁之家');
    expect(restarted.colonyTabName(ColonyTab.memorial), '星光纪念馆');
    expect(restarted.colonyTabName(ColonyTab.milestones), '成长大事记');
    await tester.tap(find.text('星光纪念馆'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('添加纪念'), findsOneWidget);
    await tester.longPress(find.text('星光纪念馆'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入菜单名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('星光纪念馆'), findsOneWidget);
    await tester.longPress(find.text('星光纪念馆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(TabBar), matching: find.text('英灵殿')),
      findsOneWidget,
    );
    expect(find.byTooltip('添加纪念'), findsOneWidget);
    await restarted.load();
    expect(restarted.colonyTabName(ColonyTab.memorial), '英灵殿');
    expect(restarted.colonyTabName(ColonyTab.colonies), '蚂蚁之家');
    expect(tester.takeException(), isNull);
  });

  testWidgets('milestone tab opens the overview', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('里程碑')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byTooltip('返回我的蚁群'), findsNothing);
    expect(find.byTooltip('分享'), findsOneWidget);
    final intro = tester.widget<Text>(find.text('记录重要的时刻\n让每一个值得铭记的瞬间，都被永远铭刻'));
    expect(intro.style?.fontSize, 18);
    await tester.scrollUntilVisible(
      find.text('还没有里程碑，添加一个值得铭记的成长节点吧。'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(MilestonesOverviewPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('还没有里程碑，添加一个值得铭记的成长节点吧。'), findsOneWidget);
    expect(find.text('添加里程碑'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('总览')),
    );
    await tester.pumpAndSettle();
    expect(find.text('历史'), findsOneWidget);
  });

  testWidgets('colony overview tab opens the three sections', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('总览'));
    await tester.pumpAndSettle();
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('现役'), findsOneWidget);
    expect(find.text('英灵殿'), findsWidgets);
  });

  testWidgets(
    'menu rename settings retain old name on failure and allow retry',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openCategory(tester, '外观与展示');
      expect(find.text('菜单名称'), findsOneWidget);
      expect(find.text('英灵殿'), findsNothing);
      await tester.tap(find.text('菜单名称'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('英灵殿'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '纪念馆');
      failWrites = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(themeController.colonyTabName(ColonyTab.memorial), '英灵殿');
      failWrites = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('纪念馆'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('online edition can be selected and persists the choice', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openCategory(tester, '在线服务');
    expect(selected(tester, '离线版'), isTrue);
    expect(find.text('检查更新'), findsNothing);
    expect(find.text('应用已是最新版本'), findsNothing);
    expect(find.text('个人中心与签到'), findsNothing);
    await tester.tap(find.text('在线版'));
    await tester.pumpAndSettle();
    expect(selected(tester, '离线版'), isFalse);
    expect(selected(tester, '在线版'), isTrue);
    expect(find.text('个人中心与签到'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('在线版 ·'), findsOneWidget);
    final restarted = AppPreferences(AppDatabase.instance);
    await restarted.load();
    expect(restarted.edition, AppEdition.online);
  });

  testWidgets('failed online edition change keeps the existing preference', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openCategory(tester, '在线服务');
    failWrites = true;
    await tester.tap(find.text('在线版'));
    await tester.pumpAndSettle();
    expect(selected(tester, '离线版'), isTrue);
    expect(selected(tester, '在线版'), isFalse);
    expect(find.textContaining('操作未完成'), findsOneWidget);
  });

  testWidgets(
    'restore offers both modes and cancellation leaves settings unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(app());
      await openCategory(tester, '数据管理');
      await tester.scrollUntilVisible(find.text('恢复备份'), 180);
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复备份'));
      await tester.pumpAndSettle();
      expect(find.text('选择恢复方式'), findsOneWidget);
      expect(find.text('增量恢复'), findsOneWidget);
      expect(find.text('覆盖恢复'), findsOneWidget);
      expect(find.textContaining('相同 ID'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('恢复完成；'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
        for (final entry in {
          '在线服务': ['在线版'],
          '外观与展示': [
            '简化模式',
            '雾蓝',
            '纯白',
            dark ? '深蓝 #BFD3EA' : '深蓝 #243B53',
            '深色',
          ],
          '数据管理': ['数据推送', '撤销上一次恢复'],
          '帮助与反馈': ['交流群二维码'],
          '关于与更新': ['检查更新'],
        }.entries) {
          await openCategory(tester, entry.key);
          for (final label in entry.value) {
            await tester.scrollUntilVisible(
              find.text(label),
              180,
              scrollable: find.byType(Scrollable).first,
            );
            expect(tester.takeException(), isNull);
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: antKeepTheme(ThemeColor.forest, dark: dark),
            home: const Scaffold(body: DiscoverPage()),
          ),
        );
        await openCategory(tester, '养护提醒');
        for (final label in ['本地养护提醒', '提醒时间']) {
          await tester.scrollUntilVisible(find.text(label), 180);
          expect(tester.takeException(), isNull);
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(DiscoverPage), findsOneWidget);
        await themeController.setSimpleMode(true);
        await tester.pumpWidget(app(dark: dark));
        await openCategory(tester, '养护提醒');
        expect(find.text('本地养护提醒'), findsOneWidget);
      },
    );
  }
}
