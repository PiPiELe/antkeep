import 'dart:convert';

class WildCatchColony {
  const WildCatchColony({this.queenCount, this.workerCount, this.note});

  final int? queenCount;
  final int? workerCount;
  final String? note;

  void validate() {
    bool invalidCount(int? value) =>
        value != null && (value < 0 || value > 1000000);
    if (invalidCount(queenCount) ||
        invalidCount(workerCount) ||
        (note?.length ?? 0) > 300) {
      throw const FormatException('野采蚁群内容无效。');
    }
  }

  factory WildCatchColony.fromJson(Map<String, dynamic> json) {
    final colony = WildCatchColony(
      queenCount: json['queen_count'] as int?,
      workerCount: json['worker_count'] as int?,
      note: json['note'] as String?,
    );
    colony.validate();
    return colony;
  }

  Map<String, Object?> toJson() => {
    'queen_count': queenCount,
    'worker_count': workerCount,
    'note': note,
  };
}

class WildCatchSpecies {
  const WildCatchSpecies({required this.name, required this.colonies});

  final String name;
  final List<WildCatchColony> colonies;

  void validate() {
    if (name.trim().isEmpty || name.length > 100 || colonies.isEmpty) {
      throw const FormatException('野采蚁种或蚁群内容无效。');
    }
    for (final colony in colonies) {
      colony.validate();
    }
  }

  factory WildCatchSpecies.fromJson(Map<String, dynamic> json) {
    final species = WildCatchSpecies(
      name: json['name'] as String,
      colonies: (json['colonies'] as List)
          .map(
            (row) =>
                WildCatchColony.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
    );
    species.validate();
    return species;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'colonies': colonies.map((colony) => colony.toJson()).toList(),
  };
}

class WildCatchRecord {
  const WildCatchRecord({
    required this.id,
    required this.caughtAt,
    required this.place,
    required this.createdAt,
    required this.species,
    this.hasSpecificTime = false,
    this.note,
    this.latitude,
    this.longitude,
  });

  final String id;
  final DateTime caughtAt;
  final bool hasSpecificTime;
  final String place;
  final List<WildCatchSpecies> species;
  final String? note;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  void validate() {
    if (id.isEmpty ||
        place.trim().isEmpty ||
        place.length > 100 ||
        (note?.length ?? 0) > 500 ||
        (latitude == null) != (longitude == null) ||
        (latitude != null &&
            (!latitude!.isFinite || latitude! < -90 || latitude! > 90)) ||
        (longitude != null &&
            (!longitude!.isFinite || longitude! < -180 || longitude! > 180))) {
      throw const FormatException('野采记录内容无效。');
    }
    for (final entry in species) {
      entry.validate();
    }
  }

  factory WildCatchRecord.fromMap(Map<String, Object?> row) {
    final record = WildCatchRecord(
      id: row['id']! as String,
      caughtAt: DateTime.parse(row['caught_at']! as String),
      hasSpecificTime: (row['has_specific_time'] as int? ?? 0) == 1,
      place: row['place']! as String,
      species: (jsonDecode(row['species_json']! as String) as List)
          .map(
            (entry) => WildCatchSpecies.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
      note: row['note'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(row['created_at']! as String),
    );
    record.validate();
    return record;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'caught_at': caughtAt.toIso8601String(),
    'has_specific_time': hasSpecificTime ? 1 : 0,
    'place': place,
    'species_json': jsonEncode(species.map((entry) => entry.toJson()).toList()),
    'note': note,
    'latitude': latitude,
    'longitude': longitude,
    'created_at': createdAt.toIso8601String(),
  };
}
