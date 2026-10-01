import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/domain/antden_species_directory.dart';
import 'package:antkeep/domain/species_profile.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/species_encyclopedia_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundles the previously consulted species for offline use', () {
    expect(
      speciesProfiles.map((profile) => profile.name),
      containsAll(['费氏弓背蚁', '猎镰猛蚁', '窄颈弓背蚁', '横纹齿猛蚁']),
    );
  });

  test('AntDen directory only exposes validated public detail links', () async {
    final directory = await AntDenSpeciesDirectory.load();
    final reference = directory.singleWhere(
      (item) => item.scientificName == 'Harpegnathos venator',
    );

    expect(reference.displayName, '猎镰猛蚁');
    expect(reference.sourceUrl, Uri.parse('https://antden.net/antShow/33'));
    expect(reference.matches('猎镰'), isTrue);
  });

  test('direct lookup accepts identities but never broad search terms', () {
    for (final name in [
      '费氏弓背蚁',
      '黑金弓背蚁',
      '黑斑弓背蚁',
      '费氏弓背蚁（黑金弓背蚁）',
      '费氏弓背蚁（自定义俗名）',
      ' CAMPONOTUS FEDTSCHENKOI ',
    ]) {
      expect(findSpeciesProfile(name), same(speciesProfiles.first));
    }
    expect(findSpeciesProfile('猎镰猛蚁')!.name, '猎镰猛蚁');
    expect(findSpeciesProfile('Camponotus angusticollis')!.name, '窄颈弓背蚁');
    expect(findSpeciesProfile('横纹齿针蚁')!.name, '横纹齿猛蚁');
    for (final name in [
      '',
      ' ',
      '弓背蚁',
      'Camponotus',
      '蚁亚科',
      '无颚齿收获蚁',
      '未知物种（黑金弓背蚁）',
    ]) {
      expect(findSpeciesProfile(name), isNull);
    }
  });

  testWidgets('discovery opens encyclopedia, search and detail return work', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DiscoverPage())),
    );
    await tester.tap(find.text('蚂蚁百科'));
    await tester.pumpAndSettle();
    expect(find.byType(SpeciesEncyclopediaPage), findsOneWidget);

    for (final query in ['黑金', '黑斑', ' CAMPONOTUS FEDTSCHENKOI ', '蚁亚科']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(find.text('费氏弓背蚁'), findsOneWidget);
    }

    await tester.tap(find.text('费氏弓背蚁'));
    await tester.pumpAndSettle();
    expect(find.byType(SpeciesDetailPage), findsOneWidget);
    expect(find.text('基础分类'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '蚁亚科',
    );

    await tester.enterText(find.byType(TextField), '尚未收录的物种');
    await tester.pumpAndSettle();
    expect(find.text('暂无匹配的物种'), findsOneWidget);
    expect(find.text('费氏弓背蚁'), findsNothing);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('费氏弓背蚁'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DiscoverPage), findsOneWidget);
  });

  testWidgets('non-bundled species opens its online AntDen entry', (
    tester,
  ) async {
    final directory = (await tester.runAsync(AntDenSpeciesDirectory.load))!;
    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesEncyclopediaPage(
          directoryLoader: () => Future.value(directory),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '三尖叉多刺蚁');
    await tester.pumpAndSettle();
    expect(find.textContaining('联网查看完整资料和图片'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '三尖叉多刺蚁'));
    await tester.pumpAndSettle();

    expect(find.byType(OnlineSpeciesDetailPage), findsOneWidget);
    expect(find.text('查看蚁丘最新资料和图片'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('detail remains readable on narrow screen, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: antKeepTheme(ThemeColor.forest, dark: dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SpeciesDetailPage(profile: speciesProfiles.first),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['基础分类', '体型数据', '饲养信息', '资料说明']) {
        await tester.scrollUntilVisible(find.text(label), 200);
        expect(find.text(label), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(
        find.text(speciesProfiles.first.source),
        150,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
