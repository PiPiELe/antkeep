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
  String? content;
  String? seenAnnouncement;

  @override
  Future<String?> readContent() async => content;
  @override
  Future<void> writeContent(String value) async => content = value;
  @override
  Future<String?> readSeenAnnouncement() async => seenAnnouncement;
  @override
  Future<void> writeSeenAnnouncement(String id) async => seenAnnouncement = id;
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
  test(
    'published announcement appears once per edit and can be withdrawn',
    () async {
      final payload = jsonDecode(snapshot()) as Map<String, dynamic>;
      payload['texts'] = {
        'app.announcement': {
          'title': '停机通知',
          'body': '今晚维护。',
          'updatedAt': '2026-10-09T01:00:00Z',
        },
      };
      var raw = jsonEncode(payload);
      final store = MemoryOnlineStore();
      final first = controller(store, (_) async => response(raw, 200));
      await first.setEnabled(true);
      expect(first.pendingAnnouncement?.title, '停机通知');
    await first.acknowledgeAnnouncement(first.pendingAnnouncement!.id);
    expect(first.pendingAnnouncement, isNull);
    first.dispose();

    final cachedOnly = MemoryOnlineStore()..content = raw;
    final unavailable = controller(cachedOnly, (_) async => response('{}', 503));
    await unavailable.setEnabled(true);
    expect(unavailable.pendingAnnouncement, isNull);
    await unavailable.setEnabled(false);
    expect(unavailable.pendingAnnouncement, isNull);
    unavailable.dispose();

    final reopened = controller(store, (_) async => response(raw, 200));
      await reopened.setEnabled(true);
      expect(reopened.pendingAnnouncement, isNull);
      payload['version'] = 2;
      raw = jsonEncode(payload);
      await reopened.refreshContent();
      expect(reopened.pendingAnnouncement, isNull);
      (payload['texts'] as Map<String, dynamic>)['app.announcement'] = {
        'title': '恢复通知',
        'body': '维护已结束。',
        'updatedAt': '2026-10-09T02:00:00Z',
      };
      payload['version'] = 3;
      raw = jsonEncode(payload);
      await reopened.refreshContent();
      expect(reopened.pendingAnnouncement?.title, '恢复通知');
      payload['texts'] = <String, dynamic>{};
      payload['version'] = 4;
      raw = jsonEncode(payload);
      await reopened.refreshContent();
      expect(reopened.pendingAnnouncement, isNull);
      reopened.dispose();
    },
  );

  test(
    'care notices use published texts, cached content and offline fallback',
    () async {
      final payload = jsonDecode(snapshot()) as Map<String, dynamic>;
      payload['texts'] = {
        'inventory.help': {'title': '物品帮助', 'body': '不能出现在新手提示'},
        'beginner-care.water': {'title': '检查供水', 'body': '供水详情'},
        'beginner-care.quiet': {'title': '减少打扰', 'body': '安静详情'},
      };
      final raw = jsonEncode(payload);
      final decoded = PublicContent.decode(raw);
      expect(decoded.beginnerCareNotices.map((n) => n.title), ['检查供水', '减少打扰']);
      expect(decoded.beginnerCareNotices.first.description, '供水详情');
      final store = MemoryOnlineStore();
      final live = controller(store, (_) async => response(raw, 200));
      await live.setEnabled(true);
      expect(live.content.beginnerCareNotices.length, 2);
      expect(store.content, raw);
      live.dispose();
      final restarted = controller(store, (_) async => response('{}', 503));
      await restarted.setEnabled(true);
      expect(restarted.content.beginnerCareNotices.first.title, '检查供水');
      await restarted.setEnabled(false);
      expect(restarted.content.beginnerCareNotices.length, 8);
      restarted.dispose();
    },
  );

  test(
    'old snapshots and unrelated or empty texts use bundled care notices',
    () {
      final payload = jsonDecode(snapshot()) as Map<String, dynamic>;
      for (final texts in [
        null,
        <String, dynamic>{},
        {
          'inventory.help': {'title': '帮助', 'body': '说明'},
        },
      ]) {
        payload['texts'] = texts;
        expect(
          PublicContent.decode(jsonEncode(payload)).beginnerCareNotices,
          same(PublicContent.bundled.beginnerCareNotices),
        );
      }
    },
  );

  test('invalid care text never replaces valid cached content', () async {
    final payload = jsonDecode(snapshot()) as Map<String, dynamic>;
    payload['texts'] = {
      'beginner-care.valid': {'title': '有效提示', 'body': '正文'},
    };
    final store = MemoryOnlineStore()..content = jsonEncode(payload);
    payload['texts'] = {
      'beginner-care.invalid': {'title': ' ', 'body': '正文'},
    };
    expect(
      () => PublicContent.decode(jsonEncode(payload)),
      throwsFormatException,
    );
    final app = controller(
      store,
      (_) async => response(jsonEncode(payload), 200),
    );
    await app.setEnabled(true);
    expect(app.content.beginnerCareNotices.single.title, '有效提示');
    expect(
      PublicContent.decode(store.content!).beginnerCareNotices.single.title,
      '有效提示',
    );
    app.dispose();
  });

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
    expect(c.hasSession, isTrue);
    expect(c.user?.id, 'alice');
    await c.refreshCheckin(submit: true);
    expect(c.checkin?.totalDays, 1);
    await c.logout();
    expect(c.hasSession, isFalse);
    expect(c.user, isNull);
    expect(c.checkin, isNull);
    expect(
      paths.where((p) => p.contains('colony') || p.contains('media')),
      isEmpty,
    );
    c.dispose();
  });
  test('session failure clears in-memory credentials; ordinary network failure does not', () async {
    final store = MemoryOnlineStore();
    var status = 503;
    final c = controller(store, (r) async {
      if (r.url.path == '/api/public/content') return response(snapshot(), 200);
      if (r.url.path == '/api/app/auth/login') {
        return response(
          jsonEncode({'token': 'session-a', 'user': user('alice')}),
          200,
        );
      }
      return response('{"message":"failed"}', status);
    });
    await c.setEnabled(true);
    await c.login('alice', 'password');
    await c.refreshCheckin();
    expect(c.hasSession, isTrue);
    status = 401;
    await c.refreshCheckin();
    expect(c.hasSession, isFalse);
    expect(c.checkin, isNull);
    c.dispose();
  });
  test(
    'switching offline ignores pending content and auth responses',
    () async {
      final store = MemoryOnlineStore();
      final pendingContent = Completer<http.Response>();
      final c = controller(store, (r) {
        if (r.url.path == '/api/public/content') return pendingContent.future;
        throw StateError('must not send followup after mode change');
      });
      final start = c.setEnabled(true);
      await c.setEnabled(false);
      pendingContent.complete(response(snapshot(), 200));
      await start;
      expect(c.user, isNull);
      expect(c.content.version, 0);
      expect(store.content, isNull);
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
    expect(c.hasSession, isFalse);
    expect(c.user, isNull);
    c.dispose();
  });
  test('a session does not survive a controller restart', () async {
    final store = MemoryOnlineStore();
    final paths = <String>[];
    Future<http.Response> handler(http.Request request) async {
      paths.add(request.url.path);
      if (request.url.path == '/api/public/content') {
        return response(snapshot(), 200);
      }
      if (request.url.path == '/api/app/auth/login') {
        return response(
          jsonEncode({'token': 'session-a', 'user': user('alice')}),
          200,
        );
      }
      throw StateError(request.url.path);
    }

    final first = controller(store, handler);
    await first.setEnabled(true);
    await first.login('alice', 'password');
    expect(first.hasSession, isTrue);
    first.dispose();

    final restarted = controller(store, handler);
    await restarted.setEnabled(true);
    expect(restarted.hasSession, isFalse);
    expect(restarted.user, isNull);
    expect(paths, isNot(contains('/api/app/me')));
    restarted.dispose();
  });
  test('account switch replaces checkin state after logout', () async {
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
    await c.logout();
    expect(c.hasSession, isFalse);
    expect(c.user, isNull);
    await c.login('bob', 'password');
    expect(c.user?.id, 'bob');
    expect(c.checkin?.totalDays, 0);
    c.dispose();
  });
  test('content rejects duplicate templates and unsupported expiry', () {
    final data = jsonDecode(snapshot()) as Map<String, dynamic>;
    (data['itemTemplates'] as List).add(data['itemTemplates'][0]);
    expect(() => PublicContent.decode(jsonEncode(data)), throwsFormatException);
    final bad = jsonDecode(snapshot()) as Map<String, dynamic>;
    bad['itemTemplates'][0]['expiry'] = {'type': 'fixedDate'};
    expect(() => PublicContent.decode(jsonEncode(bad)), throwsFormatException);
  });
}
