import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'domain/care_task.dart';
import 'domain/models.dart';

class CareTasksSection extends StatefulWidget {
  const CareTasksSection({
    super.key,
    required this.colony,
    required this.onRecord,
  });

  final Colony colony;
  final Future<bool> Function(CareTask task) onRecord;

  @override
  State<CareTasksSection> createState() => _CareTasksSectionState();
}

class _CareTasksSectionState extends State<CareTasksSection> {
  late Future<List<CareTask>> _tasks = _load();
  bool _busy = false;
  bool _expanded = true;

  Future<List<CareTask>> _load() =>
      AppDatabase.instance.listCareTasks(colonyId: widget.colony.id);

  void _reload() => setState(() {
    _tasks = _load();
  });

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('待办操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(List<CareTask> tasks, [CareTask? old]) async {
    final available = CareTaskType.values
        .where(
          (type) =>
              old?.type == type || !tasks.any((task) => task.type == type),
        )
        .toList();
    if (available.isEmpty) return;
    var type = old?.type ?? available.first;
    final interval = TextEditingController(text: '${old?.intervalDays ?? 7}');
    var due = old?.nextDueOn ?? DateUtils.dateOnly(DateTime.now());
    final form = GlobalKey<FormState>();
    try {
      final result = await showDialog<CareTask>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(old == null ? '新增养护待办' : '编辑养护待办'),
            content: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<CareTaskType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: '养护事项'),
                      items: [
                        for (final item in available)
                          DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                      ],
                      onChanged: old != null
                          ? null
                          : (value) {
                              if (value != null) update(() => type = value);
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: interval,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '每隔几天',
                        helperText: '1～365 天；完成后从完成当天重新计算',
                      ),
                      validator: (value) {
                        final days = int.tryParse(value?.trim() ?? '');
                        return days == null || days < 1 || days > 365
                            ? '请输入 1～365 天'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('下次到期'),
                      subtitle: Text(_date(due)),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: due,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (selected != null) update(() => due = selected);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    CareTask(
                      id: old?.id ?? const Uuid().v4(),
                      colonyId: widget.colony.id,
                      type: type,
                      intervalDays: int.parse(interval.text.trim()),
                      nextDueOn: due,
                      lastCompletedOn: old?.lastCompletedOn,
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      if (result != null && mounted) {
        await _change(() => AppDatabase.instance.saveCareTask(result));
      }
    } finally {
      interval.dispose();
    }
  }

  Future<void> _delete(CareTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除待办？'),
        content: Text('删除「${task.type.label}」计划；已有日记会保留。'),
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
    if (confirmed == true && mounted) {
      await _change(() => AppDatabase.instance.deleteCareTask(task.id));
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: _expanded ? 14 : 0,
      ),
      child: FutureBuilder<List<CareTask>>(
        future: _tasks,
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? const <CareTask>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '养护待办',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!widget.colony.archived &&
                      tasks.length < CareTaskType.values.length)
                    TextButton.icon(
                      onPressed: _busy ? null : () => _edit(tasks),
                      icon: const Icon(Icons.add),
                      label: const Text('添加'),
                    ),
                  IconButton(
                    tooltip: _expanded ? '折叠养护待办' : '展开养护待办',
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ),
                ],
              ),
              if (!_expanded)
                const SizedBox.shrink()
              else if (snapshot.hasError)
                Text('读取待办失败：${snapshot.error}')
              else if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator()
              else if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.colony.archived ? '该蚁群已归档。' : '可按每窝蚁群设置投喂、补水和清洁周期。',
                  ),
                )
              else
                for (final task in tasks)
                  Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(task.type.label),
                        subtitle: Text(
                          '${task.isDue(DateTime.now()) ? '已到期' : '下次'} ${_date(task.nextDueOn)} · 每 ${task.intervalDays} 天',
                        ),
                        trailing: widget.colony.archived
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: '待办操作',
                                onSelected: (value) {
                                  if (value == 'edit') _edit(tasks, task);
                                  if (value == 'delete') _delete(task);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑计划'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除计划'),
                                  ),
                                ],
                              ),
                      ),
                      if (!widget.colony.archived)
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      if (await widget.onRecord(task) &&
                                          mounted) {
                                        _reload();
                                      }
                                    },
                              icon: const Icon(Icons.check),
                              label: const Text('完成并记日记'),
                            ),
                            TextButton(
                              onPressed: _busy || !task.isDue(DateTime.now())
                                  ? null
                                  : () => _change(
                                      () => AppDatabase.instance
                                          .postponeCareTask(task),
                                    ),
                              child: const Text('顺延至明天'),
                            ),
                          ],
                        ),
                    ],
                  ),
            ],
          );
        },
      ),
    ),
  );
}

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
