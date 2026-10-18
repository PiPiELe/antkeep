/// Parses yuan without floating-point rounding; null means blank or invalid.
int? parsePurchasePrice(String value) {
  final text = value.trim();
  if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
  final cents = int.tryParse('${parts[0]}$fraction');
  // Keep cents exact on both native platforms and the web preview.
  return cents != null && cents <= 9007199254740991 ? cents : null;
}

String? formatPurchasePrice(int? cents) {
  if (cents == null) return null;
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

/// Derived from the colony's purchase price; never persisted as a value rating.
enum ColonyPriceTier {
  tens('十元级'),
  hundreds('百元级'),
  thousands('千元级'),
  tenThousands('万元级');

  const ColonyPriceTier(this.label);
  final String label;

  static ColonyPriceTier? fromCents(int? cents) {
    if (cents == null || cents < 1000) return null;
    if (cents < 10000) return tens;
    if (cents < 100000) return hundreds;
    if (cents < 1000000) return thousands;
    return tenThousands;
  }
}
