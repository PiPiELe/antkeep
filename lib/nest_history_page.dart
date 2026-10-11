import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/models.dart';
import 'domain/nest_entry.dart';

class NestHistoryPage extends StatefulWidget {
  const NestHistoryPage({super.key, required this.colony});

  final Colony colony;

  @override
  State<NestHistoryPage> createState() => _NestHistoryPageState();
}

class _NestHistoryPageState extends State<NestHistoryPage> {
  late Future<List<NestEntry>> _entries = _load();
  late Colony _colony = widget.colony;

  Future<List<NestEntry>> _load() =>
      AppDatabase.instance.listNestEntries(widget.colony.id);

  Future<void> _refresh() async {
    final colony = await AppDatabase.instance.findColony(widget.colony.id);
    if (!mounted) return;
    setState(() {
      if (colony != null) _colony = colony;
      _entries = _load();
    });
  }

  Future<void> _edit([NestEntry? entry]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _NestEntryFormPage(colony: _colony, entry: entry),
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _delete(NestEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除巢体记录？'),
        content: Text(
          entry.isCurrent
              ? '删除后，当前巢体会变为未设置。历史记录无法自动判断哪座巢正在使用。'
              : '确定删除这条巢体履历吗？此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppDatabase.instance.deleteNestEntry(entry);
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('巢体履历')),
    floatingActionButton: widget.colony.archived
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('添加巢体'),
          ),
    body: FutureBuilder<List<NestEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        if (entries.isEmpty) return const Center(child: Text('还没有巢体履历'));
        final ordered = [...entries]
          ..sort((a, b) {
            if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
            final dateOrder = (b.startedOn ?? DateTime(0)).compareTo(
              a.startedOn ?? DateTime(0),
            );
            return dateOrder != 0
                ? dateOrder
                : b.createdAt.compareTo(a.createdAt);
          });
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('保存每次使用的巢体。启用日期可以留空；旧档案不会被推测为某一天换巢。'),
            ),
            for (final entry in ordered)
              Card(
                child: ListTile(
                  leading: Icon(entry.isCurrent ? Icons.home : Icons.history),
                  title: Text(
                    entry.name?.isNotEmpty == true
                        ? '${entry.name} · ${entry.nestType}'
                        : entry.nestType,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.isCurrent ? '当前使用 · ' : ''}启用日期：${entry.startedOn == null ? '未知' : chineseDate(entry.startedOn!)}',
                      ),
                      if (entry.note?.isNotEmpty == true) Text(entry.note!),
                    ],
                  ),
                  isThreeLine: entry.note?.isNotEmpty == true,
                  onTap: widget.colony.archived ? null : () => _edit(entry),
                  trailing: widget.colony.archived
                      ? null
                      : IconButton(
                          tooltip: '删除巢体记录',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(entry),
                        ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _NestEntryFormPage extends StatefulWidget {
  const _NestEntryFormPage({required this.colony, this.entry});
  final Colony colony;
  final NestEntry? entry;

  @override
  State<_NestEntryFormPage> createState() => _NestEntryFormPageState();
}

class _NestEntryFormPageState extends State<_NestEntryFormPage> {
  final _form = GlobalKey<FormState>();
  late final _type = TextEditingController(text: widget.entry?.nestType ?? '');
  late final _name = TextEditingController(text: widget.entry?.name ?? '');
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  late DateTime? _startedOn = widget.entry?.startedOn;
  late bool _isCurrent =
      widget.entry?.isCurrent ?? widget.colony.nestType == null;
  var _saving = false;

  @override
  void dispose() {
    _type.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _startedOn ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10),
    );
    if (chosen != null && mounted) setState(() => _startedOn = chosen);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final entry = NestEntry(
        id: widget.entry?.id ?? const Uuid().v4(),
        colonyId: widget.colony.id,
        nestType: _type.text.trim(),
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        startedOn: _startedOn,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        isCurrent: _isCurrent,
        createdAt: widget.entry?.createdAt ?? DateTime.now(),
      );
      await AppDatabase.instance.saveNestEntry(entry);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.entry == null ? '添加巢体' : '编辑巢体记录')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _type,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '巢体类型 *',
              hintText: '如试管巢、石膏巢、活动区',
            ),
            validator: (value) =>
                value?.trim().isEmpty == true ? '请填写巢体类型' : null,
          ),
          TextFormField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '名称或模块（可选）',
              hintText: '如一号试管、主巢＋活动区',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _startedOn == null
                  ? '启用日期：未知'
                  : '启用日期：${chineseDate(_startedOn!)}',
            ),
            trailing: Wrap(
              children: [
                if (_startedOn != null)
                  IconButton(
                    tooltip: '清除日期',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _startedOn = null),
                  ),
                IconButton(
                  tooltip: '选择日期',
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _chooseDate,
                ),
              ],
            ),
            onTap: _chooseDate,
          ),
          TextFormField(
            controller: _note,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              hintText: '记录补水结构、接口、换巢原因等',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('当前使用的巢体'),
            subtitle: const Text('开启后同步更新蚁群档案中的巢体类型'),
            value: _isCurrent,
            onChanged: (value) => setState(() => _isCurrent = value),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    ),
  );
}
