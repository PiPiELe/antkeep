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
  Widget build(BuildContext context) => ReadableWidth(
    maxWidth: 1040,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: (_) => onSearch(),
                  decoration: InputDecoration(
                    hintText: '搜索品种 / 编号 / 标签',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            onPressed: () {
                              search.clear();
                              onSearch();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: '新增蚁群',
                onPressed: onAdd,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: '筛选',
                onPressed: onFilter,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in quickFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: filter,
                  ),
              ],
            ),
          ),
          if (conditions.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 4, children: conditions),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(count == total ? '$count 群' : '$count/$total 群'),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 4),
                      Text(_orderLabel(order)),
                      const Icon(Icons.expand_more, size: 16),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<ColonyDisplayStyle>(
                tooltip: '切换列表样式',
                initialValue: style,
                onSelected: onStyle,
                itemBuilder: (_) => [
                  for (final value in ColonyDisplayStyle.values)
                    PopupMenuItem(value: value, child: Text(value.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.view_list_outlined, size: 18),
                      const SizedBox(width: 4),
                      Text(style.label),
                    ],
                  ),
                ),
              ),
              if (onBatch != null)
                IconButton(
                  tooltip: '批量养护记录',
                  onPressed: onBatch,
                  icon: const Icon(Icons.playlist_add_check),
                ),
              if (onClear != null)
                TextButton(onPressed: onClear, child: const Text('显示全部')),
            ],
          ),
        ],
      ),
    ),
  );
}

String _orderLabel(ColonyWorkerOrder order) => switch (order) {
  ColonyWorkerOrder.manual => '默认排序',
  ColonyWorkerOrder.ascending => '工蚁少到多',
  ColonyWorkerOrder.descending => '工蚁多到少',
};
