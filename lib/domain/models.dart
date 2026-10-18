import 'dart:convert';

import 'purchase_price.dart';
import 'colony_growth.dart';

class Colony {
  const Colony({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.species,
    this.acquiredOn,
    this.source,
    this.wildCatchLinked = false,
    this.purchasePriceCents,
    this.queenCount,
    this.specializedCount,
    this.showSpecialized = false,
    this.initialWorkerCount,
    this.initialEggCount,
    this.initialLarvaCount,
    this.initialCocoonCount,
    this._developmentPath,
    this.nestType,
    this.targetTemperatureLower,
    this.targetTemperature,
    this.targetHumidityLower,
    this.targetHumidity,
    this.coverPhotoPath,
    this.archived = false,
    this._growth,
  });

  final String id;
  final String name;
  final String? species;
  final DateTime? acquiredOn;
  final String? source;
  final bool wildCatchLinked;
  bool get isWildCatch =>
      wildCatchLinked ||
      RegExp(r'^野采(?:$|[（(\s])').hasMatch(source?.trim() ?? '');
  final int? purchasePriceCents;

  String? get purchasePriceText => formatPurchasePrice(purchasePriceCents);
  ColonyPriceTier? get priceTier =>
      ColonyPriceTier.fromCents(purchasePriceCents);
  final int? queenCount;
  final int? specializedCount;
  final bool showSpecialized;
  final int? initialWorkerCount;
  final int? initialEggCount;
  final int? initialLarvaCount;
  final int? initialCocoonCount;
  final GrowthPath? _developmentPath;
  GrowthPath get developmentPath =>
      _developmentPath ?? _growth?.path ?? GrowthPath.eggToCocoonToWorker;
  final String? nestType;
  final double? targetTemperatureLower;
  final double? targetTemperature;
  final double? targetHumidityLower;
  final double? targetHumidity;
  final String? coverPhotoPath;
  final bool archived;
  final ColonyGrowth? _growth;
  ColonyGrowth? get growth => _growth?.withPath(developmentPath);
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isNewQueenColony => initialWorkerCount == 0;

  ColonyScale? get scale => ColonyScale.fromWorkerCount(initialWorkerCount);

  /// Elapsed calendar days; unknown arrival dates stay unknown.
  int? husbandryDays(DateTime today) {
    final start = acquiredOn;
    if (start == null) return null;
    // Use date components in UTC so daylight-saving changes do not lose a day.
    final days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    return days < 0 ? 0 : days;
  }

  GrowthPopulation currentPopulation(Iterable<CareRecord> records) {
    final sorted = records.where((r) => r.colonyId == id).toList()
      ..sort(CareRecord.comparePopulationOrder);
    var eggs = initialEggCount;
    var larvae = initialLarvaCount;
    var cocoons = initialCocoonCount;
    var workers = initialWorkerCount;
    for (final record in sorted) {
      eggs = record.eggCount ?? eggs;
      larvae = record.larvaCount ?? larvae;
      cocoons = record.pupaCount ?? cocoons;
      workers = record.workerCountAfter(workers);
    }
    return GrowthPopulation(
      eggs: eggs,
      larvae: larvae,
      cocoons: cocoons,
      workers: workers,
    );
  }

  int? currentWorkerCount(Iterable<CareRecord> records) =>
      currentPopulation(records).workers;

  int? currentQueenCount(Iterable<CareRecord> records) {
    if (queenCount == null || queenCount! < 0) return null;
    var remaining = queenCount!;
    for (final record in records.where((r) => r.colonyId == id)) {
      remaining = record.queenDeaths > remaining
          ? 0
          : remaining - record.queenDeaths;
    }
    return remaining;
  }

  factory Colony.fromMap(
    Map<String, Object?> map, {
    bool wildCatchLinked = false,
  }) => Colony(
    id: map['id']! as String,
    name: map['name']! as String,
    species: map['species'] as String?,
    acquiredOn: _dateOrNull(map['acquired_on']),
    source: map['source'] as String?,
    wildCatchLinked: wildCatchLinked,
    purchasePriceCents: map['purchase_price_cents'] as int?,
    queenCount: map['queen_count'] as int?,
    specializedCount: map['specialized_count'] as int?,
    showSpecialized: (map['show_specialized'] as int? ?? 0) == 1,
    initialWorkerCount: map['initial_worker_count'] as int?,
    initialEggCount: map['initial_egg_count'] as int?,
    initialLarvaCount: map['initial_larva_count'] as int?,
    initialCocoonCount: map['initial_cocoon_count'] as int?,
    developmentPath: GrowthPath.fromStorage(map['development_path']),
    nestType: map['nest_type'] as String?,
    targetTemperatureLower: (map['target_temperature_lower'] as num?)
        ?.toDouble(),
    targetTemperature: (map['target_temperature'] as num?)?.toDouble(),
    targetHumidityLower: (map['target_humidity_lower'] as num?)?.toDouble(),
    targetHumidity: (map['target_humidity'] as num?)?.toDouble(),
    coverPhotoPath: map['cover_photo_path'] as String?,
    archived: (map['archived'] as int? ?? 0) == 1,
    growth: ColonyGrowth.decode(map['auto_growth_json']),
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'species': species,
    'acquired_on': acquiredOn?.toIso8601String(),
    'source': source,
    'purchase_price_cents': purchasePriceCents,
    'queen_count': queenCount,
    'specialized_count': specializedCount,
    'show_specialized': showSpecialized ? 1 : 0,
    'initial_worker_count': initialWorkerCount,
    'initial_egg_count': initialEggCount,
    'initial_larva_count': initialLarvaCount,
    'initial_cocoon_count': initialCocoonCount,
    'development_path': _developmentPath?.name,
    'nest_type': nestType,
    'target_temperature_lower': targetTemperatureLower,
    'target_temperature': targetTemperature,
    'target_humidity_lower': targetHumidityLower,
    'target_humidity': targetHumidity,
    'cover_photo_path': coverPhotoPath,
    'archived': archived ? 1 : 0,
    'auto_growth_json': growth?.encode(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

enum ColonyScale {
  small('小群'),
  medium('中群'),
  large('大群'),
  superLarge('超大群');

  const ColonyScale(this.label);
  final String label;

  static ColonyScale? fromWorkerCount(int? workers) {
    if (workers == null) return null;
    if (workers <= 100) return ColonyScale.small;
    if (workers < 500) return ColonyScale.medium;
    if (workers < 10000) return ColonyScale.large;
    return ColonyScale.superLarge;
  }
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
    this.workerMortalityCount,
    this.queenMortalityCount,
    this.feedingFood,
    this.feedingAmount,
    this.feedingResponse,
    this.feedingLeftovers,
    this.growthRule,
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
  final int? workerMortalityCount;
  final int? queenMortalityCount;
  final String? feedingFood;
  final String? feedingAmount;
  final FeedingResponse? feedingResponse;
  final bool? feedingLeftovers;

  /// Rule used for an automatic estimate; null means a user-entered snapshot.
  final ColonyGrowth? growthRule;
  final List<String> photos;
  final DateTime createdAt;

  /// Stable event ordering shared by current counts and quantity charts.
  static int comparePopulationOrder(CareRecord a, CareRecord b) {
    final time = a.occurredAt.compareTo(b.occurredAt);
    if (time != 0) return time;
    // A cycle settles after all observations made at its due time. This also
    // applies when an observation is entered later with the same event time.
    final aEstimate = a.isAutomaticGrowthEstimate;
    final bEstimate = b.isAutomaticGrowthEstimate;
    if (aEstimate != bEstimate) return aEstimate ? 1 : -1;
    final created = a.createdAt.compareTo(b.createdAt);
    return created != 0 ? created : a.id.compareTo(b.id);
  }

  bool get isAutomaticGrowthEstimate =>
      id.startsWith('growth:') &&
      type == CareRecordType.observation &&
      (note?.startsWith('自动扩充（估算）') ?? false);

  int get workerDeaths =>
      type == CareRecordType.mortality && (workerMortalityCount ?? 0) > 0
      ? workerMortalityCount!
      : 0;

  int get queenDeaths =>
      type == CareRecordType.mortality && (queenMortalityCount ?? 0) > 0
      ? queenMortalityCount!
      : 0;

  /// Explicit totals already include deaths; otherwise replay the death event.
  /// Unknown populations stay unknown and historical overcounts stop at zero.
  int? workerCountAfter(int? previous) {
    if (workerCount != null && workerCount! >= 0) return workerCount;
    if (previous == null || previous < 0) return null;
    return workerDeaths > previous ? 0 : previous - workerDeaths;
  }

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
    workerMortalityCount: map['worker_mortality_count'] as int?,
    queenMortalityCount: map['queen_mortality_count'] as int?,
    feedingFood: map['feeding_food'] as String?,
    feedingAmount: map['feeding_amount'] as String?,
    feedingResponse: map['feeding_response'] == null
        ? null
        : FeedingResponse.fromStorage(map['feeding_response'] as String),
    feedingLeftovers: switch (map['feeding_leftovers']) {
      null => null,
      0 => false,
      1 => true,
      _ => throw const FormatException('无效的剩余食物状态'),
    },
    growthRule: ColonyGrowth.decode(map['auto_growth_rule_json']),
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
    'worker_mortality_count': workerMortalityCount,
    'queen_mortality_count': queenMortalityCount,
    'feeding_food': feedingFood,
    'feeding_amount': feedingAmount,
    'feeding_response': feedingResponse?.storageValue,
    'feeding_leftovers': feedingLeftovers == null
        ? null
        : (feedingLeftovers! ? 1 : 0),
    'auto_growth_rule_json': growthRule?.encode(),
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
    this.purchasePriceCents,
    this.groupName,
    this.purpose,
    this.category,
    this.iconKey,
    this.supportsExpiry,
    this.specNote,
    this.batches,
    this.hidden = false,
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
  final int? purchasePriceCents;
  final String? groupName;
  final String? purpose;
  final bool hidden;
  final String? category;
  final String? iconKey;
  final bool? supportsExpiry;
  final String? specNote;
  // Null denotes a legacy row; an empty list denotes no acquisition records.
  final List<InventoryBatch>? batches;

  String get productName => groupLabel ?? name;
  bool get allowsExpiry =>
      supportsExpiry ?? expiryType != InventoryExpiryType.none;
  String get categoryLabel => category ?? defaultInventoryCategory(productName);
  List<InventoryBatch> get records =>
      batches ??
      [
        if (purchased)
          InventoryBatch(
            id: 'legacy-$id',
            quantity: quantity,
            costCents: purchasePriceCents,
            acquiredAt: purchasedAt,
            expiresAt: effectiveExpiryDate(),
            note: purpose,
          ),
      ];

  InventoryItem withRecords(List<InventoryBatch> records) {
    final dates =
        records
            .where((r) => r.quantity != 0 && r.expiresAt != null)
            .map((r) => r.expiresAt!)
            .toList()
          ..sort();
    final acquired =
        records
            .where((r) => r.acquiredAt != null)
            .map((r) => r.acquiredAt!)
            .toList()
          ..sort();
    final costs = records.where((r) => r.costCents != null).toList();
    return InventoryItem.fromMap({
      ...toMap(),
      'batches_json': jsonEncode(records.map((r) => r.toMap()).toList()),
      'supports_expiry': allowsExpiry ? 1 : 0,
      'purchased': records.isEmpty ? 0 : 1,
      'quantity': records.isEmpty || records.any((r) => r.quantity == null)
          ? null
          : records.fold<int>(0, (sum, r) => sum + r.quantity!),
      'purchase_price_cents': costs.isEmpty
          ? null
          : costs.fold<int>(0, (sum, r) => sum + r.costCents!),
      'purchased_at': acquired.isEmpty ? null : acquired.last.toIso8601String(),
      'expiry_type': dates.isEmpty ? 'none' : 'fixed_date',
      'expires_at': dates.isEmpty ? null : dates.first.toIso8601String(),
      'shelf_life_months': null,
    });
  }

  String? get groupLabel =>
      groupName ??
      (name.startsWith('离心管 ')
          ? '离心管'
          : name.startsWith('试管 ')
          ? '试管'
          : null);

  String get childLabel => groupName == null && groupLabel != null
      ? name.substring(groupLabel!.length).trim()
      : name;

  String get fullName => groupName == null ? name : '$groupName · $name';

  String? get purchasePriceText => formatPurchasePrice(purchasePriceCents);

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
    purchasePriceCents: map['purchase_price_cents'] as int?,
    groupName: map['group_name'] as String?,
    purpose: map['purpose'] as String?,
    hidden: map['hidden'] == 1,
    category: map['category'] as String?,
    iconKey: map['icon_key'] as String?,
    supportsExpiry: map['supports_expiry'] == null
        ? null
        : map['supports_expiry'] == 1,
    specNote: map['spec_note'] as String?,
    batches: map['batches_json'] == null
        ? null
        : InventoryBatch.decode(map['batches_json'] as String),
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
    'purchase_price_cents': purchasePriceCents,
    'group_name': groupName,
    'purpose': purpose,
    'hidden': hidden ? 1 : 0,
    'category': category,
    'icon_key': iconKey,
    'supports_expiry': supportsExpiry == null
        ? null
        : supportsExpiry!
        ? 1
        : 0,
    'spec_note': specNote,
    'batches_json': batches == null
        ? null
        : jsonEncode(batches!.map((r) => r.toMap()).toList()),
  };
}

const inventoryCategories = ['喂食', '工具', '环境', '巢室', '生活', '其他'];

String defaultInventoryCategory(String name) {
  if (RegExp('喂食|营养|色素|喂水').hasMatch(name)) return '喂食';
  if (RegExp('恒温|泡沫|温湿|防逃|小灯').hasMatch(name)) return '环境';
  if (RegExp('巢|试管|离心管|软管|海绵').hasMatch(name)) return '巢室';
  if (RegExp('棉|玻璃纸').hasMatch(name)) return '生活';
  return '工具';
}

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.quantity,
    required this.acquiredAt,
    this.costCents,
    this.expiresAt,
    this.note,
  });
  final String id;
  final int? quantity;
  final DateTime? acquiredAt;
  final int? costCents;
  final DateTime? expiresAt;
  final String? note;

  // Date-only expiry: a batch remains valid throughout its expiry day.
  int? daysRemaining([DateTime? now]) {
    if (expiresAt == null || quantity == 0) return null;
    final today = now ?? DateTime.now();
    return DateTime.utc(
      expiresAt!.year,
      expiresAt!.month,
      expiresAt!.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  }

  bool isExpired([DateTime? now]) => (daysRemaining(now) ?? 0) < 0;
  bool isExpiring([DateTime? now]) {
    final days = daysRemaining(now);
    return days != null && days >= 0 && days <= 7;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'quantity': quantity,
    'acquired_at': acquiredAt?.toIso8601String(),
    'cost_cents': costCents,
    'expires_at': expiresAt?.toIso8601String(),
    'note': note,
  };
  factory InventoryBatch.fromMap(Map<String, dynamic> map) {
    final batch = InventoryBatch(
      id: map['id'] as String,
      quantity: map['quantity'] as int?,
      costCents: map['cost_cents'] as int?,
      acquiredAt: _dateOrNull(map['acquired_at']),
      expiresAt: _dateOrNull(map['expires_at']),
      note: map['note'] as String?,
    );
    if (batch.id.isEmpty ||
        (batch.quantity ?? 0) < 0 ||
        (batch.costCents ?? 0) < 0 ||
        (batch.note?.length ?? 0) > 200) {
      throw const FormatException('入手记录格式无效');
    }
    return batch;
  }
  static List<InventoryBatch> decode(String source) {
    final ids = <String>{};
    final records = (jsonDecode(source) as List)
        .map(
          (entry) =>
              InventoryBatch.fromMap(Map<String, dynamic>.from(entry as Map)),
        )
        .toList();
    if (records.any((r) => !ids.add(r.id))) {
      throw const FormatException('入手记录 ID 重复');
    }
    return records;
  }
}

bool inventoryMatches(String query, Iterable<String?> values) {
  final needle = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (needle.isEmpty) return true;
  return values.any((value) {
    final text = (value ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    var index = 0;
    for (final char in needle.runes) {
      index = text.indexOf(String.fromCharCode(char), index);
      if (index < 0) return false;
      index++;
    }
    return true;
  });
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
    this.purchasePriceCents,
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
  final int? purchasePriceCents;

  String? get purchasePriceText => formatPurchasePrice(purchasePriceCents);
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
    purchasePriceCents: map['purchase_price_cents'] as int?,
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
    'purchase_price_cents': purchasePriceCents,
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
  cleaning('cleaning', '清洁'),
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

enum FeedingResponse {
  eager('eager', '进食积极'),
  normal('normal', '正常进食'),
  little('little', '少量进食'),
  refused('refused', '未进食'),
  unobserved('unobserved', '尚未观察');

  const FeedingResponse(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static FeedingResponse fromStorage(String value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => throw FormatException('无效的进食情况：$value'),
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
