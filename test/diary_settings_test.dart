import 'dart:convert';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/diary_preferences.dart';
import 'package:antkeep/diary_settings_page.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/population_forecast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_test.dart' show MemorySettings;

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(finder, delta);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'old installations preserve full display and incremental entry',
    () async {
      final preferences = AppPreferences(MemorySettings());
      await preferences.load();
      expect(preferences.diary.preset, DiaryPreset.full);
      expect(preferences.diary.incremental, isTrue);
      expect(preferences.diary.display.counts, isTrue);
      expect(preferences.diary.display.populationExpanded, isFalse);
    },
  );

  test(
    'custom combination survives presets and restart without changing entry',
    () async {
      final store = MemorySettings();
      final preferences = AppPreferences(store);
      final custom = const DiaryDisplay().copyWith(
        counts: false,
        fullNotes: false,
        includeBrood: true,
        forecast: true,
        horizon: ForecastHorizon.week,
      );
      await preferences.setDiary(
        preferences.diary.customize(custom).withIncremental(false),
      );
      for (final preset in [
        DiaryPreset.daily,
        DiaryPreset.full,
        DiaryPreset.compact,
      ]) {
        await preferences.setDiary(preferences.diary.select(preset));
        expect(preferences.diary.incremental, isFalse);
      }
      final restarted = AppPreferences(store);
      await restarted.load();
      expect(restarted.diary.preset, DiaryPreset.compact);
      expect(restarted.diary.incremental, isFalse);
      await restarted.setDiary(restarted.diary.select(DiaryPreset.custom));
      expect(restarted.diary.display.toJson(), custom.toJson());
    },
  );

  test('invalid and future preference fields fall back safely', () async {
    final store = MemorySettings();
    final preferences = AppPreferences(store);
    for (final raw in [
      'broken',
      '[]',
      'null',
      jsonEncode({
        'preset': 'unknown',
        'incremental': 'false',
        'custom': {'counts': 0, 'horizon': 'year'},
      }),
    ]) {
      store.values['diary_preferences'] = raw;
      await preferences.load();
      expect(preferences.diary.preset, DiaryPreset.full);
      expect(preferences.diary.incremental, isTrue);
      expect(preferences.diary.custom.counts, isTrue);
      expect(preferences.diary.custom.horizon, ForecastHorizon.month);
    }
  });

  test('failed persistence leaves the live preference unchanged', () async {
    final store = MemorySettings();
    final preferences = AppPreferences(store);
    var calls = 0;
    preferences.addListener(() => calls++);
    store.failWrites = true;
    await expectLater(
      preferences.setDiary(preferences.diary.select(DiaryPreset.daily)),
      throwsStateError,
    );
    expect(preferences.diary.preset, DiaryPreset.full);
    expect(calls, 0);
  });

  final colony = Colony(
    id: 'settings',
    name: '设置测试',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    showSpecialized: true,
    specializedCount: 3,
  );

  testWidgets(
    'presets, customization and restore work at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = AppPreferences(MemorySettings());
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: DiarySettingsPage(preferences: preferences, colony: colony),
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '日常'));
      await tester.pumpAndSettle();
      expect(preferences.diary.display.counts, isFalse);
      final photos = find.widgetWithText(SwitchListTile, '显示照片缩略图');
      await reveal(tester, photos);
      await tester.tap(photos);
      await tester.pumpAndSettle();
      expect(preferences.diary.preset, DiaryPreset.custom);
      expect(preferences.diary.display.photos, isFalse);
      await reveal(tester, find.widgetWithText(ChoiceChip, '完整'), delta: -250);
      await tester.tap(find.widgetWithText(ChoiceChip, '完整'));
      await tester.pumpAndSettle();
      expect(preferences.diary.display.counts, isTrue);
      await tester.tap(find.widgetWithText(ChoiceChip, '自定义'));
      await tester.pumpAndSettle();
      expect(preferences.diary.display.photos, isFalse);
      expect(preferences.diary.incremental, isTrue);
      expect(colony.specializedCount, 3);
      expect(colony.growth, isNull);
      await reveal(tester, find.text('群落自动扩充'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history editing locks totals and unavailable rule editors stay disabled',
    (tester) async {
      final preferences = AppPreferences(MemorySettings());
      await tester.pumpWidget(
        MaterialApp(
          home: DiarySettingsPage(
            preferences: preferences,
            colony: colony,
            editingRecord: true,
          ),
        ),
      );
      final increment = find.widgetWithText(SwitchListTile, '增量');
      await reveal(tester, increment);
      expect(tester.widget<SwitchListTile>(increment).value, isFalse);
      expect(tester.widget<SwitchListTile>(increment).onChanged, isNull);
      expect(preferences.diary.incremental, isTrue);
      await reveal(tester, find.text('特化'));
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '特化')).onTap,
        isNull,
      );
      await reveal(tester, find.text('群落自动扩充'));
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, '群落自动扩充')).onTap,
        isNull,
      );
    },
  );

  testWidgets('failed save reports error without updating the active form', (
    tester,
  ) async {
    final store = MemorySettings()..failWrites = true;
    final preferences = AppPreferences(store);
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: DiarySettingsPage(
          preferences: preferences,
          colony: colony,
          recordIncremental: true,
          onRecordIncrementalChanged: (value) => changed = value,
        ),
      ),
    );
    final increment = find.widgetWithText(SwitchListTile, '增量');
    await reveal(tester, increment);
    await tester.tap(increment);
    await tester.pumpAndSettle();
    expect(changed, isNull);
    expect(preferences.diary.incremental, isTrue);
    expect(tester.widget<SwitchListTile>(increment).value, isTrue);
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
  });
}
