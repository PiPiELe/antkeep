import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/domain/colony_growth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('classic interface restores the 1.0.10 colony form', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: antKeepTheme(ThemeColor.forest),
        home: const InterfaceStyleScope(
          style: InterfaceStyle.classic,
          child: ColonyFormPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<GrowthPath>), findsOneWidget);
    expect(find.byType(DropdownMenu<GrowthPath>), findsNothing);
    expect(find.widgetWithText(FilledButton, '保存蚁群'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('count labels fit on a narrow screen at text scale $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: antKeepTheme(ThemeColor.forest),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const ColonyFormPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find
            .ancestor(of: find.text('品种与昵称'), matching: find.byType(Card))
            .evaluate()
            .single,
        find
            .ancestor(
              of: find.byKey(const ValueKey('colony-name')),
              matching: find.byType(Card),
            )
            .evaluate()
            .single,
      );
      final customSpeciesAction = find.text('未收录？');
      expect(
        tester.getTopLeft(customSpeciesAction).dx,
        greaterThan(tester.getTopRight(find.text('品种与昵称')).dx),
      );
      expect(
        tester.getBottomLeft(customSpeciesAction).dy,
        lessThan(tester.getTopLeft(find.text('品种分类/细分种类')).dy),
      );
      expect(tester.widget<Text>(customSpeciesAction).style?.fontSize, 10);

      final countHint = find.text('档案起始数量，日记中的死亡数量会从此扣减');
      await tester.ensureVisible(countHint);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(countHint).dy,
        lessThan(tester.getTopLeft(find.text('发育模式')).dy),
      );
      expect(tester.widget<Text>(countHint).style?.fontSize, 10);

      for (final label in ['蚁后 *', '工蚁 *', '卵', '蛹茧']) {
        final field = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
          reason: '$label must be fully visible',
        );
      }
      final queenField = find.widgetWithText(TextFormField, '蚁后 *');
      final workerField = find.widgetWithText(TextFormField, '工蚁 *');
      await tester.ensureVisible(queenField);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(queenField).dy,
        tester.getTopLeft(workerField).dy,
        reason: 'queen and worker fields must align at the top',
      );

      final specialized = find.text('特化');
      await tester.scrollUntilVisible(
        specialized,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find
            .ancestor(of: specialized, matching: find.byType(Card))
            .evaluate()
            .single,
        find
            .ancestor(of: find.text('数量'), matching: find.byType(Card))
            .evaluate()
            .single,
      );

      final acquiredOn = find.text('入手日期（可选）');
      final cover = find.text('添加封面照片');
      await tester.scrollUntilVisible(
        acquiredOn,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(acquiredOn).dy, tester.getTopLeft(cover).dy);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'development menu overlays the counts and nest picker keeps selection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: antKeepTheme(ThemeColor.forest),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const ColonyFormPage(),
        ),
      );
      final selector = find.byType(DropdownMenu<GrowthPath>);
      final queen = find.widgetWithText(TextFormField, '蚁后 *');
      await tester.ensureVisible(selector);
      final queenGap =
          tester.getTopLeft(queen).dy - tester.getBottomLeft(selector).dy;
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(queen).dy - tester.getBottomLeft(selector).dy,
        closeTo(queenGap, .01),
      );
      await tester.tap(find.text(GrowthPath.eggToWorker.label).last);
      await tester.pumpAndSettle();

      final specialized = find.text('特化');
      await tester.scrollUntilVisible(
        specialized,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(specialized);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '特化数量'), findsOneWidget);

      final nest = find.widgetWithText(TextFormField, '巢体类型（可选）');
      await tester.ensureVisible(nest);
      await tester.tap(nest);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '亚克力巢'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(nest).initialValue, '亚克力巢');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dark development menu marks its selected option', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: antKeepTheme(ThemeColor.forest, dark: true),
        home: const ColonyFormPage(),
      ),
    );
    final selector = find.byType(DropdownMenu<GrowthPath>);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();

    final selected = find.widgetWithText(
      MenuItemButton,
      GrowthPath.eggToCocoonToWorker.label,
    );
    expect(selected, findsOneWidget);
    expect(
      tester
          .widget<MenuItemButton>(selected)
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      isNot(Colors.transparent),
    );
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
