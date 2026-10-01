import 'dart:convert';
import 'dart:io';

import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File pickedImage;
  String? pickerResult;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
  );
  final preview = find.byWidgetPredicate(
    (widget) => widget is Image && widget.semanticLabel == '封面照片预览',
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('antkeep-cover-test-');
    pickedImage = await File('${directory.path}/picked.png')
        .writeAsBytes(bytes);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    await LocalMediaStore.instance.initialize();
    await LocalMediaStore.instance.restoreFiles({'existing.png': bytes});
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => pickerResult,
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

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // File I/O runs outside the widget test's fake clock.
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (preview.evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('selected cover previews before save and survives cancellation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ColonyFormPage()));
    expect(preview, findsNothing);
    pickerResult = pickedImage.path;
    await pick(tester, '添加封面照片（可选）');
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    expect(find.text('封面无法预览，请重新选择照片'), findsNothing);
    expect((tester.widget<Image>(preview).image as MemoryImage).bytes, bytes);

    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('封面预览'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    pickerResult = null;
    await pick(tester, '已选择封面照片');
    expect(preview, findsOneWidget);
    expect((tester.widget<Image>(preview).image as MemoryImage).bytes, bytes);
    expect(tester.takeException(), isNull);
  });

  for (final existing in [true, false]) {
    testWidgets('existing cover loads or reports missing file ($existing)', (
      tester,
    ) async {
      final now = DateTime.now();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: ColonyFormPage(
              colony: Colony(
                id: 'cover-colony',
                name: '封面测试',
                coverPhotoPath: existing ? 'existing.png' : 'missing.png',
                createdAt: now,
                updatedAt: now,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
      await tester.scrollUntilVisible(
        find.text('更换封面照片'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      if (existing) {
        expect(preview, findsOneWidget);
        expect(find.text('封面无法预览，请重新选择照片'), findsNothing);
        expect(
          (tester.widget<Image>(preview).image as MemoryImage).bytes,
          bytes,
        );
      } else {
        expect(find.text('封面无法预览，请重新选择照片'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
