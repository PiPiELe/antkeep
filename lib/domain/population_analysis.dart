import 'models.dart';

enum PopulationMetric {
  workers('工蚁'),
  eggs('卵'),
  larvae('幼虫'),
  pupae('蛹/茧'),
  total('总数量'),
  juveniles('幼体/若虫'),
  adults('成体');

  const PopulationMetric(this.label);
  final String label;
  static const colonyMetrics = [workers, eggs, larvae, pupae];
  static const feederMetrics = [total, juveniles, adults];
}

enum PopulationTrend {
  insufficient('数据不足'),
  flat('平稳'),
  rising('稳定上升'),
  falling('稳定下降'),
  fluctuating('数量波动');

  const PopulationTrend(this.label);
  final String label;
}

class PopulationPoint {
  const PopulationPoint(this.time, this.count);
  final DateTime time;
  final int count;
}

/// Uses only observed values. Missing quantities never become zero or carry
/// forward from a different observation. Duplicate instants use the last entry.
List<PopulationPoint> colonyPopulation(
  Colony colony,
  List<CareRecord> records,
  PopulationMetric metric,
) {
  final initial = switch (metric) {
    PopulationMetric.workers => colony.initialWorkerCount,
    PopulationMetric.eggs => colony.initialEggCount,
    PopulationMetric.larvae => colony.initialLarvaCount,
    PopulationMetric.pupae => colony.initialCocoonCount,
    _ => null,
  };
  final values = <int, PopulationPoint>{};
  void add(DateTime time, int? count) {
    if (count != null && count >= 0) {
      values[time.microsecondsSinceEpoch] = PopulationPoint(time, count);
    }
  }

  add(colony.acquiredOn ?? colony.createdAt, initial);
  final ordered = records.where((r) => r.colonyId == colony.id).toList()
    ..sort((a, b) {
      final order = a.createdAt.compareTo(b.createdAt);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  for (final record in ordered) {
    add(record.occurredAt, switch (metric) {
      PopulationMetric.workers => record.workerCount,
      PopulationMetric.eggs => record.eggCount,
      PopulationMetric.larvae => record.larvaCount,
      PopulationMetric.pupae => record.pupaCount,
      _ => null,
    });
  }
  return values.values.toList()..sort((a, b) => a.time.compareTo(b.time));
}

/// Reconstructs the latest known colony total at every quantity observation.
///
/// A blank field is kept unknown instead of becoming zero. Once a quantity has
/// been recorded it remains the latest known value until that quantity is
/// recorded again; this makes a total useful even when a care record updates
/// only workers or only brood.
List<PopulationPoint> colonyPopulationTotal(
  Colony colony,
  List<CareRecord> records, {
  required bool includeBrood,
}) {
  int? valid(int? value) => value != null && value >= 0 ? value : null;

  final queen = valid(colony.queenCount);
  final specialized = colony.showSpecialized
      ? valid(colony.specializedCount)
      : null;
  var workers = valid(colony.initialWorkerCount);
  var eggs = valid(colony.initialEggCount);
  var larvae = valid(colony.initialLarvaCount);
  var pupae = valid(colony.initialCocoonCount);
  final values = <int, PopulationPoint>{};

  int? total() {
    final counts = <int?>[
      queen,
      specialized,
      workers,
      if (includeBrood) ...[eggs, larvae, pupae],
    ].whereType<int>().toList();
    if (counts.isEmpty) return null;
    return counts.fold<int>(0, (sum, count) => sum + count);
  }

  void add(DateTime time) {
    final count = total();
    if (count != null) {
      values[time.microsecondsSinceEpoch] = PopulationPoint(time, count);
    }
  }

  add(colony.acquiredOn ?? colony.createdAt);
  final ordered = records.where((r) => r.colonyId == colony.id).toList()
    ..sort((a, b) {
      final order = a.createdAt.compareTo(b.createdAt);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  for (final record in ordered) {
    var changed = false;
    final worker = valid(record.workerCount);
    if (worker != null) {
      workers = worker;
      changed = true;
    }
    if (includeBrood) {
      final egg = valid(record.eggCount);
      if (egg != null) {
        eggs = egg;
        changed = true;
      }
      final larva = valid(record.larvaCount);
      if (larva != null) {
        larvae = larva;
        changed = true;
      }
      final pupa = valid(record.pupaCount);
      if (pupa != null) {
        pupae = pupa;
        changed = true;
      }
    }
    if (changed) add(record.occurredAt);
  }
  return values.values.toList()..sort((a, b) => a.time.compareTo(b.time));
}

List<PopulationPoint> feederPopulation(
  FeederType feeder,
  List<FeederRecord> records,
  PopulationMetric metric,
) {
  final values = <int, PopulationPoint>{};
  final ordered = records.where((r) => r.feeder == feeder).toList()
    ..sort((a, b) {
      final order = a.createdAt.compareTo(b.createdAt);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  for (final record in ordered) {
    final count = switch (metric) {
      PopulationMetric.juveniles => record.juvenileCount,
      PopulationMetric.adults => record.adultCount,
      PopulationMetric.total =>
        record.juvenileCount != null &&
                record.adultCount != null &&
                record.juvenileCount! >= 0 &&
                record.adultCount! >= 0
            ? record.juvenileCount! + record.adultCount!
            : null,
      _ => null,
    };
    if (count != null && count >= 0) {
      values[record.occurredAt.microsecondsSinceEpoch] = PopulationPoint(
        record.occurredAt,
        count,
      );
    }
  }
  return values.values.toList()..sort((a, b) => a.time.compareTo(b.time));
}

/// A conservative description of recorded counts, not a growth prediction.
PopulationTrend populationTrend(List<PopulationPoint> points) {
  if (points.length < 3) return PopulationTrend.insufficient;
  var rises = false;
  var falls = false;
  for (var i = 1; i < points.length; i++) {
    rises |= points[i].count > points[i - 1].count;
    falls |= points[i].count < points[i - 1].count;
  }
  if (rises && falls) return PopulationTrend.fluctuating;
  if (rises) return PopulationTrend.rising;
  if (falls) return PopulationTrend.falling;
  return PopulationTrend.flat;
}
