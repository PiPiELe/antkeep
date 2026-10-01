import 'package:antkeep/online/app_update.dart';
import 'package:antkeep/online/app_update_controller.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('test version comparison follows numeric fourth part', () {
    final testVersion = AppVersion.parse('1.0.7.1');
    expect(testVersion.toString(), '1.0.7.1');
    expect(testVersion.compareTo(AppVersion.parse('1.0.7')), greaterThan(0));
    expect(testVersion.compareTo(AppVersion.parse('1.0.7.2')), lessThan(0));
    expect(testVersion.compareTo(AppVersion.parse('1.0.8')), lessThan(0));
    expect(
      AppVersion.parse('1.0.7.10').compareTo(AppVersion.parse('1.0.7.2')),
      greaterThan(0),
    );
    expect(AppVersion.parse('1.0.7.0').compareTo(AppVersion.parse('1.0.7')), 0);
    expect(() => AppVersion.parse('1.0.7.01'), throwsFormatException);
    expect(() => AppVersion.parse('1.0.7.1.2'), throwsFormatException);
  });

  test(
    'four-part installed version can check a production update policy',
    () async {
      final updates = AppUpdateController(
        api: OnlineApi(
          baseUrl: 'https://updates.example.test',
          clientFactory: () => MockClient(
            (_) async => http.Response(
              '{"version":1,"enabled":true,"latestVersion":"1.0.8","minimumVersion":null,"downloadUrl":"https://example.test/download","releaseNotes":"update"}',
              200,
            ),
          ),
        ),
        currentVersion: () async => '1.0.7.1',
        supportsUpdates: () => true,
        diagnosticsEnabled: true,
      );
      addTearDown(updates.dispose);
      await updates.setOnline(true);
      expect(updates.availability, AppUpdateAvailability.optional);
      expect(updates.error, isNull);
      expect(updates.diagnostics, contains('当前: 1.0.7.1; 最新: 1.0.8'));
    },
  );

  AppUpdateController create(
    Future<http.Response> Function(http.Request) respond, {
    bool enabled = true,
  }) => AppUpdateController(
    api: OnlineApi(
      baseUrl: 'https://updates.example.test',
      clientFactory: () => MockClient(respond),
    ),
    currentVersion: () async => '1.0.7.1',
    supportsUpdates: () => true,
    diagnosticsEnabled: enabled,
  );

  test(
    'captures network cause and replaces previous diagnostic on retry',
    () async {
      var fails = true;
      final updates = create((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.body, isEmpty);
        if (fails) {
          throw http.ClientException(
            'Failed host lookup: updates.example.test',
          );
        }
        return http.Response('{}', 404);
      });
      addTearDown(updates.dispose);
      await updates.setOnline(true);
      await updates.check(manual: true);
      expect(updates.error, '无法连接服务，请检查网络后重试。');
      expect(updates.diagnostics, contains('Failed host lookup'));
      expect(updates.diagnostics, contains('/api/public/app-update/android'));
      expect(updates.diagnostics, contains('总耗时:'));
      fails = false;
      await updates.check(manual: true);
      expect(updates.error, isNull);
      expect(updates.diagnostics, contains('HTTP 404'));
      expect(updates.diagnostics, isNot(contains('Failed host lookup')));
    },
  );

  test('captures HTTP metadata without copying response bodies', () async {
    final updates = create(
      (_) async => http.Response(
        '<html>gateway-private-detail</html>',
        502,
        headers: {'content-type': 'text/html'},
      ),
    );
    addTearDown(updates.dispose);
    await updates.setOnline(false);
    await updates.check(manual: true);
    expect(updates.diagnostics, contains('HTTP 502'));
    expect(updates.diagnostics, contains('text/html'));
    expect(updates.diagnostics, isNot(contains('gateway-private-detail')));
  });

  test('ordinary builds do not retain diagnostics', () async {
    final updates = create((_) async {
      throw http.ClientException('network-error');
    }, enabled: false);
    addTearDown(updates.dispose);
    await updates.setOnline(true);
    await updates.check(manual: true);
    expect(updates.diagnostics, '尚未检查更新，请点击检查更新。');
    expect(updates.error, isNotNull);
  });

  test(
    'identifies invalid update JSON after a successful HTTP response',
    () async {
      final updates = create((_) async => http.Response('not json', 200));
      addTearDown(updates.dispose);
      await updates.setOnline(true);
      await updates.check(manual: true);
      expect(updates.error, '更新策略格式无效，已忽略。');
      expect(updates.diagnostics, contains('HTTP 200'));
      expect(updates.diagnostics, contains('FormatException'));
    },
  );
}
