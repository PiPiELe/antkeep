import 'dart:async';
import 'dart:convert';

import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/usage/usage_controller.dart';
import 'package:antkeep/usage/usage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryUsageStore implements UsageStore {
  bool? consent;
  String? id, date;
  Completer<void>? holdId;
  bool failWrite = false;
  @override
  Future<bool?> readConsent() async => consent;
  @override
  Future<void> writeConsent(bool value) async {
    if (failWrite) throw StateError('storage failure');
    consent = value;
  }

  @override
  Future<String?> readId() async {
    await holdId?.future;
    return id;
  }

  @override
  Future<void> writeId(String value) async {
    id = value;
  }

  @override
  Future<String?> readReportedDate() async => date;
  @override
  Future<void> writeReportedDate(String value) async {
    date = value;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MemoryUsageStore store;
  late UsageController controller;
  late DateTime now;
  late List<http.Request> requests;
  var failNetwork = false;
  setUp(() {
    store = MemoryUsageStore();
    requests = [];
    failNetwork = false;
    now = DateTime.parse('2026-10-31T15:59:59Z');
    controller = UsageController(
      store: store,
      now: () => now,
      api: OnlineApi(
        baseUrl: 'https://usage.example.test',
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (failNetwork) throw http.ClientException('offline');
          return http.Response(
            jsonEncode({'date': UsageController.beijingDate(now)}),
            200,
          );
        }),
      ),
    );
  });
  tearDown(() => controller.dispose());

  test('no consent means no network and no installation identifier', () async {
    await controller.load();
    controller.setForeground(true);
    await flush();
    expect(controller.needsConsent, isTrue);
    expect(requests, isEmpty);
    expect(store.id, isNull);
    await controller.setConsent(false);
    await flush();
    expect(requests, isEmpty);
    expect(store.id, isNull);
  });

  test('anonymous report without account or edition uses same ID and once per Beijing day', () async {
    await controller.load();
    controller.setForeground(true);
    await controller.setConsent(true);
    await flush();
    expect(requests, hasLength(1));
    final first = requests.single;
    expect(first.url.path, '/api/public/usage');
    expect(first.method, 'POST');
    expect(first.headers.containsKey('Authorization'), isFalse);
    expect(first.headers.containsKey('Cookie'), isFalse);
    final body = jsonDecode(first.body) as Map<String, dynamic>;
    expect(body.keys, ['installationId']);
    expect(
      body['installationId'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    controller.setForeground(false);
    controller.setForeground(true);
    await controller.report();
    await flush();
    expect(requests, hasLength(1));
    now = DateTime.parse('2026-10-31T16:00:00Z');
    await controller.report();
    expect(requests, hasLength(2));
    expect(requests.last.body, first.body);
    expect(store.date, '2026-11-01');
  });

  test('saved successful date prevents resending after restart', () async {
    store.consent = true;
    store.date = '2026-10-31';
    await controller.load();
    controller.setForeground(true);
    await flush();
    expect(requests, isEmpty);
  });

  test(
    'network failure is silent and retried only in foreground after backoff',
    () async {
      store.consent = true;
      failNetwork = true;
      await controller.load();
      controller.setForeground(true);
      await flush();
      expect(requests, hasLength(1));
      expect(store.date, isNull);
      await controller.report();
      expect(requests, hasLength(1));
      controller.setForeground(false);
      now = now.add(const Duration(minutes: 6));
      failNetwork = false;
      await controller.report();
      expect(requests, hasLength(1));
      controller.setForeground(true);
      await flush();
      expect(requests, hasLength(2));
      expect(store.date, '2026-11-01');
    },
  );

  test('revocation while loading ID prevents request, and later days remain disabled', () async {
    store.consent = true;
    store.holdId = Completer<void>();
    await controller.load();
    controller.setForeground(true);
    await flush();
    await controller.setConsent(false);
    store.holdId!.complete();
    await flush();
    expect(requests, isEmpty);
    now = now.add(const Duration(days: 2));
    await controller.report();
    expect(requests, isEmpty);
    expect(controller.api.enabled, isFalse);
  });

  test('failed consent persistence never enables upload', () async {
    await controller.load();
    controller.setForeground(true);
    store.failWrite = true;
    await expectLater(controller.setConsent(true), throwsStateError);
    await flush();
    expect(requests, isEmpty);
    expect(controller.enabled, isFalse);
  });

  testWidgets(
    'settings require explicit consent and support immediate opt-out',
    (tester) async {
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: UsageSettings(controller: controller)),
        ),
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('参与匿名使用统计？'), findsOneWidget);
      expect(controller.enabled, isFalse);
      await tester.tap(find.text('不参与'));
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意参与'));
      await tester.pumpAndSettle();
      expect(controller.enabled, isTrue);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);
      expect(requests, isEmpty);
    },
  );
}
