import 'dart:math' as math;

import 'colony_growth.dart';
import 'models.dart';

/// Resolve a manual stage increment to a snapshot at the event's time.
/// All transfers are simultaneous, so newly entered stages can feed later ones.
CareRecord resolveRecordIncrement(
  Colony colony,
  Iterable<CareRecord> history,
  CareRecord record,
) {
  final base = colony.currentPopulation(
    history.where((r) => !r.occurredAt.isAfter(record.occurredAt)),
  );
  final withCocoons = colony.developmentPath == GrowthPath.eggToCocoonToWorker;
  final inputs = [
    record.eggCount,
    record.larvaCount,
    record.pupaCount,
    record.workerCount,
  ];
  if (inputs.any((n) => n != null && (n < 0 || n > 1000000))) {
    throw const FormatException('数量请输入 0～1000000 的整数');
  }
  if (!withCocoons && (record.pupaCount ?? 0) != 0) {
    throw const FormatException('当前发育模式不经过茧，请在蚁群信息中修改模式');
  }
  int? count(String label, int? current, int? added, int consumed) {
    if (added == null && consumed == 0) return null;
    if (current == null || current < 0) {
      throw FormatException('$label数量未知，请先关闭增量填写当前总数');
    }
    final result = current + (added ?? 0) - consumed;
    if (result < 0) throw FormatException('$label数量不足，请校正总数或减少转化数量');
    return result;
  }

  final workers = count('工蚁', base.workers, record.workerCount, 0);
  return CareRecord.fromMap({
    ...record.toMap(),
    'egg_count': count('卵', base.eggs, record.eggCount, record.larvaCount ?? 0),
    'larva_count': count(
      '幼虫',
      base.larvae,
      record.larvaCount,
      (withCocoons ? record.pupaCount : record.workerCount) ?? 0,
    ),
    'pupa_count': withCocoons
        ? count('茧', base.cocoons, record.pupaCount, record.workerCount ?? 0)
        : null,
    // A death-only record stays an event so edits/deletion can be replayed.
    // When an increment produces a snapshot, store its post-death total.
    'worker_count': workers == null
        ? null
        : math.max(0, workers - record.workerDeaths),
  });
}
