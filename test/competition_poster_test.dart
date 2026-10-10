import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antkeep/online/competition_poster_page.dart';

void main() {
  final detail = <String, dynamic>{
    'title': '秋季新后成长挑战赛',
    'scoreMode': 'POINTS',
    'broodPointsEnabled': true,
    'startDate': '2026-10-01',
    'endDate': null,
    'state': 'ACTIVE',
    'today': '2026-10-10',
    'participantCount': 2,
    'namesVisible': true,
    'entries': [
      {
        'rank': 1,
        'contestantId': '12345678-1111-4111-8111-123456789012',
        'username': 'private-user',
        'colonyName': 'private-colony',
        'workerCount': 4,
        'eggCount': 2,
        'larvaCount': 1,
        'cocoonCount': 0,
        'score': 19,
      },
    ],
  };

  for (final style in CompetitionPosterStyle.values) {
    for (final size in CompetitionPosterSize.values) {
      testWidgets(
        'leaderboard ${style.label} ${size.label} exports exact pixels without names',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 2400);
          tester.view.devicePixelRatio = 3;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: CompetitionPoster(
                      detail: detail,
                      kind: CompetitionPosterKind.leaderboard,
                      size: size,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.textContaining('ID 12345678'), findsOneWidget);
          expect(find.textContaining('private-user'), findsNothing);
          expect(find.textContaining('private-colony'), findsNothing);
          expect(tester.takeException(), isNull);
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final png = await boundary.toImage(pixelRatio: 3);
          expect(png.width, 1080);
          expect(png.height, size.pixelHeight);
          png.dispose();
        },
      );

      testWidgets(
        'promotion ${style.label} ${size.label} shows schedule and rules with long title',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 2400);
          tester.view.devicePixelRatio = 3;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: CompetitionPoster(
                    detail: {...detail, 'title': '很长的比赛名称' * 10},
                    kind: CompetitionPosterKind.promotion,
                    size: size,
                    style: style,
                  ),
                ),
              ),
            ),
          );
          expect(find.text('2026-10-01 — 长期进行'), findsOneWidget);
          expect(find.textContaining('新增工蚁 +2 分'), findsOneWidget);
          expect(find.textContaining('打开蚁记在线版'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final art in CompetitionAntArt.values.skip(1)) {
    testWidgets('${art.label} artwork renders in challenge poster', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CompetitionPoster(
                detail: detail,
                kind: CompetitionPosterKind.promotion,
                size: CompetitionPosterSize.portrait,
                style: CompetitionPosterStyle.challenge,
                antArt: art,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == art.assetPath,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
