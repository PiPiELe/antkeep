import 'dart:convert';

import 'package:flutter/material.dart';

import 'diary_preferences.dart';

abstract class AppSettingsStore {
  Future<Map<String, String>> readSettings();
  Future<void> writeSettings(Map<String, String> values);
}

enum ThemeColor {
  forest('森林绿', Color(0xff3f6048)),
  ocean('海洋蓝', Color(0xff32639a)),
  amber('琥珀橙', Color(0xff946020)),
  lavender('薰衣草紫', Color(0xff79569c)),
  rose('玫瑰粉', Color(0xffa4486b)),
  mistBlue('雾蓝', Color(0xffafc2db)),
  white('纯白', Colors.white);

  const ThemeColor(this.label, this.color);
  final String label;
  final Color color;
}

enum FontColor {
  theme('跟随主题', null, null),
  ink('墨黑', Color(0xff000000), Color(0xfff5f5f5)),
  graphite('石墨灰', Color(0xff424242), Color(0xffd6d6d6)),
  navy('深蓝', Color(0xff243b53), Color(0xffbfd3ea)),
  green('墨绿', Color(0xff285943), Color(0xffb7dbc7)),
  brown('栗棕', Color(0xff654735), Color(0xffe5cbb8)),
  purple('暗紫', Color(0xff59446b), Color(0xffd8c4e8));

  const FontColor(this.label, this.color, this.darkColor);
  final String label;
  final Color? color;
  final Color? darkColor;

  Color? resolve(bool dark) => dark ? darkColor : color;

  String hex(bool dark) => resolve(dark) == null
      ? '自动'
      : '#${(resolve(dark)!.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

enum AppEdition {
  offline('离线版'),
  online('在线版');

  const AppEdition(this.label);
  final String label;
}

enum ColonyTab {
  colonies('我的蚁群', 'colonies_tab_name'),
  memorial('英灵殿', 'memorial_tab_name');

  const ColonyTab(this.defaultName, this.settingKey);
  final String defaultName;
  final String settingKey;
}

class AppPreferences extends ChangeNotifier {
  AppPreferences(this.store);
  final AppSettingsStore store;

  DiaryPreferences diary = const DiaryPreferences();

  Future<void> setDiary(DiaryPreferences value) async {
    await store.writeSettings({
      'diary_preferences': jsonEncode(value.toJson()),
    });
    diary = value;
    notifyListeners();
  }

  bool onboardingCompleted = false;
  bool beginner = false;
  bool simpleMode = false;
  bool careRemindersEnabled = false;
  int careReminderMinuteOfDay = 20 * 60;
  AppEdition edition = AppEdition.offline;
  ThemeMode themeMode = ThemeMode.system;
  ThemeColor themeColor = ThemeColor.forest;
  FontColor fontColor = FontColor.theme;
  List<String> _colonyOrder = const [];
  List<String> get colonyOrder => _colonyOrder;

  Future<void> setColonyOrder(Iterable<String> ids) async {
    final order = List<String>.unmodifiable(ids.toSet());
    await store.writeSettings({'colony_order': jsonEncode(order)});
    _colonyOrder = order;
    notifyListeners();
  }

  final _colonyTabNames = <ColonyTab, String>{};

  String colonyTabName(ColonyTab tab) =>
      _colonyTabNames[tab] ?? tab.defaultName;

  Future<void> setColonyTabName(ColonyTab tab, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.characters.length > 12) {
      throw ArgumentError('菜单名称须为 1～12 个字符');
    }
    await store.writeSettings({tab.settingKey: trimmed});
    _colonyTabNames[tab] = trimmed;
    notifyListeners();
  }

  Future<void> load() async {
    final values = await store.readSettings();
    diary = const DiaryPreferences();
    try {
      final savedDiary = jsonDecode(values['diary_preferences'] ?? '{}');
      if (savedDiary is Map<String, dynamic>) {
        diary = DiaryPreferences.fromJson(savedDiary);
      }
    } on FormatException {
      // A damaged preference must not prevent opening local records.
    }
    _colonyOrder = const [];
    try {
      final order = jsonDecode(values['colony_order'] ?? '[]');
      if (order is List && order.every((id) => id is String)) {
        _colonyOrder = List<String>.unmodifiable(order.cast<String>().toSet());
      }
    } on FormatException {
      // Invalid local ordering must not prevent loading the other preferences.
    }
    _colonyTabNames.clear();
    for (final tab in ColonyTab.values) {
      final name = values[tab.settingKey]?.trim();
      if (name != null && name.isNotEmpty && name.characters.length <= 12) {
        _colonyTabNames[tab] = name;
      }
    }
    onboardingCompleted = values['onboarding_completed'] == 'true';
    beginner = values['keeper_experience'] == 'beginner';
    simpleMode = values['simple_mode'] == 'true';
    careRemindersEnabled = values['care_reminders_enabled'] == 'true';
    careReminderMinuteOfDay =
        int.tryParse(values['care_reminder_minute_of_day'] ?? '') ?? 20 * 60;
    edition = AppEdition.values.firstWhere(
      (edition) => edition.name == values['app_edition'],
      orElse: () => AppEdition.offline,
    );
    themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == values['theme_mode'],
      orElse: () => switch (values['dark_theme']) {
        'true' => ThemeMode.dark,
        'false' => ThemeMode.light,
        _ => ThemeMode.system,
      },
    );
    themeColor = ThemeColor.values.firstWhere(
      (color) => color.name == values['theme_color'],
      orElse: () => ThemeColor.forest,
    );
    fontColor = FontColor.values.firstWhere(
      (color) => color.name == values['font_color'],
      orElse: () => FontColor.theme,
    );
    notifyListeners();
  }

  Future<void> completeOnboarding({
    required AppEdition edition,
    required bool beginner,
    required ThemeColor color,
    required ThemeMode mode,
  }) async {
    await store.writeSettings({
      'keeper_experience': beginner ? 'beginner' : 'experienced',
      'app_edition': edition.name,
      'theme_color': color.name,
      'theme_mode': mode.name,
      'onboarding_completed': 'true',
    });
    this.beginner = beginner;
    this.edition = edition;
    themeColor = color;
    themeMode = mode;
    onboardingCompleted = true;
    notifyListeners();
  }

  Future<void> setEdition(AppEdition edition) async {
    await store.writeSettings({'app_edition': edition.name});
    this.edition = edition;
    notifyListeners();
  }

  Future<void> setThemeColor(ThemeColor color) async {
    await store.writeSettings({'theme_color': color.name});
    themeColor = color;
    notifyListeners();
  }

  Future<void> setFontColor(FontColor color) async {
    await store.writeSettings({'font_color': color.name});
    fontColor = color;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await store.writeSettings({'theme_mode': mode.name});
    themeMode = mode;
    notifyListeners();
  }

  Future<void> setBeginner(bool enabled) async {
    await store.writeSettings({
      'keeper_experience': enabled ? 'beginner' : 'experienced',
    });
    beginner = enabled;
    notifyListeners();
  }

  Future<void> setSimpleMode(bool enabled) async {
    await store.writeSettings({'simple_mode': enabled.toString()});
    simpleMode = enabled;
    notifyListeners();
  }

  Future<void> setCareReminder({
    required bool enabled,
    required int minuteOfDay,
  }) async {
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw ArgumentError.value(minuteOfDay, 'minuteOfDay');
    }
    await store.writeSettings({
      'care_reminders_enabled': enabled.toString(),
      'care_reminder_minute_of_day': minuteOfDay.toString(),
    });
    careRemindersEnabled = enabled;
    careReminderMinuteOfDay = minuteOfDay;
    notifyListeners();
  }
}

ThemeData antKeepTheme(
  ThemeColor color, {
  bool dark = false,
  FontColor fontColor = FontColor.theme,
}) {
  var scheme = ColorScheme.fromSeed(
    seedColor: dark && color == ThemeColor.forest
        ? const Color(0xff7da985)
        : color.color,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  if (color == ThemeColor.mistBlue) {
    // Keep the requested accent exact instead of the seed-generated shade.
    scheme = scheme.copyWith(
      primaryContainer: color.color,
      onPrimaryContainer: Colors.black,
      secondaryContainer: color.color,
      onSecondaryContainer: Colors.black,
    );
  } else if (color == ThemeColor.white) {
    final foreground = dark ? Colors.white : Colors.black;
    final background = dark ? const Color(0xff121212) : Colors.white;
    final container = dark ? const Color(0xff242424) : const Color(0xfff5f5f5);
    scheme = scheme.copyWith(
      primary: foreground,
      onPrimary: background,
      primaryContainer: container,
      onPrimaryContainer: foreground,
      secondary: foreground,
      onSecondary: background,
      secondaryContainer: container,
      onSecondaryContainer: foreground,
      tertiary: foreground,
      onTertiary: background,
      tertiaryContainer: container,
      onTertiaryContainer: foreground,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: foreground,
      surfaceDim: container,
      surfaceBright: background,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: container,
      surfaceContainerHigh: container,
      surfaceContainerHighest: container,
      surfaceTint: Colors.transparent,
      outline: foreground,
      outlineVariant: dark ? const Color(0xff424242) : const Color(0xffdddddd),
      inverseSurface: foreground,
      onInverseSurface: background,
      inversePrimary: background,
    );
  }
  final monochrome = color == ThemeColor.white;
  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: monochrome
        ? scheme.surface
        : dark
        ? const Color(0xff0d0f0d)
        : null,
    appBarTheme: monochrome
        ? AppBarTheme(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
          )
        : dark
        ? const AppBarTheme(backgroundColor: Color(0xff121512))
        : null,
    cardColor: monochrome
        ? scheme.surface
        : dark
        ? const Color(0xff181c18)
        : null,
    filledButtonTheme: color == ThemeColor.mistBlue
        ? FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: color.color,
              foregroundColor: Colors.black,
            ),
          )
        : null,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
  final textColor = fontColor.resolve(dark);
  if (textColor == null) return theme;
  // Text preferences must not recolor icons or status/button foregrounds.
  final textTheme = theme.textTheme.apply(
    bodyColor: textColor,
    displayColor: textColor,
  );
  return theme.copyWith(
    textTheme: textTheme,
    listTileTheme: ListTileThemeData(textColor: textColor),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      labelStyle: TextStyle(color: textColor),
      hintStyle: TextStyle(color: textColor),
    ),
  );
}
