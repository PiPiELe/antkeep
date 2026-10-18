import 'package:antkeep/domain/models.dart';
import 'package:antkeep/domain/purchase_price.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('colony price tiers use exact cent boundaries', () {
    for (final entry in <int?, ColonyPriceTier?>{
      null: null,
      -1: null,
      0: null,
      999: null,
      1000: ColonyPriceTier.tens,
      9999: ColonyPriceTier.tens,
      10000: ColonyPriceTier.hundreds,
      99999: ColonyPriceTier.hundreds,
      100000: ColonyPriceTier.thousands,
      999999: ColonyPriceTier.thousands,
      1000000: ColonyPriceTier.tenThousands,
      9007199254740991: ColonyPriceTier.tenThousands,
    }.entries) {
      expect(
        ColonyPriceTier.fromCents(entry.key),
        entry.value,
        reason: '${entry.key} cents',
      );
    }
  });

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
