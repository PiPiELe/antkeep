import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/purchase_price.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('yuan is converted to exact cents and formatted with two decimals', () {
    for (final entry in {
      '0': 0,
      '12': 1200,
      '12.3': 1230,
      '0.29': 29,
      ' 001.01 ': 101,
    }.entries) {
      expect(parsePurchasePrice(entry.key), entry.value);
      expect(
        parsePurchasePrice(formatPurchasePrice(entry.value)!),
        entry.value,
      );
    }
    expect(formatPurchasePrice(0), '0.00');
    expect(formatPurchasePrice(null), isNull);
  });

  test('invalid or unsafe amounts are rejected without silent rounding', () {
    for (final value in [
      '',
      ' ',
      '-1',
      'NaN',
      'Infinity',
      '1e2',
      '1.234',
      '12.',
      '.29',
      'abc',
      '90071992547409.92',
    ]) {
      expect(parsePurchasePrice(value), isNull, reason: value);
    }
  });

  test('missing purchase price remains unknown in legacy records', () {
    final now = DateTime(2026, 9, 29);
    final colony = Colony(id: 'c', name: 'c', createdAt: now, updatedAt: now);
    final colonyMap = colony.toMap()..remove('purchase_price_cents');
    expect(Colony.fromMap(colonyMap).purchasePriceCents, isNull);
    final feeder = FeederRecord(
      id: 'f',
      feeder: FeederType.dubia,
      type: FeederRecordType.observation,
      occurredAt: now,
      createdAt: now,
    );
    final feederMap = feeder.toMap()..remove('purchase_price_cents');
    expect(FeederRecord.fromMap(feederMap).purchasePriceCents, isNull);
  });
}
