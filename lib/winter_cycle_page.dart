import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/models.dart';
import 'domain/winter_cycle.dart';

class WinterCyclePage extends StatefulWidget {
  const WinterCyclePage({super.key, required this.colony});
  final Colony colony;

  @override
  State<WinterCyclePage> createState() => _WinterCyclePageState();
}

class _WinterCyclePageState extends State<WinterCyclePage> {
  late Future<List<WinterCycle>> _cycles = AppDatabase.instance
      .listWinterCycles(widget.colony.id);

  void _refresh() => setState(() {
    _cycles = AppDatabase.instance.listWinterCycles(widget.colony.id);
  });

  Future<void> _edit([WinterCycle? cycle]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _WinterCycleForm(colony: widget.colony, cycle: cycle),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _delete(WinterCycle cycle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除越冬周期？'),
        content: const Text('这条记录删除后无法恢复。'),
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
    if (confirmed != true) return;
    try {
      await AppDatabase.instance.deleteWinterCycle(cycle);
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.colony.name} · 越冬周期')),
    floatingActionButton: widget.colony.archived
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('开始周期'),
          ),
    body: FutureBuilder<List<WinterCycle>>(
      future: _cycles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cycles = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            const Text('记录实际开始、计划结束与实际结束日期。不同蚁种的越冬需求不同，请按自己的饲养方案填写。'),
            const SizedBox(height: 12),
            if (cycles.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('还没有越冬周期。'),
                ),
              ),
            for (final cycle in cycles)
              Card(
                child: ListTile(
                  leading: Icon(
                    cycle.endedOn == null ? Icons.ac_unit : Icons.history,
                  ),
                  title: Text(
                    cycle.endedOn == null
                        ? '进行中 · 已${DateTime.now().difference(cycle.startedOn).inDays.clamp(0, 99999) + 1}天'
                        : '已结束 · ${cycle.endedOn!.difference(cycle.startedOn).inDays + 1}天',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('开始：${chineseDate(cycle.startedOn)}'),
                      if (cycle.plannedEndOn != null)
                        Text(
                          '计划结束：${chineseDate(cycle.plannedEndOn!)}${cycle.endedOn == null && !cycle.plannedEndOn!.isAfter(DateTime.now()) ? ' · 已到计划日期' : ''}',
                        ),
                      if (cycle.endedOn != null)
                        Text('实际结束：${chineseDate(cycle.endedOn!)}'),
                      if (cycle.note?.isNotEmpty == true) Text(cycle.note!),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: widget.colony.archived ? null : () => _edit(cycle),
                  trailing: widget.colony.archived
                      ? null
                      : IconButton(
                          tooltip: '删除越冬周期',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(cycle),
                        ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _WinterCycleForm extends StatefulWidget {
  const _WinterCycleForm({required this.colony, this.cycle});
  final Colony colony;
  final WinterCycle? cycle;
  @override
  State<_WinterCycleForm> createState() => _WinterCycleFormState();
}

class _WinterCycleFormState extends State<_WinterCycleForm> {
  late DateTime _start =
      widget.cycle?.startedOn ?? DateUtils.dateOnly(DateTime.now());
  DateTime? _planned;
  DateTime? _end;
  late final _note = TextEditingController(text: widget.cycle?.note);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _planned = widget.cycle?.plannedEndOn;
    _end = widget.cycle?.endedOn;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(String field) async {
    final current = field == 'start'
        ? _start
        : field == 'planned'
        ? _planned
        : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (field == 'start') {
        _start = date;
      } else if (field == 'planned') {
        _planned = date;
      } else {
        _end = date;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.saveWinterCycle(
        WinterCycle(
          id: widget.cycle?.id ?? const Uuid().v4(),
          colonyId: widget.colony.id,
          startedOn: _start,
          plannedEndOn: _planned,
          endedOn: _end,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          createdAt: widget.cycle?.createdAt ?? DateTime.now(),
        ),
      );
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
    appBar: AppBar(title: Text(widget.cycle == null ? '开始越冬周期' : '编辑越冬周期')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('实际开始'),
          subtitle: Text(chineseDate(_start)),
          onTap: () => _pick('start'),
        ),
        ListTile(
          title: const Text('计划结束'),
          subtitle: Text(_planned == null ? '未设置' : chineseDate(_planned!)),
          onTap: () => _pick('planned'),
          trailing: _planned == null
              ? null
              : IconButton(
                  tooltip: '清除计划结束日期',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _planned = null),
                ),
        ),
        ListTile(
          title: const Text('实际结束'),
          subtitle: Text(_end == null ? '仍在进行' : chineseDate(_end!)),
          onTap: () => _pick('end'),
          trailing: _end == null
              ? null
              : IconButton(
                  tooltip: '改为进行中',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _end = null),
                ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
