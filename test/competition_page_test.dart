import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:antkeep/data/app_database.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/online/competition_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'online_controller_test.dart'
    show MemoryOnlineStore, controller, response, snapshot, summary, user;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MethodCall? pickerCall;
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
      (call) async {
        pickerCall = call;
        return '${directory.path}/photo.png';
      },
    );
    await File('${directory.path}/photo.png').writeAsBytes(photo);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final fontFile = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (await fontFile.exists()) {
      final font = FontLoader('PreviewChinese');
      font.addFont(fontFile.readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
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
    await AppDatabase.instance.saveColony(
      Colony(
        id: 'colony-with-workers',
        name: '已有工蚁的蚁群',
        createdAt: now,
        updatedAt: now,
        initialWorkerCount: 5,
        initialEggCount: 0,
        initialLarvaCount: 2,
        initialCocoonCount: 1,
      ),
    );
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
      await tester.pumpAndSettle();
      expect(find.text('拍照'), findsOneWidget);
      await tester.tap(find.text('拍照'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump();
        if (find.text('已选图片 · 重新选择').evaluate().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('已选图片 · 重新选择'), findsOneWidget);
    expect((pickerCall?.arguments as Map)['source'], ImageSource.camera.index);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('colony-2').last);
    await tester.pumpAndSettle();
    expect(find.text('选择报名图片（必选）'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('选择报名图片（必选）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从图库选择'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump();
        if (find.text('已选图片 · 重新选择').evaluate().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('已选图片 · 重新选择'), findsOneWidget);
    expect((pickerCall?.arguments as Map)['source'], ImageSource.gallery.index);
    await tester.tap(find.text('全部比赛'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('contest-2'));
    await until(tester, find.text('选择报名图片（必选）'));
    expect(find.text('已选图片 · 重新选择'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    online.dispose();
  });

  testWidgets('worker colony can enter with separate origin counts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Map<String, dynamic>? submitted;
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
          return response(jsonEncode([contest('contest-1')]), 200);
        case '/api/app/competitions/contest-1':
          return response(
            jsonEncode({
              ...contest('contest-1'),
              'title': '巴巴养殖赛',
              'startDate': '2026-10-10',
              'endDate': '2026-10-17',
            }),
            200,
          );
        case '/api/app/competitions/disclaimer':
          return response(
            jsonEncode({
              'id': 'disclaimer-1',
              'title': '比赛声明',
              'version': 1,
              'content': '请如实填写参赛数量。',
            }),
            200,
          );
        case '/api/app/competitions/contest-1/entries':
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return response(
            jsonEncode({'entryId': 'entry-1', 'date': '2026-10-10'}),
            201,
          );
      }
      return response('{}', 404);
    });
    await tester.runAsync(() async {
      await online.setEnabled(true);
      await online.login('alice', 'password');
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('competition-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'PreviewChinese'),
          home: CompetitionPage(controller: online, initialId: 'contest-1'),
        ),
      ),
    );
    await until(tester, find.text('选择报名图片（必选）'));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已有工蚁的蚁群').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('选择报名图片（必选）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从图库选择'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump();
        if (find.text('已选图片 · 重新选择').evaluate().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('已选图片 · 重新选择'), findsOneWidget);
    await tester.ensureVisible(find.text('报名并上传'));
    await tester.tap(find.text('报名并上传'));
    await until(tester, find.text('标注参赛数量来源'));
    final inputs = find.byType(TextFormField);
    for (final (index, value) in ['2', '3', '1', '2'].indexed) {
      await tester.enterText(inputs.at(index), value);
    }
    await tester.pumpAndSettle();
    final previewPath = Platform.environment['ANTKEEP_PREVIEW_PATH'];
    if (previewPath != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('competition-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(previewPath).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await tester.tap(find.text('确认数量'));
    await tester.pumpAndSettle();
    await until(tester, find.text('比赛声明 · v1'));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并报名'));
    await until(tester, find.text('报名成功，今日数据已上传。'));
    expect(submitted?['workerCount'], 5);
    expect(submitted?['adoptedWorkerCount'], 2);
    expect(submitted?['ownWorkerCount'], 3);
    expect(submitted?['adoptedBroodCount'], 1);
    expect(submitted?['ownBroodCount'], 2);
    await tester.pumpWidget(const SizedBox());
    online.dispose();
  });
}
