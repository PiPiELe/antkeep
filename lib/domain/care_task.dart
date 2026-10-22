import 'models.dart';

enum CareTaskType {
  feeding('feeding', '投喂', CareRecordType.feeding),
  protein('feeding_protein', '蛋白', CareRecordType.feeding),
  sugar('feeding_sugar', '糖类', CareRecordType.feeding),
  seeds('feeding_seeds', '种子', CareRecordType.feeding),
  watering('watering', '补水', CareRecordType.watering),
  cleaning('cleaning', '清洁', CareRecordType.cleaning);

  const CareTaskType(this.storageValue, this.label, this.recordType);
  final String storageValue;
  final String label;
  final CareRecordType recordType;

  bool get isFeeding => recordType == CareRecordType.feeding;
  bool get isSplitFeeding => isFeeding && this != feeding;

  static CareTaskType fromStorage(String value) => values.firstWhere(
    (type) => type.storageValue == value,
    orElse: () => throw FormatException('无效的养护待办类型：$value'),
  );
}

class CareTask {
  const CareTask({
    required this.id,
    required this.colonyId,
    required this.type,
    required this.intervalDays,
    required this.nextDueOn,
    this.lastCompletedOn,
    this.lastFedAt,
    this.removalHours,
    this.removalDueAt,
  });

  final String id;
  final String colonyId;
  final CareTaskType type;
  final int intervalDays;
  final DateTime nextDueOn;
  final DateTime? lastCompletedOn;

  final DateTime? lastFedAt;

  /// Null means removal reminders are disabled for this food.
  final int? removalHours;
  final DateTime? removalDueAt;

  bool removalIsDue(DateTime now) =>
      removalDueAt != null && !removalDueAt!.isAfter(now);
  bool needsAttention(DateTime now) => isDue(now) || removalIsDue(now);
  String attentionLabel(DateTime now) =>
      removalIsDue(now) ? '${type.label}撤食' : type.label;

  bool isDue(DateTime now) => !DateTime(
    nextDueOn.year,
    nextDueOn.month,
    nextDueOn.day,
  ).isAfter(DateTime(now.year, now.month, now.day));

  CareTask copyWith({DateTime? nextDueOn, DateTime? lastCompletedOn}) =>
      CareTask(
        id: id,
        colonyId: colonyId,
        type: type,
        intervalDays: intervalDays,
        nextDueOn: nextDueOn ?? this.nextDueOn,
        lastCompletedOn: lastCompletedOn ?? this.lastCompletedOn,
        lastFedAt: lastFedAt,
        removalHours: removalHours,
        removalDueAt: removalDueAt,
      );

  factory CareTask.fromMap(Map<String, Object?> row) {
    final type = CareTaskType.fromStorage(row['task_type'] as String);
    final hours = row['removal_hours'] as int?;
    final fed = row['last_fed_at'] == null
        ? null
        : DateTime.parse(row['last_fed_at'] as String);
    final removal = row['removal_due_at'] == null
        ? null
        : DateTime.parse(row['removal_due_at'] as String);
    if (hours != null && (!type.isFeeding || hours < 1 || hours > 720)) {
      throw const FormatException('撤食时长需为 1～720 小时，且仅适用于投喂');
    }
    if ((!type.isFeeding && fed != null) ||
        (removal != null &&
            (hours == null || fed == null || !removal.isAfter(fed)))) {
      throw const FormatException('撤食计时状态无效');
    }
    final interval = row['interval_days'] as int;
    if (interval < 1 || interval > 365) {
      throw const FormatException('待办周期需为 1～365 天');
    }
    DateTime date(Object? value) {
      final parsed = DateTime.parse(value as String);
      if (parsed.hour != 0 || parsed.minute != 0 || parsed.second != 0) {
        throw const FormatException('待办日期格式无效');
      }
      return parsed;
    }

    return CareTask(
      id: row['id'] as String,
      colonyId: row['colony_id'] as String,
      type: type,
      lastFedAt: fed,
      removalHours: hours,
      removalDueAt: removal,
      intervalDays: interval,
      nextDueOn: date(row['next_due_on']),
      lastCompletedOn: row['last_completed_on'] == null
          ? null
          : date(row['last_completed_on']),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'colony_id': colonyId,
    'task_type': type.storageValue,
    'last_fed_at': lastFedAt?.toIso8601String(),
    'removal_hours': removalHours,
    'removal_due_at': removalDueAt?.toIso8601String(),
    'interval_days': intervalDays,
    'next_due_on': DateTime(
      nextDueOn.year,
      nextDueOn.month,
      nextDueOn.day,
    ).toIso8601String(),
    'last_completed_on': lastCompletedOn == null
        ? null
        : DateTime(
            lastCompletedOn!.year,
            lastCompletedOn!.month,
            lastCompletedOn!.day,
          ).toIso8601String(),
  };
}
