enum MemorialKind {
  queen('蚁后死亡', '君王死社稷'),
  worker('工蚁死亡', '将士守山河'),
  brood('幼体夭折（幼虫／蛹／茧）', '未绽放的生命'),
  colony('整群结束', '遗失的文明');

  const MemorialKind(this.label, this.epitaph);
  final String label;
  final String epitaph;
}

class Memorial {
  const Memorial({
    required this.id,
    required this.kind,
    required this.name,
    required this.createdAt,
    this.colonyId,
    this.species,
    this.diedOn,
    this.farewell,
    this.cause,
    this.observation,
    this.lesson,
  });

  final String id;
  final MemorialKind kind;
  final String name;
  final String? colonyId;
  final String? species;
  final DateTime? diedOn;
  final String? farewell;
  final String? cause;
  final String? observation;
  final String? lesson;
  final DateTime createdAt;

  void validate() {
    if (id.isEmpty || name.trim().isEmpty) {
      throw const FormatException('请填写纪念名称。');
    }
  }

  factory Memorial.fromMap(Map<String, Object?> row) {
    final kinds = MemorialKind.values.where((k) => k.name == row['kind']);
    if (kinds.isEmpty) throw const FormatException('纪念类型无效。');
    final memorial = Memorial(
      id: row['id'] as String,
      kind: kinds.single,
      name: row['name'] as String,
      colonyId: row['colony_id'] as String?,
      species: row['species'] as String?,
      diedOn: row['died_on'] == null
          ? null
          : DateTime.parse(row['died_on'] as String),
      farewell: row['farewell'] as String?,
      cause: row['cause'] as String?,
      observation: row['observation'] as String?,
      lesson: row['lesson'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
    memorial.validate();
    return memorial;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'colony_id': colonyId,
    'species': species,
    'died_on': diedOn?.toIso8601String(),
    'farewell': farewell,
    'cause': cause,
    'observation': observation,
    'lesson': lesson,
    'created_at': createdAt.toIso8601String(),
  };
}
