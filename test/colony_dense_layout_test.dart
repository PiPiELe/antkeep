import 'dart:io';
import 'dart:ui' as ui;

import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/colony_dense_layout.dart';
import 'package:antkeep/widgets/fading_horizontal_scroll.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();
  DenseColonyEntry entry(int i) {
    final names = ['日本弓背蚁', '红火蚁', '黑棘蚁', '黄猄蚁', '大头蚁', '铺道蚁'];
    final species = [
      'Camponotus japonicus',
      'Solenopsis invicta',
      'Polyrhachis vicina',
      'Lasius flavus',
      'Pheidole megacephala',
      'Tetramorium caespitum',
    ];
    final days = [128, 76, 210, 12, 98, 156];
    return DenseColonyEntry(
      colony: Colony(
        id: ['JP-01', 'HH-02', 'BT-03', 'LY-04', 'DT-05', 'PD-06'][i],
        name: names[i],
        species: species[i],
        queenCount: 1,
        acquiredOn: now.subtract(Duration(days: days[i])),
        purchasePriceCents: [68000, 32000, 45000, 18000, 26000, 15000][i],
        createdAt: now,
        updatedAt: now,
      ),
      population: GrowthPopulation(
        workers: [126, 342, 89, 18, 204, 312][i],
        larvae: [38, 112, 24, 6, 67, 90][i],
        eggs: i == 0 || i == 4 ? 5 : null,
      ),
      queens: 1,
      dueFeeding: i == 3,
      records: [
        CareRecord(
          id: 'r$i',
          colonyId: 'x',
          type: CareRecordType.feeding,
          occurredAt: now.subtract(Duration(days: [2, 1, 3, 5, 2, 3][i])),
          createdAt: now,
          temperature: [26, 28, 25, 24, 27, 26][i].toDouble(),
          humidity: [68, 62, 70, 55, 60, 65][i].toDouble(),
        ),
      ],
    );
  }

  for (final dark in [false, true]) {
    for (final width in [430.0, 320.0]) {
      testWidgets(
        'dense ${dark ? 'dark' : 'light'} $width renders and filters',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 860);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final font = FontLoader('PreviewChinese')
            ..addFont(rootBundle.load('assets/fonts/NotoSerifSC.ttf'));
          const previewFont = String.fromEnvironment('PREVIEW_FONT');
          if (previewFont.isNotEmpty) {
            await tester.runAsync(() async {
              final data = await File(previewFont).readAsBytes();
              final sans = FontLoader('PreviewSans')
                ..addFont(Future.value(ByteData.sublistView(data)));
              await sans.load();
            });
          }
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await tester.runAsync(icons.load);
          await tester.runAsync(font.load);
          var adds = 0;
          var filters = 0;
          String? opened;
          await tester.pumpWidget(
            MaterialApp(
              theme: antKeepTheme(ThemeColor.forest, dark: dark).copyWith(
                textTheme: ThemeData().textTheme.apply(
                  fontFamily: previewFont.isEmpty
                      ? 'PreviewChinese'
                      : 'PreviewSans',
                ),
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('preview'),
                  child: Column(
                    children: [
                      ColonyDenseTabs(
                        labels: const ['我的蚁群', '总览', '英灵殿', '里程碑'],
                        selectedIndex: 0,
                        onSelected: (_) {},
                        onRename: (_) {},
                        onShare: () {},
                        onAnalysis: () {},
                      ),
                      Expanded(
                        child: ColonyDenseList(
                          entries: List.generate(6, entry),
                          onAdd: () => adds++,
                          onFilter: () => filters++,
                          onOpen: (c) => opened = c.id,
                          onDuration: (_) {},
                          onDelete: (_) {},
                          onRefresh: () async {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await precacheImage(
              const AssetImage('assets/images/default-ant-cover.png'),
              tester.element(find.byType(ColonyDenseList)),
            );
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          const previewDirectory = String.fromEnvironment('DENSE_PREVIEW_DIR');
          if (width == 430 && previewDirectory.isNotEmpty) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('preview')),
            );
            await tester.runAsync(() async {
              final img = await boundary.toImage(pixelRatio: 2);
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(previewDirectory).create(recursive: true);
              await File('$previewDirectory/${dark ? 'dark' : 'light'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }
          await tester.tap(find.byTooltip('新增蚁群'));
          expect(adds, 1);
          await tester.tap(find.byTooltip('筛选'));
          expect(filters, 1);
          await tester.enterText(find.byType(TextField), 'JP-01');
          await tester.pumpAndSettle();
          expect(find.text('日本弓背蚁'), findsOneWidget);
          expect(find.text('红火蚁'), findsNothing);
          await tester.tap(find.text('日本弓背蚁'));
          expect(opened, 'JP-01');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final dark in [false, true]) {
    testWidgets('dense long text scrolls without opening card dark=$dark', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var opened = false;
      final longEntry = DenseColonyEntry(
        colony: Colony(
          id: 'long',
          name: '这是一窝名字非常长的日本弓背蚁需要滑动查看完整名称',
          species:
              'Camponotus japonicus very long scientific species description',
          source: '野采',
          initialWorkerCount: 0,
          purchasePriceCents: 10000,
          createdAt: now,
          updatedAt: now,
        ),
        population: const GrowthPopulation(workers: 20),
        queens: 1,
        records: [],
        dueFeeding: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: antKeepTheme(ThemeColor.forest, dark: dark),
          home: Scaffold(
            body: ColonyDenseList(
              entries: [longEntry],
              onAdd: () {},
              onFilter: () {},
              onOpen: (_) => opened = true,
              onDuration: (_) {},
              onDelete: (_) {},
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final kind in ['name', 'species', 'tags']) {
        final viewport = find.byKey(ValueKey('dense-$kind-long'));
        expect(tester.widget(viewport), isA<FadingHorizontalScroll>());
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.descendant(
                of: viewport,
                matching: find.byType(SingleChildScrollView),
              ),
            )
            .controller!;
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        final initialText = find
            .descendant(of: viewport, matching: find.byType(Text))
            .first;
        final originalX = tester.getTopLeft(initialText).dx;
        await tester.drag(viewport, const Offset(-60, 0));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        expect(tester.getTopLeft(initialText).dx, lessThan(originalX));
        expect(opened, isFalse);
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, 0);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dense tabs preserve secondary destinations and rename actions', (
    tester,
  ) async {
    int? selected;
    int? renamed;
    var shared = false;
    var analyzed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 430,
            child: ColonyDenseTabs(
              labels: const ['我的蚁群', '总览', '英灵殿', '里程碑'],
              selectedIndex: 0,
              onSelected: (i) => selected = i,
              onRename: (i) => renamed = i,
              onShare: () => shared = true,
              onAnalysis: () => analyzed = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('总览'));
    expect(selected, 1);
    await tester.longPress(find.text('我的蚁群'));
    expect(renamed, 0);
    await tester.tap(find.text('分析'));
    expect(analyzed, isTrue);
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('里程碑'));
    expect(selected, 3);
    await tester.tap(find.byTooltip('分享'));
    expect(shared, isTrue);
    expect(tester.takeException(), isNull);
  });

  test(
    'latest observations are independent; unknown values remain unknown',
    () {
      final e = entry(0);
      final data = DenseColonyEntry(
        colony: e.colony,
        population: e.population,
        queens: 1,
        dueFeeding: false,
        records: [
          CareRecord(
            id: 'a',
            colonyId: 'x',
            type: CareRecordType.observation,
            occurredAt: now,
            createdAt: now,
            humidity: 70,
          ),
          ...e.records,
        ],
      );
      expect(data.temperature, 26);
      expect(data.humidity, 70);
      expect(data.lastFeeding, e.lastFeeding);
      final empty = DenseColonyEntry(
        colony: e.colony,
        population: e.population,
        queens: 1,
        dueFeeding: false,
        records: [],
      );
      expect(empty.temperature, isNull);
      expect(empty.humidity, isNull);
      expect(empty.lastFeeding, isNull);
    },
  );
}
