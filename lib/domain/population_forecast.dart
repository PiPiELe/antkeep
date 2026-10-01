import 'dart:math' as math;

import 'colony_growth.dart';
import 'models.dart';
import 'population_analysis.dart';

enum ForecastHorizon {
  week('7 天'),
  fortnight('14 天'),
  month('1 个月');

  const ForecastHorizon(this.label);
  final String label;

  DateTime endFrom(DateTime now) {
    if (this != month) {
      return DateTime(
        now.year,
        now.month,
        now.day + (this == week ? 7 : 14),
        now.hour,
        now.minute,
        now.second,
        now.millisecond,
        now.microsecond,
      );
    }
    final next = DateTime(now.year, now.month + 1);
    final day = math.min(now.day, DateTime(next.year, next.month + 1, 0).day);
    return DateTime(
      next.year,
      next.month,
      day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
  }
}

/// Pure projection: never creates records or advances the saved cycle counter.
/// Includes an anchor at now and an endpoint, even if no growth is due in range.
List<PopulationPoint> colonyPopulationForecast(
  Colony colony,
  List<CareRecord> records, {
  required DateTime now,
  ForecastHorizon horizon = ForecastHorizon.month,
  PopulationMetric metric = PopulationMetric.workers,
  bool includeBrood = true,
}) {
  final growth = colony.growth;
  if (growth == null ||
      colony.archived ||
      !const [
        PopulationMetric.workers,
        PopulationMetric.eggs,
        PopulationMetric.pupae,
        PopulationMetric.total,
      ].contains(metric)) {
    return [];
  }
  final known =
      records
          .where((r) => r.colonyId == colony.id && !r.occurredAt.isAfter(now))
          .toList()
        ..sort((a, b) {
          final time = a.occurredAt.compareTo(b.occurredAt);
          if (time != 0) return time;
          final created = a.createdAt.compareTo(b.createdAt);
          return created != 0 ? created : a.id.compareTo(b.id);
        });
  int? valid(int? value) => value != null && value >= 0 ? value : null;
  var eggs = valid(colony.initialEggCount);
  var cocoons = valid(colony.initialCocoonCount);
  var workers = valid(colony.initialWorkerCount);
  int? larvae;
  for (final record in known) {
    eggs = valid(record.eggCount) ?? eggs;
    cocoons = valid(record.pupaCount) ?? cocoons;
    workers = valid(record.workerCount) ?? workers;
    larvae = valid(record.larvaCount) ?? larvae;
  }
  var population = GrowthPopulation(
    eggs: eggs,
    cocoons: cocoons,
    workers: workers,
  );
  int? count() {
    if (metric != PopulationMetric.total) {
      return switch (metric) {
        PopulationMetric.workers => population.workers,
        PopulationMetric.eggs => population.eggs,
        PopulationMetric.pupae => population.cocoons,
        _ => null,
      };
    }
    final values = [
      valid(colony.queenCount),
      if (colony.showSpecialized) valid(colony.specializedCount),
      population.workers,
      if (includeBrood) ...[population.eggs, larvae, population.cocoons],
    ].whereType<int>().toList();
    return values.isEmpty
        ? null
        : values.fold<int>(0, (sum, value) => sum + value);
  }

  if (count() == null) return [];
  final result = <PopulationPoint>[PopulationPoint(now, count()!)];
  final end = horizon.endFrom(now);
  // Find the first future cycle without replaying already elapsed periods.
  final elapsedDays = DateTime.utc(now.year, now.month, now.day)
      .difference(
        DateTime.utc(
          growth.startedAt.year,
          growth.startedAt.month,
          growth.startedAt.day,
        ),
      )
      .inDays;
  var cycle = math.max(growth.completedCycles + 1, switch (growth.frequency) {
    GrowthFrequency.daily => elapsedDays,
    GrowthFrequency.weekly => elapsedDays ~/ 7,
    GrowthFrequency.monthly =>
      (now.year - growth.startedAt.year) * 12 +
          now.month -
          growth.startedAt.month,
  });
  while (!growth.dueAt(cycle).isAfter(now)) {
    cycle++;
  }
  while (!growth.dueAt(cycle).isAfter(end)) {
    population = growth.advance(population);
    result.add(PopulationPoint(growth.dueAt(cycle++), count()!));
  }
  if (result.last.time.isBefore(end)) {
    result.add(PopulationPoint(end, count()!));
  }
  return result;
}
