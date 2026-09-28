import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/local_media_store.dart';
import 'domain/models.dart';

const _speciesOptions = <String, List<String>>{
  '收获蚁': ['工匠收获蚁'],
  '弓背蚁': ['黑金弓背蚁', '大头弓背蚁'],
  '猛蚁': ['横纹猛蚁'],
};

const _nestTypeOptions = [
  '试管巢',
  '平面巢',
  '折叠巢',
  '石膏巢',
  '亚克力巢',
  '沙土巢',
  '木巢',
  '加气砖巢',
  '生态缸巢',
  '3D 打印巢',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalMediaStore.instance.initialize();
    await AppDatabase.instance.open();
    await themeController.load();
    runApp(const AntKeepApp());
  } catch (error) {
    runApp(_StartupError(error: error));
  }
}

final themeController = _ThemeController();

class _ThemeController extends ChangeNotifier {
  var _darkThemeEnabled = false;

  bool get darkThemeEnabled => _darkThemeEnabled;

  Future<void> load() async {
    _darkThemeEnabled = await AppDatabase.instance.isDarkThemeEnabled();
  }

  Future<void> setDarkThemeEnabled(bool enabled) async {
    if (enabled == _darkThemeEnabled) return;
    final previous = _darkThemeEnabled;
    _darkThemeEnabled = enabled;
    notifyListeners();
    try {
      await AppDatabase.instance.setDarkThemeEnabled(enabled);
    } catch (_) {
      _darkThemeEnabled = previous;
      notifyListeners();
      rethrow;
    }
  }
}

class AntKeepApp extends StatelessWidget {
  const AntKeepApp({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => MaterialApp(
      title: '蚁记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3f6048)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff7da985),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff0d0f0d),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xff121512)),
        cardColor: const Color(0xff181c18),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      themeMode: themeController.darkThemeEnabled
          ? ThemeMode.dark
          : ThemeMode.light,
      home: const HomePage(),
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('蚁记无法打开本地存储。\n$error'),
        ),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    const titles = ['我的蚁群', '最近记录', '物品', '待办', '设置'];
    final pages = [
      const ColoniesPage(),
      const RecentRecordsPage(),
      const InventoryPage(),
      const CarePlanPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.hive_outlined),
            selectedIcon: Icon(Icons.hive),
            label: '蚁群',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: '物品',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: '待办',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class ColoniesPage extends StatefulWidget {
  const ColoniesPage({super.key});
  @override
  State<ColoniesPage> createState() => _ColoniesPageState();
}

class _ColoniesPageState extends State<ColoniesPage> {
  late Future<List<Colony>> _colonies;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _colonies = AppDatabase.instance.listColonies();

  Future<void> _newColony() async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ColonyFormPage()));
    if (saved == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _newColony,
      icon: const Icon(Icons.add),
      label: const Text('新入手蚁群'),
    ),
    body: FutureBuilder<List<Colony>>(
      future: _colonies,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState('读取蚁群失败：${snapshot.error}');
        }
        final colonies = snapshot.data!;
        if (colonies.isEmpty) {
          return const _EmptyState(
            icon: Icons.hive_outlined,
            title: '还没有蚁群',
            message: '新入手时建立一窝蚁群，再独立记录投喂、环境、数量和照片。',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: colonies.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ColonyCard(
              colony: colonies[index],
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ColonyDetailPage(colonyId: colonies[index].id),
                  ),
                );
                if (mounted) setState(_reload);
              },
            ),
          ),
        );
      },
    ),
  );
}

class _ColonyCard extends StatelessWidget {
  const _ColonyCard({required this.colony, required this.onTap});
  final Colony colony;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (colony.species?.isNotEmpty == true) colony.species!,
      if (colony.queenCount != null) '${colony.queenCount} 只蚁后',
      if (colony.initialWorkerCount != null) '${colony.initialWorkerCount} 只工蚁',
      if (colony.nestType?.isNotEmpty == true) colony.nestType!,
    ];
    return Card(
      child: ListTile(
        leading: colony.coverPhotoPath == null
            ? const CircleAvatar(child: Icon(Icons.hive_outlined))
            : _StoredImage(
                relativePath: colony.coverPhotoPath!,
                width: 48,
                height: 48,
                borderRadius: 24,
              ),
        title: Text(colony.name),
        subtitle: Text(details.isEmpty ? '尚未补充档案' : details.join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class ColonyFormPage extends StatefulWidget {
  const ColonyFormPage({super.key});
  @override
  State<ColonyFormPage> createState() => _ColonyFormPageState();
}

class _ColonyFormPageState extends State<ColonyFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _species = TextEditingController();
  final _source = TextEditingController();
  final _queens = TextEditingController();
  final _workers = TextEditingController();
  final _nest = TextEditingController();
  final _targetTemperature = TextEditingController();
  final _targetHumidity = TextEditingController();
  String? _speciesFamily;
  String? _selectedSpecies;
  DateTime? _acquiredOn;
  XFile? _cover;
  var _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _species,
      _source,
      _queens,
      _workers,
      _nest,
      _targetTemperature,
      _targetHumidity,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await AppDatabase.instance.saveColony(
        Colony(
          id: const Uuid().v4(),
          name: _name.text.trim(),
          species: _selectedSpecies,
          acquiredOn: _acquiredOn,
          source: _textOrNull(_source.text),
          queenCount: int.tryParse(_queens.text),
          initialWorkerCount: int.tryParse(_workers.text),
          nestType: _textOrNull(_nest.text),
          targetTemperature: double.tryParse(_targetTemperature.text),
          targetHumidity: double.tryParse(_targetHumidity.text),
          coverPhotoPath: _cover == null
              ? null
              : await LocalMediaStore.instance.copyImage(_cover!),
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新入手蚁群')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '蚁群昵称 *',
              hintText: '例如：红土一号',
            ),
            validator: (value) =>
                _textOrNull(value ?? '') == null ? '请填写一个昵称' : null,
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            label: const Text('品种分类'),
            hintText: '搜索或选择分类',
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: _speciesOptions.keys
                .map(
                  (family) => DropdownMenuEntry(value: family, label: family),
                )
                .toList(),
            onSelected: (family) {
              setState(() {
                _speciesFamily = family;
                _selectedSpecies = null;
                _species.clear();
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            key: ValueKey(_speciesFamily),
            controller: _species,
            enabled: _speciesFamily != null,
            label: const Text('细分品种'),
            hintText: _speciesFamily == null ? '请先选择品种分类' : '搜索或选择品种',
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              for (final species in _speciesOptions[_speciesFamily] ?? const [])
                DropdownMenuEntry(value: species, label: species),
            ],
            onSelected: (species) => setState(() => _selectedSpecies = species),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queens,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '蚁后数量'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _workers,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '初始工蚁数量'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            controller: _nest,
            label: const Text('巢体类型'),
            hintText: '搜索或选择巢体类型',
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: _nestTypeOptions
                .map((type) => DropdownMenuEntry(value: type, label: type))
                .toList(),
          ),
          const SizedBox(height: 12),
          Text('环境预警上限（可选）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetTemperature,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '温度上限 °C'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _targetHumidity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '湿度上限 %'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _source,
            decoration: const InputDecoration(labelText: '来源'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              _acquiredOn == null
                  ? '选择入手日期（可选）'
                  : '入手日期：${_date(_acquiredOn!)}',
            ),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                initialDate: _acquiredOn ?? DateTime.now(),
              );
              if (date != null) setState(() => _acquiredOn = date);
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_outlined),
            label: Text(_cover == null ? '添加封面照片（可选）' : '已选择封面照片'),
            onPressed: () async {
              final image = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 86,
              );
              if (image != null) setState(() => _cover = image);
            },
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存蚁群'),
          ),
        ],
      ),
    ),
  );
}

class ColonyDetailPage extends StatefulWidget {
  const ColonyDetailPage({super.key, required this.colonyId});
  final String colonyId;
  @override
  State<ColonyDetailPage> createState() => _ColonyDetailPageState();
}

class _ColonyDetailPageState extends State<ColonyDetailPage> {
  late Future<_Detail> _detail;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _detail = _load();
  Future<_Detail> _load() async => _Detail(
    await AppDatabase.instance.findColony(widget.colonyId),
    await AppDatabase.instance.listRecords(widget.colonyId),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<_Detail>(
    future: _detail,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final detail = snapshot.data;
      if (detail?.colony == null) {
        return const Scaffold(
          body: _EmptyState(
            icon: Icons.error_outline,
            title: '找不到蚁群',
            message: '这窝蚂蚁可能已经被归档。',
          ),
        );
      }
      final colony = detail!.colony!;
      return Scaffold(
        appBar: AppBar(title: Text(colony.name)),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('添加记录'),
          onPressed: () async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => RecordFormPage(colony: colony)),
            );
            if (saved == true && mounted) setState(_reload);
          },
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _ColonySummary(colony: colony),
            const SizedBox(height: 22),
            Text('养殖时间线', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (detail.records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: _EmptyState(
                  icon: Icons.article_outlined,
                  title: '还没有记录',
                  message: '从一次投喂或观察开始。',
                ),
              ),
            ...detail.records.map(
              (record) => _RecordCard(record: record, colony: colony),
            ),
          ],
        ),
      );
    },
  );
}

class _Detail {
  const _Detail(this.colony, this.records);
  final Colony? colony;
  final List<CareRecord> records;
}

class _ColonySummary extends StatelessWidget {
  const _ColonySummary({required this.colony});
  final Colony colony;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (colony.coverPhotoPath != null) ...[
            _StoredImage(
              relativePath: colony.coverPhotoPath!,
              width: double.infinity,
              height: 180,
              borderRadius: 12,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            colony.species ?? '未填写品种',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (colony.queenCount != null)
                Chip(label: Text('${colony.queenCount} 只蚁后')),
              if (colony.initialWorkerCount != null)
                Chip(label: Text('${colony.initialWorkerCount} 只工蚁')),
              if (colony.nestType?.isNotEmpty == true)
                Chip(label: Text(colony.nestType!)),
              if (colony.targetTemperature != null)
                Chip(label: Text('温度 ≤ ${colony.targetTemperature}°C')),
              if (colony.targetHumidity != null)
                Chip(label: Text('湿度 ≤ ${colony.targetHumidity}%')),
              if (colony.acquiredOn != null)
                Chip(label: Text('入手 ${_date(colony.acquiredOn!)}')),
            ],
          ),
        ],
      ),
    ),
  );
}

class RecordFormPage extends StatefulWidget {
  const RecordFormPage({super.key, required this.colony});
  final Colony colony;
  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  final _note = TextEditingController();
  final _temperature = TextEditingController();
  final _humidity = TextEditingController();
  final _eggs = TextEditingController();
  final _larvae = TextEditingController();
  final _pupae = TextEditingController();
  final _workers = TextEditingController();
  final _photos = <XFile>[];
  var _type = CareRecordType.observation;
  var _occurredAt = DateTime.now();
  var _saving = false;
  @override
  void dispose() {
    for (final c in [
      _note,
      _temperature,
      _humidity,
      _eggs,
      _larvae,
      _pupae,
      _workers,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final photos = <String>[];
      for (final photo in _photos) {
        photos.add(await LocalMediaStore.instance.copyImage(photo));
      }
      await AppDatabase.instance.saveRecord(
        CareRecord(
          id: const Uuid().v4(),
          colonyId: widget.colony.id,
          type: _type,
          occurredAt: _occurredAt,
          note: _textOrNull(_note.text),
          temperature: double.tryParse(_temperature.text),
          humidity: double.tryParse(_humidity.text),
          eggCount: int.tryParse(_eggs.text),
          larvaCount: int.tryParse(_larvae.text),
          pupaCount: int.tryParse(_pupae.text),
          workerCount: int.tryParse(_workers.text),
          photos: photos,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _occurredAt,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time != null) {
      setState(
        () => _occurredAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('记录 ${widget.colony.name}')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('记录类型', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: CareRecordType.values
              .map(
                (type) => ChoiceChip(
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule),
          label: Text('发生时间：${_dateTime(_occurredAt)}'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '备注',
            hintText: '例如：喂了半只面包虫，进食积极',
          ),
        ),
        const SizedBox(height: 16),
        Text('环境与数量（不清楚可留空）', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _temperature,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '温度 °C'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _humidity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '湿度 %'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _eggs,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '卵数'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _larvae,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '幼虫数'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pupae,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '蛹数'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _workers,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '工蚁数量（可估计）'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _photos.isEmpty ? '添加照片（可选）' : '已选择 ${_photos.length} 张照片',
          ),
          onPressed: () async {
            final images = await ImagePicker().pickMultiImage(imageQuality: 86);
            if (images.isNotEmpty) setState(() => _photos.addAll(images));
          },
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_photos[index].path),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存记录'),
        ),
      ],
    ),
  );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, this.colony});
  final CareRecord record;
  final Colony? colony;
  @override
  Widget build(BuildContext context) {
    final temperatureExceeded =
        record.temperature != null &&
        colony?.targetTemperature != null &&
        record.temperature! > colony!.targetTemperature!;
    final humidityExceeded =
        record.humidity != null &&
        colony?.targetHumidity != null &&
        record.humidity! > colony!.targetHumidity!;
    final facts = <String>[
      if (record.temperature != null) '${record.temperature}°C',
      if (record.humidity != null) '${record.humidity}%',
      if (record.eggCount != null) '卵 ${record.eggCount}',
      if (record.larvaCount != null) '幼虫 ${record.larvaCount}',
      if (record.pupaCount != null) '蛹 ${record.pupaCount}',
      if (record.workerCount != null) '工蚁 ${record.workerCount}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(record.type)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    record.type.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  _dateTime(record.occurredAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (record.note?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(record.note!),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                facts.join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (temperatureExceeded || humidityExceeded) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (temperatureExceeded)
                    '温度 ${record.temperature}°C 高于预设上限 ${colony!.targetTemperature}°C',
                  if (humidityExceeded)
                    '湿度 ${record.humidity}% 高于预设上限 ${colony!.targetHumidity}%',
                ].join('；'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (record.photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: record.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => _StoredImage(
                    relativePath: record.photos[index],
                    width: 88,
                    height: 88,
                    borderRadius: 8,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RecentRecordsPage extends StatefulWidget {
  const RecentRecordsPage({super.key});
  @override
  State<RecentRecordsPage> createState() => _RecentRecordsPageState();
}

class _RecentRecordsPageState extends State<RecentRecordsPage> {
  late Future<List<CareRecord>> _records;
  @override
  void initState() {
    super.initState();
    _records = AppDatabase.instance.listRecentRecords();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CareRecord>>(
    future: _records,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _ErrorState('读取记录失败：${snapshot.error}');
      }
      final records = snapshot.data!;
      if (records.isEmpty) {
        return const _EmptyState(
          icon: Icons.article_outlined,
          title: '还没有养殖记录',
          message: '进入一窝蚂蚁后，点击“添加记录”。',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        itemBuilder: (context, i) => _RecordCard(record: records[i]),
      );
    },
  );
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late Future<List<InventoryItem>> _items;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _items = AppDatabase.instance.listInventory();

  Future<void> _addItem() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增物品'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '物品名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('新增'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await AppDatabase.instance.saveInventoryItem(
        InventoryItem(
          id: const Uuid().v4(),
          name: name,
          purchased: false,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addItem,
      icon: const Icon(Icons.add),
      label: const Text('新增物品'),
    ),
    body: FutureBuilder<List<InventoryItem>>(
      future: _items,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState('读取物品失败：${snapshot.error}');
        }
        final items = snapshot.data!;
        final needed = items.where((item) => !item.purchased).toList();
        final purchased = items.where((item) => item.purchased).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text('待购清单', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            ...needed.map(_itemTile),
            const SizedBox(height: 18),
            Text('已购', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            if (purchased.isEmpty) const Text('还没有标记为已购的物品。'),
            ...purchased.map(_itemTile),
          ],
        );
      },
    ),
  );

  Widget _itemTile(InventoryItem item) => Card(
    child: CheckboxListTile(
      title: Text(item.name),
      value: item.purchased,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (value) async {
        await AppDatabase.instance.setInventoryPurchased(
          item.id,
          value ?? false,
        );
        if (mounted) setState(_reload);
      },
    ),
  );
}

class CarePlanPage extends StatelessWidget {
  const CarePlanPage({super.key});
  @override
  Widget build(BuildContext context) => const _EmptyState(
    icon: Icons.check_circle_outline,
    title: '待办提醒即将加入',
    message: '下一阶段会在本机创建投喂、补水和检查提醒，不依赖服务器推送。',
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const ListTile(
        leading: Icon(Icons.phonelink_lock_outlined),
        title: Text('本地优先'),
        subtitle: Text('蚁群、记录和照片仅保存在本设备；没有账号、服务器或自动同步。'),
      ),
      const Divider(),
      SwitchListTile(
        secondary: const Icon(Icons.dark_mode_outlined),
        title: const Text('黑色主题'),
        subtitle: const Text('使用深色界面，并保存在本机'),
        value: themeController.darkThemeEnabled,
        onChanged: (enabled) async {
          try {
            await themeController.setDarkThemeEnabled(enabled);
          } catch (error) {
            if (context.mounted) _showError(context, error);
          }
        },
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.upload_file_outlined),
        title: const Text('导出备份'),
        subtitle: const Text('生成包含记录和照片的 .zip 文件'),
        onTap: () async {
          try {
            await BackupService(
              AppDatabase.instance,
              LocalMediaStore.instance,
            ).exportBackup();
            if (context.mounted) _showInfo(context, '已完成备份导出。');
          } catch (error) {
            if (context.mounted) _showError(context, error);
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.download_outlined),
        title: const Text('恢复备份'),
        subtitle: const Text('恢复会替换本机现有蚁群与记录'),
        onTap: () async {
          final approved = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('恢复并替换本地数据？'),
              content: const Text('当前蚁群和记录会被选中的备份替换。请先导出当前数据。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('选择备份'),
                ),
              ],
            ),
          );
          if (approved != true || !context.mounted) return;
          try {
            await BackupService(
              AppDatabase.instance,
              LocalMediaStore.instance,
            ).restoreBackup();
            if (context.mounted) _showInfo(context, '已恢复备份，请返回蚁群页查看。');
          } catch (error) {
            if (context.mounted) _showError(context, error);
          }
        },
      ),
    ],
  );
}

class _StoredImage extends StatelessWidget {
  const _StoredImage({
    required this.relativePath,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final String relativePath;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
    future: LocalMediaStore.instance.fileFor(relativePath),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return SizedBox(
          width: width,
          height: height,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError || snapshot.data == null) {
        return _missingImage(context);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          snapshot.data!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stackTrace) => _missingImage(context),
        ),
      );
    },
  );

  Widget _missingImage(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    child: const Icon(Icons.broken_image_outlined),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Text(message)),
  );
}

IconData _icon(CareRecordType type) => switch (type) {
  CareRecordType.feeding => Icons.restaurant_outlined,
  CareRecordType.watering => Icons.water_drop_outlined,
  CareRecordType.observation => Icons.visibility_outlined,
  CareRecordType.environment => Icons.thermostat_outlined,
  CareRecordType.relocation => Icons.home_work_outlined,
  CareRecordType.brood => Icons.egg_outlined,
  CareRecordType.mortality => Icons.remove_circle_outline,
  CareRecordType.note => Icons.edit_note_outlined,
};
String? _textOrNull(String value) => value.trim().isEmpty ? null : value.trim();
String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _dateTime(DateTime value) =>
    '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作未完成：$error')));
void _showInfo(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
