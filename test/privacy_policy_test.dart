import 'dart:convert';

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/privacy_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettings implements AppSettingsStore {
  final values = <String, String>{};

  @override
  Future<Map<String, String>> readSettings() async => Map.of(values);

  @override
  Future<void> writeSettings(Map<String, String> updates) async {
    values.addAll(updates);
  }
}

String _agreement({int version = 3}) => jsonEncode({
  'id': 'd2dd7c49-73f1-438a-9961-2b643529d99c',
  'version': version,
  'title': '蚁记隐私政策',
  'effectiveDate': '2026-10-01',
  'developerName': '蚁记开发者',
  'contact': 'privacy@example.test',
  'content': '本应用将蚁群、记录和照片保存在本机。' * 8,
  'publishedAt': '2026-10-01T00:00:00Z',
});

void main() {
  test('published privacy agreement validates its version and content', () {
    final agreement = PrivacyAgreement.decode(_agreement());
    expect(agreement.version, 3);
    expect(agreement.title, '蚁记隐私政策');
    expect(agreement.content, contains('照片保存在本机'));
    expect(
      () => PrivacyAgreement.decode(_agreement(version: 0)),
      throwsFormatException,
    );
  });

  test(
    'privacy acceptance is persisted for the exact published version',
    () async {
      final store = _MemorySettings();
      final preferences = AppPreferences(store);
      await preferences.load();
      expect(preferences.hasAcceptedPrivacyPolicy, isFalse);

      await preferences.acceptPrivacyPolicy(3);
      expect(preferences.hasAcceptedPrivacyPolicyVersion(3), isTrue);
      expect(preferences.hasAcceptedPrivacyPolicyVersion(4), isFalse);

      final restarted = AppPreferences(store);
      await restarted.load();
      expect(restarted.hasAcceptedPrivacyPolicyVersion(3), isTrue);
    },
  );
}
