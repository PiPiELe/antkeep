import 'dart:math';

import 'package:antkeep/domain/beginner_care_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'random selection covers bundled notices without consecutive repeats',
    () {
      final random = Random(42);
      final seen = <String>{};
      BeginnerCareNotice? previous;
      for (var i = 0; i < 200; i++) {
        final notice = randomBeginnerCareNotice(
          previous: previous,
          random: random,
        );
        expect(notice.id, isNot(previous?.id));
        expect(notice.title, isNotEmpty);
        expect(notice.description, isNotEmpty);
        seen.add(notice.id);
        previous = notice;
      }
      expect(
        seen,
        bundledBeginnerCareNotices.map((notice) => notice.id).toSet(),
      );
      expect(seen.length, 8);
    },
  );

  test('empty pool falls back and a single notice stays usable', () {
    expect(
      bundledBeginnerCareNotices,
      contains(randomBeginnerCareNotice(notices: [])),
    );
    const notice = BeginnerCareNotice(
      id: 'only',
      title: '标题',
      description: '正文',
    );
    expect(
      randomBeginnerCareNotice(notices: [notice], previous: notice),
      same(notice),
    );
  });

  test('reloaded objects still exclude the previous stable id', () {
    const previous = BeginnerCareNotice(
      id: 'a',
      title: '旧标题',
      description: '正文',
    );
    const updated = BeginnerCareNotice(
      id: 'a',
      title: '新标题',
      description: '正文',
    );
    const other = BeginnerCareNotice(id: 'b', title: '另一条', description: '正文');
    expect(
      randomBeginnerCareNotice(notices: [updated, other], previous: previous),
      same(other),
    );
  });
}
