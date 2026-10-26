import 'package:flutter/material.dart';

import '../app_preferences.dart';
import 'readable_width.dart';
import '../domain/colony_list_filter.dart';

/// All list densities share the same controls and caller-owned query state.
class ColonyListToolbar extends StatelessWidget {
  const ColonyListToolbar({
    super.key,
    required this.search,
    required this.onSearch,
    required this.onAdd,
    required this.onFilter,
    required this.style,
    required this.onStyle,
    required this.order,
    required this.onOrder,
    required this.count,
    required this.total,
    required this.quickFilters,
    required this.conditions,
    this.onBatch,
    this.onClear,
  });

  final TextEditingController search;
  final VoidCallback onSearch, onAdd, onFilter;
  final ColonyDisplayStyle style;
  final ValueChanged<ColonyDisplayStyle> onStyle;
  final ColonyWorkerOrder order;
  final ValueChanged<ColonyWorkerOrder> onOrder;
  final int count, total;
  final List<Widget> quickFilters, conditions;
  final VoidCallback? onBatch, onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outline = scheme.outlineVariant;
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: outline),
    );
    Widget separator() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 18,
        child: VerticalDivider(width: 1, color: outline),
      ),
    );
    Widget menuLabel(IconData icon, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Text(label),
          const SizedBox(width: 6),
          const Icon(Icons.expand_more, size: 20),
        ],
      ),
    );

    return ReadableWidth(
      maxWidth: 1040,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: (_) => onSearch(),
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '搜索品种 / 编号 / 标签',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 22),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空搜索',
                              onPressed: () {
                                search.clear();
                                onSearch();
                              },
                              icon: const Icon(Icons.close, size: 20),
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      constraints: const BoxConstraints(minHeight: 44),
                      border: searchBorder,
                      enabledBorder: searchBorder,
                      focusedBorder: searchBorder.copyWith(
                        borderSide: BorderSide(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: '新增蚁群',
                  onPressed: onAdd,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    fixedSize: const Size(44, 44),
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(Icons.add, size: 28),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: '筛选',
                  onPressed: onFilter,
                  style: IconButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    fixedSize: const Size(44, 44),
                    side: BorderSide(color: outline),
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(Icons.tune, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Theme(
              data: theme.copyWith(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                chipTheme: theme.chipTheme.copyWith(
                  backgroundColor: scheme.surfaceContainerLow,
                  selectedColor: scheme.primary,
                  checkmarkColor: scheme.onPrimary,
                  labelStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13.5,
                  ),
                  secondaryLabelStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontSize: 13.5,
                  ),
                  side: WidgetStateBorderSide.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.selected)
                          ? scheme.primary
                          : outline,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  showCheckmark: true,
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < quickFilters.length; i++) ...[
                      if (i != 0) const SizedBox(width: 8),
                      quickFilters[i],
                    ],
                  ],
                ),
              ),
            ),
            if (conditions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, runSpacing: 4, children: conditions),
              ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IconTheme.merge(
                data: IconThemeData(color: scheme.onSurfaceVariant),
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  child: Row(
                    children: [
                      Text(
                        count == total ? '$count 群' : '$count/$total 群',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      separator(),
                      PopupMenuButton<ColonyWorkerOrder>(
                        tooltip: '排序方式',
                        initialValue: order,
                        onSelected: onOrder,
                        itemBuilder: (_) => [
                          for (final value in ColonyWorkerOrder.values)
                            PopupMenuItem(
                              value: value,
                              child: Text(_orderLabel(value)),
                            ),
                        ],
                        child: menuLabel(Icons.sort, _orderLabel(order)),
                      ),
                      separator(),
                      PopupMenuButton<ColonyDisplayStyle>(
                        tooltip: '切换列表样式',
                        initialValue: style,
                        onSelected: onStyle,
                        itemBuilder: (_) => [
                          for (final value in ColonyDisplayStyle.values)
                            PopupMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        child: menuLabel(Icons.grid_view_outlined, style.label),
                      ),
                      if (onBatch != null)
                        IconButton(
                          tooltip: '批量养护记录',
                          onPressed: onBatch,
                          icon: const Icon(Icons.playlist_add_check),
                        ),
                      if (onClear != null)
                        TextButton(
                          onPressed: onClear,
                          child: const Text('显示全部'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _orderLabel(ColonyWorkerOrder order) => switch (order) {
  ColonyWorkerOrder.manual => '默认排序',
  ColonyWorkerOrder.ascending => '工蚁少到多',
  ColonyWorkerOrder.descending => '工蚁多到少',
};
