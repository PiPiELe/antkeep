import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/wild_catch_record.dart';

class WildCatchPage extends StatefulWidget {
  const WildCatchPage({super.key});

  @override
  State<WildCatchPage> createState() => _WildCatchPageState();
}

class _WildCatchPageState extends State<WildCatchPage> {
  late Future<List<WildCatchRecord>> _records = AppDatabase.instance
      .listWildCatchRecords();

  void _refresh() => setState(() {
    _records = AppDatabase.instance.listWildCatchRecords();
  });

  Future<void> _edit([WildCatchRecord? record]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _WildCatchForm(record: record)),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _delete(WildCatchRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除野采记录？'),
        content: const Text('这条本地记录删除后无法恢复。'),
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
      await AppDatabase.instance.deleteWildCatchRecord(record.id);
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
    appBar: AppBar(title: const Text('蚂蚁野采记录')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('记录战果'),
    ),
    body: FutureBuilder<List<WildCatchRecord>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('还没有野采记录，记录第一次野采战果吧。'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final record = snapshot.data![index];
            return Card(
              child: ListTile(
                title: Text(record.place),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        chineseDate(record.caughtAt),
                        if (record.hasSpecificTime)
                          TimeOfDay.fromDateTime(record.caughtAt)
                              .format(context),
                        '${record.species.length} 种 · ${record.species.fold<int>(0, (total, entry) => total + entry.colonies.length)} 群',
                      ].join(' · '),
                    ),
                    for (final entry in record.species) ...[
                      Text('${entry.name} · ${entry.colonies.length} 群'),
                      for (var i = 0; i < entry.colonies.length; i++)
                        Text(
                          '  第 ${i + 1} 群：${_colonySummary(entry.colonies[i])}',
                        ),
                    ],
                    if (record.note?.isNotEmpty == true) Text(record.note!),
                  ],
                ),
                isThreeLine: true,
                onTap: () => _edit(record),
                trailing: IconButton(
                  tooltip: '删除野采记录',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(record),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

String _colonySummary(WildCatchColony colony) {
  final parts = [
    if (colony.queenCount != null) '蚁后 ${colony.queenCount} 只',
    if (colony.workerCount != null) '工蚁 ${colony.workerCount} 只',
    if (colony.note?.isNotEmpty == true) colony.note!,
  ];
  return parts.isEmpty ? '未填写数量' : parts.join(' · ');
}

class _ColonyDraft {
  _ColonyDraft([WildCatchColony? colony])
    : queens = TextEditingController(text: colony?.queenCount?.toString()),
      workers = TextEditingController(text: colony?.workerCount?.toString()),
      note = TextEditingController(text: colony?.note);

  final TextEditingController queens;
  final TextEditingController workers;
  final TextEditingController note;

  void dispose() {
    queens.dispose();
    workers.dispose();
    note.dispose();
  }

  WildCatchColony toModel() => WildCatchColony(
    queenCount: queens.text.trim().isEmpty
        ? null
        : int.parse(queens.text.trim()),
    workerCount: workers.text.trim().isEmpty
        ? null
        : int.parse(workers.text.trim()),
    note: note.text.trim().isEmpty ? null : note.text.trim(),
  );
}

class _SpeciesDraft {
  _SpeciesDraft([WildCatchSpecies? species])
    : name = TextEditingController(text: species?.name),
      colonies = species == null
          ? [_ColonyDraft()]
          : species.colonies.map(_ColonyDraft.new).toList();

  final TextEditingController name;
  final List<_ColonyDraft> colonies;

  void dispose() {
    name.dispose();
    for (final colony in colonies) {
      colony.dispose();
    }
  }

  WildCatchSpecies toModel() => WildCatchSpecies(
    name: name.text.trim(),
    colonies: colonies.map((colony) => colony.toModel()).toList(),
  );
}

class _WildCatchForm extends StatefulWidget {
  const _WildCatchForm({this.record});

  final WildCatchRecord? record;

  @override
  State<_WildCatchForm> createState() => _WildCatchFormState();
}

class _WildCatchFormState extends State<_WildCatchForm> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _caughtAt =
      widget.record?.caughtAt ?? DateUtils.dateOnly(DateTime.now());
  late bool _specificTime = widget.record?.hasSpecificTime ?? false;
  late final _place = TextEditingController(text: widget.record?.place);
  late final List<_SpeciesDraft> _species =
      widget.record?.species.map(_SpeciesDraft.new).toList() ?? [];
  final _retiredSpecies = <_SpeciesDraft>[];
  final _retiredColonies = <_ColonyDraft>[];
  late final _note = TextEditingController(text: widget.record?.note);
  bool _saving = false;

  @override
  void dispose() {
    _place.dispose();
    for (final entry in _species) {
      entry.dispose();
    }
    for (final entry in _retiredSpecies) {
      entry.dispose();
    }
    for (final colony in _retiredColonies) {
      colony.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _caughtAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(
        () => _caughtAt = DateTime(
          date.year,
          date.month,
          date.day,
          _specificTime ? _caughtAt.hour : 0,
          _specificTime ? _caughtAt.minute : 0,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_caughtAt),
    );
    if (time != null && mounted) {
      setState(
        () => _caughtAt = DateTime(
          _caughtAt.year,
          _caughtAt.month,
          _caughtAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  String? _countError(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final count = int.tryParse(value.trim());
    if (count == null || count < 0 || count > 1000000) {
      return '请输入 0～1000000 的整数';
    }
    return null;
  }

  void _removeSpecies(_SpeciesDraft draft) => setState(() {
    _species.remove(draft);
    _retiredSpecies.add(draft);
  });

  void _removeColony(_SpeciesDraft species, _ColonyDraft colony) =>
      setState(() {
        species.colonies.remove(colony);
        _retiredColonies.add(colony);
      });

  Widget _colonyEditor(_SpeciesDraft species, int index) {
    final colony = species.colonies[index];
    return Padding(
      key: ObjectKey(colony),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('第 ${index + 1} 群')),
              if (species.colonies.length > 1)
                IconButton(
                  tooltip: '删除第 ${index + 1} 群',
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeColony(species, colony),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: colony.queens,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '蚁后数量',
                    border: OutlineInputBorder(),
                  ),
                  validator: _countError,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: colony.workers,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '工蚁数量',
                    border: OutlineInputBorder(),
                  ),
                  validator: _countError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: colony.note,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: '这群的备注（可选）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speciesEditor(int index) {
    final draft = _species[index];
    return Card(
      key: ObjectKey(draft),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '蚁种 ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '删除蚁种 ${index + 1}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeSpecies(draft),
                ),
              ],
            ),
            TextFormField(
              controller: draft.name,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: '蚁种名称 *',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写蚁种名称' : null,
            ),
            for (var i = 0; i < draft.colonies.length; i++)
              _colonyEditor(draft, i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => draft.colonies.add(_ColonyDraft())),
                icon: const Icon(Icons.add),
                label: const Text('添加蚁群'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.saveWildCatchRecord(
        WildCatchRecord(
          id: widget.record?.id ?? const Uuid().v4(),
          caughtAt: _caughtAt,
          hasSpecificTime: _specificTime,
          place: _place.text.trim(),
          species: _species.map((entry) => entry.toModel()).toList(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          createdAt: widget.record?.createdAt ?? DateTime.now(),
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
    appBar: AppBar(title: Text(widget.record == null ? '记录野采战果' : '编辑野采记录')),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? '保存中…' : '保存记录'),
      ),
    ),
    body: Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: const Text('野采日期'),
              subtitle: Text(chineseDate(_caughtAt)),
              onTap: _pickDate,
            ),
            SwitchListTile(
              title: const Text('记录具体时间'),
              value: _specificTime,
              onChanged: (value) => setState(() {
                _specificTime = value;
                if (!value) _caughtAt = DateUtils.dateOnly(_caughtAt);
              }),
            ),
            if (_specificTime)
              ListTile(
                title: const Text('时间'),
                subtitle: Text(
                  TimeOfDay.fromDateTime(_caughtAt).format(context),
                ),
                onTap: _pickTime,
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _place,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: '野采地点 *',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写野采地点' : null,
            ),
            Text('野采战果', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_species.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('还没有添加蚁种；没有采到蚂蚁也可以保存本次野采。'),
              ),
            for (var index = 0; index < _species.length; index++)
              _speciesEditor(index),
            OutlinedButton.icon(
              onPressed: () => setState(() => _species.add(_SpeciesDraft())),
              icon: const Icon(Icons.add),
              label: const Text('添加蚁种'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '本次野采备注（可选）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
