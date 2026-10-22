import 'dart:io';
import 'dart:ui' as ui;

import 'package:antkeep/auto_backup_page.dart';
import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/colony_label_page.dart';
import 'package:antkeep/data/auto_backup_controller.dart';
import 'package:antkeep/data/share_image_export.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'auto_backup_controller_test.dart'
    show MemoryBackupSettings, FakeBackupStorage;

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('/private/tmp/antkeep-qr-auto-backup-ui');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('first consent can decline, retry a failed save and enable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = MemoryBackupSettings();
    final storage = FakeBackupStorage();
    final controller = AutoBackupController(settings, storage);
    await controller.load();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: antKeepTheme(ThemeColor.forest),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAutoBackupConsent(context, controller),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await capture(tester, key, 'consent-320');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('暂不开启'));
    await tester.pumpAndSettle();
    expect(controller.enabled, isFalse);
    expect(controller.needsConsent, isFalse);
    expect(storage.creates, 0);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    settings.fail = true;
    await tester.tap(find.text('开启自动备份'));
    await tester.pumpAndSettle();
    expect(find.text('选择未保存，请重试。'), findsOneWidget);
    expect(controller.enabled, isFalse);
    settings.fail = false;
    await tester.tap(find.text('开启自动备份'));
    await tester.pumpAndSettle();
    expect(controller.enabled, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'backup management enables, creates and keeps existing backups when disabled',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AutoBackupController(
        MemoryBackupSettings(),
        FakeBackupStorage(),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: antKeepTheme(ThemeColor.forest),
            home: AutoBackupPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(controller.enabled, isTrue);
      expect(find.text('导出到应用外'), findsOneWidget);
      await capture(tester, key, 'backups-320');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);
      expect(find.text('导出到应用外'), findsOneWidget);
    },
  );

  testWidgets(
    'label has a readable QR and saves a high resolution PNG at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      Uint8List? exported;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ShareImageExport.channel,
        (call) async {
          exported = call.arguments['bytes'] as Uint8List;
          return '图片已保存';
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ShareImageExport.channel,
          null,
        ),
      );
      final at = DateTime(2026, 10, 21);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: antKeepTheme(ThemeColor.forest),
            home: ColonyLabelPage(
              colony: Colony(
                id: '550e8400-e29b-41d4-a716-446655440000',
                name: '黑金弓背蚁 · 一号试管',
                species: 'Camponotus fedtschenkoi',
                createdAt: at,
                updatedAt: at,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      await capture(tester, key, 'label-320');
      await tester.ensureVisible(find.text('保存标签图片'));
      await tester.tap(find.text('保存标签图片'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(exported, isNotNull);
      expect(exported!.take(4), [137, 80, 78, 71]);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.runAsync(
          () =>
              File('/private/tmp/antkeep-qr-auto-backup-ui/printed-label.png')
                  .writeAsBytes(exported!),
        );
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
