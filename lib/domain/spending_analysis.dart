class SpendingSummary {
  const SpendingSummary({
    required this.coloniesCents,
    required this.inventoryCents,
    required this.feedersCents,
  });

  final int coloniesCents;
  final int inventoryCents;
  final int feedersCents;

  int get totalCents => coloniesCents + inventoryCents + feedersCents;

  List<({String label, int cents})> get categories => [
    (label: '蚁群', cents: coloniesCents),
    (label: '已购物品', cents: inventoryCents),
    (label: 'DLC 养殖', cents: feedersCents),
  ];
}
