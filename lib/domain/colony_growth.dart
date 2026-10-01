import 'dart:convert';
import 'dart:math' as math;

enum GrowthFrequency {
  daily('每日'),
  weekly('每周'),
  monthly('每月');

  const GrowthFrequency(this.label);
  final String label;
}

enum GrowthPath {
  eggToWorker('卵 → 幼 → 工'),
  eggToCocoonToWorker('卵 → 幼 → 茧 → 工');

  const GrowthPath(this.label);
  final String label;

  static GrowthPath? fromStorage(Object? value) {
    if (value == null) return null;
    final path = values.where((path) => path.name == value).firstOrNull;
    if (path == null) throw const FormatException('发育模式无效');
    return path;
  }
}

/// A null increment consumes this stage along the path; zero explicitly holds it.
class ColonyGrowth {
  const ColonyGrowth({
    required this.frequency,
    required this.path,
    required this.startedAt,
    this.eggs,
    this.larvae,
    this.cocoons,
    this.workers,
    this.completedCycles = 0,
  });

  final GrowthFrequency frequency;
  final GrowthPath path;
  final DateTime startedAt;
  final int? eggs;
  final int? larvae;
  final int? cocoons;
  final int? workers;
  final int completedCycles;

  DateTime dueAt(int cycle) {
    if (frequency != GrowthFrequency.monthly) {
      return DateTime(
        startedAt.year,
        startedAt.month,
        startedAt.day + cycle * (frequency == GrowthFrequency.weekly ? 7 : 1),
        startedAt.hour,
        startedAt.minute,
        startedAt.second,
        startedAt.millisecond,
        startedAt.microsecond,
      );
    }
    final month = DateTime(startedAt.year, startedAt.month + cycle);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(
      month.year,
      month.month,
      math.min(startedAt.day, lastDay),
      startedAt.hour,
      startedAt.minute,
      startedAt.second,
      startedAt.millisecond,
      startedAt.microsecond,
    );
  }

  ColonyGrowth completed(int cycles) => ColonyGrowth(
    frequency: frequency,
    path: path,
    startedAt: startedAt,
    eggs: eggs,
    larvae: larvae,
    cocoons: cocoons,
    workers: workers,
    completedCycles: cycles,
  );

  ColonyGrowth withPath(GrowthPath value) => ColonyGrowth(
    frequency: frequency,
    path: value,
    startedAt: startedAt,
    eggs: eggs,
    larvae: larvae,
    cocoons: value == GrowthPath.eggToCocoonToWorker ? cocoons : null,
    workers: workers,
    completedCycles: completedCycles,
  );

  String encode() => jsonEncode({
    'frequency': frequency.name,
    'path': path.name,
    'startedAt': startedAt.toIso8601String(),
    'eggs': eggs,
    'larvae': larvae,
    'cocoons': cocoons,
    'workers': workers,
    'completedCycles': completedCycles,
  });

  static ColonyGrowth? decode(Object? value) {
    if (value == null) return null;
    final map = jsonDecode(value as String) as Map<String, dynamic>;
    final frequency = GrowthFrequency.values
        .where((v) => v.name == map['frequency'])
        .firstOrNull;
    final path = GrowthPath.values
        .where((v) => v.name == map['path'])
        .firstOrNull;
    if (frequency == null || path == null) {
      throw const FormatException('自动扩充选项无效');
    }
    for (final key in [
      'eggs',
      'larvae',
      'cocoons',
      'workers',
      'completedCycles',
    ]) {
      final count = map[key];
      if ((key == 'completedCycles' && count == null) ||
          (count != null && (count is! int || count < 0 || count > 1000000))) {
        throw const FormatException('自动扩充数量无效');
      }
    }
    if (path == GrowthPath.eggToWorker && map['cocoons'] != null) {
      throw const FormatException('卵到工路径不支持茧增长');
    }
    return ColonyGrowth(
      frequency: frequency,
      path: path,
      startedAt: DateTime.parse(map['startedAt'] as String).toLocal(),
      eggs: map['eggs'] as int?,
      larvae: map['larvae'] as int?,
      cocoons: map['cocoons'] as int?,
      workers: map['workers'] as int?,
      completedCycles: map['completedCycles'] as int,
    );
  }

  GrowthPopulation advance(GrowthPopulation current) {
    var eggCount = current.eggs;
    var larvaCount = current.larvae;
    var cocoonCount = current.cocoons;
    var workerCount = current.workers;
    var workerGain = workerCount == null ? 0 : workers ?? 0;
    if (path == GrowthPath.eggToWorker) {
      if (larvae == null) {
        workerGain = math.min(workerGain, larvaCount ?? 0);
        if (larvaCount != null) larvaCount -= workerGain;
      }
    } else {
      // Workers emerge from the stock present at the start of the cycle.
      if (cocoons == null) {
        workerGain = math.min(workerGain, cocoonCount ?? 0);
        if (cocoonCount != null) cocoonCount -= workerGain;
      }
      var cocoonGain = cocoonCount == null ? 0 : cocoons ?? 0;
      if (larvae == null) {
        cocoonGain = math.min(cocoonGain, larvaCount ?? 0);
        if (larvaCount != null) larvaCount -= cocoonGain;
      }
      if (cocoonCount != null) cocoonCount += cocoonGain;
    }
    var larvaGain = larvaCount == null ? 0 : larvae ?? 0;
    if (eggs == null) {
      larvaGain = math.min(larvaGain, eggCount ?? 0);
      if (eggCount != null) eggCount -= larvaGain;
    }
    if (larvaCount != null) larvaCount += larvaGain;
    if (eggCount != null) eggCount += eggs ?? 0;
    if (workerCount != null) workerCount += workerGain;
    return GrowthPopulation(
      eggs: eggCount,
      larvae: larvaCount,
      cocoons: cocoonCount,
      workers: workerCount,
    );
  }
}

class GrowthPopulation {
  const GrowthPopulation({this.eggs, this.larvae, this.cocoons, this.workers});
  final int? eggs;
  final int? larvae;
  final int? cocoons;
  final int? workers;
}
