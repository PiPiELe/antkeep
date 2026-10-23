import 'dart:async';

import 'package:flutter/material.dart';

import 'colony_display_styles.dart';
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
    this.showMemorial = true,
    this.loadStats = loadColonyOverviewStats,
    this.onOpenColonies,
    this.onOpenMemorial,
  });

  final bool active;
  final bool showMemorial;
  final Future<ColonyOverviewStats> Function() loadStats;
  final VoidCallback? onOpenColonies;
  final VoidCallback? onOpenMemorial;

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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _OverviewSection(
            title: '历史',
            subtitle: '仍保留档案的蚁群；工蚁按数量记录累计估算，死亡不扣减',
            icon: Icons.folder_copy_rounded,
            illustration: 'assets/overview/history.png',
            onDetails: () => _showHistoryDetails(context, stats),
            metrics: [
              (
                label: '蚁群数',
                value: '${stats.historicalColonies}',
                kind: _MetricKind.colony,
              ),
              (
                label: '新后群数',
                value: '${stats.historicalNewQueenColonies}',
                kind: _MetricKind.newQueen,
              ),
              (
                label: '蚁后数',
                value: stats.historicalQueens,
                kind: _MetricKind.queen,
              ),
              (
                label: '工蚁数',
                value: stats.historicalWorkers,
                kind: _MetricKind.worker,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _OverviewSection(
            title: '现役',
            subtitle: '当前饲养的蚁群；蚁后与工蚁数已计入死亡记录',
            icon: Icons.home_rounded,
            illustration: 'assets/overview/active.png',
            onDetails:
                widget.onOpenColonies ??
                () =>
                    _showSectionDetails(context, '现役', '当前饲养的蚁群；蚁后与工蚁数已计入死亡记录'),
            metrics: [
              (
                label: '蚁群数',
                value: '${stats.activeColonies}',
                kind: _MetricKind.colony,
              ),
              (
                label: '新后群数',
                value: '${stats.activeNewQueenColonies}',
                kind: _MetricKind.newQueen,
              ),
              (
                label: '蚁后数',
                value: stats.activeQueens,
                kind: _MetricKind.queen,
              ),
              (
                label: '工蚁数',
                value: stats.activeWorkers,
                kind: _MetricKind.worker,
              ),
            ],
          ),
          if (widget.showMemorial) ...[
            const SizedBox(height: 16),
            _OverviewSection(
              title: '英灵殿',
              subtitle: '归档蚁群数及已保存的蚁后、工蚁纪念数',
              icon: Icons.account_balance_rounded,
              illustration: 'assets/overview/memorial.png',
              onDetails:
                  widget.onOpenMemorial ??
                  () =>
                      _showSectionDetails(context, '英灵殿', '归档蚁群数及已保存的蚁后、工蚁纪念数'),
              metrics: [
                (
                  label: '蚁群数',
                  value: '${stats.memorialColonies}',
                  kind: _MetricKind.colony,
                ),
                (
                  label: '蚁后数',
                  value: '${stats.memorialQueens}',
                  kind: _MetricKind.queen,
                ),
                (
                  label: '工蚁数',
                  value: '${stats.memorialWorkers}',
                  kind: _MetricKind.worker,
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  void _showHistoryDetails(BuildContext context, ColonyOverviewStats stats) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('历史统计', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                '保留档案的蚁群共 ${stats.historicalColonies} 群，其中现役 ${stats.activeColonies} 群，已归档 ${stats.memorialColonies} 群。',
              ),
              const SizedBox(height: 8),
              const Text('蚁后数按档案初始数量统计；工蚁数按数量记录累计估算，死亡不扣减。数量不完整时显示“≥”或“未知”。'),
            ],
          ),
        ),
      ),
    );
  }

  void _showSectionDetails(
    BuildContext context,
    String title,
    String description,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(description),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MetricKind { colony, newQueen, queen, worker }

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.illustration,
    required this.onDetails,
    required this.metrics,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String illustration;
  final VoidCallback onDetails;
  final List<({String label, String value, _MetricKind kind})> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark
            ? theme.colorScheme.surfaceContainer
            : const Color(0xFFFFFAF6),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: dark ? .12 : .08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: 65,
            right: -14,
            bottom: -10,
            width: 270,
            child: Opacity(
              opacity: dark ? .35 : .8,
              child: Image.asset(
                illustration,
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                excludeFromSemantics: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: const Color(0xFF9A6330), size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onDetails,
                      style: TextButton.styleFrom(
                        foregroundColor: dark
                            ? theme.colorScheme.onSurface
                            : const Color(0xFF70461F),
                        backgroundColor: dark
                            ? theme.colorScheme.surfaceContainerHigh
                            : const Color(0xFFF8EEE7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        minimumSize: const Size(0, 40),
                      ),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      label: const Text('查看详情'),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 2),
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth;
                    final metricsWidth = maxWidth < 270
                        ? maxWidth
                        : maxWidth * (maxWidth < 320 ? .88 : .82);
                    return SizedBox(
                      width: metricsWidth,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width: (metricsWidth - 8) / 2,
                              child: _MetricTile(metric: metric),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final ({String label, String value, _MetricKind kind}) metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (metric.kind) {
      _MetricKind.colony => (const Color(0xFFF8EBDC), const Color(0xFF9B622B)),
      _MetricKind.newQueen => (
        const Color(0xFFEBEEDC),
        const Color(0xFF77914E),
      ),
      _MetricKind.queen => (const Color(0xFFF9E2DF), const Color(0xFFAA5A50)),
      _MetricKind.worker => (const Color(0xFFEDE7F4), const Color(0xFF67597B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: switch (metric.kind) {
              _MetricKind.colony => AntSymbol(color: foreground, size: 24),
              _MetricKind.newQueen => Icon(
                Icons.spa_rounded,
                color: foreground,
                size: 23,
              ),
              _MetricKind.queen => Icon(
                Icons.workspace_premium_rounded,
                color: foreground,
                size: 23,
              ),
              _MetricKind.worker => Icon(
                Icons.pest_control_rounded,
                color: foreground,
                size: 23,
              ),
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
