enum MilestoneArtwork {
  harvest('种群发展', 'stone-chronicle.jpg'),
  hunt('勇士狩猎-软体昆虫', 'ponerine-hunt.jpg'),
  beetleHunt('勇士狩猎-甲壳昆虫', 'beetle-hunt.jpg'),
  battle('种群之战', 'colony-battle.jpg'),
  brood('卵幼铺底', 'brood-nursery.jpg'),
  emergence('破茧新生', 'cocoon-emergence.jpg'),
  firstWorker('文明第一步', 'first-worker.jpg');

  const MilestoneArtwork(this.label, this.fileName);
  final String label;
  final String fileName;
  String get assetPath => 'assets/milestone/$fileName';

  static MilestoneArtwork fromStorage(Object? value) {
    if (value == null) return MilestoneArtwork.harvest;
    for (final artwork in values) {
      if (artwork.name == value) return artwork;
    }
    throw const FormatException('里程碑石刻画无效。');
  }
}

class Milestone {
  const Milestone({
    required this.id,
    this.colonyId,
    required this.title,
    required this.occurredAt,
    required this.createdAt,
    this.note,
    this.artwork = MilestoneArtwork.harvest,
  });

  final String id;
  final String? colonyId;
  final String title;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String? note;
  final MilestoneArtwork artwork;

  void validate() {
    if (id.isEmpty ||
        (colonyId?.isEmpty ?? false) ||
        title.trim().isEmpty ||
        title.trim().length > 80) {
      throw const FormatException('里程碑标题需为 1～80 字。');
    }
  }

  factory Milestone.fromMap(Map<String, Object?> map) {
    final milestone = Milestone(
      id: map['id']! as String,
      colonyId: map['colony_id'] as String?,
      title: map['title']! as String,
      occurredAt: DateTime.parse(map['occurred_at']! as String),
      createdAt: DateTime.parse(map['created_at']! as String),
      note: map['note'] as String?,
      artwork: MilestoneArtwork.fromStorage(map['artwork']),
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
    'artwork': artwork.name,
  };
}
