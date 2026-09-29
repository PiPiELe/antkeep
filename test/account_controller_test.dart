import 'dart:async';
import 'dart:convert';

import 'package:antkeep/account_controller.dart';
import 'package:antkeep/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class Settings implements AppSettingsStore {
  final values = <String, String>{};
  @override
  Future<Map<String, String>> readSettings() async => values;
  @override
  Future<void> writeSettings(Map<String, String> updates) async =>
      values.addAll(updates);
}

Map<String, dynamic> profile({bool checkedIn = false}) => {
  'user': {'id': 'test-user', 'username': 'keeper', 'nickname': '养蚁人'},
  'checkIn': {
    'serverDate': '2026-09-29',
    'checkedInToday': checkedIn,
    'totalDays': checkedIn ? 1 : 0,
    'streakDays': checkedIn ? 1 : 0,
    'recentDates': checkedIn ? ['2026-09-29'] : <String>[],
  },
};
http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'account requests default to disabled even with a configured service',
    () async {
      var requests = 0;
      final controller = AccountController(
        preferences: AppPreferences(Settings())..edition = AppEdition.online,
        baseUrl: 'https://accounts.test',
        client: MockClient((_) async {
          requests++;
          return jsonResponse({'token': 'test-token', ...profile()});
        }),
      );
      addTearDown(controller.dispose);
      expect(controller.configured, isTrue);
      expect(controller.requestsEnabled, isFalse);
      await controller.authenticate(
        username: 'keeper',
        password: 'test-password',
      );
      await controller.authenticate(
        username: 'keeper',
        password: 'test-password',
        nickname: '养蚁人',
      );
      await controller.refresh();
      await controller.checkIn();
      await controller.updateNickname('新昵称');
      await controller.logout();
      expect(requests, 0);
      expect(controller.signedIn, isFalse);
      expect(controller.error, '账号与签到暂未开放。');
    },
  );

  test(
    'server controls counts; credentials are not stored; failures allow retry',
    () async {
      final settings = Settings();
      final preferences = AppPreferences(settings)..edition = AppEdition.online;
      var checkInRequests = 0;
      var failCheckIn = true;
      final controller = AccountController(
        requestsEnabled: true,
        preferences: preferences,
        baseUrl: 'https://accounts.test',
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          if (request.url.path.endsWith('/login')) {
            return jsonResponse({'token': 'test-token', ...profile()});
          }
          expect(request.headers['Authorization'], 'Bearer test-token');
          if (request.url.path.endsWith('/check-in')) {
            checkInRequests++;
            expect(request.body, isEmpty);
            if (failCheckIn) return jsonResponse({}, 503);
            return jsonResponse(profile(checkedIn: true));
          }
          if (request.url.path.endsWith('/logout')) {
            return jsonResponse({'ok': true});
          }
          return jsonResponse({}, 401);
        }),
      );
      addTearDown(controller.dispose);
      await controller.authenticate(
        username: 'keeper',
        password: 'test-password',
      );
      expect(controller.signedIn, isTrue);
      expect(settings.values, isEmpty);
      await controller.checkIn();
      expect(controller.account!.totalDays, 0);
      expect(controller.error, isNotNull);
      failCheckIn = false;
      await controller.checkIn();
      expect(controller.account!.totalDays, 1);
      expect(controller.error, isNull);
      expect(checkInRequests, 2);
      await controller.refresh();
      expect(controller.signedIn, isFalse);
      expect(controller.error, contains('登录已失效'));
    },
  );

  test(
    'offline blocks traffic and invalidates an in-flight login response',
    () async {
      final preferences = AppPreferences(Settings())
        ..edition = AppEdition.online;
      final pending = Completer<http.Response>();
      var requests = 0;
      final controller = AccountController(
        requestsEnabled: true,
        preferences: preferences,
        baseUrl: 'https://accounts.test',
        client: MockClient((request) {
          requests++;
          return pending.future;
        }),
      );
      addTearDown(controller.dispose);
      final login = controller.authenticate(
        username: 'keeper',
        password: 'test-password',
      );
      await Future<void>.delayed(Duration.zero);
      await preferences.setEdition(AppEdition.offline);
      pending.complete(jsonResponse({'token': 'test-token', ...profile()}));
      await login;
      expect(controller.signedIn, isFalse);
      expect(controller.busy, isFalse);
      await controller.authenticate(
        username: 'keeper',
        password: 'test-password',
      );
      await controller.checkIn();
      expect(requests, 1);
    },
  );

  test(
    'parallel taps are serialized and logout revokes the server session',
    () async {
      final pending = Completer<http.Response>();
      var checkIns = 0;
      var logouts = 0;
      final controller = AccountController(
        requestsEnabled: true,
        preferences: AppPreferences(Settings())..edition = AppEdition.online,
        baseUrl: 'https://accounts.test',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return jsonResponse({'token': 'test-token', ...profile()});
          }
          if (request.url.path.endsWith('/logout')) {
            logouts++;
            return jsonResponse({'ok': true});
          }
          checkIns++;
          return pending.future;
        }),
      );
      addTearDown(controller.dispose);
      await controller.authenticate(
        username: 'keeper',
        password: 'test-password',
      );
      final first = controller.checkIn();
      await controller.checkIn();
      pending.complete(jsonResponse(profile(checkedIn: true)));
      await first;
      expect(checkIns, 1);
      await controller.logout();
      expect(logouts, 1);
      expect(controller.signedIn, isFalse);
    },
  );

  test(
    'unconfigured and insecure remote services do not receive credentials',
    () async {
      for (final url in [
        '',
        'http://remote.test',
        'https://user:secret@remote.test',
      ]) {
        final controller = AccountController(
          requestsEnabled: true,
          preferences: AppPreferences(Settings())..edition = AppEdition.online,
          baseUrl: url,
          client: MockClient(
            (_) => throw StateError('Must not send credentials'),
          ),
        );
        expect(controller.configured, isFalse);
        await controller.authenticate(
          username: 'keeper',
          password: 'test-password',
        );
        expect(controller.signedIn, isFalse);
        controller.dispose();
      }
    },
  );
}
