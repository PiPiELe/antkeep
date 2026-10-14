import 'dart:convert';

import 'package:antkeep/online/feedback_page.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'online_controller_test.dart'
    show MemoryOnlineStore, snapshot, summary, user;

class FeedbackApi extends OnlineApi {
  FeedbackApi() : super(baseUrl: 'https://api.example.test');
  final submissions = <Map<String, dynamic>>[];
  String? submittedToken;

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
        return jsonEncode({'token': 'feedback-token', 'user': user('keeper')});
      case '/api/app/check-ins/summary':
        return jsonEncode(summary(0));
      case '/api/app/feedback':
        submittedToken = token;
        submissions.add(body!);
        return jsonEncode({
          'id': body['operationId'],
          'category': body['category'],
          'content': body['content'],
          'createdAt': '2026-10-14T00:00:00Z',
        });
      default:
        return '{}';
    }
  }
}

void main() {
  testWidgets('feedback requires online login and submits only typed text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FeedbackApi();
    final controller = OnlineController(api: api, store: MemoryOnlineStore());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: FeedbackPage(controller: controller)),
    );
    expect(find.textContaining('仅在线版可用'), findsOneWidget);
    expect(find.text('提交反馈'), findsNothing);

    await controller.setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.text('登录 / 注册'), findsOneWidget);
    await controller.login('keeper', 'password123');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提交反馈'));
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();
    expect(api.submissions, isEmpty);
    expect(find.text('请填写 1–2000 字的反馈内容。'), findsOneWidget);

    await tester.ensureVisible(find.text('更好的想法'));
    await tester.tap(find.text('更好的想法'));
    await tester.enterText(find.byType(TextField), '  希望增加筛选  ');
    await tester.ensureVisible(find.text('提交反馈'));
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();
    expect(api.submittedToken, 'feedback-token');
    expect(api.submissions, hasLength(1));
    expect(
      api.submissions.single.keys,
      containsAll(['category', 'content', 'operationId']),
    );
    expect(api.submissions.single.keys, hasLength(3));
    expect(api.submissions.single['category'], 'IDEA');
    expect(api.submissions.single['content'], '希望增加筛选');
    expect(find.text('已提交，感谢你的反馈。'), findsOneWidget);
    expect(find.text('希望增加筛选'), findsNothing);
  });
}
