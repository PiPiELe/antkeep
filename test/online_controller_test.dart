import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:antkeep/online/content.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:antkeep/online/online_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryOnlineStore implements OnlineStore {
  String? token, content;
  bool failDelete = false;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String? value) async {
    if (value == null && failDelete) throw StateError('storage failure');
    token = value;
  }

  @override
  Future<String?> readContent() async => content;
  @override
  Future<void> writeContent(String value) async => content = value;
}

String snapshot({int version = 1, String name = '糖水'}) => jsonEncode({
  'id': 'publication-1',
  'version': version,
  'publishedAt': '2026-09-29T00:00:00Z',
  'itemTemplates': [
    {
      'id': 'sugar-water',
      'name': name,
      'category': '食物',
      'defaultUnit': '瓶',
      'expiry': {'type': 'none'},
      'enabled': true,
    },
  ],
  'onboarding': {
    'title': '新手指南',
    'summary': '保持本地备份',
    'steps': [
      {'id': 'backup', 'title': '备份', 'body': '导出 ZIP'},
    ],
  },
});
Map<String, dynamic> user(String id) => {
  'id': id,
  'username': id,
  'role': 'USER',
};
Map<String, dynamic> summary(int count) => {
  'date': '2026-09-29',
  'checkedInToday': count > 0,
  'consecutiveDays': count,
  'totalDays': count,
};
OnlineController controller(
  MemoryOnlineStore store,
  Future<http.Response> Function(http.Request) respond,
) => OnlineController(
  api: OnlineApi(
    baseUrl: 'https://api.example.test',
    clientFactory: () => MockClient(respond),
  ),
  store: store,
);

http.Response response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('offline sends no requests and always uses bundled content', () async {
    var calls = 0;
    final c = controller(MemoryOnlineStore(), (r) async {
      calls++;
      return response(snapshot(), 200);
    });
    await c.refreshContent();
    await c.login('user', 'password');
    await c.refreshCheckin(submit: true);
    expect(calls, 0);
    expect(c.content.version, 0);
    expect(c.user, isNull);
    c.dispose();
  });
  test(
    'guest loads public content; invalid refresh preserves last valid cache',
    () async {
      final store = MemoryOnlineStore();
      var invalid = false;
      final c = controller(store, (r) async {
        expect(r.url.path, '/api/public/content');
        expect(r.headers.containsKey('authorization'), false);
        return response(invalid ? '{}' : snapshot(), 200);
      });
      await c.setEnabled(true);
      expect(c.user, isNull);
      expect(c.content.templates.single.name, '糖水');
      final saved = store.content;
      invalid = true;
      await c.refreshContent();
      expect(store.content, saved);
      expect(c.content.version, 1);
      await c.setEnabled(false);
      expect(c.content, PublicContent.bundled);
      c.dispose();
    },
  );
  test(
    'restart uses cache when network fails and corrupt cache falls back',
    () async {
      final store = MemoryOnlineStore()..content = snapshot(version: 2);
      Future<http.Response> fail(http.Request r) async =>
          throw const SocketException('offline');
      final c = controller(store, fail);
      await c.setEnabled(true);
      expect(c.content.version, 2);
      c.dispose();
      store.content = 'broken';
      final other = controller(store, fail);
      await other.setEnabled(true);
      expect(other.content.version, 0);
      expect(other.busy, false);
      other.dispose();
    },
  );
  test('register login and checkin use only account fields and clear state on logout', () async {
    final store = MemoryOnlineStore();
    final paths = <String>[];
    final c = controller(store, (r) async {
      paths.add(r.url.path);
      switch (r.url.path) {
        case '/api/public/content':
          return response(snapshot(), 200);
        case '/api/app/auth/register':
          expect((jsonDecode(r.body) as Map).keys.toSet(), {
            'username',
            'password',
          });
          return response(jsonEncode(user('alice')), 201);
        case '/api/app/auth/login':
          return response(
            jsonEncode({'token': 'session-a', 'user': user('alice')}),
            200,
          );
        case '/api/app/check-ins/summary':
          return response(jsonEncode(summary(0)), 200);
        case '/api/app/check-ins':
          expect(r.body, isEmpty);
          expect(r.headers['authorization'], 'Bearer session-a');
          return response(jsonEncode(summary(1)), 200);
        case '/api/app/auth/logout':
          return response('{"ok":true}', 200);
      }
      throw StateError(r.url.path);
    });
    await c.setEnabled(true);
    await c.login('alice', 'password', register: true);
    expect(store.token, 'session-a');
    expect(c.user?.id, 'alice');
    await c.refreshCheckin(submit: true);
    expect(c.checkin?.totalDays, 1);
    await c.logout();
    expect(store.token, isNull);
    expect(c.user, isNull);
    expect(c.checkin, isNull);
    expect(
      paths.where((p) => p.contains('colony') || p.contains('media')),
      isEmpty,
    );
    c.dispose();
  });
  test(
    'expired session clears credentials; ordinary network failure does not',
    () async {
      final store = MemoryOnlineStore()..token = 'expired';
      var status = 503;
      final c = controller(
        store,
        (r) async => r.url.path == '/api/public/content'
            ? response(snapshot(), 200)
            : response('{"message":"failed"}', status),
      );
      await c.setEnabled(true);
      expect(store.token, 'expired');
      expect(c.user, isNull);
      await c.setEnabled(false);
      status = 401;
      await c.setEnabled(true);
      expect(store.token, isNull);
      expect(c.checkin, isNull);
      c.dispose();
    },
  );
  test(
    'switching offline ignores pending content and auth responses',
    () async {
      final store = MemoryOnlineStore()..token = 'old';
      final pendingContent = Completer<http.Response>(),
          pendingMe = Completer<http.Response>();
      final meStarted = Completer<void>();
      final c = controller(store, (r) {
        if (r.url.path == '/api/public/content') return pendingContent.future;
        if (r.url.path == '/api/app/me') {
          meStarted.complete();
          return pendingMe.future;
        }
        throw StateError('must not send followup after mode change');
      });
      final start = c.setEnabled(true);
      await meStarted.future;
      await c.setEnabled(false);
      pendingContent.complete(response(snapshot(), 200));
      pendingMe.complete(response(jsonEncode(user('old')), 200));
      await start;
      expect(c.user, isNull);
      expect(c.content.version, 0);
      expect(store.content, isNull);
      expect(store.token, 'old');
      c.dispose();
    },
  );
  test('login response after mode switch is not persisted', () async {
    final store = MemoryOnlineStore();
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final c = controller(store, (r) {
      if (r.url.path == '/api/public/content') {
        return Future.value(response(snapshot(), 200));
      }
      started.complete();
      return pending.future;
    });
    await c.setEnabled(true);
    final login = c.login('alice', 'password');
    await started.future;
    await c.setEnabled(false);
    pending.complete(
      response(jsonEncode({'token': 'late', 'user': user('alice')}), 200),
    );
    await login;
    expect(store.token, isNull);
    expect(c.user, isNull);
    c.dispose();
  });
  test(
    'account switch replaces checkin state; failed logout can be retried',
    () async {
      final store = MemoryOnlineStore();
      final c = controller(store, (r) async {
        if (r.url.path == '/api/public/content') {
          return response(snapshot(), 200);
        }
        if (r.url.path == '/api/app/auth/login') {
          final name = jsonDecode(r.body)['username'] as String;
          return response(jsonEncode({'token': name, 'user': user(name)}), 200);
        }
        if (r.url.path == '/api/app/check-ins/summary') {
          return response(
            jsonEncode(
              summary(r.headers['authorization'] == 'Bearer alice' ? 5 : 0),
            ),
            200,
          );
        }
        return response('{"ok":true}', 200);
      });
      await c.setEnabled(true);
      await c.login('alice', 'password');
      expect(c.checkin?.totalDays, 5);
      store.failDelete = true;
      await c.logout();
      expect(c.hasSession, true);
      expect(c.user, isNull);
      store.failDelete = false;
      await c.logout();
      expect(store.token, isNull);
      await c.login('bob', 'password');
      expect(c.user?.id, 'bob');
      expect(c.checkin?.totalDays, 0);
      c.dispose();
    },
  );
  test('content rejects duplicate templates and unsupported expiry', () {
    final data = jsonDecode(snapshot()) as Map<String, dynamic>;
    (data['itemTemplates'] as List).add(data['itemTemplates'][0]);
    expect(() => PublicContent.decode(jsonEncode(data)), throwsFormatException);
    final bad = jsonDecode(snapshot()) as Map<String, dynamic>;
    bad['itemTemplates'][0]['expiry'] = {'type': 'fixedDate'};
    expect(() => PublicContent.decode(jsonEncode(bad)), throwsFormatException);
  });
}
