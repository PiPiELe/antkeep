import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'app_preferences.dart';
import 'data/app_database.dart';
import 'date_display.dart';
import 'memorial_share_page.dart';
import 'domain/memorial.dart';
import 'domain/models.dart';
import 'widgets/memorial_kind_icon.dart';
import 'widgets/tombstone_icon.dart';

typedef OpenMemorialColony = Future<void> Function(BuildContext, String);

class MemorialPage extends StatefulWidget {
  const MemorialPage({super.key, required this.onOpenColony, this.preferences});
  final OpenMemorialColony onOpenColony;
  final AppPreferences? preferences;

  @override
  State<MemorialPage> createState() => _MemorialPageState();
}

class _MemorialPageState extends State<MemorialPage> {
  late Future<({List<Memorial> memorials, Map<String, String> colonyNames})>
  _items;
  StreamSubscription<void>? _changes;
  final _expandedGroups = <String>{};
  bool _initialGroupOpened = false;
  bool _grouped = false;
  bool _savingGrouping = false;
  bool _newestFirst = true;
  String _selectedColonyId = '';

  ColorFilter _footerFilter(Color background, Brightness brightness) {
    if (brightness == Brightness.light) {
      return ColorFilter.mode(background, BlendMode.multiply);
    }
    final value = background.toARGB32();
    final red = ((value >> 16) & 0xff).toDouble();
    final green = ((value >> 8) & 0xff).toDouble();
    final blue = (value & 0xff).toDouble();
    // White in the artwork becomes the chosen surface; the engraved details
    // become a restrained warm highlight on dark surfaces.
    return ColorFilter.matrix([
      -0.4485,
      -0.8805,
      -0.171,
      0,
      red + 382.5,
      -0.381,
      -0.7485,
      -0.1455,
      0,
      green + 325.5,
      -0.3135,
      -0.6165,
      -0.120,
      0,
      blue + 268.5,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  @override
  void initState() {
    super.initState();
    _grouped = widget.preferences?.memorialGrouped ?? true;
    _reload();
    _changes = AppDatabase.instance.memorialChanges.listen((_) {
      if (mounted) setState(_reload);
    });
  }

  void _reload() {
    _items = _loadItems();
  }

  Future<({List<Memorial> memorials, Map<String, String> colonyNames})>
  _loadItems() async => (
    memorials: await AppDatabase.instance.listMemorials(),
    colonyNames: await AppDatabase.instance.memorialColonyNames(),
  );

  Future<void> _setGrouped(bool value) async {
    if (_savingGrouping) return;
    setState(() => _savingGrouping = true);
    try {
      await widget.preferences?.setMemorialGrouped(value);
      if (mounted) setState(() => _grouped = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存展示方式失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _savingGrouping = false);
    }
  }

  Widget _memorialCard(Memorial item, {bool grouped = false}) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: grouped ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: dark ? colors.surfaceContainerLow : const Color(0xFFFFFCF9),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(grouped ? 0 : 18),
        side: grouped
            ? BorderSide.none
            : BorderSide(
                color: dark ? colors.outlineVariant : const Color(0xFFEADDD2),
              ),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MemorialDetailPage(
              memorialId: item.id,
              onOpenColony: widget.onOpenColony,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/memorial/memorial-render-hero.png',
                  width: 94,
                  height: 94,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: dark ? colors.primary : const Color(0xFF60529B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.kind.epitaph,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.species ?? '品种未填写'} · ${item.diedOn == null ? '日期未填写' : chineseDate(item.diedOn!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    if (item.farewell?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: dark
                              ? colors.surfaceContainerHighest
                              : const Color(0xFFFBF1E6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '「${item.farewell!.trim()}」',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: dark
                                    ? colors.onSurface
                                    : const Color(0xFF92531D),
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right,
                size: 21,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupCard(
    MapEntry<String, List<Memorial>> group,
    Map<String, String> colonyNames,
  ) {
    final title = group.key.isEmpty
        ? '未关联蚁群'
        : colonyNames[group.key] ?? '已删除的蚁群';
    final expanded = _expandedGroups.contains(group.key);
    final kind = group.value.first.kind;
    final kindName = switch (kind) {
      MemorialKind.colony => '蚁群',
      MemorialKind.queen => '蚁后',
      MemorialKind.worker => '工蚁',
      MemorialKind.brood => '幼体',
    };
    final iconColor = switch (kind) {
      MemorialKind.colony => const Color(0xFF8F4D0C),
      MemorialKind.queen => const Color(0xFF783C31),
      MemorialKind.worker => const Color(0xFF3D374D),
      MemorialKind.brood => const Color(0xFF56734D),
    };
    final iconBackground = switch (kind) {
      MemorialKind.colony => const Color(0xFFFBE2C9),
      MemorialKind.queen => const Color(0xFFF0D2CF),
      MemorialKind.worker => const Color(0xFFE6DDF0),
      MemorialKind.brood => const Color(0xFFE0EAD9),
    };
    void toggle() => setState(() {
      if (expanded) {
        _expandedGroups.remove(group.key);
      } else {
        _expandedGroups.add(group.key);
      }
    });
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shadowColor: const Color(0x403B2615),
      color: Theme.of(context).brightness == Brightness.dark
          ? colors.surfaceContainerLow
          : const Color(0xFFFFFAF5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? colors.outlineVariant
              : const Color(0xFFF1E5DA),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: toggle,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: iconBackground,
                      child: MemorialKindIcon(
                        kind: kind,
                        size: 30,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${group.value.length} 条$kindName纪念',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '${expanded ? '折叠' : '展开'}$title',
                      onPressed: toggle,
                      icon: Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            for (final item in group.value) ...[
              const Divider(height: 1),
              _memorialCard(item, grouped: true),
            ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _add({bool wholeColony = false}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MemorialFormPage(wholeColony: wholeColony),
      ),
    );
  }

  Widget _header(Map<String, String> colonyNames) {
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stackedControls = width < 370 || textScale > 1.15;
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    return SizedBox(
      height: width / 2.35 + (textScale - 1) * 80 + (stackedControls ? 48 : 0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/memorial/memorial-render-hero.png',
            fit: BoxFit.cover,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xBFFBF6F0),
                  Color(0x55FBF6F0),
                  Color(0x00FBF6F0),
                ],
                stops: [0, 0.34, 0.65],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 23, 17, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '英灵殿',
                  style: TextStyle(
                    fontSize: 28,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF17120E),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '铭记每一只离去的伙伴，\n它们曾为蚁群付出。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF5C606D),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 7,
                    children: [
                      Material(
                        color: const Color(0xFFFBE8D5),
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _savingGrouping
                              ? null
                              : () => _setGrouped(!_grouped),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: _grouped
                                        ? accent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: accent,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: _grouped
                                      ? Icon(
                                          Icons.check,
                                          size: 15,
                                          color: onAccent,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '按蚁群折叠',
                                  style: const TextStyle(
                                    color: Color(0xFF79400C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: stackedControls ? 160 : width * 0.28,
                        height: 36,
                        padding: const EdgeInsets.only(left: 13, right: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFCF9),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: colonyNames.containsKey(_selectedColonyId)
                                ? _selectedColonyId
                                : '',
                            isExpanded: true,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF555B68),
                            ),
                            dropdownColor: const Color(0xFFFFFCF9),
                            style: const TextStyle(
                              color: Color(0xFF202027),
                              fontSize: 13,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('全部蚁群'),
                              ),
                              for (final entry in colonyNames.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(
                                    entry.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _selectedColonyId = value ?? ''),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    floatingActionButton: MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const TombstoneIcon(size: 24),
          onPressed: () => _add(),
          child: const Text('单独添加'),
        ),
        MenuItemButton(
          leadingIcon: const TombstoneIcon(size: 24),
          onPressed: () => _add(wholeColony: true),
          child: const Text('整群移入'),
        ),
      ],
      builder: (context, controller, child) {
        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final buttonColor = Color.lerp(
          primary,
          Colors.black,
          theme.brightness == Brightness.dark ? 0.48 : 0.12,
        )!;
        return Tooltip(
          message: '添加纪念',
          child: Material(
            color: buttonColor,
            elevation: 4,
            shadowColor: const Color(0x40472A17),
            borderRadius: BorderRadius.circular(13),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(buttonColor, Colors.white, 0.14)!,
                    Color.lerp(buttonColor, Colors.black, 0.18)!,
                  ],
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 31,
                        height: 30,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: TombstoneIcon(
                                size: 26,
                                color: Colors.white,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Icon(
                                Icons.add,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '新增纪念',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
    body:
        FutureBuilder<
          ({List<Memorial> memorials, Map<String, String> colonyNames})
        >(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('加载失败，点击重试'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final allColonyNames = <String, String>{};
            for (final item in data.memorials) {
              if (item.colonyId != null) {
                allColonyNames[item.colonyId!] =
                    data.colonyNames[item.colonyId!] ?? '已删除的蚁群';
              }
            }
            final selected = allColonyNames.containsKey(_selectedColonyId)
                ? _selectedColonyId
                : '';
            final items =
                data.memorials
                    .where(
                      (item) => selected.isEmpty || item.colonyId == selected,
                    )
                    .toList()
                  ..sort(
                    (a, b) => _newestFirst
                        ? b.createdAt.compareTo(a.createdAt)
                        : a.createdAt.compareTo(b.createdAt),
                  );
            final groups = <String, List<Memorial>>{};
            for (final item in items) {
              groups.putIfAbsent(item.colonyId ?? '', () => []).add(item);
            }
            final grouped = groups.entries.toList();
            if (_grouped && !_initialGroupOpened && grouped.isNotEmpty) {
              _expandedGroups.add(grouped.first.key);
              _initialGroupOpened = true;
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ColorFiltered(
                        colorFilter: _footerFilter(
                          Theme.of(context).scaffoldBackgroundColor,
                          Theme.of(context).brightness,
                        ),
                        child: Image.asset(
                          'assets/memorial/memorial-render-footer.png',
                          width: double.infinity,
                          height: 110,
                          fit: BoxFit.cover,
                          alignment: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                ),
                ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    _header(allColonyNames),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 18, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '共 ${groups.length} 个蚁群 · ${items.length} 条纪念',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                          PopupMenuButton<bool>(
                            tooltip: '纪念排序',
                            initialValue: _newestFirst,
                            onSelected: (value) =>
                                setState(() => _newestFirst = value),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: true, child: Text('最新添加优先')),
                              PopupMenuItem(
                                value: false,
                                child: Text('最早添加优先'),
                              ),
                            ],
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sort, size: 18),
                                const SizedBox(width: 5),
                                const Text('按时间排序'),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 70, 28, 20),
                        child: Column(
                          children: [
                            const TombstoneIcon(size: 56),
                            const SizedBox(height: 16),
                            Text(
                              selected.isEmpty ? '为逝去的小生命留一份纪念' : '这个蚁群还没有纪念',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '它们无声地来过，却曾竭尽全力地活着。',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            if (_grouped)
                              for (final group in grouped)
                                _groupCard(group, data.colonyNames)
                            else
                              for (final item in items) _memorialCard(item),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
  );
}

class MemorialFormPage extends StatefulWidget {
  const MemorialFormPage({
    super.key,
    this.wholeColony = false,
    this.colony,
    this.memorial,
    this.initialId,
    this.initialKind,
    this.initialDiedOn,
    this.lockKind = false,
  });
  final bool wholeColony;
  final Colony? colony;
  final Memorial? memorial;
  final String? initialId;
  final MemorialKind? initialKind;
  final DateTime? initialDiedOn;
  final bool lockKind;

  @override
  State<MemorialFormPage> createState() => _MemorialFormPageState();
}

class _MemorialFormPageState extends State<MemorialFormPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _species;
  late final TextEditingController _farewell;
  late final TextEditingController _cause;
  late final TextEditingController _observation;
  late final TextEditingController _lesson;
  late MemorialKind _kind;
  String? _colonyId;
  DateTime? _diedOn;
  List<Colony> _colonies = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late final String _id;

  @override
  void initState() {
    super.initState();
    final item = widget.memorial;
    _id = widget.initialId ?? const Uuid().v4();
    _kind =
        item?.kind ??
        widget.initialKind ??
        (widget.wholeColony ? MemorialKind.colony : MemorialKind.queen);
    _colonyId = item?.colonyId ?? widget.colony?.id;
    _diedOn = item?.diedOn ?? widget.initialDiedOn;
    _name = TextEditingController(text: item?.name ?? widget.colony?.name);
    _species = TextEditingController(
      text: item?.species ?? widget.colony?.species,
    );
    _farewell = TextEditingController(text: item?.farewell);
    _cause = TextEditingController(text: item?.cause);
    _observation = TextEditingController(text: item?.observation);
    _lesson = TextEditingController(text: item?.lesson);
    _loadColonies();
  }

  Future<void> _loadColonies() async {
    try {
      final colonies = await AppDatabase.instance.listColonies();
      if (_colonyId != null && !colonies.any((c) => c.id == _colonyId)) {
        final linked = await AppDatabase.instance.findColony(_colonyId!);
        if (linked != null) colonies.add(linked);
      }
      if (mounted) {
        setState(() {
          _colonies = colonies;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '蚁群加载失败，请重试';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _species,
      _farewell,
      _cause,
      _observation,
      _lesson,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_kind == MemorialKind.colony &&
        _colonyId == null &&
        widget.memorial == null) {
      setState(() => _error = '请选择要移入的蚁群');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_kind == MemorialKind.colony && widget.memorial == null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('整群移入英灵殿？'),
            content: const Text('档案、照片和日记都会保留，自动扩充将关闭。可以从纪念详情恢复到饲养列表。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认移入'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      String? optional(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      await AppDatabase.instance.saveMemorial(
        Memorial(
          id: widget.memorial?.id ?? _id,
          kind: _kind,
          name: _name.text.trim(),
          createdAt: widget.memorial?.createdAt ?? DateTime.now(),
          colonyId: _colonyId,
          species: optional(_species),
          diedOn: _diedOn,
          farewell: optional(_farewell),
          cause: optional(_cause),
          observation: optional(_observation),
          lesson: optional(_lesson),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请确认关联蚁群仍存在且未重复移入后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    alignLabelWithHint: true,
    filled: true,
    fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
  );

  Widget _dropdownField<T>({
    required String label,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T?>? onChanged,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The menu needs a known row height to reopen at the selected item.
        // Measure using the bold selected style and reserve room for its check.
        var itemHeight = 56.0;
        for (final (_, text) in options) {
          final painter =
              TextPainter(
                text: TextSpan(
                  text: text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(
                maxWidth: (constraints.maxWidth - 84).clamp(
                  1.0,
                  double.infinity,
                ),
              );
          final height = painter.height + 28;
          if (height > itemHeight) itemHeight = height;
          painter.dispose();
        }
        return Theme(
          data: theme.copyWith(
            focusColor: colors.primary.withValues(alpha: 0.04),
            hoverColor: colors.primary.withValues(alpha: 0.04),
          ),
          child: ButtonTheme(
            alignedDropdown: true,
            child: DropdownButtonFormField<T>(
              initialValue: value,
              isExpanded: true,
              decoration: _fieldDecoration(label),
              borderRadius: BorderRadius.circular(16),
              dropdownColor: colors.surfaceContainerLow,
              elevation: 3,
              menuMaxHeight: 320,
              itemHeight: itemHeight,
              icon: const Icon(Icons.expand_more_rounded),
              iconEnabledColor: colors.primary,
              selectedItemBuilder: (context) => [
                for (final (_, text) in options)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              items: [
                for (final (option, text) in options)
                  DropdownMenuItem<T>(
                    value: option,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 48),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: option == value ? colors.primaryContainer : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              text,
                              style: option == value
                                  ? TextStyle(
                                      color: colors.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    )
                                  : null,
                            ),
                          ),
                          if (option == value) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: colors.onPrimaryContainer,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _formSection({
    required String title,
    required List<Widget> children,
  }) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.memorial != null
            ? '编辑纪念'
            : widget.wholeColony
            ? '帝国飞升'
            : '飞升英灵殿',
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _saving || _loading ? null : _save,
          child: Text(_saving ? '保存中…' : '保存纪念'),
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _form,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _kind == MemorialKind.colony
                        ? const TombstoneIcon(size: 40)
                        : MemorialKindIcon(kind: _kind),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _kind.epitaph,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '为相伴的时光，留一份纪念',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _formSection(
                title: '纪念信息',
                children: [
                  if (_kind != MemorialKind.colony)
                    _dropdownField<MemorialKind>(
                      label: '纪念类型',
                      value: _kind,
                      options: [
                        for (final kind in [
                          MemorialKind.queen,
                          MemorialKind.worker,
                          MemorialKind.brood,
                        ])
                          (kind, kind.label),
                      ],
                      onChanged: widget.memorial != null || widget.lockKind
                          ? null
                          : (kind) => setState(() => _kind = kind!),
                    ),
                  if (_kind != MemorialKind.colony) const SizedBox(height: 12),
                  if (_loading)
                    const LinearProgressIndicator()
                  else if (_error == '蚁群加载失败，请重试')
                    TextButton(onPressed: _loadColonies, child: Text(_error!))
                  else
                    _dropdownField<String>(
                      label: _kind == MemorialKind.colony
                          ? '移入的蚁群 *'
                          : '关联蚁群（选填）',
                      value: _colonyId ?? '',
                      options: [
                        ('', _kind == MemorialKind.colony ? '请选择蚁群' : '不关联蚁群'),
                        for (final colony in _colonies)
                          (colony.id, colony.name),
                      ],
                      onChanged:
                          widget.memorial?.kind == MemorialKind.colony ||
                              widget.colony != null
                          ? null
                          : (id) {
                              setState(() {
                                _colonyId = id == '' ? null : id;
                                if (_colonyId != null) {
                                  final colony = _colonies.firstWhere(
                                    (c) => c.id == _colonyId,
                                  );
                                  if (_name.text.trim().isEmpty ||
                                      _kind == MemorialKind.colony) {
                                    _name.text = colony.name;
                                  }
                                  if (_species.text.trim().isEmpty ||
                                      _kind == MemorialKind.colony) {
                                    _species.text = colony.species ?? '';
                                  }
                                }
                              });
                            },
                    ),
                  if (_kind == MemorialKind.queen)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '关联后可以记录蚁群的后续结局。蚁后离世不会自动结束整个蚁群，也不修改数量。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: _fieldDecoration('纪念名称 *'),
                    textInputAction: TextInputAction.next,
                    maxLength: 80,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请填写纪念名称'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _species,
                    decoration: _fieldDecoration('品种（选填）'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLow,
                    title: Text(
                      _kind == MemorialKind.colony ? '整群结束日期（选填）' : '离世日期（选填）',
                    ),
                    subtitle: Text(
                      _diedOn == null ? '未知 / 暂不填写' : chineseDate(_diedOn!),
                    ),
                    trailing: _diedOn == null
                        ? const Icon(Icons.calendar_today_outlined)
                        : IconButton(
                            tooltip: '清除日期',
                            onPressed: () => setState(() => _diedOn = null),
                            icon: const Icon(Icons.close),
                          ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _diedOn ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (date != null && mounted) {
                        setState(() => _diedOn = date);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _formSection(
                title: '告别留言',
                children: [
                  TextFormField(
                    controller: _farewell,
                    decoration: _fieldDecoration('想对它说的话（选填）'),
                    minLines: 2,
                    maxLines: 4,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: [
                    _cause,
                    _observation,
                    _lesson,
                  ].any((c) => c.text.trim().isNotEmpty),
                  maintainState: true,
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(
                    '经验记录（选填）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    '留一点经验给未来的自己',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  children: [
                    TextFormField(
                      controller: _cause,
                      decoration: _fieldDecoration('离世原因（选填，可写未知）'),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _observation,
                      decoration: _fieldDecoration('最后的观察（选填）'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _lesson,
                      decoration: _fieldDecoration('这次学到了什么（选填）'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MemorialDetailPage extends StatefulWidget {
  const MemorialDetailPage({
    super.key,
    required this.memorialId,
    required this.onOpenColony,
  });
  final String memorialId;
  final OpenMemorialColony onOpenColony;

  @override
  State<MemorialDetailPage> createState() => _MemorialDetailPageState();
}

typedef _MemorialDetail = ({
  Memorial? item,
  Colony? colony,
  List<Memorial> related,
});

class _MemorialDetailPageState extends State<MemorialDetailPage> {
  late Future<_MemorialDetail> _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _detail = _load();
  }

  Future<_MemorialDetail> _load() async {
    final items = await AppDatabase.instance.listMemorials();
    final matches = items.where((m) => m.id == widget.memorialId);
    final item = matches.isEmpty ? null : matches.single;
    final colony = item?.colonyId == null
        ? null
        : await AppDatabase.instance.findColony(item!.colonyId!);
    return (
      item: item,
      colony: colony,
      related: items
          .where(
            (m) =>
                item?.colonyId != null &&
                m.colonyId == item!.colonyId &&
                m.id != item.id,
          )
          .toList(),
    );
  }

  Future<void> _openForm({Memorial? item, Colony? colony}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MemorialFormPage(
          memorial: item,
          colony: colony,
          wholeColony: colony != null,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _remove(Memorial item, {bool restore = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(restore ? '恢复到饲养列表？' : '删除这份纪念？'),
        content: Text(
          restore
              ? '将撤销本次整群纪念，原有档案、日记和蚁后、工蚁、幼体纪念保留。自动扩充保持关闭，需要时可重新设置。'
              : '仅删除这份纪念，不影响关联蚁群和养护记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(restore ? '确认恢复' : '确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (restore) {
        await AppDatabase.instance.restoreMemorialColony(item.id);
      } else {
        await AppDatabase.instance.deleteMemorial(item.id);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('纪念详情')),
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surface
        : const Color(0xFFFBF6F1),
    body: FutureBuilder<_MemorialDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(_reload),
              child: const Text('加载失败，点击重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final detail = snapshot.data!;
        final item = detail.item;
        if (item == null) return const Center(child: Text('这份纪念已移除'));
        final colony = detail.colony;
        final ended = detail.related.where(
          (m) => m.kind == MemorialKind.colony,
        );
        final colors = Theme.of(context).colorScheme;
        final borderColor = Theme.of(context).brightness == Brightness.dark
            ? colors.outlineVariant
            : const Color(0xFFE8D9CB);
        Widget paragraph(String title, String? value) => value == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? colors.surface
                        : const Color(0xFFFFFAF6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(value),
                    ],
                  ),
                ),
              );
        final content = ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 195,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/memorial/memorial-garden-header.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xB5362519), Color(0x00362519)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 14,
                      child: Text(
                        item.kind.epitaph,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? colors.surface
                    : const Color(0xFFFFFAF6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFB47B43)
                            .withValues(alpha: 0.15),
                        child: MemorialKindIcon(
                          kind: item.kind,
                          size: 25,
                          color: const Color(0xFF9C673B),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Text(
                    '${item.kind.label} · ${item.species ?? '品种未填写'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.diedOn == null ? '日期未填写' : chineseDate(item.diedOn!),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('生成纪念分享图'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFFA56933),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemorialSharePage(memorial: item),
                ),
              ),
            ),
            paragraph('留给它的话', item.farewell),
            if (colony != null) ...[
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Theme.of(context).brightness == Brightness.dark
                    ? colors.surface
                    : const Color(0xFFFFFAF6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: borderColor),
                ),
                child: ListTile(
                  title: Text('关联蚁群 · ${colony.name}'),
                  subtitle: Text(colony.archived ? '整群已结束 · 档案与日记保留' : '仍在饲养中'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await widget.onOpenColony(context, colony.id);
                    if (mounted) setState(_reload);
                  },
                ),
              ),
              if (item.kind == MemorialKind.queen && !colony.archived)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openForm(colony: colony),
                  icon: const TombstoneIcon(size: 20),
                  label: const Text('记录后续：整群结束'),
                ),
              if (item.kind == MemorialKind.queen && ended.isNotEmpty)
                paragraph(
                  '后续结局',
                  '蚁群已于${ended.first.diedOn == null ? '日期未填写时' : chineseDate(ended.first.diedOn!)}结束，完整故事保存在下方关联纪念中。',
                ),
            ],
            if (detail.related.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('同一蚁群的纪念', style: Theme.of(context).textTheme.titleMedium),
              for (final related in detail.related)
                ListTile(
                  leading: MemorialKindIcon(kind: related.kind, size: 28),
                  title: Text(related.name),
                  subtitle: Text(
                    '${related.kind.label} · ${related.diedOn == null ? '日期未填写' : chineseDate(related.diedOn!)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MemorialDetailPage(
                          memorialId: related.id,
                          onOpenColony: widget.onOpenColony,
                        ),
                      ),
                    );
                    if (mounted) setState(_reload);
                  },
                ),
            ],
            paragraph('离世原因', item.cause),
            paragraph('最后的观察', item.observation),
            paragraph('这次学到了什么', item.lesson),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : () => _openForm(item: item),
              child: const Text('编辑纪念'),
            ),
            if (item.kind == MemorialKind.colony && colony != null)
              TextButton(
                onPressed: _busy ? null : () => _remove(item, restore: true),
                child: const Text('恢复到饲养列表'),
              )
            else
              TextButton(
                onPressed: _busy ? null : () => _remove(item),
                child: const Text('删除纪念'),
              ),
          ],
        );
        return content;
      },
    ),
  );
}
