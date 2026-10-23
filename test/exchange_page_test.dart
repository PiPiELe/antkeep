import 'dart:convert';

import 'package:antkeep/online/exchange_page.dart';
import 'package:antkeep/online/online_api.dart';
import 'package:antkeep/online/online_controller.dart';
import 'package:antkeep/main.dart' show DiscoverPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'online_controller_test.dart'
    show MemoryOnlineStore, snapshot, summary, user;

class ExchangeApi extends OnlineApi {
  ExchangeApi() : super(baseUrl: 'https://api.example.test');
  Map<String, dynamic>? submitted;
  @override
  Future<String> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
  }) async {
    if (path == '/api/public/content') return snapshot();
    final uri = Uri.parse(path);
    if (uri.path == '/api/public/exchange-listings') {
      final items =
          <Map<String, dynamic>>[
            {
              'id': 'listing-1',
              'title': '新后群',
              'category': 'ANT',
              'species': '弓背蚁',
              'priceYuan': 28.5,
              'region': '北京市',
              'description': '仅作售卖信息展示',
              'status': 'APPROVED',
              'seller': 'keeper',
            },
            {
              'id': 'listing-2',
              'title': '试管巢',
              'category': 'ITEM',
              'species': null,
              'priceYuan': 12,
              'region': '上海市',
              'description': '适合小群使用',
              'status': 'APPROVED',
              'seller': 'keeper',
            },
          ].where((item) {
            final category = uri.queryParameters['category'] ?? '';
            final query = uri.queryParameters['query'] ?? '';
            return (category.isEmpty || item['category'] == category) &&
                (query.isEmpty ||
                    '${item['title']} ${item['species']} ${item['description']} ${item['region']}'
                        .contains(query));
          }).toList();
      return jsonEncode({'items': items, 'total': items.length, 'page': 1});
    }
    if (path == '/api/app/auth/login') {
      return jsonEncode({'token': 'exchange-token', 'user': user('keeper')});
    }
    if (path == '/api/app/check-ins/summary') return jsonEncode(summary(0));
    if (path == '/api/app/exchange-listings/mine') return '[]';
    if (path == '/api/app/exchange-listings' && method == 'POST') {
      submitted = body;
      return jsonEncode({'id': 'submitted', 'status': 'PENDING'});
    }
    throw StateError('Unexpected request: $method $path');
  }
}

void main() {
  testWidgets('discover hides exchange entries while paused', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DiscoverPage())),
    );
    expect(find.text('交易所'), findsNothing);
    expect(find.text('我的发布'), findsNothing);
    expect(find.text('蚂蚁百科'), findsOneWidget);
    expect(find.text('蚁友比赛'), findsOneWidget);
  });

  testWidgets('exchange only shows approved listings', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OnlineController(
      api: ExchangeApi(),
      store: MemoryOnlineStore(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ExchangePage(controller: controller)),
    );
    expect(find.textContaining(exchangeNotice), findsOneWidget);
    expect(find.textContaining('切换到在线版'), findsOneWidget);
    expect(find.text('新后群'), findsNothing);

    await controller.setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.text('新后群'), findsOneWidget);
    expect(find.text('发布售卖信息'), findsNothing);
    final warningTop = tester
        .getTopLeft(find.textContaining(exchangeNotice))
        .dy;
    final listingTop = tester.getTopLeft(find.text('新后群')).dy;
    expect(warningTop, lessThan(listingTop));
    expect(
      tester.widget<Text>(find.textContaining(exchangeNotice)).style?.fontSize,
      13,
    );
    final image = find.byKey(const ValueKey('exchange-image-listing-1'));
    expect(tester.getSize(image), const Size(108, 108));
    expect(
      tester.getTopLeft(image).dx,
      greaterThan(tester.getTopRight(find.text('新后群')).dx),
    );
    tester.view.physicalSize = const Size(900, 700);
    await tester.pumpAndSettle();
    expect(tester.getSize(image), const Size(136, 136));
    expect(
      tester.getTopLeft(image).dx,
      greaterThan(tester.getTopRight(find.text('新后群')).dx),
    );

    await controller.login('keeper', 'password123');
    await tester.pumpAndSettle();
    expect(find.text('发布售卖信息'), findsNothing);
    expect(find.text('新后群'), findsOneWidget);
  });

  testWidgets('my posts contains the publishing action', (tester) async {
    final controller = OnlineController(
      api: ExchangeApi(),
      store: MemoryOnlineStore(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ExchangePage(controller: controller, mine: true)),
    );
    await controller.setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.text('我的发布'), findsOneWidget);
    expect(find.text('新后群'), findsNothing);
    expect(find.text('登录 / 注册'), findsOneWidget);

    await controller.login('keeper', 'password123');
    await tester.pumpAndSettle();
    expect(find.text('发布售卖信息'), findsOneWidget);
    expect(find.text('交易信息'), findsNothing);
  });

  testWidgets('category, fuzzy search and list detail work together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OnlineController(
      api: ExchangeApi(),
      store: MemoryOnlineStore(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ExchangePage(controller: controller)),
    );
    await controller.setEnabled(true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部种类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('物品').last);
    await tester.pumpAndSettle();
    expect(find.text('新后群'), findsNothing);
    expect(find.text('试管巢'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '试管');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    final table = find.byType(DataTable);
    for (final heading in ['商品', '商品种类', '标价', '城市']) {
      expect(
        find.descendant(of: table, matching: find.text(heading)),
        findsOneWidget,
      );
    }
    final cityHeader = find.descendant(of: table, matching: find.text('城市'));
    expect(tester.getTopLeft(cityHeader).dx, lessThan(390));
    expect(
      tester.getTopLeft(find.text('上海市')).dx,
      closeTo(tester.getTopLeft(cityHeader).dx, 2),
    );
    await tester.tap(find.text('试管巢'));
    await tester.pumpAndSettle();
    expect(find.text('适合小群使用'), findsOneWidget);
    Navigator.of(tester.element(find.text('适合小群使用'))).pop();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(900, 700);
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('publishing asks for species only for ants', (tester) async {
    final api = ExchangeApi();
    final controller = OnlineController(api: api, store: MemoryOnlineStore());
    addTearDown(controller.dispose);
    await controller.setEnabled(true);
    await controller.login('keeper', 'password123');
    await tester.pumpWidget(
      MaterialApp(
        home: ExchangeSubmitPage(
          controller: controller,
          cityOptions: Future.value({
            '河北省': ['石家庄市'],
          }),
        ),
      ),
    );
    expect(find.text('蚂蚁品种'), findsOneWidget);
    await tester.tap(find.text('蚂蚁').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('物品').last);
    await tester.pumpAndSettle();
    expect(find.text('蚂蚁品种'), findsNothing);
    expect(find.text('商品种类'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '标题'), '试管巢');
    await tester.enterText(find.widgetWithText(TextFormField, '标价（元）'), '12');
    await tester.ensureVisible(find.text('手填城市'));
    await tester.tap(find.text('手填城市'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '城市'), '上海市');
    await tester.enterText(find.widgetWithText(TextFormField, '说明'), '适合小群');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交审核'));
    await tester.pumpAndSettle();
    expect(api.submitted?['category'], 'ITEM');
    expect(api.submitted?.containsKey('species'), false);
    expect(api.submitted?['region'], '上海市');
  });

  testWidgets('city picker submits province and city', (tester) async {
    final api = ExchangeApi();
    final controller = OnlineController(api: api, store: MemoryOnlineStore());
    addTearDown(controller.dispose);
    await controller.setEnabled(true);
    await controller.login('keeper', 'password123');
    await tester.pumpWidget(
      MaterialApp(
        home: ExchangeSubmitPage(
          controller: controller,
          cityOptions: Future.value({
            '河北省': ['石家庄市'],
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '标题'), '新后群');
    await tester.tap(find.widgetWithText(TextFormField, '蚂蚁品种'));
    await tester.pumpAndSettle();
    final speciesSearch = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(speciesSearch, '费氏弓背蚁');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '费氏弓背蚁'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '蚂蚁品种'))
          .controller!
          .text,
      '费氏弓背蚁',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '标价（元）'), '28.5');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('省份 / 直辖市'));
    await tester.tap(find.text('省份 / 直辖市'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('河北省').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('城市 / 地级区域'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('石家庄市').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '说明'), '仅供展示');
    await tester.ensureVisible(find.text('提交审核'));
    await tester.tap(find.text('提交审核'));
    await tester.pumpAndSettle();
    expect(api.submitted?['region'], '河北省 · 石家庄市');
    expect(api.submitted?['species'], '费氏弓背蚁');
  });

  testWidgets('unlisted ant species can still be entered manually', (
    tester,
  ) async {
    final controller = OnlineController(
      api: ExchangeApi(),
      store: MemoryOnlineStore(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ExchangeSubmitPage(controller: controller)),
    );
    await tester.tap(find.text('未收录？手动填写'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '蚂蚁品种'), '未收录品种');
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '蚂蚁品种'))
          .controller!
          .text,
      '未收录品种',
    );
    expect(find.text('从品种库选择'), findsOneWidget);
  });

  testWidgets('location city needs confirmation and submits no coordinates', (
    tester,
  ) async {
    final api = ExchangeApi();
    final controller = OnlineController(api: api, store: MemoryOnlineStore());
    addTearDown(controller.dispose);
    await controller.setEnabled(true);
    await controller.login('keeper', 'password123');
    await tester.pumpWidget(
      MaterialApp(
        home: ExchangeSubmitPage(
          controller: controller,
          locateCity: () async => '浙江省 · 杭州市',
          cityOptions: Future.value({
            '浙江省': ['杭州市'],
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '标题'), '试管巢');
    await tester.tap(find.text('蚂蚁').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('物品').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '标价（元）'), '12');
    await tester.scrollUntilVisible(
      find.text('获取定位填写城市'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('获取定位填写城市'));
    await tester.pumpAndSettle();
    expect(find.text('使用定位城市？'), findsOneWidget);
    await tester.tap(find.text('使用此城市'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '城市'), findsOneWidget);
    expect(find.text('浙江省 · 杭州市'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '说明'), '仅供展示');
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提交审核'));
    await tester.tap(find.text('提交审核'));
    await tester.pumpAndSettle();
    expect(api.submitted?['region'], '浙江省 · 杭州市');
    expect(api.submitted?.containsKey('latitude'), false);
    expect(api.submitted?.containsKey('longitude'), false);
  });
}
