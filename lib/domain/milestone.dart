class Milestone {
  const Milestone({
    required this.id,
    required this.colonyId,
    required this.title,
    required this.occurredAt,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String colonyId;
  final String title;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String? note;

  void validate() {
    if (id.isEmpty ||
        colonyId.isEmpty ||
        title.trim().isEmpty ||
        title.trim().length > 80) {
      throw const FormatException('里程碑标题需为 1～80 字。');
    }
  }

  factory Milestone.fromMap(Map<String, Object?> map) {
    final milestone = Milestone(
      id: map['id']! as String,
      colonyId: map['colony_id']! as String,
      title: map['title']! as String,
      occurredAt: DateTime.parse(map['occurred_at']! as String),
      createdAt: DateTime.parse(map['created_at']! as String),
      note: map['note'] as String?,
    );
    milestone.validate();
    return milestone;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'colony_id': colonyId,
    'title': title.trim(),
    'occurred_at': occurredAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'note': note?.trim().isEmpty == true ? null : note?.trim(),
  };
}
