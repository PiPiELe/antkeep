import 'models.dart';
import 'population_analysis.dart';

/// Deaths are events: multiple records on the same local day are added together.
/// Unknown counts, other colonies, other event types and future events are omitted.
List<PopulationPoint> dailyWorkerMortality(
  String colonyId,
  Iterable<CareRecord> records, {
  required DateTime now,
}) {
  final totals = <DateTime, int>{};
  for (final record in records) {
    final count = record.workerMortalityCount;
    if (record.colonyId != colonyId ||
        record.type != CareRecordType.mortality ||
        count == null ||
        count < 0 ||
        record.occurredAt.isAfter(now)) {
      continue;
    }
    final time = record.occurredAt.toLocal();
    final day = DateTime(time.year, time.month, time.day);
    totals.update(day, (total) => total + count, ifAbsent: () => count);
  }
  return [
    for (final entry in totals.entries) PopulationPoint(entry.key, entry.value),
  ]..sort((a, b) => a.time.compareTo(b.time));
}

class MortalityComparison {
  MortalityComparison(List<PopulationPoint> days, {required DateTime now}) {
    final local = now.toLocal();
    end = DateTime(local.year, local.month, local.day);
    recentStart = DateTime(local.year, local.month, local.day - 7);
    previousStart = DateTime(local.year, local.month, local.day - 14);
    for (final point in days) {
      if (point.time.isBefore(previousStart) || !point.time.isBefore(end)) {
        continue;
      }
      if (point.time.isBefore(recentStart)) {
        previousTotal += point.count;
        previousDays++;
      } else {
        recentTotal += point.count;
        recentDays++;
      }
    }
  }

  late final DateTime previousStart;
  late final DateTime recentStart;
  late final DateTime end;
  int previousTotal = 0;
  int recentTotal = 0;
  int previousDays = 0;
  int recentDays = 0;
  bool get comparable => previousDays > 0 && recentDays > 0;
  int get delta => recentTotal - previousTotal;
  double? get percent =>
      comparable && previousTotal > 0 ? delta / previousTotal * 100 : null;
  String get label => !comparable
      ? '数据不足，暂无法比较'
      : delta > 0
      ? '已记录死亡量上升'
      : delta < 0
      ? '已记录死亡量下降'
      : '已记录死亡量持平';
}
