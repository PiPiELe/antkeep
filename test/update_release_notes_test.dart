import 'package:antkeep/online/update_release_notes.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(String notes, {Future<bool> Function(Uri)? openUrl}) =>
      MaterialApp(
        home: Scaffold(
          body: UpdateReleaseNotes(notes: notes, openUrl: openUrl),
        ),
      );

  List<TextSpan> links(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(UpdateReleaseNotes),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.textSpan != null,
        ),
      ),
    );
    return (text.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .where((span) => span.recognizer != null)
        .toList();
  }

  testWidgets(
    'web and named links preserve notes and open external applications',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = tester.binding.defaultBinaryMessenger;
      MethodCall? launch;
      messenger.setMockMethodCallHandler(channel, (call) async {
        launch = call;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        app(
          '更新详情：https://example.com/news?a=1&b=2#changes。\n'
          '[使用指南](https://example.com/help)\nhttp://example.com/legacy.',
        ),
      );
      final spans = links(tester);
      expect(spans.map((span) => span.text), [
        'https://example.com/news?a=1&b=2#changes',
        '使用指南',
        'http://example.com/legacy',
      ]);
      // Tap the rendered named link, not only its callback.
      final richText = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(UpdateReleaseNotes),
          matching: find.byType(RichText),
        ),
      );
      final plainText = richText.text.toPlainText();
      final start = plainText.indexOf('使用指南');
      final box = richText
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 4),
          )
          .first;
      await tester.tapAt(richText.localToGlobal(box.toRect().center));
      await tester.pump();
      expect(launch!.method, 'launch');
      expect(launch!.arguments['url'], 'https://example.com/help');
      expect(launch!.arguments['useSafariVC'], isFalse);
      expect(launch!.arguments['useWebView'], isFalse);
      final refreshed = links(tester);
      (refreshed.first.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
      expect(
        launch!.arguments['url'],
        'https://example.com/news?a=1&b=2#changes',
      );
      expect(plainText, contains('。\n使用指南\n'));
    },
  );

  testWidgets('browser failures stay visible and a retry can succeed', (
    tester,
  ) async {
    var succeed = false;
    await tester.pumpWidget(
      app(
        'https://example.com',
        openUrl: (_) async {
          if (!succeed) throw Exception('no browser');
          return true;
        },
      ),
    );
    (links(tester).single.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(find.text('无法打开链接，请稍后重试。'), findsOneWidget);
    succeed = true;
    (links(tester).single.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(find.text('无法打开链接，请稍后重试。'), findsNothing);
  });

  testWidgets('non-web schemes and credential URLs remain plain text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        '[脚本](javascript:alert) file:///private/test intent://settings '
        'https://user:password@example.com',
      ),
    );
    expect(links(tester), isEmpty);
    await tester.pumpWidget(app('替换文案 https://example.com/new'));
    expect(links(tester).single.text, 'https://example.com/new');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
