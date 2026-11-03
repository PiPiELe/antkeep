import 'dart:convert';
import 'dart:typed_data';

import 'package:antkeep/online/deepseek_key_page.dart';
import 'package:antkeep/online/deepseek_key_store.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'online_controller_test.dart'
    show MemoryOnlineStore, snapshot, summary, user;

class _Keys implements DeepSeekKeyStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String userId) async => values[userId];
  @override
  Future<void> write(String userId, String key) async => values[userId] = key;
  @override
  Future<void> delete(String userId) async {
    values.remove(userId);
  }
}

class _Api extends OnlineApi {
  _Api() : super(baseUrl: 'https://api.example.test');

  String? sentKey;

  @override
  Future<String> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
  }) async {
    switch (path) {
      case '/api/public/content':
        return snapshot();
      case '/api/app/auth/login':
        return jsonEncode({'token': 'session', 'user': user('alice')});
      case '/api/app/check-ins/summary':
        return jsonEncode(summary(0));
    }
    throw StateError(path);
  }

  @override
  Future<String> estimateColonyCount(
    Uint8List photo, {
    required String token,
    String? personalKey,
  }) async {
    sentKey = personalKey;
    return '{"workerCount":2,"uncertain":false}';
  }
}

void main() {
  testWidgets(
    'saves, uses, and deletes the personal key without displaying it',
    (tester) async {
      final keys = _Keys();
      final api = _Api();
      final controller = OnlineController(
        api: api,
        store: MemoryOnlineStore(),
        deepSeekKeys: keys,
      );
      await controller.setEnabled(true);
      await controller.login('alice', 'password');
      await tester.pumpWidget(
        MaterialApp(home: DeepSeekKeyPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前账号未配置个人密钥'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'personal-secret');
      await tester.tap(find.text('保存密钥'));
      await tester.pumpAndSettle();
      expect(find.text('确认使用个人密钥？'), findsOneWidget);
      expect(find.textContaining('可能产生由你承担的费用'), findsOneWidget);
      expect(keys.values, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(keys.values, isEmpty);

      await tester.tap(find.text('保存密钥'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已了解风险，保存密钥'));
      await tester.pumpAndSettle();
      expect(keys.values['alice'], 'personal-secret');
      expect(find.text('当前账号已配置个人密钥'), findsOneWidget);
      expect(find.text('personal-secret'), findsNothing);
      await controller.estimateColonyCount(Uint8List.fromList([0xff]));
      expect(api.sentKey, 'personal-secret');

      await tester.tap(find.text('删除本机密钥'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(keys.values, isEmpty);
      await controller.estimateColonyCount(Uint8List.fromList([0xff]));
      expect(api.sentKey, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
