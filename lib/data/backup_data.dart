import '../domain/models.dart';

/// Validate before touching either the live data or the previous rollback copy.
/// Model readers check field types and dates; the remaining checks mirror the
/// database constraints. Missing optional columns/tables support older backups.
class BackupData {
  BackupData._();

  static void validate(Map<String, dynamic> data) {
    final colonies = _rows(
      data,
      'colonies',
      (row) => Colony.fromMap(row).toMap(),
      required: true,
    );
    final records = _rows(
      data,
      'care_records',
      (row) => CareRecord.fromMap(row).toMap(),
      required: true,
    );
    _rows(data, 'feeder_records', (row) => FeederRecord.fromMap(row).toMap());
    final items = _rows(
      data,
      'inventory_items',
      (row) => InventoryItem.fromMap(row).toMap(),
    );
    final colonyIds = colonies.map((row) => row['id']).toSet();
    if (records.any((row) => !colonyIds.contains(row['colony_id']))) {
      throw const FormatException('备份中有记录引用了不存在的蚁群。');
    }
    final names = <(String, String)>{};
    for (final item in items) {
      if (!names.add((
        item['group_name'] as String? ?? '',
        item['name'] as String,
      ))) {
        throw const FormatException('备份中同一分组的物品名称重复。');
      }
    }
  }

  static List<Map<String, Object?>> _rows(
    Map<String, dynamic> data,
    String table,
    Map<String, Object?> Function(Map<String, Object?>) read, {
    bool required = false,
  }) {
    final entries = data[table];
    if (!required && entries == null) return const [];
    if (entries is! List) throw FormatException('备份表 $table 格式无效。');
    final ids = <String>{};
    final rows = <Map<String, Object?>>[];
    for (final entry in entries) {
      try {
        final row = Map<String, Object?>.from(entry as Map);
        final model = read(row);
        final id = row['id'] as String;
        if (id.isEmpty || !ids.add(id)) {
          throw const FormatException('记录 ID 为空或重复。');
        }
        for (final field in row.entries) {
          final value = field.value;
          if (!model.containsKey(field.key) ||
              (value == null && model[field.key] != null) ||
              (field.key == 'photos_json' && value is! String)) {
            throw FormatException('字段 ${field.key} 无效。');
          }
          if (value is num && !value.isFinite) {
            throw FormatException('字段 ${field.key} 不是有效数字。');
          }
          if ((field.key == 'quantity' ||
                  field.key == 'purchase_price_cents') &&
              value is int &&
              value < 0) {
            throw FormatException('字段 ${field.key} 不能为负数。');
          }
          if (const {
                'archived',
                'show_specialized',
                'purchased',
                'record_type',
                'feeder_type',
                'expiry_type',
              }.contains(field.key) &&
              value != model[field.key]) {
            throw FormatException('字段 ${field.key} 的取值无效。');
          }
        }
        rows.add(row);
      } on FormatException catch (error) {
        throw FormatException('备份表 $table 数据无效：${error.message}');
      } on TypeError {
        throw FormatException('备份表 $table 缺少必要字段或字段类型错误。');
      }
    }
    return rows;
  }
}
