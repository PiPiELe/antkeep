import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/flight_observation.dart';

class FlightObservationPage extends StatefulWidget {
  const FlightObservationPage({super.key});
  @override
  State<FlightObservationPage> createState() => _FlightObservationPageState();
}

class _FlightObservationPageState extends State<FlightObservationPage> {
  late Future<List<FlightObservation>> _observations = AppDatabase.instance
      .listFlightObservations();

  void _refresh() => setState(
    () => _observations = AppDatabase.instance.listFlightObservations(),
  );

  Future<void> _edit([FlightObservation? observation]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _FlightForm(observation: observation)),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _delete(FlightObservation observation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除婚飞观察？'),
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
      await AppDatabase.instance.deleteFlightObservation(observation.id);
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
    appBar: AppBar(
      title: Text('婚飞观察', style: Theme.of(context).textTheme.titleMedium),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('记录观察'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Text('本地观察记录', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        FutureBuilder<List<FlightObservation>>(
          future: _observations,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('加载失败：${snapshot.error}');
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('还没有婚飞观察记录。'),
                ),
              );
            }
            return Column(
              children: [
                for (final entry in snapshot.data!)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${entry.species?.isNotEmpty == true ? '${entry.species} · ' : ''}${entry.place}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${chineseDate(entry.observedAt)} ${TimeOfDay.fromDateTime(entry.observedAt).format(context)}${entry.count == null ? '' : ' · ${entry.count}只'}',
                          ),
                          if (entry.note?.isNotEmpty == true) Text(entry.note!),
                        ],
                      ),
                      isThreeLine: entry.note?.isNotEmpty == true,
                      onTap: () => _edit(entry),
                      trailing: IconButton(
                        tooltip: '删除观察记录',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(entry),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _FlightForm extends StatefulWidget {
  const _FlightForm({this.observation});
  final FlightObservation? observation;
  @override
  State<_FlightForm> createState() => _FlightFormState();
}

class _FlightFormState extends State<_FlightForm> {
  late DateTime _observed = widget.observation?.observedAt ?? DateTime.now();
  late final _place = TextEditingController(text: widget.observation?.place);
  late final _species = TextEditingController(
    text: widget.observation?.species,
  );
  late final _count = TextEditingController(
    text: widget.observation?.count?.toString(),
  );
  late final _note = TextEditingController(text: widget.observation?.note);
  bool _saving = false;

  @override
  void dispose() {
    _place.dispose();
    _species.dispose();
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _observed,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(
      () => _observed = DateTime(
        date.year,
        date.month,
        date.day,
        _observed.hour,
        _observed.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_observed),
    );
    if (time == null || !mounted) return;
    setState(
      () => _observed = DateTime(
        _observed.year,
        _observed.month,
        _observed.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final count = _count.text.trim().isEmpty
        ? null
        : int.tryParse(_count.text.trim());
    if (_count.text.trim().isNotEmpty && count == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('数量请输入整数。')));
      return;
    }
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.saveFlightObservation(
        FlightObservation(
          id: widget.observation?.id ?? const Uuid().v4(),
          observedAt: _observed,
          place: _place.text.trim(),
          species: _species.text.trim().isEmpty ? null : _species.text.trim(),
          count: count,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          createdAt: widget.observation?.createdAt ?? DateTime.now(),
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
    appBar: AppBar(
      title: Text(widget.observation == null ? '记录婚飞观察' : '编辑婚飞观察'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: ListTile(
                title: const Text('日期'),
                subtitle: Text(chineseDate(_observed)),
                onTap: _pickDate,
              ),
            ),
            Expanded(
              child: ListTile(
                title: const Text('时间'),
                subtitle: Text(
                  TimeOfDay.fromDateTime(_observed).format(context),
                ),
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        TextField(
          controller: _place,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: '观察地点 *',
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: _species,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: '蚁种（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: _count,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '观察数量（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          controller: _note,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '环境与行为备注（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
