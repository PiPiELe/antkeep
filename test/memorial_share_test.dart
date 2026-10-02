import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:antkeep/domain/memorial.dart';
import 'package:antkeep/memorial_share_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Memorial item(MemorialKind kind, {String? farewell}) => Memorial(
    id: kind.name,
    kind: kind,
    name: '玄甲王朝',
    species: '收获蚁 · 示例数据',
    diedOn: DateTime(2026, 10, 2),
    createdAt: DateTime(2026, 10, 2),
    farewell: farewell ?? '它们曾搬起山河，也曾点亮我的四季。\n如今王国寂静，微光仍在心间。',
    cause: '不应出现在分享图中的原因',
    lesson: '不应出现在分享图中的经验',
  );

  setUpAll(() async {
    final font = Platform.environment['ANTKEEP_TEST_FONT'];
    if (font != null) {
      final loader = FontLoader('serif')
        ..addFont(
          File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    // Load the shared native image outside individual tests' FakeAsync zones.
    for (final kind in MemorialKind.values) {
      await loadMemorialArtwork(kind);
    }
  });

  for (final kind in MemorialKind.values) {
    testWidgets(
      '${kind.name} exports a complete high-resolution PNG matching preview',
      (tester) async {
        final memorial = item(kind);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MemorialPoster(memorial: memorial)),
          ),
        );
        expect(tester.takeException(), isNull);
        final bytes = (await tester.runAsync(
          () => renderMemorialPng(memorial),
        ))!;
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await tester.runAsync(
          () => ui.instantiateImageCodec(bytes),
        );
        final frame = await tester.runAsync(() => codec!.getNextFrame());
        expect(frame!.image.width, 1200);
        expect(frame.image.height, 2700);
        frame.image.dispose();
        codec!.dispose();
        final output = Platform.environment['ANTKEEP_MEMORIAL_PREVIEW_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            await File('$output/${kind.name}.png').writeAsBytes(bytes);
          });
        }
      },
    );
  }

  testWidgets(
    'small screen, long name, unknown date and long farewell can render and save',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final memorial = Memorial.fromMap({
        ...item(MemorialKind.queen, farewell: '念' * 300).toMap(),
        'name': '纪' * 80,
        'died_on': null,
      });
      Uint8List? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: MemorialSharePage(
            memorial: memorial,
            saveImage: (bytes, name) async {
              saved = bytes;
              expect(name, endsWith('.png'));
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.text('保存图片'));
      await settle(tester);
      expect(saved, isNotNull);
      expect(find.text('分享图已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled save stays quiet; failure is retryable; repeated taps share once',
    (tester) async {
      var calls = 0;
      final share = Completer<void>();
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: MemorialSharePage(
            memorial: item(MemorialKind.colony),
            saveImage: (_, _) async {
              if (fail) throw StateError('disk full');
              return false;
            },
            shareImage: (bytes, name, origin) {
              calls++;
              expect(bytes.length, greaterThan(1000));
              expect(origin.width, greaterThan(0));
              return share.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('保存图片'));
      await settle(tester);
      expect(find.text('图片保存失败，请重试'), findsOneWidget);
      fail = false;
      ScaffoldMessenger.of(tester.element(find.byType(MemorialSharePage)))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存图片'));
      await settle(tester);
      expect(find.text('分享图已保存'), findsNothing);
      await tester.tap(find.text('分享图片'));
      await tester.tap(find.text('分享图片'));
      await settle(tester);
      expect(calls, 1);
      share.complete();
      await settle(tester);
      expect(find.text('分享图片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
}
