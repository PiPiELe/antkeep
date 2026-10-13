import 'package:antkeep/domain/models.dart';
import 'package:antkeep/main.dart';
import 'package:antkeep/share_cards_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final picker = const MethodChannel('plugins.flutter.io/image_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final now = DateTime(2026, 10, 13);
  final colony = Colony(
    id: 'photo-source-colony',
    name: '测试蚁群',
    createdAt: now,
    updatedAt: now,
  );
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(picker, (call) async {
      calls.add(call);
      return call.method == 'pickMultiImage' ? <String>[] : null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(picker, null));

  testWidgets('diary photo offers camera and multi-select gallery', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: RecordFormPage(colony: colony)));
    await tester.scrollUntilVisible(
      find.text('添加照片（可选）'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('添加照片（可选）'));
    await tester.pumpAndSettle();
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从图库选择'), findsOneWidget);

    await tester.tap(find.text('拍照'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'pickImage');
    expect((calls.single.arguments as Map)['source'], ImageSource.camera.index);

    await tester.tap(find.text('添加照片（可选）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从图库选择'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'pickMultiImage');
  });

  testWidgets('share card photo offers camera and gallery', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShareCardsPage(colony: colony, records: [], now: now),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('照片 1'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('照片 1'));
    await tester.pumpAndSettle();
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从图库选择'), findsOneWidget);

    await tester.tap(find.text('拍照'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'pickImage');
    expect((calls.single.arguments as Map)['source'], ImageSource.camera.index);

    await tester.tap(find.text('照片 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从图库选择'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'pickImage');
    expect((calls.last.arguments as Map)['source'], ImageSource.gallery.index);
  });
}
