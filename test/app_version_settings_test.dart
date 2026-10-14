import 'package:antkeep/online/app_update_controller.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:antkeep/online/online_store.dart';
import 'package:antkeep/online/online_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Store implements OnlineStore {
  @override
  Future<String?> readContent() async => null;
  @override
  Future<void> writeContent(String content) async {}
  @override
  Future<String?> readSeenAnnouncement() async => null;
  @override
  Future<void> writeSeenAnnouncement(String id) async {}
}

void main() {
  testWidgets(
    'check-in card has no refresh action and disables repeat submit',
    (tester) async {
      final online = OnlineController(
        api: OnlineApi(baseUrl: ''),
        store: _Store(),
      );
      final updates = AppUpdateController(
        api: OnlineApi(baseUrl: ''),
        currentVersion: () async => '1.0.3',
        supportsUpdates: () => false,
      );
      online.enabled = true;
      online.user = OnlineUser.fromJson({'id': 'alice', 'username': 'alice'});

      Widget settings() => MaterialApp(
        home: Scaffold(
          body: OnlineSettings(
            controller: online,
            updates: updates,
            section: OnlineSettingsSection.account,
            useOffline: () async {},
          ),
        ),
      );

      await tester.pumpWidget(settings());
      expect(find.text('刷新状态'), findsNothing);
      expect(find.widgetWithText(FilledButton, '签到'), findsOneWidget);

      online.checkin = CheckinSummary.fromJson({
        'date': '2026-10-14',
        'checkedInToday': true,
        'consecutiveDays': 3,
        'totalDays': 8,
      });
      await tester.pumpWidget(settings());
      final checkedButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '今日已签到'),
      );
      expect(checkedButton.onPressed, isNull);
      expect(find.text('2026-10-14 · 连续 3 天 · 累计 8 天'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      updates.dispose();
      online.dispose();
    },
  );

  testWidgets('installed version remains visible when update service fails', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'AntKeep',
      packageName: 'com.pipiele.antkeep',
      version: '1.0.3',
      buildNumber: '10003',
      buildSignature: '',
    );
    final updates = AppUpdateController(
      api: OnlineApi(
        baseUrl: 'https://example.test',
        clientFactory: () =>
            MockClient((_) async => throw http.ClientException('offline')),
      ),
      currentVersion: () async => '1.0.3',
      supportsUpdates: () => true,
    );
    final online = OnlineController(
      api: OnlineApi(baseUrl: ''),
      store: _Store(),
    );
    await updates.setOnline(false);
    await updates.check(manual: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OnlineSettings(
              controller: online,
              updates: updates,
              useOffline: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前 App 版本'), findsOneWidget);
    expect(find.text('1.0.3 (10003)'), findsOneWidget);
    expect(find.text('无法连接服务，请检查网络后重试。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    updates.dispose();
    online.dispose();
  });
}
