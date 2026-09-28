import 'dart:convert';

class Colony {
  const Colony({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.species,
    this.acquiredOn,
    this.source,
    this.queenCount,
    this.initialWorkerCount,
    this.nestType,
    this.targetTemperature,
    this.targetHumidity,
    this.coverPhotoPath,
    this.archived = false,
  });

  final String id;
  final String name;
  final String? species;
  final DateTime? acquiredOn;
  final String? source;
  final int? queenCount;
  final int? initialWorkerCount;
  final String? nestType;
  final double? targetTemperature;
  final double? targetHumidity;
  final String? coverPhotoPath;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Colony.fromMap(Map<String, Object?> map) => Colony(
    id: map['id']! as String,
    name: map['name']! as String,
    species: map['species'] as String?,
    acquiredOn: _dateOrNull(map['acquired_on']),
    source: map['source'] as String?,
    queenCount: map['queen_count'] as int?,
    initialWorkerCount: map['initial_worker_count'] as int?,
    nestType: map['nest_type'] as String?,
    targetTemperature: (map['target_temperature'] as num?)?.toDouble(),
    targetHumidity: (map['target_humidity'] as num?)?.toDouble(),
    coverPhotoPath: map['cover_photo_path'] as String?,
    archived: (map['archived'] as int? ?? 0) == 1,
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'species': species,
    'acquired_on': acquiredOn?.toIso8601String(),
    'source': source,
    'queen_count': queenCount,
    'initial_worker_count': initialWorkerCount,
    'nest_type': nestType,
    'target_temperature': targetTemperature,
    'target_humidity': targetHumidity,
    'cover_photo_path': coverPhotoPath,
    'archived': archived ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class CareRecord {
  const CareRecord({
    required this.id,
    required this.colonyId,
    required this.type,
    required this.occurredAt,
    required this.createdAt,
    this.note,
    this.temperature,
    this.humidity,
    this.eggCount,
    this.larvaCount,
    this.pupaCount,
    this.workerCount,
    this.photos = const [],
  });

  final String id;
  final String colonyId;
  final CareRecordType type;
  final DateTime occurredAt;
  final String? note;
  final double? temperature;
  final double? humidity;
  final int? eggCount;
  final int? larvaCount;
  final int? pupaCount;
  final int? workerCount;
  final List<String> photos;
  final DateTime createdAt;

  factory CareRecord.fromMap(Map<String, Object?> map) => CareRecord(
    id: map['id']! as String,
    colonyId: map['colony_id']! as String,
    type: CareRecordType.fromStorage(map['record_type']! as String),
    occurredAt: DateTime.parse(map['occurred_at']! as String),
    note: map['note'] as String?,
    temperature: (map['temperature'] as num?)?.toDouble(),
    humidity: (map['humidity'] as num?)?.toDouble(),
    eggCount: map['egg_count'] as int?,
    larvaCount: map['larva_count'] as int?,
    pupaCount: map['pupa_count'] as int?,
    workerCount: map['worker_count'] as int?,
    photos: _stringList(map['photos_json']),
    createdAt: DateTime.parse(map['created_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'colony_id': colonyId,
    'record_type': type.storageValue,
    'occurred_at': occurredAt.toIso8601String(),
    'note': note,
    'temperature': temperature,
    'humidity': humidity,
    'egg_count': eggCount,
    'larva_count': larvaCount,
    'pupa_count': pupaCount,
    'worker_count': workerCount,
    'photos_json': jsonEncode(photos),
    'created_at': createdAt.toIso8601String(),
  };
}

enum CareRecordType {
  feeding('feeding', '投喂'),
  watering('watering', '补水'),
  observation('observation', '观察'),
  environment('environment', '环境'),
  relocation('relocation', '换巢'),
  brood('brood', '繁殖'),
  mortality('mortality', '死亡'),
  note('note', '其他记录');

  const CareRecordType(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static CareRecordType fromStorage(String value) => values.firstWhere(
    (type) => type.storageValue == value,
    orElse: () => CareRecordType.note,
  );
}

DateTime? _dateOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

List<String> _stringList(Object? value) {
  if (value is! String || value.isEmpty) return const [];
  return (jsonDecode(value) as List<dynamic>).cast<String>();
}
