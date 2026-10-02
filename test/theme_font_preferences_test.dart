import 'package:antkeep/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_test.dart' show MemorySettings;

void main() {
  test('theme and font persist independently across restarts', () async {
    final store = MemorySettings();
    final preferences = AppPreferences(store);
    await preferences.setThemeColor(ThemeColor.mistBlue);
    await preferences.setFontColor(FontColor.navy);
    final restarted = AppPreferences(store);
    await restarted.load();
    expect(restarted.themeColor, ThemeColor.mistBlue);
    expect(restarted.fontColor, FontColor.navy);
    await restarted.setThemeColor(ThemeColor.white);
    expect(restarted.fontColor, FontColor.navy);
    await restarted.setFontColor(FontColor.theme);
    await preferences.load();
    expect(preferences.themeColor, ThemeColor.white);
    expect(preferences.fontColor, FontColor.theme);
  });

  test('legacy and unknown font values use the theme default', () async {
    final store = MemorySettings();
    final preferences = AppPreferences(store);
    await preferences.load();
    expect(preferences.fontColor, FontColor.theme);
    store.values['font_color'] = 'unknown';
    await preferences.load();
    expect(preferences.fontColor, FontColor.theme);
  });

  test('failed font save keeps selection and does not notify', () async {
    final store = MemorySettings();
    final preferences = AppPreferences(store);
    await preferences.setFontColor(FontColor.green);
    var notifications = 0;
    preferences.addListener(() => notifications++);
    store.failWrites = true;
    await expectLater(
      preferences.setFontColor(FontColor.navy),
      throwsStateError,
    );
    expect(preferences.fontColor, FontColor.green);
    expect(store.values['font_color'], 'green');
    expect(notifications, 0);
  });

  test('new themes retain exact accent and monochrome surfaces', () {
    final mist = antKeepTheme(ThemeColor.mistBlue);
    expect(mist.colorScheme.primaryContainer, const Color(0xffafc2db));
    expect(
      mist.filledButtonTheme.style!.backgroundColor!.resolve({}),
      const Color(0xffafc2db),
    );
    final white = antKeepTheme(ThemeColor.white);
    expect(white.scaffoldBackgroundColor, Colors.white);
    expect(white.colorScheme.onSurface, Colors.black);
    expect(white.colorScheme.onSurfaceVariant, Colors.black);
    expect(white.colorScheme.primary, Colors.black);
    final dark = antKeepTheme(ThemeColor.white, dark: true);
    expect(dark.colorScheme.onSurface, Colors.white);
    expect(dark.brightness, Brightness.dark);
  });

  test('font changes text without changing accent or icon colors', () {
    for (final dark in [false, true]) {
      final original = antKeepTheme(ThemeColor.mistBlue, dark: dark);
      final custom = antKeepTheme(
        ThemeColor.mistBlue,
        dark: dark,
        fontColor: FontColor.navy,
      );
      expect(custom.textTheme.bodyMedium!.color, FontColor.navy.resolve(dark));
      expect(custom.textTheme.titleLarge!.color, FontColor.navy.resolve(dark));
      expect(custom.listTileTheme.textColor, FontColor.navy.resolve(dark));
      expect(custom.colorScheme, original.colorScheme);
      expect(custom.iconTheme.color, original.iconTheme.color);
    }
  });

  test('all font presets remain readable on each theme surface', () {
    for (final color in ThemeColor.values) {
      for (final dark in [false, true]) {
        final theme = antKeepTheme(color, dark: dark);
        for (final font in FontColor.values.where(
          (font) => font != FontColor.theme,
        )) {
          final luminances = [
            font.resolve(dark)!.computeLuminance(),
            theme.colorScheme.surface.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + 0.05) / (luminances.first + 0.05),
            greaterThanOrEqualTo(4.5),
            reason: '${color.name}/${font.name}/$dark',
          );
        }
      }
    }
  });
}
