import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'data/local_notification_service.dart';
import 'data/food_reminder_coordinator.dart';
import 'domain/care_task.dart';
import 'domain/models.dart';

class CareTasksSection extends StatefulWidget {
  const CareTasksSection({
    super.key,
    required this.colony,
    required this.onRecord,
    this.compact = false,
  });

  final bool compact;
  final Colony colony;
  final Future<bool> Function(CareTask task) onRecord;

  @override
  State<CareTasksSection> createState() => _CareTasksSectionState();
}

class _CareTasksSectionState extends State<CareTasksSection> {
  late Future<List<CareTask>> _tasks = _load();
  bool _busy = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  List<CareTaskType> _available(List<CareTask> tasks, [CareTask? old]) {
    final split = tasks.any((task) => task.type.isSplitFeeding);
    return CareTaskType.values
        .where(
          (type) =>
              (type.isFeeding ? type.isSplitFeeding == split : true) &&
              (old?.type == type || !tasks.any((task) => task.type == type)),
        )
        .toList();
  }

  Future<void> _split(bool value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value ? '拆分投喂计时？' : '恢复普通投喂？'),
        content: Text(
          value
              ? '将投喂计划拆成蛋白、糖类、种子，分别设置周期和撤食提醒。旧投喂日记保留；各类从下次实际投喂开始计时，撤食提醒默认关闭。'
              : '合并为一个普通投喂计划。分类日记保留，当前分类计时和撤食提醒会清除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _change(
        () => AppDatabase.instance.setSplitFeeding(widget.colony.id, value),
      );
    }
  }

  Widget _feedingStatus(CareTask task) {
    final now = DateTime.now();
    final elapsed = task.lastFedAt == null
        ? null
        : now.difference(task.lastFedAt!);
    final remaining = task.removalDueAt?.difference(now);
    String duration(Duration value) {
      final minutes = value.inMinutes.clamp(0, 9999999);
      if (minutes < 60) return '$minutes 分钟';
      if (minutes < 1440) return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
      return '${minutes ~/ 1440} 天 ${minutes % 1440 ~/ 60} 小时';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            elapsed == null ? '尚未开始投喂计时' : '距上次投喂 ${duration(elapsed)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (remaining != null)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  remaining.isNegative || remaining == Duration.zero
                      ? '已到撤食时间'
                      : '${duration(remaining)}后撤食',
                  style: TextStyle(
                    color: task.removalIsDue(now)
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                if (!widget.colony.archived)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _change(
                            () => AppDatabase.instance.completeFoodRemoval(
                              task.id,
                            ),
                          ),
                    child: const Text('已撤食'),
                  ),
              ],
            )
          else
            Text(
              task.removalHours == null
                  ? '撤食提醒关闭'
                  : '撤食提醒：投喂后 ${task.removalHours} 小时',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!widget.colony.archived && !task.isDue(now))
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _change(
                      () => AppDatabase.instance.completeCareTask(task.id),
                    ),
              icon: const Icon(Icons.restaurant, size: 16),
              label: const Text('现在投喂'),
            ),
        ],
      ),
    );
  }

  late bool _expanded = widget.compact;

  Future<List<CareTask>> _load() async {
    final tasks = await AppDatabase.instance.listCareTasks(
      colonyId: widget.colony.id,
    );
    return tasks..sort((a, b) => a.type.index.compareTo(b.type.index));
  }

  void _reload() => setState(() {
    _tasks = _load();
  });

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
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

  Future<void> _recordTask(CareTask task) => _change(() async {
    await widget.onRecord(task);
  });

  String _taskSummary(CareTask task) {
    final days = DateUtils.dateOnly(task.nextDueOn)
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    final status = days < 0
        ? '逾期 ${-days} 天'
        : days == 0
        ? '今天到期'
        : '$days 天后';
    final schedule = days <= 0
        ? '$status · 每 ${task.intervalDays} 天'
        : '$status · ${task.nextDueOn.month}月${task.nextDueOn.day}日';
    return '$schedule${task.lastCompletedOn == null ? '' : '\n上次完成 ${_date(task.lastCompletedOn!)}'}';
  }

  Future<void> _edit(List<CareTask> tasks, [CareTask? old]) async {
    final available = _available(tasks, old);
    if (available.isEmpty) return;
    var type = old?.type ?? available.first;
    final interval = TextEditingController(text: '${old?.intervalDays ?? 7}');
    var due = old?.nextDueOn ?? DateUtils.dateOnly(DateTime.now());
    var removalEnabled = old?.removalHours != null;
    final removalHours = TextEditingController(
      text: '${old?.removalHours ?? 24}',
    );
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
                        helperMaxLines: 3,
                      ),
                      validator: (value) {
                        final days = int.tryParse(value?.trim() ?? '');
                        return days == null || days < 1 || days > 365
                            ? '请输入 1～365 天'
                            : null;
                      },
                    ),
                    if (type.isFeeding) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('撤食提醒'),
                        subtitle: const Text('仅提醒这一类食物；每次投喂重新计时'),
                        value: removalEnabled,
                        onChanged: (value) =>
                            update(() => removalEnabled = value),
                      ),
                      if (removalEnabled)
                        TextFormField(
                          controller: removalHours,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '投喂后几小时撤食',
                            helperText: '1～720 小时；系统通知可能受省电设置影响',
                            helperMaxLines: 3,
                          ),
                          validator: (value) {
                            final hours = int.tryParse(value?.trim() ?? '');
                            return hours == null || hours < 1 || hours > 720
                                ? '请输入 1～720 小时'
                                : null;
                          },
                        ),
                    ],
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
                      lastFedAt: old?.lastFedAt,
                      removalHours: type.isFeeding && removalEnabled
                          ? int.parse(removalHours.text.trim())
                          : null,
                      removalDueAt:
                          type.isFeeding &&
                              removalEnabled &&
                              old?.removalDueAt != null
                          ? old!.lastFedAt!.add(
                              Duration(
                                hours: int.parse(removalHours.text.trim()),
                              ),
                            )
                          : null,
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
        await _change(() async {
          await AppDatabase.instance.saveCareTask(result);
          if (result.removalHours != null && old?.removalHours == null) {
            var allowed = false;
            try {
              allowed = await LocalNotificationService.instance
                  .requestPermission();
            } catch (_) {}
            if (!allowed && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('撤食计时已开启，系统通知未获授权；仍可在待办中查看。')),
              );
            }
            await FoodReminderCoordinator.instance.refresh();
          }
        });
      }
    } finally {
      interval.dispose();
      removalHours.dispose();
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
    margin: widget.compact ? const EdgeInsets.symmetric(vertical: 5) : null,
    elevation: widget.compact ? 0 : null,
    color: widget.compact
        ? Theme.of(context).colorScheme.surfaceContainerLow
        : null,
    shape: widget.compact
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant
                  .withValues(alpha: .5),
            ),
          )
        : null,
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
                      widget.compact ? '养护待办 (${tasks.length})' : '养护待办',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!widget.colony.archived && _available(tasks).isNotEmpty)
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
              if (_expanded && !widget.colony.archived && snapshot.hasData)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('细分食物投喂'),
                  subtitle: const Text('蛋白、糖类、种子分别计时'),
                  value: tasks.any((task) => task.type.isSplitFeeding),
                  onChanged: _busy ? null : _split,
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
                for (final task in tasks) ...[
                  if (widget.compact)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(10),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          leading: Icon(
                            task.isDue(DateTime.now())
                                ? Icons.event_available_outlined
                                : Icons.schedule,
                          ),
                          title: Text(task.type.label),
                          subtitle: Text(_taskSummary(task)),
                          onTap: widget.colony.archived || _busy
                              ? null
                              : () => _edit(tasks, task),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (task.isDue(DateTime.now()) &&
                                  !widget.colony.archived)
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _recordTask(task),
                                  child: const Text('完成并记录'),
                                ),
                              PopupMenuButton<String>(
                                enabled: !widget.colony.archived && !_busy,
                                onSelected: (value) async {
                                  if (value == 'reminder') {
                                    _change(
                                      () =>
                                          AppDatabase.instance.completeCareTask(
                                            task.id,
                                            markFed: false,
                                          ),
                                    );
                                  }
                                  if (value == 'edit') _edit(tasks, task);
                                  if (value == 'delete') _delete(task);
                                  if (value == 'postpone') {
                                    _change(
                                      () => AppDatabase.instance
                                          .postponeCareTask(task),
                                    );
                                  }
                                  if (value == 'record') {
                                    await _recordTask(task);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (task.isDue(DateTime.now())) ...[
                                    const PopupMenuItem(
                                      value: 'reminder',
                                      child: Text('仅完成提醒（不记日记）'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'postpone',
                                      child: Text('顺延至明天'),
                                    ),
                                  ],
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑计划'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除计划'),
                                  ),
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.chevron_right, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(task.type.label),
                          subtitle: Text(_taskSummary(task)),
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
                        if (!widget.colony.archived &&
                            task.isDue(DateTime.now()))
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                    iconSize: 16,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _change(
                                          () => AppDatabase.instance
                                              .completeCareTask(
                                                task.id,
                                                markFed: false,
                                              ),
                                        ),
                                  icon: const Icon(Icons.check),
                                  label: const Text('仅完成提醒'),
                                ),
                                const SizedBox(width: 4),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                    iconSize: 16,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _recordTask(task),
                                  icon: const Icon(Icons.check),
                                  label: const Text('完成并记录'),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed:
                                      _busy || !task.isDue(DateTime.now())
                                      ? null
                                      : () => _change(
                                          () => AppDatabase.instance
                                              .postponeCareTask(task),
                                        ),
                                  child: const Text('顺延至明天'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  if (task.type.isFeeding) _feedingStatus(task),
                ],
            ],
          );
        },
      ),
    ),
  );
}

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
