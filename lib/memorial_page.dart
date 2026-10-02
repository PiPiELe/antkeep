import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'memorial_share_page.dart';
import 'domain/memorial.dart';
import 'domain/models.dart';
import 'widgets/tombstone_icon.dart';

typedef OpenMemorialColony = Future<void> Function(BuildContext, String);

class MemorialPage extends StatefulWidget {
  const MemorialPage({super.key, required this.onOpenColony});
  final OpenMemorialColony onOpenColony;

  @override
  State<MemorialPage> createState() => _MemorialPageState();
}

class _MemorialPageState extends State<MemorialPage> {
  late Future<List<Memorial>> _items;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _reload();
    _changes = AppDatabase.instance.memorialChanges.listen((_) {
      if (mounted) setState(_reload);
    });
  }

  void _reload() {
    _items = AppDatabase.instance.listMemorials();
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

  @override
  Widget build(BuildContext context) => Scaffold(
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
      builder: (context, controller, child) => FloatingActionButton(
        heroTag: 'memorial-add',
        tooltip: '添加纪念',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: const TombstoneIcon(size: 28),
      ),
    ),
    body: FutureBuilder<List<Memorial>>(
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
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TombstoneIcon(size: 64),
                  SizedBox(height: 16),
                  Text('为逝去的小生命留一份纪念'),
                  SizedBox(height: 8),
                  Text(
                    '纪念每一位渺小却不屈、奋战至最后一息的勇士，\n'
                    '纪念每一位勤勉而坚韧、为族群倾尽一生的君主，\n'
                    '纪念每一个尚未羽化、便早早沉睡的小小生命，\n'
                    '纪念每一个曾繁盛如星，终湮没于历史长河的文明。\n\n'
                    '它们无声地来过，却曾竭尽全力地活着。',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const TombstoneIcon(size: 44),
                title: Text(item.name),
                subtitle: Text(
                  '${item.kind.epitaph}\n${item.species ?? item.kind.label} · ${item.diedOn == null ? '日期未填写' : chineseDate(item.diedOn!)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MemorialDetailPage(
                      memorialId: item.id,
                      onOpenColony: widget.onOpenColony,
                    ),
                  ),
                ),
              ),
            );
          },
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
  });
  final bool wholeColony;
  final Colony? colony;
  final Memorial? memorial;

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
  final _id = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    final item = widget.memorial;
    _kind =
        item?.kind ??
        (widget.wholeColony ? MemorialKind.colony : MemorialKind.queen);
    _colonyId = item?.colonyId ?? widget.colony?.id;
    _diedOn = item?.diedOn;
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
                    const TombstoneIcon(size: 40),
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
                    DropdownButtonFormField<MemorialKind>(
                      initialValue: _kind,
                      isExpanded: true,
                      decoration: _fieldDecoration('纪念类型'),
                      items: [
                        for (final kind in [
                          MemorialKind.queen,
                          MemorialKind.worker,
                          MemorialKind.brood,
                        ])
                          DropdownMenuItem(
                            value: kind,
                            child: Text(
                              kind.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: widget.memorial != null
                          ? null
                          : (kind) => setState(() => _kind = kind!),
                    ),
                  if (_kind != MemorialKind.colony) const SizedBox(height: 12),
                  if (_loading)
                    const LinearProgressIndicator()
                  else if (_error == '蚁群加载失败，请重试')
                    TextButton(onPressed: _loadColonies, child: Text(_error!))
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _colonyId ?? '',
                      isExpanded: true,
                      decoration: _fieldDecoration(
                        _kind == MemorialKind.colony ? '移入的蚁群 *' : '关联蚁群（选填）',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(
                            _kind == MemorialKind.colony ? '请选择蚁群' : '不关联蚁群',
                          ),
                        ),
                        for (final colony in _colonies)
                          DropdownMenuItem(
                            value: colony.id,
                            child: Text(
                              colony.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
        Widget paragraph(String title, String? value) => value == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(value),
                  ],
                ),
              );
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Center(child: TombstoneIcon(size: 80)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                item.name,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                item.kind.epitaph,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${item.kind.label} · ${item.species ?? '品种未填写'}',
                textAlign: TextAlign.center,
              ),
            ),
            Center(
              child: Text(
                item.diedOn == null ? '日期未填写' : chineseDate(item.diedOn!),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('生成纪念分享图'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemorialSharePage(memorial: item),
                ),
              ),
            ),
            paragraph('留给它的话', item.farewell),
            if (colony != null) ...[
              const SizedBox(height: 20),
              Card(
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
                  leading: const TombstoneIcon(),
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
      },
    ),
  );
}
