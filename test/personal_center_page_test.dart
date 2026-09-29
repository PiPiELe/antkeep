import 'package:antkeep/account_controller.dart';
import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/personal_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'account_controller_test.dart' show Settings, jsonResponse, profile;

void main() {
  testWidgets(
    'register, server sign-in, edit nickname and logout without avatar',
    (tester) async {
      final paths = <String>[];
      final controller = AccountController(
        preferences: AppPreferences(Settings())..edition = AppEdition.online,
        baseUrl: 'https://accounts.test',
        client: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/register')) {
            return jsonResponse({'token': 'test-token', ...profile()});
          }
          if (request.url.path.endsWith('/logout')) {
            return jsonResponse({'ok': true});
          }
          return jsonResponse(
            profile(checkedIn: request.url.path.endsWith('/check-in')),
          );
        }),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: PersonalCenterPage(controller: controller)),
      );
      await tester.tap(find.text('还没有账号？注册'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'keeper');
      await tester.enterText(find.byType(TextFormField).at(1), '养蚁人');
      await tester.enterText(find.byType(TextFormField).at(2), 'test-password');
      await tester.ensureVisible(find.text('注册并登录'));
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsNothing);
      await tester.ensureVisible(find.text('立即签到'));
      await tester.tap(find.text('立即签到'));
      await tester.pumpAndSettle();
      expect(find.text('今日已签到'), findsOneWidget);
      expect(find.text('累计 1 天'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('修改昵称'));
      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '新昵称');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(paths, contains('PATCH /api/account/me'));
      await tester.ensureVisible(find.text('退出登录'));
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      expect(controller.signedIn, isFalse);
      expect(paths, contains('POST /api/account/check-in'));
      expect(paths, contains('POST /api/account/logout'));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    testWidgets('large text and small screen profile, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = AccountController(
        preferences: AppPreferences(Settings())..edition = AppEdition.online,
        baseUrl: 'https://accounts.test',
        client: MockClient(
          (_) async => jsonResponse({
            'token': 'test-token',
            ...profile(checkedIn: true),
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.authenticate(
        username: 'keeper',
        password: 'test-password',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: antKeepTheme(ThemeColor.forest, dark: dark),
          home: PersonalCenterPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('退出登录'), 200);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
