import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'domain/care_task.dart';
import 'domain/colony_growth.dart';
import 'domain/models.dart';

const colonyShowcaseBackground = Color(0xff090e14);
const _panel = Color(0xff111a25);
const _line = Color(0xff304157);
const _muted = Color(0xffadbbce);
const _orange = Color(0xffff823d);
const _blue = Color(0xff4ca7ff);
const _green = Color(0xff35dfa5);

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
    decoration: _panelDecoration(),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 11),
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
    required this.onTap,
    required this.onDurationTap,
  });

  final ColonyDisplayStyle style;
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
      decoration: _panelDecoration(accent: accent),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover == null
                        ? _ColonyAvatar(color: accent, size: compact ? 52 : 60)
                        : ClipOval(
                            child: SizedBox.square(
                              dimension: compact ? 52 : 60,
                              child: cover,
                            ),
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
                              color: Colors.white,
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
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (compact) ...[
                            const SizedBox(height: 8),
                            _Tags(colony: colony, workers: workers),
                          ],
                        ],
                      ),
                    ),
                    if (compact) ...[
                      const SizedBox(width: 6),
                      _DurationPill(
                        days: days,
                        onTap: days == null ? onDurationTap : null,
                        color: accent,
                      ),
                    ],
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 10),
                  _Tags(colony: colony, workers: workers),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _LargeDuration(
                      days: days,
                      onTap: days == null ? onDurationTap : null,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: _panelDecoration(inset: true),
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
                    decoration: _panelDecoration(inset: true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.assignment_turned_in_outlined,
                              color: accent,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              '今日待办',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${dueTasks.length} 项',
                              style: const TextStyle(color: _orange),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.chevron_right,
                              color: _muted,
                              size: 19,
                            ),
                          ],
                        ),
                        if (compact) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final task in dueTasks)
                                _Tag(
                                  task.type.label,
                                  _blue,
                                  icon: _taskIcon(task.type),
                                ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 6),
                          Text(
                            dueTasks.map((task) => task.type.label).join(' · '),
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
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

IconData _taskIcon(CareTaskType type) => switch (type) {
  CareTaskType.feeding => Icons.restaurant_rounded,
  CareTaskType.watering => Icons.water_drop_rounded,
  CareTaskType.cleaning => Icons.cleaning_services_rounded,
};

BoxDecoration _panelDecoration({Color? accent, bool inset = false}) =>
    BoxDecoration(
      gradient: inset
          ? null
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff1a222d), _panel, Color(0xff0d1722)],
            ),
      color: inset ? const Color(0xff1b2531) : null,
      borderRadius: BorderRadius.circular(inset ? 14 : 22),
      border: Border.all(
        color: accent?.withValues(alpha: .6) ?? _line,
        width: 1,
      ),
    );

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
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, color: _muted, size: 15),
          const SizedBox(width: 4),
          Text(
            days == null ? '补入手日期' : '已养 $days天',
            style: TextStyle(
              color: days == null ? _muted : color,
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
        ? const Text('补充入手日期 ›', style: TextStyle(color: _muted))
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 65,
                          height: .9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 4),
                    child: Text('天', style: TextStyle(color: _muted)),
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
            color: label == '蚁后' ? const Color(0xffffc66b) : _muted,
            size: 15,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                count?.toString() ?? '—',
                style: const TextStyle(
                  color: Colors.white,
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
        child: Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
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
  const _Tags({required this.colony, required this.workers});
  final Colony colony;
  final int? workers;

  @override
  Widget build(BuildContext context) {
    final scale = ColonyScale.fromWorkerCount(workers);
    final tags = <Widget>[
      if (colony.isNewQueenColony)
        const _Tag(
          '新后群',
          Color(0xffffbc59),
          icon: Icons.workspace_premium_rounded,
        ),
      if (colony.isWildCatch) const _Tag('野采', _green, icon: Icons.eco_rounded),
      if (scale != null) _Tag(scale.label, _blue, icon: Icons.groups_rounded),
    ];
    if (tags.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
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
