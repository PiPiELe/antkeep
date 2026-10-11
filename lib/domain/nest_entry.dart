class NestEntry {
  const NestEntry({
    required this.id,
    required this.colonyId,
    required this.nestType,
    required this.createdAt,
    this.name,
    this.startedOn,
    this.note,
    this.isCurrent = false,
  });

  final String id;
  final String colonyId;
  final String nestType;
  final String? name;
  final DateTime? startedOn;
  final String? note;
  final bool isCurrent;
  final DateTime createdAt;

  void validate() {
    if (id.isEmpty ||
        colonyId.isEmpty ||
        nestType.trim().isEmpty ||
        nestType.length > 80 ||
        (name?.length ?? 0) > 80 ||
        (note?.length ?? 0) > 500) {
      throw const FormatException('巢体记录内容无效。');
    }
  }

  factory NestEntry.fromMap(Map<String, Object?> row) {
    final entry = NestEntry(
      id: row['id']! as String,
      colonyId: row['colony_id']! as String,
      nestType: row['nest_type']! as String,
      name: row['name'] as String?,
      startedOn: row['started_on'] == null
          ? null
          : DateTime.parse(row['started_on']! as String),
      note: row['note'] as String?,
      isCurrent: row['is_current'] == 1,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
    entry.validate();
    return entry;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'colony_id': colonyId,
    'nest_type': nestType,
    'name': name,
    'started_on': startedOn?.toIso8601String(),
    'note': note,
    'is_current': isCurrent ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };
}
