import 'package:antkeep/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements AppSettingsStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<Map<String, String>> readSettings() async => Map.of(values);

  @override
  Future<void> writeSettings(Map<String, String> updates) async {
    if (failWrites) throw StateError('unavailable');
    values.addAll(updates);
  }
}

void main() {
  test('ultra simple defaults, persistence and mode switching', () async {
    final store = _Store();
    final preferences = AppPreferences(store);
    await preferences.load();
    expect(preferences.simpleMode, isFalse);
    expect(preferences.ultraSimpleMode, isFalse);
    for (final feature in UltraSimpleFeature.values) {
      expect(preferences.showFeature(feature), isTrue);
      expect(preferences.ultraFeatureEnabled(feature), feature.defaultEnabled);
    }

    await preferences.setSimpleMode(true);
    await preferences.setUltraSimpleMode(true);
    expect(preferences.simpleMode, isFalse);
    expect(preferences.ultraSimpleMode, isTrue);
    expect(preferences.showFeature(UltraSimpleFeature.inventory), isTrue);
    expect(preferences.showFeature(UltraSimpleFeature.careTasks), isFalse);
    await preferences.setUltraFeature(UltraSimpleFeature.memorial, true);
    await preferences.setUltraFeature(UltraSimpleFeature.inventory, false);

    final restarted = AppPreferences(store);
    await restarted.load();
    expect(restarted.ultraSimpleMode, isTrue);
    expect(restarted.simpleMode, isFalse);
    expect(restarted.showFeature(UltraSimpleFeature.memorial), isTrue);
    expect(restarted.showFeature(UltraSimpleFeature.inventory), isFalse);
    await restarted.setSimpleMode(true);
    expect(restarted.ultraSimpleMode, isFalse);
    expect(restarted.simpleMode, isTrue);
    expect(restarted.showFeature(UltraSimpleFeature.inventory), isTrue);

    store.failWrites = true;
    await expectLater(restarted.setUltraSimpleMode(true), throwsStateError);
    expect(restarted.simpleMode, isTrue);
    expect(restarted.ultraSimpleMode, isFalse);
  });
}
