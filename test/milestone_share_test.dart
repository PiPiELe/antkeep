import 'dart:io';
import 'dart:ui' as ui;

import 'package:antkeep/domain/milestone.dart';
import 'package:antkeep/domain/models.dart';
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

  setUpAll(() async {
    final font = Platform.environment['ANTKEEP_TEST_FONT'];
    if (font != null) {
      final loader = FontLoader('serif')
        ..addFont(
          File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    for (final artwork in MilestoneArtwork.values) {
      await loadMilestoneArtwork(artwork);
    }
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
      title: '独立里程碑',
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
    final bytes = await tester.runAsync(
      () => renderMilestonePng(null, independent, MilestoneArtwork.harvest),
    );
    expect(bytes, isNotNull);
    expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
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
    await tester.tap(find.text('种群之战'));
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
