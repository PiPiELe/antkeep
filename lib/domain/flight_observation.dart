class FlightObservation {
  const FlightObservation({
    required this.id,
    required this.observedAt,
    required this.place,
    required this.createdAt,
    this.species,
    this.count,
    this.note,
  });

  final String id;
  final DateTime observedAt;
  final String place;
  final String? species;
  final int? count;
  final String? note;
  final DateTime createdAt;

  void validate() {
    if (id.isEmpty ||
        place.trim().isEmpty ||
        place.length > 100 ||
        (species?.length ?? 0) > 100 ||
        (note?.length ?? 0) > 500 ||
        (count != null && (count! < 0 || count! > 1000000))) {
      throw const FormatException('婚飞观察内容无效。');
    }
  }

  factory FlightObservation.fromMap(Map<String, Object?> row) {
    final entry = FlightObservation(
      id: row['id']! as String,
      observedAt: DateTime.parse(row['observed_at']! as String),
      place: row['place']! as String,
      species: row['species'] as String?,
      count: row['count'] as int?,
      note: row['note'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
    entry.validate();
    return entry;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'observed_at': observedAt.toIso8601String(),
    'place': place,
    'species': species,
    'count': count,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };
}
