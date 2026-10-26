import 'package:flutter/material.dart';

import 'domain/colony_growth.dart';
import 'domain/models.dart';
import 'domain/colony_tag.dart';
import 'domain/purchase_price.dart';
import 'widgets/fading_horizontal_scroll.dart';
import 'widgets/readable_width.dart';

/// Values come from local records; absent observations remain unknown.
class DenseColonyEntry {
  DenseColonyEntry({
    required this.colony,
    required this.population,
    required this.queens,
    required List<CareRecord> records,
    required this.dueFeeding,
    this.cover,
    this.tagOrder = ColonyTag.values,
  }) : records = [...records]
         ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  final List<ColonyTag> tagOrder;
  final Colony colony;
  final GrowthPopulation population;
  final int? queens;
  final List<CareRecord> records;
  final bool dueFeeding;
  final Widget? cover;
  DateTime? get lastFeeding => records
      .where((r) => r.type == CareRecordType.feeding)
      .map((r) => r.occurredAt)
      .firstOrNull;
  double? get temperature =>
      records.map((r) => r.temperature).whereType<double>().firstOrNull;
  double? get humidity =>
      records.map((r) => r.humidity).whereType<double>().firstOrNull;
}

class _Palette {
  _Palette(BuildContext context) : scheme = Theme.of(context).colorScheme;
  final ColorScheme scheme;
  bool get dark => scheme.brightness == Brightness.dark;
  Color get background => scheme.surface;
  Color get card => scheme.surfaceContainerLow;
  Color get inset => scheme.surfaceContainer;
  Color get ink => scheme.onSurface;
  Color get muted => scheme.onSurfaceVariant;
  Color get accent => scheme.primary;
}

enum _QuickFilter {
  all('全部'),
  newQueen('新后群'),
  wild('野采'),
  hundreds('百元级'),
  thousands('千元级'),
  feeding('待喂食');

  const _QuickFilter(this.label);
  final String label;
  bool matches(DenseColonyEntry e) => switch (this) {
    all => true,
    newQueen => e.colony.isNewQueenColony,
    wild => e.colony.isWildCatch,
    hundreds => e.colony.priceTier == ColonyPriceTier.hundreds,
    thousands => e.colony.priceTier == ColonyPriceTier.thousands,
    feeding => e.dueFeeding,
  };
}

class ColonyDenseList extends StatefulWidget {
  const ColonyDenseList({
    super.key,
    required this.entries,
    required this.onAdd,
    required this.onFilter,
    required this.onOpen,
    required this.onDuration,
    required this.onDelete,
    required this.onRefresh,
    this.onReorder,
    this.showCareTasks = true,
    this.header,
    this.emptyActions,
  });
  final List<DenseColonyEntry> entries;
  final VoidCallback onAdd, onFilter;
  final ValueChanged<Colony> onOpen, onDuration, onDelete;
  final Future<void> Function() onRefresh;
  final void Function(int, int)? onReorder;
  final bool showCareTasks;
  final Widget? header, emptyActions;
  @override
  State<ColonyDenseList> createState() => _ColonyDenseListState();
}

class _ColonyDenseListState extends State<ColonyDenseList> {
  String query = '';
  _QuickFilter filter = _QuickFilter.all;
  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    final quickFilters = widget.showCareTasks
        ? _QuickFilter.values
        : _QuickFilter.values
              .where((value) => value != _QuickFilter.feeding)
              .toList();
    final activeFilter = !widget.showCareTasks && filter == _QuickFilter.feeding
        ? _QuickFilter.all
        : filter;
    final entries = widget.header != null
        ? widget.entries
        : widget.entries
              .where(
                (e) =>
                    activeFilter.matches(e) &&
                    '${e.colony.name} ${e.colony.species ?? ''} ${e.colony.id} ${_labels(e).map((t) => t.$1).join(' ')}'
                        .toLowerCase()
                        .contains(query.toLowerCase().trim()),
              )
              .toList();
    final canReorder =
        widget.onReorder != null &&
        query.trim().isEmpty &&
        activeFilter == _QuickFilter.all;
    return ColoredBox(
      color: p.background,
      child: Column(
        children: [
          if (widget.header != null)
            widget.header!
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        onChanged: (value) => setState(() => query = value),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '搜索品种 / 编号 / 标签',
                          hintStyle: TextStyle(color: p.muted, fontSize: 13),
                          prefixIcon: Icon(
                            Icons.search,
                            color: p.muted,
                            size: 23,
                          ),
                          filled: true,
                          fillColor: p.inset,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  IconButton.filled(
                    onPressed: widget.onAdd,
                    tooltip: '新增蚁群',
                    style: IconButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.scheme.onPrimary,
                      minimumSize: const Size(38, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.add, size: 29),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: widget.onFilter,
                    tooltip: '筛选',
                    style: IconButton.styleFrom(
                      backgroundColor: p.inset,
                      foregroundColor: p.muted,
                      minimumSize: const Size(38, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.tune, size: 22),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 30,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: quickFilters.length,
                separatorBuilder: (_, index) => const SizedBox(width: 5),
                itemBuilder: (context, index) {
                  final item = quickFilters[index];
                  final selected = activeFilter == item;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => filter = item),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: selected ? p.accent : p.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? p.accent
                                : p.scheme.outlineVariant.withValues(alpha: .3),
                          ),
                        ),
                        child: Text(
                          '${item.label} (${widget.entries.where(item.matches).length})',
                          style: TextStyle(
                            fontSize: 11,
                            color: selected ? p.scheme.onPrimary : p.muted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ReorderableListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: readablePagePadding(
                  context,
                  maxWidth: 1040,
                  minHorizontal: 5,
                  top: 0,
                  bottom: 12,
                ),
                buildDefaultDragHandles: false,
                header: entries.isEmpty
                    ? widget.emptyActions ??
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('没有符合条件的蚁群'),
                          )
                    : null,
                itemCount: entries.length,
                onReorderItem: (a, b) {
                  if (canReorder) widget.onReorder!(a, b);
                },
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(entry.colony.id),
                    index: index,
                    enabled: canReorder,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Dismissible(
                        key: ValueKey('dense-${entry.colony.id}'),
                        direction: DismissDirection.startToEnd,
                        background: ColoredBox(
                          color: p.scheme.errorContainer,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(
                              Icons.delete_outline,
                              color: p.scheme.onErrorContainer,
                            ),
                          ),
                        ),
                        confirmDismiss: (_) async {
                          widget.onDelete(entry.colony);
                          return false;
                        },
                        child: ColonyDenseCard(
                          entry: entry,
                          onTap: () => widget.onOpen(entry.colony),
                          onDuration: () => widget.onDuration(entry.colony),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<(String, Color)> _labels(DenseColonyEntry e) {
  final available = <ColonyTag, (String, Color)>{
    if (e.colony.isNewQueenColony)
      ColonyTag.newQueen: ('新后群', const Color(0xff16812e)),
    if (e.colony.isWildCatch)
      ColonyTag.wildCatch: ('野采', const Color(0xff16812e)),
    if (ColonyScale.fromWorkerCount(e.population.workers) case final scale?)
      ColonyTag.scale: (scale.label, const Color(0xff1675ee)),
    if (e.colony.priceTier case final tier?)
      ColonyTag.price: (tier.label, const Color(0xffa66a12)),
  };
  return [for (final tag in e.tagOrder) ?available[tag]];
}

class ColonyDenseCard extends StatelessWidget {
  const ColonyDenseCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDuration,
  });
  final DenseColonyEntry entry;
  final VoidCallback onTap, onDuration;
  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    final e = entry;
    final c = e.colony;
    final days = c.husbandryDays(DateTime.now());
    final last = e.lastFeeding;
    final feedDays = last == null
        ? null
        : DateUtils.dateOnly(DateTime.now())
              .difference(DateUtils.dateOnly(last))
              .inDays;
    final labels = _labels(e);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
          child: Column(
            children: [
              SizedBox(
                height: 73,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 70,
                        height: 73,
                        child:
                            e.cover ??
                            Image.asset(
                              'assets/images/default-ant-cover.png',
                              fit: BoxFit.cover,
                            ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 22,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: FadingHorizontalScroll(
                                          key: ValueKey('dense-name-${c.id}'),
                                          child: Text(
                                            c.name,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              color: p.ink,
                                              fontSize: 14,
                                              height: 1.15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      if (c.id.length <= 8)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: p.inset,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            c.id,
                                            style: TextStyle(
                                              color: p.muted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * .36,
                                  ),
                                  child: FadingHorizontalScroll(
                                    key: ValueKey('dense-tags-${c.id}'),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final (label, color)
                                            in labels) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: p.dark ? .24 : .11,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 9,
                                                height: 1,
                                                color: p.dark
                                                    ? Color.lerp(
                                                        color,
                                                        Colors.white,
                                                        .45,
                                                      )
                                                    : color,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: e.dueFeeding
                                        ? const Color(0xffff5450)
                                        : const Color(0xff13977c),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 17,
                                  color: p.muted,
                                ),
                              ],
                            ),
                          ),
                          FadingHorizontalScroll(
                            key: ValueKey('dense-species-${c.id}'),
                            child: Text(
                              c.species ?? '—',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 34,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _metric(
                                  context,
                                  '蚁后',
                                  '${e.queens ?? '—'}',
                                  Icons.bug_report_outlined,
                                ),
                                const SizedBox(width: 4),
                                _metric(
                                  context,
                                  '工蚁',
                                  '${e.population.workers ?? '—'}',
                                  Icons.bug_report_outlined,
                                ),
                                const SizedBox(width: 4),
                                _metric(
                                  context,
                                  '幼虫',
                                  '${e.population.larvae ?? '—'}',
                                  Icons.egg_outlined,
                                ),
                                const SizedBox(width: 4),
                                _metric(
                                  context,
                                  '已养',
                                  days == null ? '—' : '$days天',
                                  Icons.calendar_today_outlined,
                                  onTap: onDuration,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: p.inset,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  children: [
                    _detail(
                      context,
                      Icons.restaurant,
                      '上次喂食 ',
                      feedDays == null ? '—' : '$feedDays天前',
                      flex: 5,
                      alert: e.dueFeeding,
                    ),
                    _divider(p),
                    _detail(
                      context,
                      Icons.thermostat_outlined,
                      '温度 ',
                      e.temperature == null
                          ? '—'
                          : '${_number(e.temperature!)}°C',
                    ),
                    _divider(p),
                    _detail(
                      context,
                      Icons.water_drop_outlined,
                      '湿度 ',
                      e.humidity == null ? '—' : '${_number(e.humidity!)}%',
                    ),
                    _divider(p),
                    _detail(
                      context,
                      Icons.sell_outlined,
                      '',
                      c.purchasePriceText == null
                          ? '—'
                          : '¥${c.purchasePriceText!.replaceFirst(RegExp(r'\.00$'), '')}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(_Palette p) => Container(
    width: .5,
    height: 12,
    color: p.scheme.outlineVariant,
    margin: const EdgeInsets.symmetric(horizontal: 10),
  );
  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final p = _Palette(context);
    return Expanded(
      child: Material(
        color: p.inset,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  _DenseLineIcon(icon, size: 17, color: p.muted),
                  const SizedBox(width: 7),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 9,
                          height: 1.3,
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    int flex = 4,
    bool alert = false,
  }) {
    final p = _Palette(context);
    return Expanded(
      flex: flex,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            _DenseLineIcon(icon, size: 13, color: p.muted),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: p.muted, fontSize: 10)),
            Text(
              value,
              style: TextStyle(
                color: alert ? p.scheme.error : p.ink,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// Scrollable destinations with fixed trailing actions.
class ColonyDenseTabs extends StatefulWidget {
  const ColonyDenseTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    required this.onRename,
    required this.onShare,
    this.onAnalysis,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected, onRename;
  final VoidCallback onShare;
  final VoidCallback? onAnalysis;
  @override
  State<ColonyDenseTabs> createState() => _ColonyDenseTabsState();
}

class _ColonyDenseTabsState extends State<ColonyDenseTabs> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: p.background,
        border: Border(
          bottom: BorderSide(
            color: p.scheme.outlineVariant.withValues(alpha: .4),
            width: .5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _scroll,
              builder: (context, child) {
                final left = _scroll.hasClients && _scroll.offset > .5;
                final right =
                    !_scroll.hasClients ||
                    _scroll.offset < _scroll.position.maxScrollExtent - .5;
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      left ? Colors.transparent : Colors.white,
                      Colors.white,
                      Colors.white,
                      right ? Colors.transparent : Colors.white,
                    ],
                    stops: const [0, .035, .965, 1],
                  ).createShader(bounds),
                  child: child,
                );
              },
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(left: 16),
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < widget.labels.length; i++)
                    SizedBox(
                      width: widget.labels[i].runes.length * 16.0 + 48,
                      child: InkWell(
                        onTap: () => widget.onSelected(i),
                        onLongPress: () => widget.onRename(i),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: Text(
                                widget.labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: i == widget.selectedIndex
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: i == widget.selectedIndex
                                      ? p.ink
                                      : p.muted,
                                ),
                              ),
                            ),
                            if (i == widget.selectedIndex)
                              Positioned(
                                bottom: 0,
                                left: 12,
                                right: 12,
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: p.accent,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
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
          if (widget.onAnalysis != null)
            SizedBox(
              width: 100,
              child: TextButton.icon(
                onPressed: widget.onAnalysis,
                icon: Icon(Icons.show_chart, color: p.accent, size: 24),
                label: Text(
                  '分析',
                  style: TextStyle(fontSize: 16, color: p.muted),
                ),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ),
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: '分享',
              onPressed: widget.onShare,
              icon: const Icon(Icons.ios_share_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _DenseLineIcon extends StatelessWidget {
  const _DenseLineIcon(this.icon, {required this.size, required this.color});
  final IconData icon;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _DenseIconPainter(icon, color),
  );
}

class _DenseIconPainter extends CustomPainter {
  const _DenseIconPainter(this.icon, this.color);
  final IconData icon;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), pen);
    if (icon == Icons.bug_report_outlined) {
      canvas.drawOval(const Rect.fromLTWH(9, 3, 6, 5), pen);
      canvas.drawOval(const Rect.fromLTWH(10, 9, 4, 5), pen);
      canvas.drawOval(const Rect.fromLTWH(9, 15, 6, 7), pen);
      line(10, 3, 9, 0);
      line(14, 3, 15, 0);
      for (final y in [9.0, 13.0, 17.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(10, y)
            ..lineTo(6, y - 2)
            ..lineTo(4, y + 3),
          pen,
        );
        canvas.drawPath(
          Path()
            ..moveTo(14, y)
            ..lineTo(18, y - 2)
            ..lineTo(20, y + 3),
          pen,
        );
      }
    } else if (icon == Icons.egg_outlined) {
      canvas.save();
      canvas.translate(12, 12);
      canvas.rotate(.5);
      canvas.drawOval(const Rect.fromLTWH(-6, -9, 12, 18), pen);
      for (final y in [-5.0, -1.0, 3.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(-5, y)
            ..quadraticBezierTo(0, y + 3, 5, y + 2),
          pen,
        );
      }
      canvas.restore();
    } else if (icon == Icons.calendar_today_outlined) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 5, 18, 16),
          const Radius.circular(2),
        ),
        pen,
      );
      line(3, 10, 21, 10);
      line(7, 2, 7, 7);
      line(17, 2, 17, 7);
    } else if (icon == Icons.thermostat_outlined) {
      canvas.drawPath(
        Path()
          ..moveTo(9, 14)
          ..lineTo(9, 5)
          ..arcToPoint(const Offset(15, 5), radius: const Radius.circular(3))
          ..lineTo(15, 14)
          ..arcToPoint(
            const Offset(9, 14),
            radius: const Radius.circular(5),
            largeArc: true,
          ),
        pen,
      );
      line(12, 7, 12, 17);
      canvas.drawCircle(const Offset(12, 18), 1.5, pen);
    } else if (icon == Icons.water_drop_outlined) {
      canvas.drawPath(
        Path()
          ..moveTo(12, 2)
          ..cubicTo(9, 7, 5, 11, 5, 15)
          ..cubicTo(5, 24, 19, 24, 19, 15)
          ..cubicTo(19, 11, 15, 7, 12, 2)
          ..close(),
        pen,
      );
      canvas.drawPath(
        Path()
          ..moveTo(9, 13)
          ..quadraticBezierTo(7, 17, 11, 18),
        pen,
      );
    } else if (icon == Icons.sell_outlined) {
      canvas.drawPath(
        Path()
          ..moveTo(12, 3)
          ..lineTo(21, 3)
          ..lineTo(21, 12)
          ..lineTo(11, 22)
          ..lineTo(2, 13)
          ..close(),
        pen,
      );
      canvas.drawCircle(const Offset(17, 7), 1, pen);
    } else if (icon == Icons.restaurant) {
      for (final x in [5.0, 8.0, 11.0]) {
        line(x, 2, x, 9);
      }
      canvas.drawPath(
        Path()
          ..moveTo(5, 8)
          ..quadraticBezierTo(8, 15, 11, 8),
        pen,
      );
      line(8, 12, 8, 22);
      line(18, 2, 18, 22);
      canvas.drawPath(
        Path()
          ..moveTo(18, 2)
          ..quadraticBezierTo(13, 6, 15, 13)
          ..lineTo(18, 13),
        pen,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DenseIconPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.color != color;
}
