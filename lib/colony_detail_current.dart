part of 'main.dart';

// The classic detail remains in main.dart. This presentation uses the same
// local records and actions, without persisting a second copy of colony data.
class _CurrentColonyProfile extends StatelessWidget {
  const _CurrentColonyProfile({
    required this.colony,
    required this.records,
    this.onDurationTap,
    this.onEdit,
  });
  final Colony colony;
  final List<CareRecord> records;
  final VoidCallback? onDurationTap, onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final photos = <String>{
      if (colony.coverPhotoPath != null) colony.coverPhotoPath!,
      for (final record in records) ...record.photos,
    }.toList();
    final population = colony.currentPopulation(records);
    final counts = <(String, int?)>[
      ('蚁后', colony.currentQueenCount(records)),
      ('工蚁', colony.currentWorkerCount(records)),
      ('卵', population.eggs),
      ('幼虫', population.larvae),
      ('茧', population.cocoons),
      if (colony.showSpecialized) ('特化', colony.specializedCount),
    ];
    Widget photo(String path, double width, double height) => _StoredImage(
      relativePath: path,
      width: width,
      height: height,
      borderRadius: 9,
      previewTitle: colony.name,
    );
    void gallery() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: photos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) => LayoutBuilder(
              builder: (context, box) =>
                  photo(photos[index], box.maxWidth, box.maxHeight),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final height = (box.maxWidth * .24).clamp(88.0, 132.0);
            return SizedBox(
              height: height,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (photos.isEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.asset(
                              'assets/images/default-ant-cover.png',
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          photo(photos.first, double.infinity, height),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: InkWell(
                            onTap: onDurationTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .65),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                colony.archived
                                    ? '养殖已结束'
                                    : colony.acquiredOn == null
                                    ? '设置入手日期'
                                    : '已养殖 ${math.max(0, DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(colony.acquiredOn!)).inDays)} 天',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (photos.length > 1) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: math.min(4, photos.length - 1),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          mainAxisExtent: (height - 6) / 2,
                        ),
                        itemBuilder: (context, index) => LayoutBuilder(
                          builder: (context, tile) => Stack(
                            fit: StackFit.expand,
                            children: [
                              photo(
                                photos[index + 1],
                                tile.maxWidth,
                                tile.maxHeight,
                              ),
                              if (index == 3 && photos.length > 5)
                                Material(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(9),
                                  child: InkWell(
                                    onTap: gallery,
                                    child: Center(
                                      child: Text(
                                        '+${photos.length - 4}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        FadingHorizontalScroll(
          child: _ColonyTags(
            colony: colony,
            workers: colony.currentWorkerCount(records),
            singleLine: true,
          ),
        ),
        const SizedBox(height: 10),
        _DetailSurface(
          child: LayoutBuilder(
            builder: (context, box) => Wrap(
              children: [
                for (final entry in counts)
                  SizedBox(
                    width:
                        box.maxWidth / (counts.length > 5 ? 3 : counts.length),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            entry.$1,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              entry.$2?.toString() ?? '—',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final columns =
                box.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(12) > 16
                ? 2
                : 4;
            final entries = <(IconData, String, String)>[
              (
                Icons.calendar_month_outlined,
                '入手日期',
                colony.acquiredOn == null ? '未填写' : _date(colony.acquiredOn!),
              ),
              (
                Icons.people_outline,
                '来源',
                colony.source?.trim().isNotEmpty == true
                    ? colony.source!
                    : '未填写',
              ),
              (
                Icons.account_balance_wallet_outlined,
                '购入价格',
                colony.purchasePriceCents == null
                    ? '未填写'
                    : '¥${colony.purchasePriceText}',
              ),
              (Icons.home_outlined, '饲养环境', colony.nestType ?? '未填写'),
            ];
            final missing = entries.any((entry) => entry.$3 == '未填写');
            entries.removeWhere((entry) => entry.$3 == '未填写');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (missing && onEdit != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('补充蚁群档案'),
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        width: (box.maxWidth - 6 * (columns - 1)) / columns,
                        child: _DetailSurface(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      entry.$1,
                                      size: 15,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        entry.$2,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                FadingHorizontalScroll(
                                  child: Text(
                                    entry.$3,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DetailSurface extends StatelessWidget {
  const _DetailSurface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: child,
    );
  }
}

class _CurrentPanel extends StatelessWidget {
  const _CurrentPanel({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.toggle,
    required this.child,
    required this.details,
    required this.summary,
  });
  final String summary;
  final String title;
  final IconData icon;
  final bool expanded;
  final VoidCallback toggle;
  final Widget child;
  final Widget details;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: _DetailSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Icon(icon, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        summary,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: Text(title)),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: details,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('详情 ›'),
                ),
                IconButton(
                  onPressed: toggle,
                  tooltip: expanded ? '折叠$title' : '展开$title',
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (expanded) child,
          ],
        ),
      ),
    ),
  );
}

class _CurrentPopulationPanel extends StatefulWidget {
  const _CurrentPopulationPanel({
    super.key,
    required this.colony,
    required this.records,
    required this.details,
    required this.expanded,
    required this.includeBrood,
    required this.onExpandedChanged,
  });
  final bool expanded, includeBrood;
  final ValueChanged<bool> onExpandedChanged;
  final Colony colony;
  final List<CareRecord> records;
  final Widget details;
  @override
  State<_CurrentPopulationPanel> createState() =>
      _CurrentPopulationPanelState();
}

class _CurrentPopulationPanelState extends State<_CurrentPopulationPanel> {
  int days = 30;
  @override
  Widget build(BuildContext context) {
    final all = colonyPopulationTotal(
      widget.colony,
      widget.records,
      includeBrood: widget.includeBrood,
    );
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final points = days == 0
        ? all
        : all.where((point) => !point.time.isBefore(cutoff)).toList();
    final population = widget.colony.currentPopulation(widget.records);
    return _CurrentPanel(
      title: '种群数量',
      summary:
          '${all.isEmpty ? '暂无已知数量' : '当前已知合计 ${all.last.count}'} · ${widget.includeBrood ? '含卵幼茧' : '成年个体'}',
      icon: Icons.show_chart,
      expanded: widget.expanded,
      toggle: () => widget.onExpandedChanged(!widget.expanded),
      details: widget.details,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              children: [
                for (final range in [7, 30, 90, 0])
                  ChoiceChip(
                    label: Text(range == 0 ? '全部' : '$range天'),
                    selected: days == range,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => days = range),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (points.length == 1)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('已有 1 个数量时间点；继续记录后查看变化趋势'),
            )
          else if (points.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('此时间范围暂无数量记录'),
            )
          else
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: _ColonyPopulationChartPainter(
                  points,
                  Theme.of(context).colorScheme,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in <(String, int?, Color)>[
                (
                  '工蚁',
                  widget.colony.currentWorkerCount(widget.records),
                  Colors.blue,
                ),
                ('卵', population.eggs, Colors.orange),
                ('幼虫', population.larvae, Colors.green),
                ('茧', population.cocoons, Colors.purple),
              ])
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.circle, size: 9, color: entry.$3),
                  label: Text(
                    '${entry.$1} ${entry.$2 ?? '—'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
          Text(
            '曲线为${widget.includeBrood ? '含卵幼茧' : '成年个体'}的已知数量合计；未填写项不按零估算',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _CurrentMortalityPanel extends StatefulWidget {
  const _CurrentMortalityPanel({
    super.key,
    required this.records,
    required this.colony,
    required this.expanded,
    required this.onExpandedChanged,
  });
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final List<CareRecord> records;
  final Colony colony;
  @override
  State<_CurrentMortalityPanel> createState() => _CurrentMortalityPanelState();
}

class _CurrentMortalityPanelState extends State<_CurrentMortalityPanel> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final all = dailyWorkerMortality(
      widget.colony.id,
      widget.records,
      now: now,
    );
    final start = DateTime(now.year, now.month, now.day - 29);
    final points = all.where((point) => !point.time.isBefore(start)).toList();
    final month = all
        .where(
          (point) =>
              point.time.year == now.year && point.time.month == now.month,
        )
        .toList();
    String total(List<PopulationPoint> list) => list.isEmpty
        ? '—'
        : '${list.fold<int>(0, (sum, point) => sum + point.count)}';
    return _CurrentPanel(
      title: '死亡分析',
      summary: points.isEmpty
          ? '近30天暂无工蚁死亡数量记录'
          : '近30天记录 ${total(points)} 只工蚁死亡',
      icon: Icons.monitor_heart_outlined,
      expanded: widget.expanded,
      toggle: () => widget.onExpandedChanged(!widget.expanded),
      details: WorkerMortalityAnalysisCard(points: all),
      child: Column(
        children: [
          if (points.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('近30天暂无工蚁死亡数量记录'),
            )
          else
            SizedBox(
              height: 115,
              width: double.infinity,
              child: CustomPaint(
                painter: _DetailMortalityPainter(
                  points,
                  start,
                  Theme.of(context).colorScheme,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final entry in [
                ('本月工蚁死亡', total(month)),
                ('近30天', total(points)),
                ('记录天数', '${points.length}'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _DetailSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Text(
                              entry.$1,
                              style: const TextStyle(fontSize: 10),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.$2,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Text('仅汇总已记录数量；未记录日期不视为零。', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _DetailMortalityPainter extends CustomPainter {
  _DetailMortalityPainter(this.points, this.start, this.colors);
  final List<PopulationPoint> points;
  final DateTime start;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final maximum = points.fold<int>(
      1,
      (value, point) => math.max(value, point.count),
    );
    final plot = Rect.fromLTRB(28, 8, size.width - 4, size.height - 22);
    void text(String value, Offset offset) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, offset);
      painter.dispose();
    }

    for (final tick in <int>{0, maximum ~/ 2, maximum}) {
      final y = plot.bottom - tick / maximum * plot.height;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()..color = colors.outlineVariant,
      );
      text('$tick', Offset(0, y - 6));
    }
    for (final point in points) {
      final day = DateUtils.dateOnly(point.time).difference(start).inDays;
      final x = plot.left + (day + .5) / 30 * plot.width;
      canvas.drawRect(
        Rect.fromLTRB(
          x - plot.width / 100,
          plot.bottom - point.count / maximum * plot.height,
          x + plot.width / 100,
          plot.bottom,
        ),
        Paint()..color = colors.error.withValues(alpha: .65),
      );
    }
    text('${start.month}/${start.day}', Offset(plot.left, plot.bottom + 6));
    final end = DateTime(start.year, start.month, start.day + 29);
    text('${end.month}/${end.day}', Offset(plot.right - 30, plot.bottom + 6));
  }

  @override
  bool shouldRepaint(_DetailMortalityPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.colors != colors ||
      oldDelegate.start != start;
}

class _CurrentDiaryCard extends StatelessWidget {
  const _CurrentDiaryCard({required this.record, required this.details});
  final CareRecord record;
  final Widget details;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: _DetailSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_stories_outlined, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.type.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _dateTime(record.occurredAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    record.note?.trim().isNotEmpty == true
                        ? record.note!
                        : '已记录养护信息',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (record.workerMortalityCount != null)
                    Text(
                      '工蚁死亡 ${record.workerMortalityCount}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (record.queenMortalityCount != null)
                    Text(
                      '蚁后死亡 ${record.queenMortalityCount}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (context) => SafeArea(
                        child: SingleChildScrollView(child: details),
                      ),
                    ),
                    child: const Text('查看详情', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
            if (record.photos.isNotEmpty) ...[
              const SizedBox(width: 8),
              _StoredImage(
                relativePath: record.photos.first,
                width: 76,
                height: 76,
                borderRadius: 9,
                previewTitle: record.type.label,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _CurrentDiaryFilters extends StatelessWidget {
  const _CurrentDiaryFilters({
    required this.type,
    required this.showMilestones,
    required this.timeLabel,
    required this.onType,
    required this.onTime,
    required this.onSearch,
  });
  final String type;
  final bool showMilestones;
  final String timeLabel;
  final ValueChanged<String> onType;
  final ValueChanged<_DiaryTimeFilter> onTime;
  final ValueChanged<String> onSearch;
  @override
  Widget build(BuildContext context) {
    Widget label(IconData icon, String text) => _DetailSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Icon(Icons.expand_more, size: 13),
          ],
        ),
      ),
    );
    final typePicker = PopupMenuButton<String>(
      key: const ValueKey('diary-type-filter'),
      tooltip: '按日记类别筛选',
      onSelected: onType,
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('全部类别')),
        for (final value in CareRecordType.values)
          PopupMenuItem(value: value.storageValue, child: Text(value.label)),
        if (showMilestones)
          const PopupMenuItem(value: 'milestone', child: Text('里程碑')),
      ],
      child: label(
        Icons.category_outlined,
        type.isEmpty
            ? '全部类别'
            : type == 'milestone'
            ? '里程碑'
            : CareRecordType.fromStorage(type).label,
      ),
    );
    final timePicker = PopupMenuButton<_DiaryTimeFilter>(
      key: const ValueKey('diary-time-filter'),
      tooltip: '按时间筛选',
      onSelected: onTime,
      itemBuilder: (_) => [
        for (final value in _DiaryTimeFilter.values)
          PopupMenuItem(value: value, child: Text(value.label)),
      ],
      child: label(Icons.calendar_month_outlined, timeLabel),
    );
    final search = TextField(
      key: const ValueKey('diary-search'),
      style: const TextStyle(fontSize: 12),
      onChanged: onSearch,
      decoration: InputDecoration(
        hintText: '搜索',
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 30),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(12) > 16) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: typePicker),
                    const SizedBox(width: 6),
                    Expanded(child: timePicker),
                  ],
                ),
                const SizedBox(height: 6),
                search,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: typePicker),
              const SizedBox(width: 6),
              Expanded(child: timePicker),
              const SizedBox(width: 6),
              Expanded(child: search),
            ],
          );
        },
      ),
    );
  }
}
