import 'dart:math';

import 'package:antkeep/lottery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
    int seconds = 6,
    int speed = 2,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.tap(find.text('数字跳动'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lottery_direct_seconds')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$seconds 秒').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lottery_direct_speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text({1: '慢速', 2: '中速', 3: '快速'}[speed]!).last);
    await tester.pumpAndSettle();
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

  testWidgets('automatic draw keeps rolling before stopping at six seconds', (
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
    await tester.pump(const Duration(milliseconds: 3600));
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
    await tester.pump(const Duration(seconds: 6));
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

  for (final seconds in [4, 8, 10]) {
    testWidgets('direct draw automatically stops at $seconds seconds', (
      tester,
    ) async {
      await startDirectDraw(tester, seconds: seconds);
      await tester.pump(Duration(milliseconds: seconds * 1000 - 1));
      expect(find.text('抽中数字'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('抽中数字'), findsOneWidget);
      expect(displayedNumber(tester), inInclusiveRange(5, 8));
    });
  }

  for (final option in {1: 200, 2: 100, 3: 40}.entries) {
    testWidgets(
      'direct speed ${option.key} updates every ${option.value} milliseconds',
      (tester) async {
        await startDirectDraw(tester, speed: option.key, manual: true);
        final number = find.byKey(const ValueKey('lottery-number'));
        final initialText = tester.widget<Text>(number);
        await tester.pump(Duration(milliseconds: option.value - 1));
        expect(tester.widget<Text>(number), same(initialText));
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.widget<Text>(number), isNot(same(initialText)));
        for (final dropdown in tester.widgetList<DropdownButton<int>>(
          find.byType(DropdownButton<int>),
        )) {
          expect(dropdown.onChanged, isNull);
        }
        await tester.tap(find.text('暂停'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButton<int>>(
                find.byKey(const ValueKey('lottery_direct_seconds')),
              )
              .onChanged,
          isNull,
        );
        expect(
          tester
              .widget<DropdownButton<int>>(
                find.byKey(const ValueKey('lottery_direct_speed')),
              )
              .onChanged,
          isNotNull,
        );
      },
    );
  }

  testWidgets(
    'direct preferences survive reopening independently from wheel settings',
    (tester) async {
      await startDirectDraw(tester, seconds: 10, speed: 1);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('lottery_wheel_seconds')),
            )
            .value,
        6,
      );
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('lottery_wheel_speed')),
            )
            .value,
        2,
      );
      await tester.tap(find.text('数字跳动'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('lottery_direct_seconds')),
            )
            .value,
        10,
      );
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('lottery_direct_speed')),
            )
            .value,
        1,
      );
      expect(find.textContaining('10 秒后自动暂停'), findsOneWidget);
    },
  );

  testWidgets('wheel mode validates the number of displayed options', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '101');
    final generateButton = find.text('生成转盘');
    await tester.ensureVisible(generateButton);
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('转盘数字已随机打乱。'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('转盘数字已随机打乱。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final speed in [1, 2, 3]) {
    for (final seconds in [4, 6, 8, 10]) {
      testWidgets('wheel waits $seconds seconds at speed $speed', (
        tester,
      ) async {
        await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButton<int>>(
                find.byKey(const ValueKey('lottery_wheel_seconds')),
              )
              .value,
          6,
        );
        await tester.tap(find.byKey(const ValueKey('lottery_wheel_seconds')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('$seconds 秒').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('lottery_wheel_speed')));
        await tester.pumpAndSettle();
        await tester.tap(find.text({1: '慢速', 2: '中速', 3: '快速'}[speed]!).last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), '1');
        await tester.enterText(find.byType(TextField).at(1), '4');
        await tester.ensureVisible(find.text('生成转盘'));
        await tester.tap(find.text('生成转盘'));
        await tester.pump();
        await tester.scrollUntilVisible(find.text('转动转盘'), 200);
        await tester.pumpAndSettle();
        await tester.tap(find.text('转动转盘'));
        await tester.pump();
        expect(find.text('转盘转动中…'), findsOneWidget);
        expect(find.text('抽中数字'), findsNothing);
        await tester.pump(Duration(seconds: seconds - 1));
        expect(find.text('抽中数字'), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump();
        expect(find.text('转动转盘'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('lottery-wheel-result')),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(find.text('抽中数字'), findsOneWidget);
        expect(displayedNumber(tester), inInclusiveRange(1, 4));
        final rotation = tester
            .widget<RotationTransition>(
              find.byKey(const ValueKey('lottery-rotation')),
            )
            .turns
            .value;
        final expectedTurns = seconds * {1: 0.25, 2: 0.5, 3: 5 / 2.2}[speed]!;
        expect(rotation, closeTo(expectedTurns, 0.5));
        expect(tester.takeException(), isNull);

        // A second draw must use the same duration and clear the old result.
        await tester.scrollUntilVisible(
          find.text('转动转盘'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('转动转盘'));
        await tester.pump();
        expect(find.text('抽中数字'), findsNothing);
        await tester.pump(Duration(seconds: seconds));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump();
        expect(find.text('转动转盘'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('lottery-wheel-result')),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(find.text('抽中数字'), findsOneWidget);

        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButton<int>>(
                find.byKey(const ValueKey('lottery_wheel_seconds')),
              )
              .value,
          seconds,
        );
        expect(
          tester
              .widget<DropdownButton<int>>(
                find.byKey(const ValueKey('lottery_wheel_speed')),
              )
              .value,
          speed,
        );
      });
    }
  }

  testWidgets('leaving an active wheel cancels the animation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '4');
    await tester.ensureVisible(find.text('生成转盘'));
    await tester.tap(find.text('生成转盘'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('转动转盘'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('转动转盘'));
    await tester.pump();
    expect(find.text('转盘转动中…'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'legacy duration keeps medium speed and both controls lock during a draw',
    (tester) async {
      SharedPreferences.setMockInitialValues({'lottery_wheel_seconds': 8});
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: LotteryPage()));
      await tester.pumpAndSettle();
      final duration = find.byKey(const ValueKey('lottery_wheel_seconds'));
      final speed = find.byKey(const ValueKey('lottery_wheel_speed'));
      expect(tester.widget<DropdownButton<int>>(duration).value, 8);
      expect(tester.widget<DropdownButton<int>>(speed).value, 2);
      expect(tester.getTopLeft(duration).dy, tester.getTopLeft(speed).dy);
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), '4');
      await tester.tap(find.text('生成转盘'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('转动转盘'));
      await tester.pump();
      expect(tester.widget<DropdownButton<int>>(duration).onChanged, isNull);
      expect(tester.widget<DropdownButton<int>>(speed).onChanged, isNull);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int>>(duration).onChanged, isNotNull);
      expect(tester.widget<DropdownButton<int>>(speed).onChanged, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
