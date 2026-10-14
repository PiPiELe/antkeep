import 'dart:convert';

class WildCatchColony {
  const WildCatchColony({
    this.queenCount,
    this.workerCount,
    this.note,
    this.colonyId,
  });

  final int? queenCount;
  final int? workerCount;
  final String? note;
  final String? colonyId;

  WildCatchColony withColonyId(String? id) => WildCatchColony(
    queenCount: queenCount,
    workerCount: workerCount,
    note: note,
    colonyId: id,
  );

  void validate() {
    bool invalidCount(int? value) =>
        value != null && (value < 0 || value > 1000000);
    if (invalidCount(queenCount) ||
        invalidCount(workerCount) ||
        (note?.length ?? 0) > 300 ||
        (colonyId != null && colonyId!.trim().isEmpty)) {
      throw const FormatException('野采蚁群内容无效。');
    }
  }

  factory WildCatchColony.fromJson(Map<String, dynamic> json) {
    final colony = WildCatchColony(
      queenCount: json['queen_count'] as int?,
      workerCount: json['worker_count'] as int?,
      note: json['note'] as String?,
      colonyId: json['colony_id'] as String?,
    );
    colony.validate();
    return colony;
  }

  Map<String, Object?> toJson() => {
    'queen_count': queenCount,
    'worker_count': workerCount,
    'note': note,
    if (colonyId != null) 'colony_id': colonyId,
  };
}

class WildCatchSpecies {
  const WildCatchSpecies({required this.name, required this.colonies});

  final String name;
  final List<WildCatchColony> colonies;

  String get displayName => name.isEmpty ? '未填写品种' : name;

  void validate() {
    if ((name.isNotEmpty && name.trim().isEmpty) ||
        name.length > 100 ||
        colonies.isEmpty) {
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

class WildCatchEvent {
  const WildCatchEvent({
    required this.at,
    required this.action,
    required this.detail,
    this.photoPaths = const [],
  });

  final DateTime at;
  final String action;
  final String detail;
  final List<String> photoPaths;

  void validate() {
    if (action.isEmpty ||
        action.length > 40 ||
        detail.length > 600 ||
        photoPaths.any(
          (path) =>
              path.isEmpty ||
              path.contains('..') ||
              path.contains('/') ||
              path.contains('\\'),
        )) {
      throw const FormatException('野采时间线内容无效。');
    }
  }

  factory WildCatchEvent.fromJson(Map<String, dynamic> json) {
    final event = WildCatchEvent(
      at: DateTime.parse(json['at'] as String),
      action: json['action'] as String,
      detail: json['detail'] as String,
      photoPaths: (json['photo_paths'] as List? ?? const []).cast<String>(),
    );
    event.validate();
    return event;
  }

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'action': action,
    'detail': detail,
    'photo_paths': photoPaths,
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
    this.photos = const [],
    this.startedAt,
    this.endedAt,
    this.events = const [],
  });

  final String id;
  final DateTime caughtAt;
  final bool hasSpecificTime;
  final String place;
  final List<WildCatchSpecies> species;
  final String? note;
  final double? latitude;
  final double? longitude;
  final List<String> photos;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<WildCatchEvent> events;
  final DateTime createdAt;

  bool get isLive => startedAt != null;
  bool get isActive => startedAt != null && endedAt == null;

  WildCatchRecord withLiveChange({
    String? place,
    String? note,
    double? latitude,
    double? longitude,
    List<String>? photos,
    List<WildCatchSpecies>? species,
    DateTime? endedAt,
    WildCatchEvent? event,
  }) => WildCatchRecord(
    id: id,
    caughtAt: caughtAt,
    hasSpecificTime: hasSpecificTime,
    place: place ?? this.place,
    note: note ?? this.note,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    photos: photos ?? this.photos,
    species: species ?? this.species,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    events: event == null ? events : [...events, event],
    createdAt: createdAt,
  );

  void validate() {
    if (id.isEmpty ||
        (place.trim().isEmpty && !isActive) ||
        place.length > 100 ||
        (endedAt != null && startedAt == null) ||
        (startedAt != null &&
            endedAt != null &&
            endedAt!.isBefore(startedAt!)) ||
        (note?.length ?? 0) > 500 ||
        (!isLive && species.any((entry) => entry.name.isEmpty)) ||
        (latitude == null) != (longitude == null) ||
        (latitude != null &&
            (!latitude!.isFinite || latitude! < -90 || latitude! > 90)) ||
        (longitude != null &&
            (!longitude!.isFinite || longitude! < -180 || longitude! > 180)) ||
        photos.any(
          (photo) =>
              photo.isEmpty ||
              photo.contains('..') ||
              photo.contains('/') ||
              photo.contains('\\'),
        )) {
      throw const FormatException('野采记录内容无效。');
    }
    for (final entry in species) {
      entry.validate();
    }
    for (final event in events) {
      event.validate();
      if (startedAt == null || event.at.isBefore(startedAt!)) {
        throw const FormatException('野采时间线时间无效。');
      }
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
      photos: (jsonDecode(row['photos_json'] as String? ?? '[]') as List)
          .cast<String>(),
      startedAt: row['started_at'] == null
          ? null
          : DateTime.parse(row['started_at']! as String),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at']! as String),
      events: (jsonDecode(row['events_json'] as String? ?? '[]') as List)
          .map(
            (entry) => WildCatchEvent.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
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
    'photos_json': jsonEncode(photos),
    'started_at': startedAt?.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'events_json': jsonEncode(events.map((event) => event.toJson()).toList()),
    'created_at': createdAt.toIso8601String(),
  };
}
