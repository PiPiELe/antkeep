import 'dart:async';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySettings implements AppSettingsStore {
  final values = <String, String>{};
  bool failWrites = false;
  Completer<void>? pendingWrite;
  int writes = 0;

  @override
  Future<Map<String, String>> readSettings() async => Map.of(values);

  @override
  Future<void> writeSettings(Map<String, String> updates) async {
    writes++;
    if (failWrites) throw StateError('Storage unavailable');
    if (pendingWrite != null) await pendingWrite!.future;
    values.addAll(updates);
  }
}

Widget testApp(AppPreferences preferences) => AnimatedBuilder(
  animation: preferences,
  builder: (context, _) => MaterialApp(
    theme: antKeepTheme(preferences.themeColor),
    darkTheme: antKeepTheme(preferences.themeColor, dark: true),
    themeMode: preferences.themeMode,
    home: preferences.onboardingCompleted
        ? const Scaffold(body: Text('已进入首页'))
        : OnboardingPage(preferences: preferences),
  ),
);

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (find
      .ancestor(of: finder, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  test(
    'old settings keep dark mode and unknown colors fall back safely',
    () async {
      final store = MemorySettings()
        ..values.addAll({'dark_theme': 'true', 'theme_color': 'unknown'});
      final preferences = AppPreferences(store);
      await preferences.load();
      expect(preferences.onboardingCompleted, isFalse);
      expect(preferences.themeMode, ThemeMode.dark);
      expect(preferences.themeColor, ThemeColor.forest);
    },
  );

  test(
    'new installs follow system and legacy light preference is preserved',
    () async {
      final store = MemorySettings();
      final preferences = AppPreferences(store);
      await preferences.load();
      expect(preferences.themeMode, ThemeMode.system);
      store.values['dark_theme'] = 'false';
      await preferences.load();
      expect(preferences.themeMode, ThemeMode.light);
      await preferences.setThemeMode(ThemeMode.system);
      final restarted = AppPreferences(store);
      await restarted.load();
      expect(restarted.themeMode, ThemeMode.system);
      store.values['theme_mode'] = 'unknown';
      await restarted.load();
      expect(restarted.themeMode, ThemeMode.light);
    },
  );

  test(
    'local care reminder settings persist with a valid daily time',
    () async {
      final store = MemorySettings();
      final preferences = AppPreferences(store);
      await preferences.load();
      expect(preferences.careRemindersEnabled, isFalse);
      expect(preferences.careReminderMinuteOfDay, 20 * 60);

      await preferences.setCareReminder(
        enabled: true,
        minuteOfDay: 7 * 60 + 30,
      );

      final restarted = AppPreferences(store);
      await restarted.load();
      expect(restarted.careRemindersEnabled, isTrue);
      expect(restarted.careReminderMinuteOfDay, 7 * 60 + 30);
    },
  );

  testWidgets(
    'system brightness updates preview and home while manual modes stay fixed',
    (tester) async {
      final store = MemorySettings();
      final preferences = AppPreferences(store);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(testApp(preferences));
      await tapText(tester, '离线版');
      await tapText(tester, '下一步');
      Brightness previewBrightness() =>
          Theme.of(tester.element(find.text('我的蚁群'))).brightness;
      expect(previewBrightness(), Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(previewBrightness(), Brightness.dark);
      await tapText(tester, '浅色');
      expect(previewBrightness(), Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      await tapText(tester, '深色');
      expect(previewBrightness(), Brightness.dark);
      await tapText(tester, '跟随系统');
      expect(previewBrightness(), Brightness.light);
      await tapText(tester, '下一步');
      await tapText(tester, '我是老玩家');
      await tapText(tester, '开始使用');
      expect(store.values['theme_mode'], 'system');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('已进入首页'))).brightness,
        Brightness.dark,
      );
      await preferences.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('已进入首页'))).brightness,
        Brightness.light,
      );
    },
  );

  testWidgets('beginner sees tips, previews color and completes only once', (
    tester,
  ) async {
    final store = MemorySettings();
    final preferences = AppPreferences(store);
    await preferences.load();
    await tester.pumpWidget(testApp(preferences));
    expect(find.text('选择使用版本'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
          .onPressed,
      isNull,
    );
    await tapText(tester, '在线版');
    await tapText(tester, '下一步');
    expect(find.text('选择你喜欢的主题色'), findsOneWidget);
    await tapText(tester, '海洋蓝');
    final previewContext = tester.element(find.text('我的蚁群'));
    expect(
      Theme.of(previewContext).colorScheme.primary,
      antKeepTheme(ThemeColor.ocean).colorScheme.primary,
    );
    await tapText(tester, '深色');
    expect(Theme.of(previewContext).brightness, Brightness.dark);
    await tapText(tester, '下一步');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
          .onPressed,
      isNull,
    );
    await tapText(tester, '我是新手');
    await tapText(tester, '下一步');
    expect(find.text('一窝蚁群，一份档案'), findsOneWidget);
    expect(store.values, isEmpty);
    await tapText(tester, '开始使用');
    expect(find.text('已进入首页'), findsOneWidget);
    expect(preferences.beginner, isTrue);
    expect(store.writes, 1);

    await tester.pumpWidget(const SizedBox());
    final restarted = AppPreferences(store);
    await restarted.load();
    await tester.pumpWidget(testApp(restarted));
    expect(find.text('已进入首页'), findsOneWidget);
    expect(restarted.themeColor, ThemeColor.ocean);
    expect(restarted.themeMode, ThemeMode.dark);
    expect(restarted.beginner, isTrue);
    expect(restarted.edition, AppEdition.online);
  });

  testWidgets(
    'experienced users still choose a theme and can change experience',
    (tester) async {
      final preferences = AppPreferences(MemorySettings());
      await tester.pumpWidget(testApp(preferences));
      await tapText(tester, '离线版');
      await tapText(tester, '下一步');
      await tapText(tester, '琥珀橙');
      await tapText(tester, '下一步');
      await tapText(tester, '我是老玩家');
      expect(find.byType(BeginnerTips), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('选择你喜欢的主题色'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '琥珀橙'))
            .selected,
        isTrue,
      );
      await tapText(tester, '下一步');
      await tapText(tester, '我是新手');
      await tapText(tester, '下一步');
      expect(find.byType(BeginnerTips), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tapText(tester, '我是老玩家');
      await tapText(tester, '开始使用');
      expect(preferences.beginner, isFalse);
      expect(find.text('已进入首页'), findsOneWidget);
    },
  );

  testWidgets('failed save stays on experience step and supports retry', (
    tester,
  ) async {
    final store = MemorySettings()..failWrites = true;
    final preferences = AppPreferences(store);
    await tester.pumpWidget(testApp(preferences));
    await tapText(tester, '离线版');
    await tapText(tester, '下一步');
    await tapText(tester, '玫瑰粉');
    await tapText(tester, '下一步');
    await tapText(tester, '我是老玩家');
    await tapText(tester, '开始使用');
    expect(find.text('设置未能保存，请重试。'), findsOneWidget);
    expect(preferences.onboardingCompleted, isFalse);
    expect(store.values, isEmpty);
    store.failWrites = false;
    await tapText(tester, '开始使用');
    expect(preferences.themeColor, ThemeColor.rose);
    expect(find.text('已进入首页'), findsOneWidget);
  });

  testWidgets(
    'pending save disables duplicate submission and back navigation',
    (tester) async {
      final store = MemorySettings()..pendingWrite = Completer<void>();
      final preferences = AppPreferences(store);
      await tester.pumpWidget(testApp(preferences));
      await tapText(tester, '离线版');
      await tapText(tester, '下一步');
      await tapText(tester, '下一步');
      await tapText(tester, '我是老玩家');
      await tapText(tester, '开始使用');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '正在保存…'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('你是养蚁新手，还是老玩家？'), findsOneWidget);
      await tapText(tester, '我是新手');
      expect(find.text('正在保存…'), findsOneWidget);
      expect(store.writes, 1);
      store.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(find.text('已进入首页'), findsOneWidget);
    },
  );

  testWidgets('unfinished onboarding is shown again after restart', (
    tester,
  ) async {
    final store = MemorySettings();
    await tester.pumpWidget(testApp(AppPreferences(store)));
    await tapText(tester, '离线版');
    await tapText(tester, '下一步');
    await tapText(tester, '琥珀橙');
    await tapText(tester, '下一步');
    await tapText(tester, '我是新手');
    await tapText(tester, '下一步');
    await tester.pumpWidget(const SizedBox());
    final restarted = AppPreferences(store);
    await restarted.load();
    await tester.pumpWidget(testApp(restarted));
    expect(find.text('选择使用版本'), findsOneWidget);
    expect(restarted.onboardingCompleted, isFalse);
  });

  testWidgets('small screen and large text can scroll through every step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(testApp(AppPreferences(MemorySettings())));
    await tapText(tester, '离线版');
    await tapText(tester, '下一步');
    await tapText(tester, '薰衣草紫');
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '薰衣草紫'))
          .selected,
      isTrue,
    );
    await tapText(tester, '跟随系统');
    await tapText(tester, '下一步');
    await tapText(tester, '我是新手');
    await tapText(tester, '下一步');
    await tapText(tester, '开始使用');
    expect(find.text('已进入首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'settings persist and failed updates keep the last saved values',
    () async {
      final store = MemorySettings();
      final preferences = AppPreferences(store);
      await preferences.setThemeColor(ThemeColor.lavender);
      await preferences.setEdition(AppEdition.online);
      await preferences.setBeginner(true);
      await preferences.setThemeMode(ThemeMode.dark);
      final restarted = AppPreferences(store);
      await restarted.load();
      expect(restarted.themeColor, ThemeColor.lavender);
      expect(restarted.edition, AppEdition.online);
      expect(restarted.beginner, isTrue);
      expect(restarted.themeMode, ThemeMode.dark);
      store.failWrites = true;
      await expectLater(
        preferences.setThemeColor(ThemeColor.rose),
        throwsStateError,
      );
      await expectLater(preferences.setBeginner(false), throwsStateError);
      await expectLater(
        preferences.setThemeMode(ThemeMode.system),
        throwsStateError,
      );
      expect(preferences.themeColor, ThemeColor.lavender);
      expect(preferences.beginner, isTrue);
      expect(preferences.themeMode, ThemeMode.dark);
    },
  );
}
