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
  test('colony order survives a fresh preferences instance', () async {
    final store = _Store();
    final preferences = AppPreferences(store);
    await preferences.setColonyOrder(['c', 'a', 'b']);
    final restarted = AppPreferences(store);
    await restarted.load();
    expect(restarted.colonyOrder, ['c', 'a', 'b']);
    store.failWrites = true;
    await expectLater(
      restarted.setColonyOrder(['b', 'a', 'c']),
      throwsStateError,
    );
    expect(restarted.colonyOrder, ['c', 'a', 'b']);
    await preferences.load();
    expect(preferences.colonyOrder, ['c', 'a', 'b']);
  });

  test('invalid ordering falls back without losing other settings', () async {
    final store = _Store();
    final preferences = AppPreferences(store);
    for (final invalid in ['bad json', '{}', '[1]', 'null']) {
      store.values.addAll({'colony_order': invalid, 'simple_mode': 'true'});
      await preferences.load();
      expect(preferences.colonyOrder, isEmpty);
      expect(preferences.simpleMode, isTrue);
    }
  });
}
