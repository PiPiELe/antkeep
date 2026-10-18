import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'domain/models.dart';
import 'domain/purchase_price.dart';

part 'inventory_sheets.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late Future<List<InventoryItem>> _items;
  final _search = TextEditingController();
  String _category = '全部';
  String? _expanded;
  bool _owned = false;
  _InventoryFilter _filter = const _InventoryFilter();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _items = AppDatabase.instance.listInventory();
  }

  Future<void> _editProduct(List<InventoryItem>? items) async {
    final changed = await _sheet<String>(context, _ItemEditor(items: items));
    if (changed != null && mounted) {
      setState(() {
        _expanded = changed;
        _category = '全部';
        _search.clear();
        _filter = const _InventoryFilter();
        _reload();
      });
    }
  }

  Future<void> _spec(List<InventoryItem> group, [InventoryItem? spec]) async {
    final changed = await _sheet<bool>(
      context,
      _SpecEditor(group: group, spec: spec),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _record(InventoryItem item, [InventoryBatch? batch]) async {
    final changed = await _sheet<bool>(
      context,
      _RecordEditor(item: item, record: batch),
    );
    if (changed == true && mounted) setState(_reload);
  }

  InventoryItem _directItem(List<InventoryItem> group) => group.firstWhere(
    (i) => i.groupLabel == null,
    orElse: () => InventoryItem(
      id: const Uuid().v4(),
      name: group.first.productName,
      purchased: false,
      createdAt: DateTime.now(),
      purpose: group.first.purpose,
      category: group.first.categoryLabel,
      iconKey: group.first.iconKey,
      supportsExpiry: group.first.allowsExpiry,
    ),
  );

  Future<void> _showFilters() async {
    final filter = await _sheet<_InventoryFilter>(
      context,
      _FilterEditor(filter: _filter, owned: _owned),
    );
    if (filter != null && mounted) setState(() => _filter = filter);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: _inventoryTheme(context),
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: _palette(context).background,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editProduct(null),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          icon: const Icon(Icons.add),
          label: const Text('新增物品'),
        ),
        body: FutureBuilder<List<InventoryItem>>(
          future: _items,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('读取物品失败'),
                      TextButton(
                        onPressed: () => setState(_reload),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }
            final groups = <String, List<InventoryItem>>{};
            for (final item in snapshot.data!) {
              groups.putIfAbsent(item.productName, () => []).add(item);
            }
            final records = [
              for (final item in snapshot.data!)
                for (final batch in item.records) (item: item, batch: batch),
            ];
            final ownedCount = groups.values
                .where((g) => g.any((i) => i.records.isNotEmpty))
                .length;
            final visible = groups.values.where((group) {
              if (_category != '全部' && group.first.categoryLabel != _category) {
                return false;
              }
              if (!inventoryMatches(_search.text, [
                group.first.productName,
                group.first.categoryLabel,
                ...group.expand((i) => [i.childLabel, i.purpose, i.specNote]),
              ])) {
                return false;
              }
              final hasRecords = group.any((i) => i.records.isNotEmpty);
              return _filter.status == '全部' ||
                  (_filter.status == '已入手') == hasRecords;
            }).toList();
            visible.sort((a, b) {
              if (_filter.sort == '未入手优先') {
                final left = a.any((i) => i.records.isNotEmpty) ? 1 : 0;
                final right = b.any((i) => i.records.isNotEmpty) ? 1 : 0;
                if (left != right) return left.compareTo(right);
              }
              final order = a.first.productName.toLowerCase().compareTo(
                b.first.productName.toLowerCase(),
              );
              return _filter.sort == '名称 Z-A' ? -order : order;
            });
            final visibleIds = visible
                .expand((g) => g.map((i) => i.id))
                .toSet();
            final ownedRecords = records
                .where(
                  (r) =>
                      visibleIds.contains(r.item.id) &&
                      _filter.matchesBatch(r.batch),
                )
                .toList();
            final order = {
              for (var index = 0; index < visible.length; index++)
                visible[index].first.productName: index,
            };
            ownedRecords.sort(
              (a, b) => order[a.item.productName]!.compareTo(
                order[b.item.productName]!,
              ),
            );
            final attention = ownedRecords
                .where((r) => r.batch.isExpired() || r.batch.isExpiring())
                .toList();
            final ordinary = ownedRecords
                .where((r) => !r.batch.isExpired() && !r.batch.isExpiring())
                .toList();
            return Column(
              children: [
                Row(
                  children: [
                    _tab(context, '推荐 (${groups.length})', false),
                    _tab(context, '已入手 ($ownedCount)', true),
                  ],
                ),
                Column(
                  children: [
                    if (_owned)
                      _stats(
                        context,
                        ownedCount,
                        records.where((r) => r.batch.isExpiring()).length,
                        records.where((r) => r.batch.isExpired()).length,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 13, 15, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '搜索名称、用途或规格',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: '清空搜索',
                                        onPressed: () =>
                                            setState(_search.clear),
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: _showFilters,
                              icon: Icon(
                                _filter.active
                                    ? Icons.filter_alt
                                    : Icons.filter_alt_outlined,
                                size: 18,
                              ),
                              label: const Text('筛选'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 58,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        scrollDirection: Axis.horizontal,
                        itemCount: inventoryCategories.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final value = ['全部', ...inventoryCategories][index];
                          return Center(
                            child: _choice(
                              context,
                              value,
                              _category == value,
                              () => setState(() => _category = value),
                            ),
                          );
                        },
                      ),
                    ),
                    if (!_owned)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(17, 0, 17, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: _muted(
                                context,
                                '共 ${visible.length} 件匹配物品',
                                size: 11,
                              ),
                            ),
                            _muted(
                              context,
                              _filter.sort == '未入手优先'
                                  ? '已入手的自动靠后'
                                  : _filter.sort,
                              size: 11,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: CustomScrollView(
                    key: PageStorageKey('inventory-$_owned'),
                    slivers: [
                      if (_owned) ...[
                        if (ownedRecords.isEmpty)
                          SliverToBoxAdapter(
                            child: _empty(
                              context,
                              '没有匹配的入手记录',
                              '在推荐中选择物品，记录你的第一次入手。',
                            ),
                          ),
                        if (attention.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _section(
                              context,
                              '需要关注 · ${attention.length} 批物品',
                              warning: true,
                            ),
                          ),
                        SliverList.list(
                          children: [
                            for (final r in attention)
                              _recordCard(context, r.item, r.batch),
                          ],
                        ),
                        if (ordinary.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _section(
                              context,
                              '我的物品 · ${ordinary.length} 条入手记录',
                            ),
                          ),
                        SliverList.list(
                          children: [
                            for (final r in ordinary)
                              _recordCard(context, r.item, r.batch),
                          ],
                        ),
                        if (ownedRecords.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: _info(
                                context,
                                '只有单独填写了有效期的入手批次，才会参与临期提醒。',
                              ),
                            ),
                          ),
                      ] else ...[
                        if (visible.isEmpty)
                          SliverToBoxAdapter(
                            child: _empty(context, '没有找到匹配物品', '试试其他关键词或筛选条件。'),
                          ),
                        SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) =>
                              _productCard(context, visible[index]),
                        ),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _tab(BuildContext context, String label, bool owned) => Expanded(
    child: InkWell(
      onTap: () => setState(() {
        _owned = owned;
        _filter = const _InventoryFilter();
        _category = '全部';
        _search.clear();
      }),
      child: Container(
        height: 49,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _palette(context).line)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: _owned == owned ? FontWeight.w700 : FontWeight.w400,
                color: _owned == owned
                    ? Theme.of(context).colorScheme.primary
                    : _palette(context).muted,
              ),
            ),
            if (_owned == owned)
              Positioned(
                bottom: 0,
                width: 75,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
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
  );

  Widget _productCard(BuildContext context, List<InventoryItem> group) {
    final item = group.first;
    final name = item.productName;
    final specs = group.where((i) => i.groupLabel != null).toList();
    final opened = _expanded == name;
    final owned = group.any((i) => i.records.isNotEmpty);
    return Container(
      margin: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(context, opened: opened),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = opened ? null : name),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(
                children: [
                  _thumbnail(context, item),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (specs.isNotEmpty)
                              _tag(context, '${specs.length} 规格'),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '用途：${item.purpose ?? '可补充物品用途'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: _palette(context).muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            _tag(context, item.categoryLabel),
                            if (owned) _tag(context, '已入手'),
                            if (item.allowsExpiry) _tag(context, '有效期可选'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    opened ? Icons.expand_less : Icons.chevron_right,
                    size: 20,
                    color: _palette(context).muted,
                  ),
                ],
              ),
            ),
          ),
          if (opened)
            Container(
              color: _palette(context).background.withValues(alpha: .5),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '规格管理',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _muted(
                        context,
                        specs.isEmpty
                            ? '当前无预设规格'
                            : '${specs.length} 种规格 · 可继续添加',
                        size: 10,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (specs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _cardDecoration(context),
                      child: Column(
                        children: [
                          _thumbnail(context, item, size: 44),
                          const SizedBox(height: 10),
                          const Text(
                            '还没有设置规格',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _muted(
                            context,
                            '可直接记录入手，也可以按尺寸、容量或材质\n创建规格，后续随时调整。',
                            size: 11,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _record(_directItem(group)),
                                  child: const Text('直接记录入手'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _spec(group),
                                  icon: const Icon(Icons.add, size: 17),
                                  label: const Text('添加规格'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else ...[
                    for (final spec in specs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            _thumbnail(context, spec, size: 37),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    spec.childLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  _muted(
                                    context,
                                    spec.records.isEmpty
                                        ? (spec.specNote ?? '未入手')
                                        : '已入手 · ${spec.records.length} 批',
                                    size: 10,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '编辑规格 ${spec.childLabel}',
                              onPressed: () => _spec(group, spec),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                            IconButton.filled(
                              tooltip: '添加入手 ${spec.childLabel}',
                              onPressed: () => _record(spec),
                              icon: const Icon(Icons.add, size: 20),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _spec(group),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加规格'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _record(_directItem(group)),
                        child: const Text('不区分规格，直接记录入手'),
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _editProduct(group),
                      child: const Text('编辑物品资料'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _recordCard(
    BuildContext context,
    InventoryItem item,
    InventoryBatch record,
  ) {
    final warning = record.isExpired() || record.isExpiring();
    return Container(
      margin: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      decoration: _cardDecoration(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _record(item, record),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              _thumbnail(context, item),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.groupLabel == null
                              ? item.name
                              : '${item.productName} · ${item.childLabel}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (warning)
                          _tag(
                            context,
                            record.isExpired() ? '已过期' : '即将到期',
                            warning: true,
                          ),
                        if (record.quantity == 0) _tag(context, '已用完'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _muted(
                      context,
                      '数量 ${record.quantity ?? '未填写'}${record.note == null ? '' : ' · ${record.note}'}',
                      size: 11,
                    ),
                    if (record.expiresAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '有效期至 ${_date(record.expiresAt!)}${record.isExpiring() ? ' · 剩余 ${record.daysRemaining()} 天' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: warning
                                ? _palette(context).warning
                                : _palette(context).muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.edit_outlined,
                color: _palette(context).muted,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryFilter {
  const _InventoryFilter({
    this.status = '全部',
    this.expiry = '全部',
    this.sort = '未入手优先',
  });
  final String status;
  final String expiry;
  final String sort;
  bool get active => status != '全部' || expiry != '全部' || sort != '未入手优先';
  bool matchesBatch(InventoryBatch record) => switch (expiry) {
    '即将到期' => record.isExpiring(),
    '已过期' => record.isExpired(),
    '未设置有效期' => record.expiresAt == null,
    _ => true,
  };
}

({Color background, Color surface, Color line, Color muted, Color warning})
_palette(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.brightness == Brightness.dark
      ? (
          background: const Color(0xff081521),
          surface: const Color(0xff15283b),
          line: const Color(0xff304b65),
          muted: const Color(0xffa0b7cc),
          warning: const Color(0xffedc48e),
        )
      : (
          background: scheme.surface,
          surface: scheme.surfaceContainerLow,
          line: scheme.outlineVariant,
          muted: scheme.onSurfaceVariant,
          warning: const Color(0xff946016),
        );
}

ThemeData _inventoryTheme(BuildContext context) {
  final theme = Theme.of(context);
  final colors = _palette(context);
  final scheme = theme.brightness == Brightness.dark
      ? theme.colorScheme.copyWith(
          primary: const Color(0xffb7d6fd),
          onPrimary: const Color(0xff092139),
          surface: colors.surface,
          onSurface: const Color(0xfff1f6fd),
          onSurfaceVariant: colors.muted,
          outline: colors.line,
        )
      : theme.colorScheme;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return theme.copyWith(
    colorScheme: scheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.background.withValues(alpha: .4),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: TextStyle(fontSize: 12, color: colors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        side: BorderSide(color: colors.line),
        textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 11),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
  );
}

String _date(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
Widget _muted(BuildContext context, String text, {double size = 12}) => Text(
  text,
  style: TextStyle(fontSize: size, color: _palette(context).muted),
);
BoxDecoration _cardDecoration(BuildContext context, {bool opened = false}) =>
    BoxDecoration(
      color: _palette(context).surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: opened
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .6)
            : _palette(context).line,
      ),
    );
Widget _tag(BuildContext context, String label, {bool warning = false}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color:
            (warning
                    ? _palette(context).warning
                    : Theme.of(context).colorScheme.primary)
                .withValues(alpha: .14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: warning
              ? _palette(context).warning
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    );

const _icons = <String, (String, IconData)>{
  'box': ('通用箱子', Icons.inventory_2_outlined),
  'tube': ('管材', Icons.science_outlined),
  'printer': ('设备', Icons.print_outlined),
  'dish': ('喂食盘', Icons.rice_bowl_outlined),
  'lamp': ('小灯', Icons.light_outlined),
  'bottle': ('瓶装', Icons.sanitizer_outlined),
  'tool': ('工具', Icons.build_outlined),
  'drop': ('水滴', Icons.water_drop_outlined),
  'thermo': ('温湿度', Icons.thermostat_outlined),
  'scissor': ('剪刀', Icons.content_cut),
};
String _itemIcon(InventoryItem item) =>
    item.iconKey ??
    switch (item.productName) {
      '3D 打印机' => 'printer',
      '试管' || '离心管' => 'tube',
      '营养液' || '防逃液' => 'bottle',
      '喂食盘' => 'dish',
      'LED 小灯' => 'lamp',
      '镊子' || '双钩针' => 'tool',
      '恒温箱' => 'thermo',
      '小剪刀' => 'scissor',
      _ => 'box',
    };
Widget _thumbnail(
  BuildContext context,
  InventoryItem item, {
  double size = 63,
}) {
  final key = _itemIcon(item);
  return ClipRRect(
    borderRadius: BorderRadius.circular(size > 45 ? 13 : 8),
    child: key == 'box'
        ? Image.asset(
            'assets/images/inventory-placeholder.png',
            width: size,
            height: size,
          )
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .1),
              borderRadius: BorderRadius.circular(size > 45 ? 13 : 8),
              border: Border.all(color: _palette(context).line),
            ),
            child: Icon(
              (_icons[key] ?? _icons['box']!).$2,
              size: size * .5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
  );
}

Widget _choice(
  BuildContext context,
  String label,
  bool selected,
  VoidCallback onTap,
) => ChoiceChip(
  label: Text(
    label,
    style: TextStyle(
      fontSize: 11,
      color: selected
          ? Theme.of(context).colorScheme.onPrimary
          : _palette(context).muted,
    ),
  ),
  selected: selected,
  showCheckmark: false,
  onSelected: (_) => onTap(),
  selectedColor: Theme.of(context).colorScheme.primary,
  backgroundColor: _palette(context).surface,
  padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  side: BorderSide(color: _palette(context).line),
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
Widget _info(BuildContext context, String text) => Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(9),
    border: Border.all(color: _palette(context).line),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.info_outline, size: 16, color: _palette(context).muted),
      const SizedBox(width: 7),
      Expanded(child: _muted(context, text, size: 11)),
    ],
  ),
);
Widget _empty(BuildContext context, String title, String description) =>
    Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 42,
            color: _palette(context).muted,
          ),
          const SizedBox(height: 16),
          Text(title),
          const SizedBox(height: 8),
          _muted(context, description),
        ],
      ),
    );
Widget _section(BuildContext context, String title, {bool warning = false}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(17, 2, 17, 12),
      child: Row(
        children: [
          Icon(
            warning ? Icons.schedule : Icons.inventory_2_outlined,
            size: 16,
            color: warning
                ? _palette(context).warning
                : _palette(context).muted,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: warning
                    ? _palette(context).warning
                    : _palette(context).muted,
              ),
            ),
          ),
        ],
      ),
    );
Widget _stats(BuildContext context, int owned, int expiring, int expired) =>
    Container(
      margin: const EdgeInsets.fromLTRB(15, 13, 15, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: _cardDecoration(context),
      child: Row(
        children: [
          for (final entry in [
            (owned, '已入手物品'),
            (expiring, '7 天内到期'),
            (expired, '已过期'),
          ])
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${entry.$1}',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: entry.$2 == '7 天内到期'
                          ? _palette(context).warning
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _muted(context, entry.$2, size: 11),
                ],
              ),
            ),
        ],
      ),
    );
