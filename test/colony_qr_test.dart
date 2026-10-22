import 'package:antkeep/domain/colony_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable local IDs round trip without private information', () {
    const id = '550e8400-e29b-41d4-a716-446655440000';
    expect(ColonyQr.decode(ColonyQr.encode(id)), id);
    expect(ColonyQr.encode(id), 'antkeep://colony/v1/$id');
  });

  test('rejects web links, unsupported versions and malformed references', () {
    for (final value in [
      '',
      'https://antkeep/colony/v1/123',
      'antkeep://colony/v2/123',
      'antkeep://evil/v1/123',
      'antkeep://colony/v1/',
      'antkeep://colony/v1/a/b',
      'antkeep://colony/v1/123?token=x',
      'antkeep://colony/v1/123#x',
      'antkeep://colony:80/v1/123',
      'antkeep://user@colony/v1/123',
      'antkeep://colony/v1/%31',
      'antkeep://colony/v1/%FF',
      'antkeep://colony/v1/..',
      'antkeep://colony/v1/${'a' * 129}',
    ]) {
      expect(ColonyQr.decode(value), isNull, reason: value);
    }
  });
}
