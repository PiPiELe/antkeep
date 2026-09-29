import 'package:antkeep/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beginner care notice rotates by day and contains one care item', () {
    final minimalDisturbance = beginnerCareNoticeFor(DateTime(2026, 9, 1));
    final temperature = beginnerCareNoticeFor(DateTime(2026, 9, 2));

    expect(minimalDisturbance.title, '尽量减少打扰');
    expect(temperature.title, '注意饲养温度');
    expect(minimalDisturbance.description, isNotEmpty);
    expect(temperature.description, isNotEmpty);
  });
}
