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
    this.specializedCount,
    this.showSpecialized = false,
    this.initialWorkerCount,
    this.initialEggCount,
    this.initialCocoonCount,
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
  final int? specializedCount;
  final bool showSpecialized;
  final int? initialWorkerCount;
  final int? initialEggCount;
  final int? initialCocoonCount;
  final String? nestType;
  final double? targetTemperature;
  final double? targetHumidity;
  final String? coverPhotoPath;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isNewQueenColony => initialWorkerCount == 0;

  ColonyScale? get scale {
    if (isNewQueenColony) return ColonyScale.newQueen;
    final workers = initialWorkerCount;
    if (workers == null) return null;
    if (workers <= 100) return ColonyScale.small;
    if (workers < 500) return ColonyScale.medium;
    if (workers < 10000) return ColonyScale.large;
    return ColonyScale.superLarge;
  }

  factory Colony.fromMap(Map<String, Object?> map) => Colony(
    id: map['id']! as String,
    name: map['name']! as String,
    species: map['species'] as String?,
    acquiredOn: _dateOrNull(map['acquired_on']),
    source: map['source'] as String?,
    queenCount: map['queen_count'] as int?,
    specializedCount: map['specialized_count'] as int?,
    showSpecialized: (map['show_specialized'] as int? ?? 0) == 1,
    initialWorkerCount: map['initial_worker_count'] as int?,
    initialEggCount: map['initial_egg_count'] as int?,
    initialCocoonCount: map['initial_cocoon_count'] as int?,
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
    'specialized_count': specializedCount,
    'show_specialized': showSpecialized ? 1 : 0,
    'initial_worker_count': initialWorkerCount,
    'initial_egg_count': initialEggCount,
    'initial_cocoon_count': initialCocoonCount,
    'nest_type': nestType,
    'target_temperature': targetTemperature,
    'target_humidity': targetHumidity,
    'cover_photo_path': coverPhotoPath,
    'archived': archived ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

enum ColonyScale {
  newQueen('新后群'),
  small('小群'),
  medium('中群'),
  large('大群'),
  superLarge('超大群');

  const ColonyScale(this.label);
  final String label;
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

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.purchased,
    required this.createdAt,
    this.expiryType = InventoryExpiryType.none,
    this.shelfLifeMonths,
    this.purchasedAt,
    this.expiresAt,
    this.quantity,
  });

  final String id;
  final String name;
  final bool purchased;
  final DateTime createdAt;
  final InventoryExpiryType expiryType;
  final int? shelfLifeMonths;
  final DateTime? purchasedAt;
  final DateTime? expiresAt;
  final int? quantity;

  DateTime? effectiveExpiryDate() => switch (expiryType) {
    InventoryExpiryType.none => null,
    InventoryExpiryType.shelfLife =>
      purchasedAt == null || shelfLifeMonths == null
          ? null
          : _addMonths(purchasedAt!, shelfLifeMonths!),
    InventoryExpiryType.fixedDate => expiresAt,
  };

  bool isExpired([DateTime? now]) {
    final expiry = effectiveExpiryDate();
    return expiry != null && expiry.isBefore(now ?? DateTime.now());
  }

  factory InventoryItem.fromMap(Map<String, Object?> map) => InventoryItem(
    id: map['id']! as String,
    name: map['name']! as String,
    purchased: (map['purchased'] as int? ?? 0) == 1,
    createdAt: DateTime.parse(map['created_at']! as String),
    expiryType: InventoryExpiryType.fromStorage(
      map['expiry_type'] as String? ?? InventoryExpiryType.none.storageValue,
    ),
    shelfLifeMonths: map['shelf_life_months'] as int?,
    purchasedAt: _dateOrNull(map['purchased_at']),
    expiresAt: _dateOrNull(map['expires_at']),
    quantity: map['quantity'] as int?,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'purchased': purchased ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'expiry_type': expiryType.storageValue,
    'shelf_life_months': shelfLifeMonths,
    'purchased_at': purchasedAt?.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'quantity': quantity,
  };
}

enum InventoryExpiryType {
  none('none', '无有效期'),
  shelfLife('shelf_life', '按购入后保质期'),
  fixedDate('fixed_date', '指定到期日');

  const InventoryExpiryType(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static InventoryExpiryType fromStorage(String value) => values.firstWhere(
    (type) => type.storageValue == value,
    orElse: () => InventoryExpiryType.none,
  );
}

class FeederRecord {
  const FeederRecord({
    required this.id,
    required this.feeder,
    required this.type,
    required this.occurredAt,
    required this.createdAt,
    this.note,
    this.temperature,
    this.humidity,
    this.juvenileCount,
    this.adultCount,
    this.mortalityCount,
  });

  final String id;
  final FeederType feeder;
  final FeederRecordType type;
  final DateTime occurredAt;
  final String? note;
  final double? temperature;
  final double? humidity;
  final int? juvenileCount;
  final int? adultCount;
  final int? mortalityCount;
  final DateTime createdAt;

  factory FeederRecord.fromMap(Map<String, Object?> map) => FeederRecord(
    id: map['id']! as String,
    feeder: FeederType.fromStorage(map['feeder_type']! as String),
    type: FeederRecordType.fromStorage(map['record_type']! as String),
    occurredAt: DateTime.parse(map['occurred_at']! as String),
    note: map['note'] as String?,
    temperature: (map['temperature'] as num?)?.toDouble(),
    humidity: (map['humidity'] as num?)?.toDouble(),
    juvenileCount: map['juvenile_count'] as int?,
    adultCount: map['adult_count'] as int?,
    mortalityCount: map['mortality_count'] as int?,
    createdAt: DateTime.parse(map['created_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'feeder_type': feeder.storageValue,
    'record_type': type.storageValue,
    'occurred_at': occurredAt.toIso8601String(),
    'note': note,
    'temperature': temperature,
    'humidity': humidity,
    'juvenile_count': juvenileCount,
    'adult_count': adultCount,
    'mortality_count': mortalityCount,
    'created_at': createdAt.toIso8601String(),
  };
}

enum FeederType {
  dubia('dubia', '杜比亚'),
  cherryRoach('cherry_roach', '樱桃蟑螂'),
  mealworm('mealworm', '面包虫'),
  cricket('cricket', '蛐蛐');

  const FeederType(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static FeederType fromStorage(String value) => values.firstWhere(
    (type) => type.storageValue == value,
    orElse: () => FeederType.dubia,
  );
}

enum FeederRecordType {
  observation('observation', '观察'),
  feeding('feeding', '投喂'),
  cleaning('cleaning', '清洁'),
  breeding('breeding', '繁殖'),
  mortality('mortality', '死亡');

  const FeederRecordType(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static FeederRecordType fromStorage(String value) => values.firstWhere(
    (type) => type.storageValue == value,
    orElse: () => FeederRecordType.observation,
  );
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

DateTime _addMonths(DateTime value, int months) {
  final offset = value.month - 1 + months;
  final year = value.year + offset ~/ 12;
  final month = offset % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(
    year,
    month,
    value.day > lastDay ? lastDay : value.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}

List<String> _stringList(Object? value) {
  if (value is! String || value.isEmpty) return const [];
  return (jsonDecode(value) as List<dynamic>).cast<String>();
}
