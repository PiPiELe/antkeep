import 'dart:convert';
import 'dart:io';

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/online/competition_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'online_controller_test.dart'
    show MemoryOnlineStore, controller, response, snapshot, summary, user;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'antkeep-competition-ui-',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => '${directory.path}/photo.png',
    );
    await File('${directory.path}/photo.png').writeAsBytes(photo);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AppDatabase.instance.open();
    final now = DateTime(2026, 10, 10);
    for (final id in ['colony-1', 'colony-2']) {
      await AppDatabase.instance.saveColony(
        Colony(
          id: id,
          name: id,
          createdAt: now,
          updatedAt: now,
          initialWorkerCount: 0,
        ),
      );
    }
  });

  tearDownAll(() async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      null,
    );
    await directory.delete(recursive: true);
  });

  Map<String, dynamic> contest(String id) => {
    'id': id,
    'title': id,
    'state': 'ACTIVE',
    'scoreMode': 'POINTS',
    'startDate': '2026-10-01',
    'endDate': null,
    'enabled': false,
    'reviewStatus': 'APPROVED',
    'broodPointsEnabled': false,
    'today': '2026-10-10',
    'myEntry': null,
    'entries': <Object>[],
  };

  Future<void> until(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump();
        if (finder.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('Timed out waiting for $finder');
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'switching accounts clears private detail even when reload fails',
    (tester) async {
      final online = controller(MemoryOnlineStore(), (request) async {
        switch (request.url.path) {
          case '/api/public/content':
            return response(snapshot(), 200);
          case '/api/app/auth/login':
            final name = jsonDecode(request.body)['username'] as String;
            return response(
              jsonEncode({'token': name, 'user': user(name)}),
              200,
            );
          case '/api/app/auth/logout':
            return response('{}', 200);
          case '/api/app/check-ins/summary':
            return response(jsonEncode(summary(0)), 200);
          case '/api/app/competitions':
            return response(jsonEncode([contest('private-contest')]), 200);
          case '/api/app/competitions/private-contest':
            return request.headers['Authorization'] == 'Bearer alice'
                ? response(jsonEncode(contest('private-contest')), 200)
                : response(jsonEncode({'message': '无权查看'}), 403);
        }
        return response('{}', 404);
      });
      await tester.runAsync(() async {
        await online.setEnabled(true);
        await online.login('alice', 'password');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CompetitionPage(
            controller: online,
            initialId: 'private-contest',
          ),
        ),
      );
      await until(tester, find.text('private-contest'));
      expect(find.text('全部比赛'), findsOneWidget);

      await tester.runAsync(online.logout);
      await tester.pump();
      expect(find.text('private-contest'), findsNothing);
      await tester.runAsync(() => online.login('bob', 'password'));
      await until(tester, find.text('无权查看'));
      expect(find.text('全部比赛'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      online.dispose();
    },
  );

  testWidgets('selected photo stays with its contest and colony', (
    tester,
  ) async {
    final online = controller(MemoryOnlineStore(), (request) async {
      switch (request.url.path) {
        case '/api/public/content':
          return response(snapshot(), 200);
        case '/api/app/auth/login':
          return response(
            jsonEncode({'token': 'alice', 'user': user('alice')}),
            200,
          );
        case '/api/app/check-ins/summary':
          return response(jsonEncode(summary(0)), 200);
        case '/api/app/competitions':
          return response(
            jsonEncode([contest('contest-1'), contest('contest-2')]),
            200,
          );
        case '/api/app/competitions/contest-1':
          return response(jsonEncode(contest('contest-1')), 200);
        case '/api/app/competitions/contest-2':
          return response(jsonEncode(contest('contest-2')), 200);
      }
      return response('{}', 404);
    });
    await tester.runAsync(() async {
      await online.setEnabled(true);
      await online.login('alice', 'password');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitionPage(controller: online, initialId: 'contest-1'),
      ),
    );
    await until(tester, find.text('选择报名图片（必选）'));

    await tester.runAsync(() async {
      await tester.tap(find.text('选择报名图片（必选）'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump();
        if (find.text('已选图片 · 重新选择').evaluate().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('已选图片 · 重新选择'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('colony-2').last);
    await tester.pumpAndSettle();
    expect(find.text('选择报名图片（必选）'), findsOneWidget);

    await tester.tap(find.text('选择报名图片（必选）'));
    await until(tester, find.text('已选图片 · 重新选择'));
    await tester.tap(find.text('全部比赛'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('contest-2'));
    await until(tester, find.text('选择报名图片（必选）'));
    expect(find.text('已选图片 · 重新选择'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    online.dispose();
  });
}
