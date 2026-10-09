import 'models.dart';

enum CareTaskType {
  feeding('feeding', '投喂', CareRecordType.feeding),
  watering('watering', '补水', CareRecordType.watering),
  cleaning('cleaning', '清洁', CareRecordType.cleaning);

  const CareTaskType(this.storageValue, this.label, this.recordType);
  final String storageValue;
  final String label;
  final CareRecordType recordType;

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
  });

  final String id;
  final String colonyId;
  final CareTaskType type;
  final int intervalDays;
  final DateTime nextDueOn;
  final DateTime? lastCompletedOn;

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
      );

  factory CareTask.fromMap(Map<String, Object?> row) {
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
      type: CareTaskType.fromStorage(row['task_type'] as String),
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
