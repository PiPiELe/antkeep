import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'domain/models.dart';

/// Guided local entry for the same care activity across several colonies.
class BatchCarePage extends StatefulWidget {
  const BatchCarePage({super.key, required this.colonies});

  final List<Colony> colonies;

  @override
  State<BatchCarePage> createState() => _BatchCarePageState();
}

class _BatchCarePageState extends State<BatchCarePage> {
  static const _types = [
    CareRecordType.feeding,
    CareRecordType.watering,
    CareRecordType.cleaning,
  ];

  final _selected = <String>{};
  final _notes = <String, TextEditingController>{};
  final _responses = <String, FeedingResponse?>{};
  final _leftovers = <String, bool?>{};
  final _food = TextEditingController();
  final _amount = TextEditingController();
  var _type = CareRecordType.feeding;
  var _occurredAt = DateUtils.dateOnly(DateTime.now());
  var _saving = false;

  @override
  void initState() {
    super.initState();
    for (final colony in widget.colonies) {
      _notes[colony.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _notes.values) {
      controller.dispose();
    }
    _food.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (chosen != null && mounted) setState(() => _occurredAt = chosen);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请逐群勾选已完成养护的蚁群')));
      return;
    }
    final colonies = widget.colonies
        .where((colony) => _selected.contains(colony.id))
        .toList();
    setState(() => _saving = true);
    try {
      var globalUpdate = false;
      for (final colony in colonies) {
        if (await AppDatabase.instance.needsGlobalGrowthRecalculation(
          colony.id,
          [_occurredAt],
        )) {
          globalUpdate = true;
          break;
        }
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认批量养护记录'),
          content: Text(
            '将在 ${colonies.length} 窝蚁群中各保存一条${_type.label}记录。'
            '${globalUpdate ? '\n\n所选日期早于种群数量界碑，保存时将全局重算相关自动扩充记录。' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回检查'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认保存'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final now = DateTime.now();
      final food = _food.text.trim();
      final amount = _amount.text.trim();
      final records = [
        for (final colony in colonies)
          CareRecord(
            id: const Uuid().v4(),
            colonyId: colony.id,
            type: _type,
            occurredAt: _occurredAt,
            createdAt: now,
            note: _notes[colony.id]!.text.trim().isEmpty
                ? null
                : _notes[colony.id]!.text.trim(),
            feedingFood: _type == CareRecordType.feeding && food.isNotEmpty
                ? food
                : null,
            feedingAmount: _type == CareRecordType.feeding && amount.isNotEmpty
                ? amount
                : null,
            feedingResponse: _type == CareRecordType.feeding
                ? _responses[colony.id]
                : null,
            feedingLeftovers: _type == CareRecordType.feeding
                ? _leftovers[colony.id]
                : null,
          ),
      ];
      await AppDatabase.instance.saveRecordsBatch(
        records,
        recalculateAllGrowth: globalUpdate,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('批量保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('批量养护记录'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text('保存 (${_selected.length})'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('选择养护项目，然后逐群勾选确实完成的蚁群。未勾选的蚁群不会生成记录。'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final type in _types)
              ChoiceChip(
                label: Text(type.label),
                selected: _type == type,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _type = type),
              ),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('养护日期'),
          subtitle: Text(
            '${_occurredAt.year}-${_occurredAt.month.toString().padLeft(2, '0')}-${_occurredAt.day.toString().padLeft(2, '0')}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _saving ? null : _pickDate,
        ),
        if (_type == CareRecordType.feeding) ...[
          TextField(
            controller: _food,
            enabled: !_saving,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '共同食物（可选）'),
          ),
          TextField(
            controller: _amount,
            enabled: !_saving,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '共同投喂量（可选）'),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text('逐群确认', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      if (_selected.length == widget.colonies.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(widget.colonies.map((c) => c.id));
                      }
                    }),
              child: Text(
                _selected.length == widget.colonies.length ? '全部取消' : '全部选择',
              ),
            ),
          ],
        ),
        for (final colony in widget.colonies)
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  value: _selected.contains(colony.id),
                  onChanged: _saving
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(colony.id);
                          } else {
                            _selected.remove(colony.id);
                          }
                        }),
                  title: Text(colony.name),
                  subtitle: Text('已完成${_type.label}'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (_selected.contains(colony.id)) ...[
                  if (_type == CareRecordType.feeding) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonFormField<FeedingResponse>(
                        initialValue: _responses[colony.id],
                        decoration: const InputDecoration(
                          labelText: '进食情况（可选）',
                        ),
                        items: [
                          for (final response in FeedingResponse.values)
                            DropdownMenuItem(
                              value: response,
                              child: Text(response.label),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => _responses[colony.id] = value,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonFormField<bool>(
                        initialValue: _leftovers[colony.id],
                        decoration: const InputDecoration(
                          labelText: '剩余食物（可选）',
                        ),
                        items: const [
                          DropdownMenuItem(value: false, child: Text('无')),
                          DropdownMenuItem(value: true, child: Text('有')),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => _leftovers[colony.id] = value,
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _notes[colony.id],
                      enabled: !_saving,
                      maxLines: 2,
                      maxLength: 500,
                      decoration: const InputDecoration(labelText: '这窝的备注（可选）'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 80),
      ],
    ),
  );
}
