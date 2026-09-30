import 'dart:math';

import 'package:antkeep/lottery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wheel range is shuffled and retains every number', () {
    expect(
      shuffledLotteryRange(1, 6, random: Random(4)),
      isNot(orderedEquals([1, 2, 3, 4, 5, 6])),
    );
    expect(
      shuffledLotteryRange(1, 6, random: Random(4)),
      unorderedEquals([1, 2, 3, 4, 5, 6]),
    );
  });

  test('wheel stop leaves the selected wedge at the top pointer', () {
    const itemCount = 99;
    const selectedIndex = 42;
    final turns = wheelTurnsForSelectedIndex(
      currentTurns: 3.25,
      selectedIndex: selectedIndex,
      itemCount: itemCount,
    );
    final selectedCenter =
        -pi / 2 + (selectedIndex + 0.5) * 2 * pi / itemCount + 2 * pi * turns;

    expect(cos(selectedCenter), closeTo(0, 0.000001));
    expect(sin(selectedCenter), closeTo(-1, 0.000001));
  });

  testWidgets('direct draw displays a number in the entered range', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.tap(find.text('直接抽取'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), '5');
    await tester.enterText(find.byType(TextField).at(1), '8');
    await tester.tap(find.text('抽取数字'));
    await tester.pump();

    expect(find.text('抽中数字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel mode validates the number of displayed options', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '101');
    final generateButton = find.text('生成转盘');
    await tester.ensureVisible(generateButton);
    await tester.tap(generateButton);
    await tester.pump();

    expect(find.textContaining('2 到 100 个数字'), findsOneWidget);
  });

  testWidgets('wheel draw shows a shuffled wheel and selected number', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '99');
    final generateButton = find.text('生成转盘');
    await tester.ensureVisible(generateButton);
    await tester.tap(generateButton);
    await tester.pump();

    await tester.ensureVisible(find.text('转盘数字已随机打乱。'));
    expect(find.text('转盘数字已随机打乱。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel result is only shown after the spin finishes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '4');
    final generateButton = find.text('生成转盘');
    await tester.ensureVisible(generateButton);
    await tester.tap(generateButton);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    await tester.tap(find.text('转动转盘'));
    await tester.pump();
    expect(find.text('转盘转动中…'), findsOneWidget);
    expect(find.text('抽中数字'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(find.text('抽中数字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
