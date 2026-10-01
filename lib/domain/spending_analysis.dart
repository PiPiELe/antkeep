class SpendingSummary {
  const SpendingSummary({
    required this.coloniesCents,
    required this.inventoryCents,
    required this.feedersCents,
    this.topEntries = const [],
  });

  final int coloniesCents;
  final int inventoryCents;
  final int feedersCents;
  final List<SpendingEntry> topEntries;

  int get totalCents => coloniesCents + inventoryCents + feedersCents;

  List<({String label, int cents})> get categories => [
    (label: '蚁群', cents: coloniesCents),
    (label: '已购物品', cents: inventoryCents),
    (label: 'DLC 养殖', cents: feedersCents),
  ];
}

class SpendingEntry {
  const SpendingEntry({
    required this.name,
    required this.category,
    required this.cents,
    this.occurredAt,
  });

  final String name;
  final String category;
  final int cents;
  final DateTime? occurredAt;
}
