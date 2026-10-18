import 'package:antkeep/app_preferences.dart';
import 'package:antkeep/colony_tag_settings_page.dart';
import 'package:antkeep/domain/colony_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements AppSettingsStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<Map<String, String>> readSettings() async => Map.of(values);

  @override
  Future<void> writeSettings(Map<String, String> updates) async {
    if (failWrites) throw StateError('unavailable');
    values.addAll(updates);
  }
}

void main() {
  test(
    'tag order persists, is immutable and failed writes keep saved order',
    () async {
      final store = _Store();
      final preferences = AppPreferences(store);
      await preferences.load();
      expect(preferences.colonyTagOrder, ColonyTag.values);
      final reversed = ColonyTag.values.reversed.toList();
      await preferences.setColonyTagOrder(reversed);
      final restarted = AppPreferences(store);
      await restarted.load();
      expect(restarted.colonyTagOrder, reversed);
      expect(() => restarted.colonyTagOrder.clear(), throwsUnsupportedError);
      store.failWrites = true;
      await expectLater(
        restarted.setColonyTagOrder(ColonyTag.values),
        throwsStateError,
      );
      expect(restarted.colonyTagOrder, reversed);
      await restarted.load();
      expect(restarted.colonyTagOrder, reversed);
    },
  );

  test(
    'unknown, missing and duplicate types preserve known saved order',
    () async {
      final store = _Store();
      store.values['colony_tag_order'] =
          '["price","future",null,1,"price","wildCatch"]';
      final preferences = AppPreferences(store);
      await preferences.load();
      expect(preferences.colonyTagOrder, [
        ColonyTag.price,
        ColonyTag.wildCatch,
        ColonyTag.newQueen,
        ColonyTag.scale,
        ColonyTag.nestType,
      ]);
      for (final invalid in ['bad json', '{}', 'null', '1', '[]']) {
        store.values.addAll({
          'colony_tag_order': invalid,
          'simple_mode': 'true',
        });
        await preferences.load();
        expect(preferences.colonyTagOrder, ColonyTag.values);
        expect(preferences.simpleMode, isTrue);
      }
    },
  );

  testWidgets('drag saves order, reset persists and failure restores rows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = _Store();
    final preferences = AppPreferences(store);
    await tester.pumpWidget(
      MaterialApp(home: ColonyTagSettingsPage(preferences: preferences)),
    );
    await tester.pumpAndSettle();
    final handles = find.byType(ReorderableDragStartListener);
    final start = tester.getCenter(handles.first);
    final end = tester.getCenter(handles.at(2));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveTo(end - const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(preferences.colonyTagOrder.take(3), [
      ColonyTag.wildCatch,
      ColonyTag.scale,
      ColonyTag.newQueen,
    ]);
    final restarted = AppPreferences(store);
    await restarted.load();
    expect(restarted.colonyTagOrder, preferences.colonyTagOrder);
    expect(
      tester.getTopLeft(find.text('蚁群规模')).dy,
      lessThan(tester.getTopLeft(find.text('新后群')).dy),
    );
    await tester.tap(find.text('恢复默认顺序'));
    await tester.pumpAndSettle();
    expect(preferences.colonyTagOrder, ColonyTag.values);
    await restarted.load();
    expect(restarted.colonyTagOrder, ColonyTag.values);
    store.failWrites = true;
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(4, 0);
    await tester.pumpAndSettle();
    expect(find.text('标签顺序保存失败，已恢复原顺序，请重试'), findsOneWidget);
    expect(preferences.colonyTagOrder, ColonyTag.values);
    expect(
      tester.getTopLeft(find.text('新后群')).dy,
      lessThan(tester.getTopLeft(find.text('价格档位')).dy),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('management page fits a narrow dark screen with larger text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: antKeepTheme(ThemeColor.forest, dark: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: ColonyTagSettingsPage(preferences: AppPreferences(_Store())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('价格档位'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('价格档位'), findsOneWidget);
  });
}
