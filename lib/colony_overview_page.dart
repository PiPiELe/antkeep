import 'dart:async';

import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'domain/memorial.dart';
import 'domain/models.dart';

class ColonyOverviewStats {
  const ColonyOverviewStats({
    required this.historicalColonies,
    required this.historicalNewQueenColonies,
    required this.historicalQueens,
    required this.historicalWorkers,
    required this.activeColonies,
    required this.activeNewQueenColonies,
    required this.activeQueens,
    required this.activeWorkers,
    required this.memorialColonies,
    required this.memorialQueens,
    required this.memorialWorkers,
  });

  final int historicalColonies;
  final int historicalNewQueenColonies;
  final String historicalQueens;
  final String historicalWorkers;
  final int activeColonies;
  final int activeNewQueenColonies;
  final String activeQueens;
  final String activeWorkers;
  final int memorialColonies;
  final int memorialQueens;
  final int memorialWorkers;

  factory ColonyOverviewStats.fromData(
    List<Colony> colonies,
    Map<String, List<CareRecord>> recordsByColony,
    List<Memorial> memorials,
  ) {
    final active = colonies.where((colony) => !colony.archived).toList();
    return ColonyOverviewStats(
      historicalColonies: colonies.length,
      historicalNewQueenColonies: colonies
          .where((colony) => colony.isNewQueenColony)
          .length,
      historicalQueens: _sumKnown(colonies.map((colony) => colony.queenCount)),
      historicalWorkers: _sumLifetimeWorkers(colonies, recordsByColony),
      activeColonies: active.length,
      activeNewQueenColonies: active
          .where((colony) => colony.isNewQueenColony)
          .length,
      activeQueens: _sumKnown(
        active.map(
          (colony) =>
              colony.currentQueenCount(recordsByColony[colony.id] ?? const []),
        ),
      ),
      activeWorkers: _sumKnown(
        active.map(
          (colony) =>
              colony.currentWorkerCount(recordsByColony[colony.id] ?? const []),
        ),
      ),
      memorialColonies: colonies.where((colony) => colony.archived).length,
      memorialQueens: memorials
          .where((item) => item.kind == MemorialKind.queen)
          .length,
      memorialWorkers: memorials
          .where((item) => item.kind == MemorialKind.worker)
          .length,
    );
  }

  static String _sumKnown(Iterable<int?> values) {
    final counts = values.toList();
    if (counts.isEmpty) return '0';
    final known = counts.whereType<int>().toList();
    if (known.isEmpty) return '未知';
    final total = known.fold<int>(0, (sum, count) => sum + count);
    return known.length == counts.length ? '$total' : '≥$total';
  }

  static String _sumLifetimeWorkers(
    List<Colony> colonies,
    Map<String, List<CareRecord>> recordsByColony,
  ) {
    var total = 0;
    var hasKnown = false;
    var incomplete = false;
    for (final colony in colonies) {
      final records = [...?recordsByColony[colony.id]]
        ..sort(CareRecord.comparePopulationOrder);
      var current = colony.initialWorkerCount;
      var lifetime = current;
      if (current == null) incomplete = true;
      for (final record in records) {
        final after = record.workerCountAfter(current);
        if (after == null) continue;
        if (current == null) {
          lifetime = after;
        } else {
          final afterDeaths = current > record.workerDeaths
              ? current - record.workerDeaths
              : 0;
          final gained = after - afterDeaths;
          if (gained > 0) lifetime = (lifetime ?? 0) + gained;
        }
        current = after;
      }
      if (lifetime != null) {
        total += lifetime;
        hasKnown = true;
      }
    }
    if (colonies.isEmpty) return '0';
    if (!hasKnown) return '未知';
    return incomplete ? '≥$total' : '$total';
  }
}

Future<ColonyOverviewStats> loadColonyOverviewStats() async {
  final database = AppDatabase.instance;
  final colonies = await database.listAllColonies();
  final records = await Future.wait(
    colonies.map((colony) => database.listRecords(colony.id)),
  );
  return ColonyOverviewStats.fromData(colonies, {
    for (var index = 0; index < colonies.length; index++)
      colonies[index].id: records[index],
  }, await database.listMemorials());
}

class ColonyOverviewPage extends StatefulWidget {
  const ColonyOverviewPage({
    super.key,
    required this.active,
    this.loadStats = loadColonyOverviewStats,
  });

  final bool active;
  final Future<ColonyOverviewStats> Function() loadStats;

  @override
  State<ColonyOverviewPage> createState() => _ColonyOverviewPageState();
}

class _ColonyOverviewPageState extends State<ColonyOverviewPage> {
  late Future<ColonyOverviewStats> _stats;
  StreamSubscription<void>? _memorialChanges;

  @override
  void initState() {
    super.initState();
    _reload();
    _memorialChanges = AppDatabase.instance.memorialChanges.listen((_) {
      if (mounted) setState(_reload);
    });
  }

  @override
  void didUpdateWidget(covariant ColonyOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reload();
  }

  void _reload() => _stats = widget.loadStats();

  @override
  void dispose() {
    _memorialChanges?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ColonyOverviewStats>(
    future: _stats,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('加载总览失败：${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final stats = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OverviewSection(
            title: '历史',
            subtitle: '仍保留档案的蚁群；工蚁按数量记录累计估算，死亡不扣减',
            metrics: [
              ('蚁群数', '${stats.historicalColonies}'),
              ('新后群数', '${stats.historicalNewQueenColonies}'),
              ('蚁后数', stats.historicalQueens),
              ('工蚁数', stats.historicalWorkers),
            ],
          ),
          const SizedBox(height: 12),
          _OverviewSection(
            title: '现役',
            subtitle: '当前饲养的蚁群；蚁后与工蚁数已计入死亡记录',
            metrics: [
              ('蚁群数', '${stats.activeColonies}'),
              ('新后群数', '${stats.activeNewQueenColonies}'),
              ('蚁后数', stats.activeQueens),
              ('工蚁数', stats.activeWorkers),
            ],
          ),
          const SizedBox(height: 12),
          _OverviewSection(
            title: '英灵殿',
            subtitle: '归档蚁群数及已保存的蚁后、工蚁纪念数',
            metrics: [
              ('蚁群数', '${stats.memorialColonies}'),
              ('蚁后数', '${stats.memorialQueens}'),
              ('工蚁数', '${stats.memorialWorkers}'),
            ],
          ),
        ],
      );
    },
  );
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.subtitle,
    required this.metrics,
  });

  final String title;
  final String subtitle;
  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final (label, value) in metrics)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(label, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
