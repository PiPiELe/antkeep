enum ColonyTag {
  newQueen('新后群', '档案起始工蚁数为 0 时显示'),
  wildCatch('野采', '野采来源或关联野采记录时显示'),
  scale('蚁群规模', '按当前工蚁数显示小群、中群、大群等'),
  nestType('巢体类型', '详情中的巢体标签，如试管巢'),
  price('价格档位', '按购入价显示十元级、百元级、千元级、万元级');

  const ColonyTag(this.label, this.description);
  final String label;
  final String description;

  /// Retain known saved types, discard duplicates, append any new types.
  static List<ColonyTag> normalizeOrder(Iterable<Object?> names) {
    final byName = {for (final tag in values) tag.name: tag};
    return List.unmodifiable({
      for (final name in names) ?byName[name],
      ...values,
    });
  }
}
