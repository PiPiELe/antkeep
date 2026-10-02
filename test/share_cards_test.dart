import 'dart:ui' as ui;

import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/share_card_data.dart';
import 'package:antkeep/data/share_image_export.dart';
import 'package:antkeep/share_cards_page.dart';
import 'package:antkeep/widgets/share_card_poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 2);
  final colony = Colony(
    id: 'c',
    name: '可乐一家',
    species: '尼科巴弓背蚁',
    acquiredOn: DateTime(2026, 6, 1),
    createdAt: DateTime(2026, 6, 1),
    updatedAt: now,
    initialWorkerCount: 5,
    queenCount: 1,
    source: '不应展示的商家',
    purchasePriceCents: 123456,
  );
  final record = CareRecord(
    id: 'r',
    colonyId: 'c',
    type: CareRecordType.observation,
    occurredAt: now,
    createdAt: now,
    workerCount: 86,
    eggCount: 0,
    note: '今天出工了',
    temperature: 26,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  testWidgets(
    'all four templates switch, privacy and unknown values stay safe',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShareCardsPage(colony: colony, records: [record], now: now),
        ),
      );
      await tester.pumpAndSettle();
      for (final kind in ShareCardKind.values) {
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, kind.label));
        await tester.tap(find.widgetWithText(ChoiceChip, kind.label));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ShareCardPoster>(find.byType(ShareCardPoster)).kind,
          kind,
        );
        expect(find.textContaining('不应展示'), findsNothing);
        expect(find.textContaining('1234.56'), findsNothing);
        expect(find.text('幼虫 0'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'direct diary entry uses selected record and editing does not change it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShareCardsPage(
            colony: colony,
            records: [record],
            initialRecord: record,
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ShareCardPoster>(find.byType(ShareCardPoster)).kind,
        ShareCardKind.diary,
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '仅用于分享');
      await tester.pumpAndSettle();
      expect(
        tester.widget<ShareCardPoster>(find.byType(ShareCardPoster)).caption,
        '仅用于分享',
      );
      expect(record.note, '今天出工了');
      await tester.ensureVisible(find.widgetWithText(FilterChip, '数量'));
      await tester.tap(find.widgetWithText(FilterChip, '数量'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ShareCardPoster>(find.byType(ShareCardPoster)).showCounts,
        isFalse,
      );
    },
  );

  testWidgets('no diary gives explicit empty state and disables save', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShareCardsPage(colony: colony, records: [], now: now),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '日记卡片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有日记'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'long diary is bounded with a visible notice and original preserved',
    (tester) async {
      final long = CareRecord(
        id: 'long',
        colonyId: 'c',
        type: CareRecordType.observation,
        occurredAt: now,
        createdAt: now,
        note: '长' * 900,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ShareCardsPage(
            colony: colony,
            records: [long],
            initialRecord: long,
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShareCardPoster>(find.byType(ShareCardPoster))
            .caption
            .length,
        600,
      );
      expect(long.note!.length, 900);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PNG export generates 1080px image and passes bytes to native saver',
    (tester) async {
      Uint8List? saved;
      messenger.setMockMethodCallHandler(ShareImageExport.channel, (
        call,
      ) async {
        saved = (call.arguments as Map)['bytes'] as Uint8List;
        return '已保存到相册';
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(ShareImageExport.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ShareCardsPage(colony: colony, records: [record], now: now),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('保存图片'));
        await tester.pump();
        for (var i = 0; i < 100 && saved == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(saved!);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1080);
        frame.image.dispose();
        codec.dispose();
      });
      expect(find.text('已保存到相册'), findsOneWidget);
    },
  );

  testWidgets('all posters paint at narrow width with long captions', (
    tester,
  ) async {
    for (final kind in ShareCardKind.values) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 288,
                    child: ShareCardPoster(
                      colony: colony,
                      records: [record],
                      kind: kind,
                      now: now,
                      from: DateTime(2026, 6, 1),
                      to: now,
                      month: now,
                      diary: record,
                      caption: '成长日记，记录每一次细微变化。' * 30,
                      dark: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3.75);
        expect(image.width, 1080);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(png!.lengthInBytes, greaterThan(1000));
        image.dispose();
      });
    }
  });
  testWidgets('permission rejection reports failure and allows retry', (
    tester,
  ) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(ShareImageExport.channel, (_) async {
      calls++;
      throw PlatformException(code: 'permission_denied');
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(ShareImageExport.channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ShareCardsPage(colony: colony, records: [], now: now),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存图片'));
      await tester.pump();
      for (var i = 0; i < 100 && calls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('未获得保存照片权限'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'direct future diary is selectable without leaking into current population',
    (tester) async {
      final future = CareRecord(
        id: 'future',
        colonyId: 'c',
        type: CareRecordType.observation,
        occurredAt: DateTime(2026, 11),
        createdAt: now,
        workerCount: 999,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ShareCardsPage(
            colony: colony,
            records: [record, future],
            initialRecord: future,
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<ShareCardPoster>(find.byType(ShareCardPoster)).diary!.id,
        'future',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '蚁群名片'));
      await tester.pumpAndSettle();
      expect(find.text('工蚁 86'), findsOneWidget);
      expect(find.textContaining('999'), findsNothing);
    },
  );
}
