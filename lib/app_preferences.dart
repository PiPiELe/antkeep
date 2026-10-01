import 'package:flutter/material.dart';

abstract class AppSettingsStore {
  Future<Map<String, String>> readSettings();
  Future<void> writeSettings(Map<String, String> values);
}

enum ThemeColor {
  forest('森林绿', Color(0xff3f6048)),
  ocean('海洋蓝', Color(0xff32639a)),
  amber('琥珀橙', Color(0xff946020)),
  lavender('薰衣草紫', Color(0xff79569c)),
  rose('玫瑰粉', Color(0xffa4486b));

  const ThemeColor(this.label, this.color);
  final String label;
  final Color color;
}

enum AppEdition {
  offline('离线版'),
  online('在线版');

  const AppEdition(this.label);
  final String label;
}

class AppPreferences extends ChangeNotifier {
  AppPreferences(this.store);
  final AppSettingsStore store;

  bool onboardingCompleted = false;
  bool beginner = false;
  bool simpleMode = false;
  bool careRemindersEnabled = false;
  int careReminderMinuteOfDay = 20 * 60;
  AppEdition edition = AppEdition.offline;
  ThemeMode themeMode = ThemeMode.system;
  ThemeColor themeColor = ThemeColor.forest;

  Future<void> load() async {
    final values = await store.readSettings();
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

ThemeData antKeepTheme(ThemeColor color, {bool dark = false}) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: dark && color == ThemeColor.forest
        ? const Color(0xff7da985)
        : color.color,
    brightness: dark ? Brightness.dark : Brightness.light,
  ),
  scaffoldBackgroundColor: dark ? const Color(0xff0d0f0d) : null,
  appBarTheme: dark
      ? const AppBarTheme(backgroundColor: Color(0xff121512))
      : null,
  cardColor: dark ? const Color(0xff181c18) : null,
  useMaterial3: true,
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
);
