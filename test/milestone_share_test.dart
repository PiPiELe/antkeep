import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:antkeep/domain/milestone.dart';
import 'package:antkeep/domain/models.dart';
import 'package:antkeep/data/local_media_store.dart';
import 'package:antkeep/milestone_share_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 10, 12);
  final colony = Colony(
    id: 'c',
    name: '玄甲蚁国',
    createdAt: date,
    updatedAt: date,
  );
  final milestone = Milestone(
    id: 'm',
    colonyId: 'c',
    title: '首批工蚁破茧新生',
    note: '温暖的巢室里，新生命终于出现。',
    occurredAt: date,
    createdAt: date,
  );
  late Directory mediaDirectory;

  setUpAll(() async {
    mediaDirectory = await Directory.systemTemp.createTemp('milestone-photo-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => mediaDirectory.path,
        );
    await LocalMediaStore.instance.initialize();
    final font = Platform.environment['ANTKEEP_TEST_FONT'];
    final loader = FontLoader('StoneSerif')
      ..addFont(
        font == null
            ? rootBundle.load('assets/fonts/NotoSerifSC.ttf')
            : File(font).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
    for (final artwork in MilestoneArtwork.values) {
      await loadMilestoneArtwork(artwork);
    }
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await mediaDirectory.delete(recursive: true);
  });

  testWidgets('own photo appears below artwork in exported PNG', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalMediaStore.instance.restoreFiles({
        'own.png': base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAIAAAACUFjqAAAAEklEQVR4nGP4z8CAB+GTG8HSALfKY52fTcuYAAAAAElFTkSuQmCC',
        ),
      }),
    );
    final withPhoto = Milestone(
      id: milestone.id,
      colonyId: milestone.colonyId,
      title: milestone.title,
      note: milestone.note,
      occurredAt: milestone.occurredAt,
      createdAt: milestone.createdAt,
      photoPath: 'own.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MilestonePoster(
              colony: colony,
              milestone: withPhoto,
              artwork: withPhoto.artwork,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.byType(Image), findsOneWidget);
    final bytes = await tester.runAsync(
      () => renderMilestonePng(colony, withPhoto, withPhoto.artwork),
    );
    final codec = await tester.runAsync(() => ui.instantiateImageCodec(bytes!));
    final frame = await tester.runAsync(() => codec!.getNextFrame());
    expect(frame!.image.width, 1200);
    expect(frame.image.height, 2400);
    final pixels = await tester.runAsync(
      () => frame.image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final offset = (2000 * 1200 + 600) * 4;
    expect(pixels!.getUint8(offset), 255);
    expect(pixels.getUint8(offset + 1), 0);
    expect(pixels.getUint8(offset + 2), 0);
    final previewDir = Platform.environment['ANTKEEP_MILESTONE_PREVIEW_DIR'];
    if (previewDir != null) {
      await tester.runAsync(
        () => File('$previewDir/user-photo.png').writeAsBytes(bytes!),
      );
    }
    frame.image.dispose();
    codec!.dispose();
  });

  for (final artwork in MilestoneArtwork.values) {
    testWidgets('${artwork.label} exports a 1200x1500 PNG', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestonePoster(
              colony: colony,
              milestone: milestone,
              artwork: artwork,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final bytes = (await tester.runAsync(
        () => renderMilestonePng(colony, milestone, artwork),
      ))!;
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await tester.runAsync(
        () => ui.instantiateImageCodec(bytes),
      );
      final frame = await tester.runAsync(() => codec!.getNextFrame());
      expect(frame!.image.width, 1200);
      expect(frame.image.height, 1500);
      frame.image.dispose();
      codec!.dispose();
      final previewDir = Platform.environment['ANTKEEP_MILESTONE_PREVIEW_DIR'];
      if (previewDir != null) {
        await tester.runAsync(() async {
          await Directory(previewDir).create(recursive: true);
          await File('$previewDir/${artwork.name}.png').writeAsBytes(bytes);
        });
      }
    });
  }

  testWidgets('unlinked milestone also renders a share image', (tester) async {
    final independent = Milestone(
      id: 'independent',
      title: '首次发现',
      occurredAt: date,
      createdAt: date,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MilestonePoster(
            milestone: independent,
            artwork: MilestoneArtwork.harvest,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('首次发现的里程碑分享图'), findsOneWidget);
    final bytes = await tester.runAsync(
      () => renderMilestonePng(null, independent, MilestoneArtwork.harvest),
    );
    expect(bytes, isNotNull);
    expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final previewDir = Platform.environment['ANTKEEP_MILESTONE_PREVIEW_DIR'];
    if (previewDir != null) {
      await tester.runAsync(() async {
        await Directory(previewDir).create(recursive: true);
        await File('$previewDir/independent.png').writeAsBytes(bytes);
      });
    }
  });

  testWidgets('selected artwork can be shared and saved with long text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longMilestone = Milestone(
      id: 'long',
      colonyId: 'c',
      title: '边境蚁群的一场漫长交战' * 6,
      note: '当时的巢室与蚁群故事。' * 100,
      occurredAt: date,
      createdAt: date,
      artwork: MilestoneArtwork.battle,
    );
    Uint8List? shared;
    Uint8List? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: MilestoneSharePage(
          colony: colony,
          milestone: longMilestone,
          shareImage: (bytes, name, origin) async {
            shared = bytes;
            expect(name, endsWith('.png'));
            expect(origin.width, greaterThan(0));
          },
          saveImage: (bytes) async {
            saved = bytes;
            return '图片已保存';
          },
        ),
      ),
    );
    expect(find.text('选择石刻画面'), findsNothing);
    await tester.tap(find.text('转发分享'));
    await _settle(tester);
    expect(shared, isNotNull);
    await tester.tap(find.text('保存图片'));
    await _settle(tester);
    expect(saved, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}
