import 'dart:async';
import 'dart:convert';

import 'package:antkeep/online/app_update.dart';
import 'package:antkeep/online/app_update_controller.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String policy({String latest = '1.1.0', String? minimum, int version = 1}) =>
    jsonEncode({
      'version': version,
      'enabled': true,
      'latestVersion': latest,
      'minimumVersion': minimum,
      'downloadUrl': 'https://downloads.example.test/antkeep',
      'releaseNotes': '修复已知问题。',
    });

http.Response response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

AppUpdateController controller({
  required Future<http.Response> Function(http.Request) respond,
  required Future<String> Function() currentVersion,
  bool supported = true,
  Future<bool> Function(Uri)? openUrl,
}) => AppUpdateController(
  api: OnlineApi(
    baseUrl: 'https://api.example.test',
    clientFactory: () => MockClient(respond),
  ),
  currentVersion: currentVersion,
  supportsUpdates: () => supported,
  openUrl: openUrl,
);

void main() {
  test(
    'three-part versions compare numerically and reject non-release labels',
    () {
      expect(
        AppVersion.parse('1.10.0').compareTo(AppVersion.parse('1.2.9')),
        greaterThan(0),
      );
      expect(AppVersion.parse('1.0.0').compareTo(AppVersion.parse('1.0.0')), 0);
      expect(() => AppVersion.parse('1.0'), throwsFormatException);
      expect(() => AppVersion.parse('v1.0.0'), throwsFormatException);
      expect(() => AppVersion.parse('1.0.0-beta'), throwsFormatException);
    },
  );

  test('offline checks anonymously and supports manual rechecking', () async {
    var calls = 0;
    final offline = controller(
      respond: (request) async {
        calls++;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/public/app-update/android');
        expect(request.url.hasQuery, isFalse);
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.body, isEmpty);
        return response(policy(), 200);
      },
      currentVersion: () async => '1.0.0',
    );
    expect(await offline.setOnline(false), isFalse);
    expect(calls, 1);
    expect(offline.online, isFalse);
    expect(offline.availability, AppUpdateAvailability.optional);
    expect(offline.takeOptionalPrompt(), isTrue);
    await offline.check(manual: true);
    expect(calls, 2);
    expect(offline.takeOptionalPrompt(), isFalse);
    offline.dispose();
  });

  test(
    'unsupported platforms make no update request in either edition',
    () async {
      var calls = 0;
      final unsupported = controller(
        respond: (_) async {
          calls++;
          return response(policy(), 200);
        },
        currentVersion: () async => '1.0.0',
        supported: false,
      );
      await unsupported.setOnline(true);
      await unsupported.setOnline(false);
      expect(calls, 0);
      unsupported.dispose();
    },
  );

  test('offline minimum version remains a dismissible update', () async {
    final updates = controller(
      respond: (_) async => response(policy(minimum: '1.1.0'), 200),
      currentVersion: () async => '1.0.0',
    );
    expect(await updates.setOnline(false), isFalse);
    expect(updates.availability, AppUpdateAvailability.optional);
    expect(updates.takeOptionalPrompt(), isTrue);
    expect(await updates.setOnline(true), isTrue);
    expect(updates.availability, AppUpdateAvailability.required);
    expect(await updates.setOnline(false), isFalse);
    expect(updates.availability, AppUpdateAvailability.optional);
    updates.dispose();
  });

  test('late online response cannot override an offline check', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final updates = controller(
      respond: (_) async => ++calls == 1
          ? pending.future
          : response(policy(latest: '1.0.0'), 200),
      currentVersion: () async => '1.0.0',
    );
    final onlineCheck = updates.setOnline(true);
    await updates.setOnline(false);
    pending.complete(response(policy(minimum: '1.1.0'), 200));
    await onlineCheck;
    expect(updates.online, isFalse);
    expect(updates.availability, AppUpdateAvailability.none);
    expect(updates.policy!.latestVersion.toString(), '1.0.0');
    expect(updates.checking, isFalse);
    updates.dispose();
  });

  test(
    'offline startup failure is silent and manual failure is visible',
    () async {
      final updates = controller(
        respond: (_) async => throw Exception('network unavailable'),
        currentVersion: () async => '1.0.0',
      );
      expect(await updates.setOnline(false), isFalse);
      expect(updates.error, isNull);
      expect(updates.checking, isFalse);
      expect(updates.availability, AppUpdateAvailability.none);
      await updates.check(manual: true);
      expect(updates.error, isNotNull);
      updates.dispose();
    },
  );

  test(
    'newer policy is optional once and does not block online mode',
    () async {
      final updates = controller(
        respond: (request) async {
          expect(request.url.path, '/api/public/app-update/android');
          expect(request.headers.containsKey('authorization'), false);
          return response(policy(latest: '1.1.0', minimum: '1.0.0'), 200);
        },
        currentVersion: () async => '1.0.0',
      );
      expect(await updates.setOnline(true), isFalse);
      expect(updates.availability, AppUpdateAvailability.optional);
      expect(updates.takeOptionalPrompt(), isTrue);
      expect(updates.takeOptionalPrompt(), isFalse);
    },
  );

  test(
    'minimum version requires update but keeps only online access blocked',
    () async {
      final updates = controller(
        respond: (_) async =>
            response(policy(latest: '1.2.0', minimum: '1.1.0'), 200),
        currentVersion: () async => '1.0.0',
      );
      expect(await updates.setOnline(true), isTrue);
      expect(updates.online, isTrue);
      expect(updates.availability, AppUpdateAvailability.required);
    },
  );

  test('missing, invalid, or failed policy never requires an update', () async {
    for (final reply in [
      response('{"message":"missing"}', 404),
      response('{}', 200),
      response('{"message":"failed"}', 503),
    ]) {
      final updates = controller(
        respond: (_) async => reply,
        currentVersion: () async => '1.0.0',
      );
      expect(await updates.setOnline(true), isFalse);
      expect(updates.availability, AppUpdateAvailability.none);
    }
  });

  test(
    'download failure is surfaced without changing the update decision',
    () async {
      final updates = controller(
        respond: (_) async => response(policy(latest: '1.1.0'), 200),
        currentVersion: () async => '1.0.0',
        openUrl: (_) async => false,
      );
      await updates.setOnline(true);
      expect(await updates.openDownload(), isFalse);
      expect(updates.availability, AppUpdateAvailability.optional);
      expect(updates.error, contains('无法打开'));
    },
  );
}
