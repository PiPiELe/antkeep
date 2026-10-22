import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'domain/care_task.dart';
import 'domain/colony_growth.dart';
import 'domain/colony_list_filter.dart';
import 'domain/models.dart';
import 'domain/colony_tag.dart';
import 'widgets/colony_price_badge.dart';
import 'widgets/fading_horizontal_scroll.dart';

Color colonyShowcaseBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

class _ShowcasePalette {
  const _ShowcasePalette(this.context);

  final BuildContext context;
  ColorScheme get scheme => Theme.of(context).colorScheme;
  bool get dark => scheme.brightness == Brightness.dark;
  Color get foreground => scheme.onSurface;
  Color get muted => dark ? const Color(0xffadbbce) : scheme.onSurfaceVariant;
  Color get panel =>
      dark ? const Color(0xff111a25) : scheme.surfaceContainerLow;
  Color get inset => dark ? const Color(0xff1b2531) : scheme.surfaceContainer;
  Color get line => dark ? const Color(0xff304157) : scheme.outlineVariant;
}

const _orange = Color(0xffff823d);
const _blue = Color(0xff4ca7ff);
const _green = Color(0xff35dfa5);

class ColonyShowcaseToolbar extends StatelessWidget {
  const ColonyShowcaseToolbar({
    super.key,
    required this.visibleCount,
    required this.totalCount,
    required this.filterCount,
    required this.workerOrder,
    required this.canBatchCare,
    required this.onBatchCare,
    required this.onWorkerOrder,
    required this.onFilter,
  });

  final int visibleCount;
  final int totalCount;
  final int filterCount;
  final ColonyWorkerOrder workerOrder;
  final bool canBatchCare;
  final VoidCallback onBatchCare;
  final ValueChanged<ColonyWorkerOrder> onWorkerOrder;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final palette = _ShowcasePalette(context);
    final count = Text(
      '$visibleCount / $totalCount 群',
      maxLines: 1,
      style: TextStyle(
        color: palette.foreground,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
    final sort = PopupMenuButton<String>(
      tooltip: '排序方式',
      onSelected: (value) {
        if (value == 'batch') {
          onBatchCare();
        } else {
          onWorkerOrder(ColonyWorkerOrder.values.byName(value));
        }
      },
      itemBuilder: (_) => [
        for (final order in ColonyWorkerOrder.values)
          PopupMenuItem(
            value: order.name,
            child: Text(_workerOrderLabel(order)),
          ),
        if (canBatchCare)
          const PopupMenuItem(value: 'batch', child: Text('批量养护记录')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, color: palette.foreground, size: 19),
            const SizedBox(width: 5),
            Text(
              _workerOrderLabel(workerOrder),
              maxLines: 1,
              style: TextStyle(color: palette.foreground, fontSize: 13),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, color: palette.muted, size: 18),
          ],
        ),
      ),
    );
    final filter = OutlinedButton.icon(
      onPressed: onFilter,
      icon: Icon(
        filterCount == 0 ? Icons.filter_alt_outlined : Icons.filter_alt,
        size: 19,
      ),
      label: Text(filterCount == 0 ? '筛选' : '筛选 $filterCount'),
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.dark ? _green : palette.scheme.primary,
        backgroundColor: palette.dark ? _green.withValues(alpha: .16) : null,
        side: BorderSide(
          color: palette.dark ? _green.withValues(alpha: .75) : palette.line,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 38),
        visualDensity: VisualDensity.compact,
      ),
    );
    final controls = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: _panelDecoration(context, inset: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          count,
          const SizedBox(width: 10),
          SizedBox(height: 25, child: VerticalDivider(color: palette.line)),
          sort,
        ],
      ),
    );
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: controls,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: Text(
            '卡片右滑删除\n长按滑动排序',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(color: palette.muted, fontSize: 10),
          ),
        ),
        const SizedBox(width: 6),
        filter,
      ],
    );
  }
}

String _workerOrderLabel(ColonyWorkerOrder order) => switch (order) {
  ColonyWorkerOrder.manual => '默认排序',
  ColonyWorkerOrder.descending => '工蚁多到少',
  ColonyWorkerOrder.ascending => '工蚁少到多',
};

class ColonyShowcaseOverview extends StatelessWidget {
  const ColonyShowcaseOverview({
    super.key,
    required this.count,
    required this.queens,
    required this.workers,
  });

  final int count;
  final String queens;
  final String workers;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('colony-showcase-overview'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
    decoration: _panelDecoration(context),
    child: Row(
      children: [
        _OverviewMetric(
          icon: Icons.bug_report_rounded,
          color: _orange,
          value: '$count',
          label: '蚁群总数',
        ),
        _OverviewMetric(
          icon: Icons.workspace_premium_rounded,
          color: const Color(0xff8d79ff),
          value: queens,
          label: '蚁后总数',
        ),
        _OverviewMetric(
          icon: Icons.groups_rounded,
          color: _green,
          value: workers,
          label: '工蚁总数',
        ),
      ],
    ),
  );
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: .17),
          child: icon == Icons.bug_report_rounded
              ? AntSymbol(color: color, size: 25)
              : Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: _ShowcasePalette(context).foreground,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ShowcasePalette(context).muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ColonyShowcaseCard extends StatelessWidget {
  const ColonyShowcaseCard({
    super.key,
    required this.style,
    required this.colony,
    required this.population,
    required this.queens,
    required this.workers,
    required this.dueTasks,
    this.cover,
    this.tagOrder = ColonyTag.values,
    required this.onTap,
    required this.onDurationTap,
  });

  final ColonyDisplayStyle style;
  final List<ColonyTag> tagOrder;
  final Colony colony;
  final GrowthPopulation population;
  final int? queens;
  final int? workers;
  final List<CareTask> dueTasks;
  final Widget? cover;
  final VoidCallback onTap;
  final VoidCallback onDurationTap;

  @override
  Widget build(BuildContext context) {
    final compact = style == ColonyDisplayStyle.compact;
    final accent = compact
        ? switch (ColonyScale.fromWorkerCount(workers)) {
            ColonyScale.small => _orange,
            ColonyScale.medium => const Color(0xffa866f2),
            ColonyScale.large || ColonyScale.superLarge => _blue,
            null => _orange,
          }
        : _orange;
    final description = [
      colony.species,
      colony.nestType,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final days = colony.husbandryDays(DateTime.now());
    final metrics = <({IconData icon, String label, int? count})>[
      (icon: Icons.workspace_premium_rounded, label: '蚁后', count: queens),
      (icon: Icons.bug_report_outlined, label: '工蚁', count: workers),
      (icon: Icons.egg_outlined, label: '卵', count: population.eggs),
      (icon: Icons.grain_rounded, label: '幼虫', count: population.larvae),
      (icon: Icons.ac_unit_rounded, label: '蛹茧', count: population.cocoons),
    ];
    if (colony.showSpecialized) {
      metrics.insert(2, (
        icon: Icons.stars_rounded,
        label: '特化',
        count: colony.specializedCount,
      ));
    }

    return Container(
      key: ValueKey('colony-${style.name}-${colony.id}'),
      decoration: _panelDecoration(context, accent: accent),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact)
                  Stack(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 105),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Identity(
                              tagOrder: tagOrder,
                              colony: colony,
                              cover: cover,
                              accent: accent,
                              description: description,
                              compact: false,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(right: 108),
                              child: _Tags(
                                colony: colony,
                                workers: workers,
                                order: tagOrder,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ShaderMask(
                                  blendMode: BlendMode.dstIn,
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: const [
                                      Colors.transparent,
                                      Colors.white,
                                      Colors.white,
                                    ],
                                    stops: [
                                      0,
                                      (20 / bounds.width).clamp(0, 1),
                                      1,
                                    ],
                                  ).createShader(bounds),
                                  child: ShaderMask(
                                    blendMode: BlendMode.dstIn,
                                    shaderCallback: (bounds) => LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: const [
                                        Colors.transparent,
                                        Colors.white,
                                        Colors.white,
                                      ],
                                      stops: [
                                        0,
                                        (20 / bounds.height).clamp(0, 1),
                                        1,
                                      ],
                                    ).createShader(bounds),
                                    child: ColoredBox(
                                      color: _ShowcasePalette(context).panel,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 20, top: 20),
                              child: _LargeDuration(
                                days: days,
                                onTap: days == null ? onDurationTap : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Identity(
                          tagOrder: tagOrder,
                          colony: colony,
                          cover: cover,
                          accent: accent,
                          description: description,
                          compact: true,
                          workers: workers,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _DurationPill(
                        days: days,
                        onTap: days == null ? onDurationTap : null,
                        color: accent,
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: _panelDecoration(context, inset: true),
                  child: Row(
                    children: [
                      for (final metric in metrics)
                        Expanded(
                          child: _PopulationMetric(
                            icon: metric.icon,
                            label: metric.label,
                            count: metric.count,
                          ),
                        ),
                    ],
                  ),
                ),
                if (dueTasks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: _panelDecoration(context, inset: true),
                    child: Row(
                      children: [
                        Icon(
                          Icons.assignment_turned_in_outlined,
                          color: accent,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '今日待办',
                          style: TextStyle(
                            color: _ShowcasePalette(context).foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${dueTasks.length} 项',
                          style: const TextStyle(color: _orange),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FadingHorizontalScroll(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final (index, task)
                                    in dueTasks.indexed) ...[
                                  if (index > 0) const SizedBox(width: 6),
                                  _Tag(
                                    task.type.label,
                                    _blue,
                                    icon: _taskIcon(task.type),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: _ShowcasePalette(context).muted,
                          size: 19,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.colony,
    required this.cover,
    required this.accent,
    required this.description,
    required this.compact,
    this.workers,
    required this.tagOrder,
  });

  final List<ColonyTag> tagOrder;
  final Colony colony;
  final Widget? cover;
  final Color accent;
  final String description;
  final bool compact;
  final int? workers;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 52.0 : 60.0;
    final palette = _ShowcasePalette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cover == null
            ? _ColonyAvatar(color: accent, size: size)
            : ClipOval(
                child: SizedBox.square(dimension: size, child: cover),
              ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                colony.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.foreground,
                  fontSize: compact ? 21 : 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
              ],
              if (compact) ...[
                const SizedBox(height: 8),
                _Tags(colony: colony, workers: workers, order: tagOrder),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

IconData _taskIcon(CareTaskType type) => switch (type) {
  CareTaskType.feeding => Icons.restaurant_rounded,
  CareTaskType.watering => Icons.water_drop_rounded,
  CareTaskType.cleaning => Icons.cleaning_services_rounded,
};

BoxDecoration _panelDecoration(
  BuildContext context, {
  Color? accent,
  bool inset = false,
}) {
  final palette = _ShowcasePalette(context);
  return BoxDecoration(
    gradient: inset
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette.dark
                ? const [
                    Color(0xff1a222d),
                    Color(0xff111a25),
                    Color(0xff0d1722),
                  ]
                : [palette.panel, palette.panel, palette.scheme.surface],
          ),
    color: inset ? palette.inset : null,
    borderRadius: BorderRadius.circular(inset ? 14 : 22),
    border: Border.all(
      color: accent?.withValues(alpha: .6) ?? palette.line,
      width: 1,
    ),
  );
}

class _ColonyAvatar extends StatelessWidget {
  const _ColonyAvatar({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [color.withValues(alpha: .95), color.withValues(alpha: .45)],
      ),
    ),
    child: Center(
      child: AntSymbol(color: Colors.white, size: size * .55),
    ),
  );
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.days, required this.color, this.onTap});
  final int? days;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(99),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: _ShowcasePalette(context).line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            color: _ShowcasePalette(context).muted,
            size: 15,
          ),
          const SizedBox(width: 4),
          Text(
            days == null ? '补入手日期' : '已养 $days天',
            style: TextStyle(
              color: days == null ? _ShowcasePalette(context).muted : color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LargeDuration extends StatelessWidget {
  const _LargeDuration({required this.days, this.onTap});
  final int? days;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: days == null
        ? Text(
            '补充入手日期 ›',
            style: TextStyle(color: _ShowcasePalette(context).muted),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '已养殖',
                  style: TextStyle(
                    color: _green,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$days',
                        style: TextStyle(
                          color: _ShowcasePalette(context).foreground,
                          fontSize: 65,
                          height: .9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      '天',
                      style: TextStyle(color: _ShowcasePalette(context).muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
  );
}

class _PopulationMetric extends StatelessWidget {
  const _PopulationMetric({
    required this.icon,
    required this.label,
    required this.count,
  });
  final IconData icon;
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: label == '蚁后'
                ? const Color(0xffffc66b)
                : _ShowcasePalette(context).muted,
            size: 15,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                count?.toString() ?? '—',
                style: TextStyle(
                  color: _ShowcasePalette(context).foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            color: _ShowcasePalette(context).muted,
            fontSize: 11,
          ),
        ),
      ),
    ],
  );
}

class AntSymbol extends StatelessWidget {
  const AntSymbol({super.key, required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _AntPainter(color));
}

class _AntPainter extends CustomPainter {
  const _AntPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final line = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final (start, end) in [
      (const Offset(43, 47), const Offset(26, 18)),
      (const Offset(48, 53), const Offset(38, 83)),
      (const Offset(54, 49), const Offset(61, 20)),
      (const Offset(58, 54), const Offset(73, 83)),
      (const Offset(68, 42), const Offset(83, 22)),
      (const Offset(72, 52), const Offset(90, 70)),
      (const Offset(79, 31), const Offset(88, 13)),
      (const Offset(70, 31), const Offset(66, 13)),
    ]) {
      canvas.drawLine(start, end, line);
    }
    final body = Paint()..color = color;
    canvas.drawOval(const Rect.fromLTWH(8, 38, 37, 31), body);
    canvas.drawCircle(const Offset(54, 51), 10, body);
    canvas.drawCircle(const Offset(73, 44), 15, body);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AntPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _Tags extends StatelessWidget {
  const _Tags({
    required this.colony,
    required this.workers,
    required this.order,
  });
  final Colony colony;
  final int? workers;
  final List<ColonyTag> order;

  @override
  Widget build(BuildContext context) {
    final scale = ColonyScale.fromWorkerCount(workers);
    final available = <ColonyTag, Widget>{
      if (colony.isNewQueenColony)
        ColonyTag.newQueen: const _Tag(
          '新后群',
          Color(0xffffbc59),
          icon: Icons.workspace_premium_rounded,
        ),
      if (colony.isWildCatch)
        ColonyTag.wildCatch: const _Tag('野采', _green, icon: Icons.eco_rounded),
      if (scale != null)
        ColonyTag.scale: _Tag(scale.label, _blue, icon: Icons.groups_rounded),
      if (colony.priceTier case final tier?)
        ColonyTag.price: ColonyPriceBadge(tier: tier),
    };
    final tags = <Widget>[for (final tag in order) ?available[tag]];
    if (tags.isEmpty) return const SizedBox.shrink();
    return FadingHorizontalScroll(
      child: Row(
        children: [
          for (final tag in tags)
            Padding(padding: const EdgeInsets.only(right: 6), child: tag),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color, {this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: .4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
