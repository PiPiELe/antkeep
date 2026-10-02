import 'dart:async';
import 'dart:convert';

import 'package:antkeep/domain/models.dart';
import 'package:antkeep/online/inventory_push_page.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'online_controller_test.dart'
    show MemoryOnlineStore, controller, response, snapshot, summary, user;

final items = [
  InventoryItem(
    id: 'liquid',
    name: '营养液',
    purchased: true,
    createdAt: DateTime(2026, 10, 1),
    quantity: 0,
    purchasePriceCents: 1234,
  ),
  InventoryItem(
    id: 'tube',
    name: '试管',
    purchased: false,
    createdAt: DateTime(2026, 10, 1),
  ),
];

// Widget tests use an immediate transport; controller tests below still exercise
// OnlineApi and HTTP encoding. This avoids real stream timers in fake widget time.
class WidgetApi extends OnlineApi {
  WidgetApi(this.respond) : super(baseUrl: 'https://api.example.test');
  final Future<http.Response> Function(http.Request) respond;
  @override
  Future<String> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final request = http.Request(method, Uri.parse(baseUrl).resolve(path));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final result = await respond(request);
    if (result.statusCode >= 400) {
      throw ApiFailure(
        (jsonDecode(result.body) as Map<String, dynamic>)['message'] as String,
        status: result.statusCode,
      );
    }
    return result.body;
  }
}

class Harness {
  Harness({this.widgetMode = false});
  final bool widgetMode;
  final requests = <http.Request>[];
  bool pushed = false;
  bool invalidSession = false;
  bool failPost = false;
  bool loseResponse = false;
  String date = '2026-10-02';
  Completer<void>? pending;
  late final OnlineController live = widgetMode
      ? OnlineController(api: WidgetApi(respond), store: MemoryOnlineStore())
      : controller(MemoryOnlineStore(), respond);
  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    switch (request.url.path) {
      case '/api/public/content':
        return response(snapshot(), 200);
      case '/api/app/auth/login':
        return response(
          jsonEncode({'token': 'secret-session', 'user': user('keeper')}),
          200,
        );
      case '/api/app/check-ins/summary':
        return response(jsonEncode(summary(0)), 200);
      case '/api/app/inventory-pushes/status':
        if (invalidSession) {
          return response(jsonEncode({'message': '登录已失效'}), 401);
        }
        return response(
          jsonEncode({
            'date': date,
            'pushedToday': pushed,
            'pushId': pushed ? 'push-1' : null,
            'itemCount': pushed ? 1 : 0,
          }),
          200,
        );
      case '/api/app/inventory-pushes':
        await pending?.future;
        if (failPost) return response(jsonEncode({'message': '服务暂不可用'}), 500);
        if (pushed) return response(jsonEncode({'message': '今日已推送'}), 409);
        pushed = true;
        if (loseResponse) throw const ApiFailure('响应丢失');
        return response(
          jsonEncode({
            'id': 'push-1',
            'date': date,
            'itemCount': 1,
            'createdAt': '2026-10-02T01:00:00Z',
          }),
          201,
        );
      default:
        return response('{}', 200);
    }
  }

  Future<void> login() async {
    await live.setEnabled(true);
    await live.login('keeper', 'password123');
  }

  List<http.Request> get uploads =>
      requests.where((r) => r.url.path == '/api/app/inventory-pushes').toList();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  test('only selected inventory is sent with authenticated identity', () async {
    final h = Harness();
    addTearDown(h.live.dispose);
    await h.login();
    await h.live.pushInventory([items.first]);
    final upload = h.uploads.single;
    expect(upload.headers['Authorization'], 'Bearer secret-session');
    expect(jsonDecode(upload.body), {
      'items': [items.first.toMap()],
    });
    expect((await h.live.inventoryPushStatus())['pushedToday'], true);
  });

  test(
    'offline, anonymous, empty selection and duplicate clicks do not upload',
    () async {
      final h = Harness();
      addTearDown(h.live.dispose);
      await expectLater(
        h.live.pushInventory(items),
        throwsA(isA<ApiFailure>()),
      );
      await h.live.setEnabled(true);
      await expectLater(
        h.live.pushInventory(items),
        throwsA(isA<ApiFailure>()),
      );
      await h.live.login('keeper', 'password123');
      expect(() => h.live.pushInventory([]), throwsA(isA<ApiFailure>()));
      h.pending = Completer<void>();
      final first = h.live.pushInventory([items.first]);
      await expectLater(
        h.live.pushInventory([items.last]),
        throwsA(isA<ApiFailure>()),
      );
      h.pending!.complete();
      await first;
      expect(h.uploads.length, 1);
    },
  );

  test(
    'server rejects another device same-day push and expired login is cleared',
    () async {
      final h = Harness();
      addTearDown(h.live.dispose);
      await h.login();
      h.pushed = true;
      await expectLater(
        h.live.pushInventory(items),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
      );
      h.invalidSession = true;
      await expectLater(
        h.live.inventoryPushStatus(),
        throwsA(isA<ApiFailure>()),
      );
      expect(h.live.user, isNull);
      expect(h.live.hasSession, false);
    },
  );

  test('late upload response after offline switch is discarded', () async {
    final h = Harness();
    addTearDown(h.live.dispose);
    await h.login();
    h.pending = Completer<void>();
    final upload = h.live.pushInventory([items.first]);
    final rejected = expectLater(upload, throwsA(isA<ApiFailure>()));
    await h.live.setEnabled(false);
    h.pending!.complete();
    await rejected;
    expect(h.live.user, isNull);
    expect(h.live.busy, false);
  });

  Future<void> open(WidgetTester tester, Harness h) async {
    await tester.runAsync(h.login);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryPushPage(
          controller: h.live,
          loadItems: () async => items,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> chooseAndConfirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('liquid')));
    await tester.pump();
    await tester.tap(find.text('推送所选 1 条'));
    await settle(tester);
    expect(find.textContaining('所选的 1 条物品数据'), findsOneWidget);
    await tester.tap(find.text('确认推送'));
    await settle(tester);
  }

  testWidgets(
    'selection requires confirmation and refresh reopens next-day quota',
    (tester) async {
      final h = Harness(widgetMode: true);
      addTearDown(h.live.dispose);
      await open(tester, h);
      expect(h.uploads, isEmpty);
      await tester.tap(find.byKey(const ValueKey('liquid')));
      await tester.pump();
      await tester.tap(find.text('推送所选 1 条'));
      await settle(tester);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(h.uploads, isEmpty);
      await tester.tap(find.text('推送所选 1 条'));
      await settle(tester);
      await tester.tap(find.text('确认推送'));
      await settle(tester);
      expect(h.uploads.length, 1);
      expect(find.text('推送成功，B 端已收到 1 条物品数据。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '今日已推送'))
            .onPressed,
        isNull,
      );
      h.date = '2026-10-03';
      h.pushed = false;
      await tester.tap(find.byTooltip('刷新推送状态'));
      await settle(tester);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '推送所选 1 条'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('failed upload leaves quota and selection available for retry', (
    tester,
  ) async {
    final h = Harness(widgetMode: true)..failPost = true;
    addTearDown(h.live.dispose);
    await open(tester, h);
    await chooseAndConfirm(tester);
    expect(h.pushed, false);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '推送所选 1 条'))
          .onPressed,
      isNotNull,
    );
    h.failPost = false;
    await tester.tap(find.text('推送所选 1 条'));
    await settle(tester);
    await tester.tap(find.text('确认推送'));
    await settle(tester);
    expect(h.pushed, true);
  });

  testWidgets(
    'lost response reads server receipt instead of silently resending',
    (tester) async {
      final h = Harness(widgetMode: true)..loseResponse = true;
      addTearDown(h.live.dispose);
      await open(tester, h);
      await chooseAndConfirm(tester);
      expect(h.uploads.length, 1);
      expect(find.text('B 端确认今日已收到 1 条物品数据，今天不能再次推送。'), findsOneWidget);
    },
  );

  testWidgets('empty inventory cannot be submitted', (tester) async {
    final h = Harness(widgetMode: true);
    addTearDown(h.live.dispose);
    await tester.runAsync(h.login);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryPushPage(controller: h.live, loadItems: () async => []),
      ),
    );
    await settle(tester);
    expect(find.text('物品栏暂无数据'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '推送所选 0 条'))
          .onPressed,
      isNull,
    );
    expect(h.uploads, isEmpty);
  });
}
