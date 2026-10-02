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

  Future<void> startDirectDraw(
    WidgetTester tester, {
    bool manual = false,
    String start = '5',
    String end = '8',
  }) async {
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.tap(find.text('数字跳动'));
    await tester.pump();
    if (manual) {
      await tester.tap(find.text('手动暂停'));
      await tester.pump();
    }
    await tester.enterText(find.byType(TextField).at(0), start);
    await tester.enterText(find.byType(TextField).at(1), end);
    await tester.tap(find.text('开始抽奖'));
    await tester.pump();
  }

  int displayedNumber(WidgetTester tester) => int.parse(
    tester.widget<Text>(find.byKey(const ValueKey('lottery-number'))).data!,
  );

  testWidgets('automatic draw keeps rolling before stopping at three seconds', (
    tester,
  ) async {
    await startDirectDraw(tester);
    expect(find.text('随机跳动中'), findsOneWidget);
    expect(find.text('抽中数字'), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
    final seen = <int>{displayedNumber(tester)};
    for (var tick = 0; tick < 30; tick++) {
      await tester.pump(const Duration(milliseconds: 80));
      final number = displayedNumber(tester);
      expect(number, inInclusiveRange(5, 8));
      seen.add(number);
    }
    expect(seen.length, greaterThan(1));
    expect(find.text('抽中数字'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('抽中数字'), findsOneWidget);
    final result = displayedNumber(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(displayedNumber(tester), result);
    expect(find.text('开始抽奖'), findsOneWidget);
  });

  testWidgets('manual draw waits for pause and can start another draw', (
    tester,
  ) async {
    await startDirectDraw(tester, manual: true, start: '-8', end: '-5');
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('随机跳动中'), findsOneWidget);
    expect(find.text('抽中数字'), findsNothing);
    final number = displayedNumber(tester);
    expect(number, inInclusiveRange(-8, -5));
    await tester.tap(find.text('暂停'));
    await tester.pump();
    expect(find.text('抽中数字'), findsOneWidget);
    expect(displayedNumber(tester), number);
    await tester.pump(const Duration(seconds: 5));
    expect(displayedNumber(tester), number);

    await tester.tap(find.text('开始抽奖'));
    await tester.pump();
    expect(find.text('抽中数字'), findsNothing);
    expect(find.text('随机跳动中'), findsOneWidget);
    await tester.tap(find.text('暂停'));
    await tester.pump();
  });

  testWidgets('a single-number range still waits for automatic pause', (
    tester,
  ) async {
    await startDirectDraw(tester, start: '7', end: '7');
    expect(displayedNumber(tester), 7);
    expect(find.text('抽中数字'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('抽中数字'), findsOneWidget);
    expect(displayedNumber(tester), 7);
  });

  testWidgets('invalid range does not start rolling', (tester) async {
    await startDirectDraw(tester, start: '8', end: '5');
    expect(find.textContaining('请输入有效的数字范围'), findsOneWidget);
    expect(find.text('随机跳动中'), findsNothing);
    expect(find.byKey(const ValueKey('lottery-number')), findsNothing);
  });

  for (final manual in [false, true]) {
    testWidgets('leaving an active draw cancels timers (manual: $manual)', (
      tester,
    ) async {
      await startDirectDraw(tester, manual: manual);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  }

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
