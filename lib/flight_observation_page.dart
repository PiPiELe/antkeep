import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/app_database.dart';
import 'data/flight_weather_service.dart';
import 'date_display.dart';
import 'domain/flight_observation.dart';

class FlightObservationPage extends StatefulWidget {
  const FlightObservationPage({super.key});
  @override
  State<FlightObservationPage> createState() => _FlightObservationPageState();
}

class _FlightObservationPageState extends State<FlightObservationPage> {
  final _weather = FlightWeatherService();
  final _city = TextEditingController();
  late Future<List<FlightObservation>> _observations = AppDatabase.instance
      .listFlightObservations();
  List<WeatherPlace>? _places;
  WeatherPlace? _selected;
  List<FlightWeatherDay>? _forecast;
  String? _weatherError;
  bool _loading = false;

  @override
  void dispose() {
    _weather.dispose();
    _city.dispose();
    super.dispose();
  }

  void _refresh() => setState(
    () => _observations = AppDatabase.instance.listFlightObservations(),
  );

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _weatherError = null;
      _places = null;
      _selected = null;
      _forecast = null;
    });
    try {
      final places = await _weather.search(_city.text);
      if (mounted) setState(() => _places = places);
    } catch (error) {
      if (mounted) setState(() => _weatherError = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadForecast(WeatherPlace place) async {
    setState(() {
      _selected = place;
      _places = null;
      _forecast = null;
      _weatherError = null;
      _loading = true;
    });
    try {
      final days = await _weather.forecast(place);
      if (mounted) setState(() => _forecast = days);
    } catch (error) {
      if (mounted) setState(() => _weatherError = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
      title: Text('婚飞观察与天气', style: Theme.of(context).textTheme.titleMedium),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('记录观察'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('天气提示', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  '手动搜索城市后获取七日预报。城市搜索词和所选坐标会发送给天气服务；观察记录只保存在本机。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _city,
                        onSubmitted: (_) => _loading ? null : _search(),
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          labelText: '城市或地区',
                          hintText: '例如：北京',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading ? null : _search,
                      child: const Text('搜索'),
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  ),
                if (_weatherError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('获取失败：$_weatherError'),
                  ),
                if (_places != null && _places!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('没有找到城市，请尝试更具体的地名。'),
                  ),
                if (_places?.isNotEmpty == true)
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount: _places!.length,
                      itemBuilder: (context, index) {
                        final place = _places![index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            place.label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          onTap: () => _loadForecast(place),
                        );
                      },
                    ),
                  ),
                if (_selected != null && _forecast != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _selected!.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '“可留意”仅按气温≥20°C、降水概率≥40%、最大风速≤20公里/小时标记天气；不代表蚂蚁一定婚飞，蚁种和当地环境也会影响时机。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: Scrollbar(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final day in _forecast!)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${chineseDate(day.date)}${day.worthWatching ? ' · 可留意' : ''}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              subtitle: Text(
                                '最高温 ${day.maxTemp?.toStringAsFixed(1) ?? '—'}°C · 降水概率 ${day.rainChance?.toString() ?? '—'}% · 最大风速 ${day.windMax?.toStringAsFixed(1) ?? '—'} km/h',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          Text(
                            '天气数据：Open-Meteo（CC BY 4.0）。预报会变化，请出行前刷新。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse('https://open-meteo.com/'),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: const Text('查看 Open-Meteo 数据来源与许可'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
