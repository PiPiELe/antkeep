import 'dart:convert';

import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:antkeep/online/online_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'online_controller_test.dart'
    show MemoryOnlineStore, snapshot, summary, user;

class _RegistrationApi extends OnlineApi {
  _RegistrationApi(this.inviteCodeRequired)
    : super(baseUrl: 'https://api.example.test');

  final bool inviteCodeRequired;
  Map<String, dynamic>? registration;

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
      case '/api/public/registration-policy':
        return jsonEncode({'inviteCodeRequired': inviteCodeRequired});
      case '/api/app/auth/register':
        registration = body;
        return jsonEncode(user('alice'));
      case '/api/app/auth/login':
        return jsonEncode({'token': 'session', 'user': user('alice')});
      case '/api/app/check-ins/summary':
        return jsonEncode(summary(0));
    }
    throw StateError(path);
  }
}

void main() {
  testWidgets(
    'required invite code blocks empty registration and sends the code',
    (tester) async {
      final api = _RegistrationApi(true);
      final controller = OnlineController(api: api, store: MemoryOnlineStore());
      await controller.setEnabled(true);
      await tester.pumpWidget(
        MaterialApp(home: LoginPage(controller: controller)),
      );

      await tester.tap(find.text('没有账号，去注册'));
      await tester.pumpAndSettle();
      expect(find.text('邀请码（必填）'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '用户名'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '密码'),
        'password123',
      );
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      expect(find.text('请输入邀请码'), findsOneWidget);
      expect(api.registration, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, '邀请码（必填）'),
        '  Invite_123  ',
      );
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      expect(api.registration, {
        'username': 'alice',
        'password': 'password123',
        'inviteCode': 'Invite_123',
      });
      controller.dispose();
    },
  );

  testWidgets('optional invite code permits registration without a code', (
    tester,
  ) async {
    final api = _RegistrationApi(false);
    final controller = OnlineController(api: api, store: MemoryOnlineStore());
    await controller.setEnabled(true);
    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );

    await tester.tap(find.text('没有账号，去注册'));
    await tester.pumpAndSettle();
    expect(find.text('邀请码（选填）'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'alice');
    await tester.enterText(
      find.widgetWithText(TextFormField, '密码'),
      'password123',
    );
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();
    expect(api.registration, {'username': 'alice', 'password': 'password123'});
    controller.dispose();
  });
}
