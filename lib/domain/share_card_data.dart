import 'models.dart';

enum ShareCardKind {
  colony('蚁群名片'),
  diary('日记卡片'),
  comparison('成长对比'),
  monthly('养蚁月报');

  const ShareCardKind(this.label);
  final String label;
}

bool isEstimatedRecord(CareRecord record) =>
    record.note?.startsWith('自动扩充（估算）') ?? false;

DateTime shareDay(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime shareDayEnd(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day + 1,
).subtract(const Duration(microseconds: 1));
String shareDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

class ShareQuantity {
  const ShareQuantity(this.value, {this.estimated = false, this.recordedAt});
  final int? value;
  final bool estimated;
  final DateTime? recordedAt;
  String get text => value == null ? '未记录' : '$value${estimated ? '（估算）' : ''}';
}

class ShareSnapshot {
  const ShareSnapshot(this.quantities);
  final Map<String, ShareQuantity> quantities;
  ShareQuantity get workers => quantities['工蚁']!;
}

/// Use each stage's latest known snapshot; never add stored totals together.
ShareSnapshot shareSnapshot(
  Colony colony,
  Iterable<CareRecord> records,
  DateTime at,
) {
  final initialDate = shareDay(colony.acquiredOn ?? colony.createdAt);
  final initialKnown = !at.isBefore(initialDate);
  final values = <String, ShareQuantity>{
    '蚁后': ShareQuantity(initialKnown ? colony.queenCount : null),
    '工蚁': ShareQuantity(initialKnown ? colony.initialWorkerCount : null),
    '卵': ShareQuantity(initialKnown ? colony.initialEggCount : null),
    '幼虫': ShareQuantity(initialKnown ? colony.initialLarvaCount : null),
    '茧': ShareQuantity(initialKnown ? colony.initialCocoonCount : null),
  };
  final sorted =
      records
          .where((r) => r.colonyId == colony.id && !r.occurredAt.isAfter(at))
          .toList()
        ..sort((a, b) {
          final time = a.occurredAt.compareTo(b.occurredAt);
          if (time != 0) return time;
          final created = a.createdAt.compareTo(b.createdAt);
          return created != 0 ? created : a.id.compareTo(b.id);
        });
  for (final record in sorted) {
    final entries = {
      '工蚁': record.workerCount,
      '卵': record.eggCount,
      '幼虫': record.larvaCount,
      '茧': record.pupaCount,
    };
    for (final entry in entries.entries) {
      if (entry.value != null) {
        values[entry.key] = ShareQuantity(
          entry.value,
          estimated: isEstimatedRecord(record),
          recordedAt: record.occurredAt,
        );
      }
    }
  }
  return ShareSnapshot(values);
}

String shareWorkerChange(ShareQuantity before, ShareQuantity after) {
  if (before.value == null || after.value == null) return '工蚁变化：数据不足';
  final delta = after.value! - before.value!;
  return '工蚁 ${delta > 0 ? '+' : ''}$delta${before.estimated || after.estimated ? '（含估算）' : ''}';
}

class ShareMonth {
  ShareMonth(Colony colony, List<CareRecord> all, DateTime month, DateTime now)
    : start = DateTime(month.year, month.month) {
    final next = DateTime(month.year, month.month + 1);
    final monthEnd = next.subtract(const Duration(microseconds: 1));
    end = monthEnd.isAfter(now) ? now : monthEnd;
    records =
        all
            .where(
              (r) =>
                  r.colonyId == colony.id &&
                  !r.occurredAt.isBefore(start) &&
                  !r.occurredAt.isAfter(end),
            )
            .toList()
          ..sort((a, b) {
            final time = a.occurredAt.compareTo(b.occurredAt);
            return time != 0 ? time : a.createdAt.compareTo(b.createdAt);
          });
    final acquired = shareDay(colony.acquiredOn ?? colony.createdAt);
    // A colony acquired this month starts from its initial population.
    before = acquired.isBefore(start)
        ? shareSnapshot(
            colony,
            all,
            start.subtract(const Duration(microseconds: 1)),
          )
        : shareSnapshot(colony, const [], acquired);
    after = shareSnapshot(colony, all, end);
  }
  final DateTime start;
  late final DateTime end;
  late final List<CareRecord> records;
  late final ShareSnapshot before;
  late final ShareSnapshot after;
  int get diaryCount => records.where((r) => !isEstimatedRecord(r)).length;
  int get estimateCount => records.length - diaryCount;
  int get activeDays => records
      .where((r) => !isEstimatedRecord(r))
      .map((r) => shareDay(r.occurredAt))
      .toSet()
      .length;
  List<CareRecord> get workerRecords =>
      records.where((r) => r.workerCount != null).toList();
  List<String> get photos => records.expand((r) => r.photos).toSet().toList();
  String get change => records.isEmpty
      ? '工蚁变化：本月暂无记录'
      : shareWorkerChange(before.workers, after.workers);
}
