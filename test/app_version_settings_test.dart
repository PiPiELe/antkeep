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
}

void main() {
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
