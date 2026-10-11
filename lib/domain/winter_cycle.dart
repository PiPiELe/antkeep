class WinterCycle {
  const WinterCycle({
    required this.id,
    required this.colonyId,
    required this.startedOn,
    required this.createdAt,
    this.plannedEndOn,
    this.endedOn,
    this.note,
  });

  final String id;
  final String colonyId;
  final DateTime startedOn;
  final DateTime? plannedEndOn;
  final DateTime? endedOn;
  final String? note;
  final DateTime createdAt;

  void validate() {
    if (id.isEmpty ||
        colonyId.isEmpty ||
        (note?.length ?? 0) > 500 ||
        (plannedEndOn != null && plannedEndOn!.isBefore(startedOn)) ||
        (endedOn != null && endedOn!.isBefore(startedOn))) {
      throw const FormatException('越冬周期内容或日期无效。');
    }
  }

  factory WinterCycle.fromMap(Map<String, Object?> row) {
    final cycle = WinterCycle(
      id: row['id']! as String,
      colonyId: row['colony_id']! as String,
      startedOn: DateTime.parse(row['started_on']! as String),
      plannedEndOn: row['planned_end_on'] == null
          ? null
          : DateTime.parse(row['planned_end_on']! as String),
      endedOn: row['ended_on'] == null
          ? null
          : DateTime.parse(row['ended_on']! as String),
      note: row['note'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
    cycle.validate();
    return cycle;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'colony_id': colonyId,
    'started_on': startedOn.toIso8601String(),
    'planned_end_on': plannedEndOn?.toIso8601String(),
    'ended_on': endedOn?.toIso8601String(),
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };
}
