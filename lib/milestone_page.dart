import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/milestone.dart';
import 'domain/models.dart';
import 'milestone_share_page.dart';

class MilestonePage extends StatefulWidget {
  const MilestonePage({super.key, required this.colony});

  final Colony colony;

  @override
  State<MilestonePage> createState() => _MilestonePageState();
}

class _MilestonePageState extends State<MilestonePage> {
  late Future<List<Milestone>> _milestones = _load();

  Future<List<Milestone>> _load() =>
      AppDatabase.instance.listMilestones(widget.colony.id);

  void _reload() => setState(() {
    _milestones = _load();
  });

  Future<void> _edit([Milestone? milestone]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MilestoneFormPage(colony: widget.colony, milestone: milestone),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(Milestone milestone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除里程碑？'),
        content: Text('确定删除「${milestone.title}」吗？'),
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
      await AppDatabase.instance.deleteMilestone(milestone);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.colony.name} · 里程碑')),
    bottomNavigationBar: widget.colony.archived
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('添加里程碑'),
              ),
            ),
          ),
    body: FutureBuilder<List<Milestone>>(
      future: _milestones,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final milestones = snapshot.data!;
        if (milestones.isEmpty) {
          return const Center(child: Text('还没有里程碑，记录一次值得纪念的事件吧。'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: milestones.length,
          itemBuilder: (context, index) {
            final milestone = milestones[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(milestone.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${chineseDate(milestone.occurredAt)}'
                      '${milestone.occurredAt.hour == 0 && milestone.occurredAt.minute == 0 ? '' : ' ${TimeOfDay.fromDateTime(milestone.occurredAt).format(context)}'}',
                    ),
                    if (milestone.note?.isNotEmpty == true)
                      Text(
                        milestone.note!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                onTap: widget.colony.archived ? null : () => _edit(milestone),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '分享里程碑',
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MilestoneSharePage(
                            colony: widget.colony,
                            milestone: milestone,
                          ),
                        ),
                      ),
                    ),
                    if (!widget.colony.archived)
                      IconButton(
                        tooltip: '删除里程碑',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(milestone),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class MilestoneFormPage extends StatefulWidget {
  const MilestoneFormPage({super.key, required this.colony, this.milestone});

  final Colony colony;
  final Milestone? milestone;

  @override
  State<MilestoneFormPage> createState() => _MilestoneFormPageState();
}

class _MilestoneFormPageState extends State<MilestoneFormPage> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  late DateTime _occurredAt =
      widget.milestone?.occurredAt ?? DateUtils.dateOnly(DateTime.now());
  late bool _hasTime =
      widget.milestone != null &&
      (_occurredAt.hour != 0 || _occurredAt.minute != 0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.text = widget.milestone?.title ?? '';
    _note.text = widget.milestone?.note ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _occurredAt,
    );
    if (date != null && mounted) {
      setState(
        () => _occurredAt = DateTime(
          date.year,
          date.month,
          date.day,
          _hasTime ? _occurredAt.hour : 0,
          _hasTime ? _occurredAt.minute : 0,
        ),
      );
    }
  }

  Future<void> _setTime(bool enabled) async {
    if (!enabled) {
      setState(() {
        _hasTime = false;
        _occurredAt = DateUtils.dateOnly(_occurredAt);
      });
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null && mounted) {
      setState(() {
        _hasTime = true;
        _occurredAt = DateTime(
          _occurredAt.year,
          _occurredAt.month,
          _occurredAt.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final milestone = Milestone(
      id: widget.milestone?.id ?? const Uuid().v4(),
      colonyId: widget.colony.id,
      title: _title.text,
      note: _note.text.trim().isEmpty ? null : _note.text,
      occurredAt: _occurredAt,
      createdAt: widget.milestone?.createdAt ?? DateTime.now(),
    );
    try {
      milestone.validate();
      setState(() => _saving = true);
      await AppDatabase.instance.saveMilestone(milestone);
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
    appBar: AppBar(title: Text(widget.milestone == null ? '添加里程碑' : '编辑里程碑')),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? '保存中…' : '保存里程碑'),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '事件标题'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('发生日期：${chineseDate(_occurredAt)}'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('记录具体时间'),
          value: _hasTime,
          onChanged: _saving ? null : _setTime,
        ),
        if (_hasTime)
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _setTime(true),
            icon: const Icon(Icons.schedule),
            label: Text(
              '具体时间：${TimeOfDay.fromDateTime(_occurredAt).format(context)}',
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 2000,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '事件说明（可选）'),
        ),
        const SizedBox(height: 24),
        const Text('里程碑仅用于记录重大事件，不参与日记和数量统计。'),
      ],
    ),
  );
}
