import 'dart:typed_data';
import 'dart:async';

import 'online/runtime.dart';
import 'online/online_widgets.dart';
import 'online/content.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'app_preferences.dart';
import 'onboarding.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/local_media_store.dart';
import 'data/local_notification_service.dart';
import 'domain/models.dart';

const _speciesOptions = <String, List<String>>{
  '收获蚁': ['工匠收获蚁', '原生收获蚁', '红胸收获蚁', '大头收获蚁', '强壮收获蚁', '针毛收获蚁', '无恶齿收获蚁'],
  '弓背蚁': [
    '黑金弓背蚁',
    '大头弓背蚁',
    '尼科巴弓背蚁',
    '巴瑞弓背蚁',
    '拟光腹弓背蚁',
    '全黄弓背蚁',
    '日本弓背蚁',
    '广布弓背蚁',
    '窄颈弓背蚁（窄径）',
  ],
  '猛蚁': ['横纹猛蚁', '横纹齿猛蚁', '聚纹双刺猛蚁', '大齿猛蚁', '扁头猛蚁'],
  '蜜罐蚁': ['墨西哥蜜罐蚁', '大平眼蜜罐蚁'],
  '孔蚁': ['巨人孔蚁'],
  '子弹蚁': ['子弹蚁'],
  '铺道蚁': ['双隆骨铺道蚁', '铺道蚁'],
  '多刺蚁': ['黄猄蚁', '拟弓多刺蚁'],
  '大头蚁': ['中华大头蚁', '皮氏大头蚁'],
  '毛蚁': ['玉米毛蚁'],
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

class BeginnerCareNotice {
  const BeginnerCareNotice({required this.title, required this.description});

  final String title;
  final String description;
}

const _beginnerCareNotices = [
  BeginnerCareNotice(
    title: '尽量减少打扰',
    description: '新入手、繁殖期或状态不稳定的蚁群尤其需要安静环境；除必要的投喂、补水和观察外，尽量少开巢、少搬动。',
  ),
  BeginnerCareNotice(
    title: '注意饲养温度',
    description: '先了解所养品种适宜的温度范围，避免暴晒、骤冷骤热和长时间贴近热源；温度异常时优先让环境恢复稳定。',
  ),
];

BeginnerCareNotice beginnerCareNoticeFor(DateTime date) =>
    _beginnerCareNotices[(date.day - 1) % _beginnerCareNotices.length];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalMediaStore.instance.initialize();
    await AppDatabase.instance.open();
    await themeController.load();
    void updateOnlineMode() => unawaited(
      onlineController.setEnabled(themeController.edition == AppEdition.online),
    );
    themeController.addListener(updateOnlineMode);
    updateOnlineMode();
    try {
      await LocalNotificationService.instance.initialize();
      if (themeController.careRemindersEnabled) {
        await LocalNotificationService.instance.scheduleDailyCareReminder(
          themeController.careReminderMinuteOfDay,
        );
      }
    } catch (_) {
      // A notification integration failure must not block access to local data.
    }
    runApp(const AntKeepApp());
  } catch (error) {
    runApp(_StartupError(error: error));
  }
}

final themeController = AppPreferences(AppDatabase.instance);

class AntKeepApp extends StatelessWidget {
  const AntKeepApp({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => MaterialApp(
      title: '蚁记',
      debugShowCheckedModeBanner: false,
      theme: antKeepTheme(themeController.themeColor),
      darkTheme: antKeepTheme(themeController.themeColor, dark: true),
      themeMode: themeController.themeMode,
      home: themeController.onboardingCompleted
          ? const HomePage()
          : OnboardingPage(preferences: themeController),
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  var _index = 0;
  late final BeginnerCareNotice _beginnerCareNotice;

  @override
  void initState() {
    super.initState();
    _beginnerCareNotice = beginnerCareNoticeFor(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onlineController.refreshCheckin());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    const titles = ['我的蚁群', '最近记录', '物品', 'DLC 养殖', '设置'];
    final pages = [
      const ColoniesPage(),
      const RecentRecordsPage(),
      const InventoryPage(),
      const DlcPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
      body: Column(
        children: [
          if (_index == 0 && themeController.beginner)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text('新手注意事项'),
                subtitle: Text(_beginnerCareNotice.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lightbulb_outline),
                      title: Text(_beginnerCareNotice.title),
                      subtitle: Text(_beginnerCareNotice.description),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: pages[_index]),
        ],
      ),
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
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label: 'DLC',
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
      if (colony.scale != null) colony.scale!.label,
      if (colony.queenCount != null) '${colony.queenCount} 只蚁后',
      if (colony.initialWorkerCount != null) '${colony.initialWorkerCount} 只工蚁',
      if (colony.initialEggCount != null) '卵 ${colony.initialEggCount}',
      if (colony.initialCocoonCount != null) '茧 ${colony.initialCocoonCount}',
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
        title: Row(
          children: [
            Expanded(child: Text(colony.name)),
            if (colony.scale != null) _ColonyScaleBadge(scale: colony.scale!),
          ],
        ),
        subtitle: Text(details.isEmpty ? '尚未补充档案' : details.join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ColonyScaleBadge extends StatelessWidget {
  const _ColonyScaleBadge({required this.scale});
  final ColonyScale scale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (scale) {
      ColonyScale.newQueen => scheme.primary,
      ColonyScale.small => scheme.secondary,
      ColonyScale.medium => scheme.tertiary,
      ColonyScale.large => scheme.primary,
      ColonyScale.superLarge => scheme.error,
    };
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        scale.label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
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
  final _source = TextEditingController();
  final _queens = TextEditingController();
  final _workers = TextEditingController();
  final _eggs = TextEditingController();
  final _cocoons = TextEditingController();
  final _targetTemperature = TextEditingController();
  final _targetHumidity = TextEditingController();
  String? _speciesFamily;
  String? _selectedSpecies;
  String? _selectedNest;
  DateTime? _acquiredOn;
  XFile? _cover;
  var _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _source,
      _queens,
      _workers,
      _eggs,
      _cocoons,
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
          initialEggCount: int.tryParse(_eggs.text),
          initialCocoonCount: int.tryParse(_cocoons.text),
          nestType: _selectedNest,
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

  Future<void> _enterCustomSpecies() async {
    final controller = TextEditingController();
    final species = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动填写品种'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：其他弓背蚁'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (species?.isNotEmpty == true && mounted) {
      setState(() => _selectedSpecies = species);
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
          _SearchableChoiceField(
            label: '品种分类',
            hintText: '点击选择分类',
            value: _speciesFamily,
            options: _speciesOptions.keys.toList(),
            onSelected: (family) {
              setState(() {
                _speciesFamily = family;
                _selectedSpecies = null;
              });
            },
          ),
          const SizedBox(height: 12),
          _SearchableChoiceField(
            key: ValueKey(_speciesFamily),
            enabled: _speciesFamily != null,
            label: '细分品种',
            hintText: _speciesFamily == null ? '请先选择品种分类' : '点击搜索或选择品种',
            value: _selectedSpecies,
            options: _speciesOptions[_speciesFamily] ?? const [],
            onSelected: (species) => setState(() => _selectedSpecies = species),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _speciesFamily == null ? null : _enterCustomSpecies,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('未收录？手动填写品种'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  decoration: const InputDecoration(
                    labelText: '初始工蚁数量',
                    helperText: '填 0 标识为新后群落',
                  ),
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
                  decoration: const InputDecoration(labelText: '卵数量（可选）'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cocoons,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '茧数量（可选）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SearchableChoiceField(
            label: '巢体类型',
            hintText: '点击搜索或选择巢体类型',
            value: _selectedNest,
            options: _nestTypeOptions,
            onSelected: (nest) => setState(() => _selectedNest = nest),
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
            decoration: InputDecoration(
              labelText: '来源',
              hintText: '选择或填写来源',
              suffixIcon: PopupMenuButton<String>(
                tooltip: '选择来源',
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (source) => setState(() => _source.text = source),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: '野采', child: Text('野采')),
                  PopupMenuItem(value: '网购', child: Text('网购')),
                  PopupMenuItem(value: '蚁友赠送', child: Text('蚁友赠送')),
                ],
              ),
            ),
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

class _SearchableChoiceField extends StatelessWidget {
  const _SearchableChoiceField({
    super.key,
    required this.label,
    required this.hintText,
    required this.value,
    required this.options,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final String hintText;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final bool enabled;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChoicePickerSheet(title: label, options: options),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('$label-$value-$enabled'),
    initialValue: value ?? '',
    readOnly: true,
    enabled: enabled,
    onTap: enabled ? () => _openPicker(context) : null,
    decoration: InputDecoration(
      labelText: label,
      hintText: hintText,
      suffixIcon: const Icon(Icons.search),
    ),
  );
}

class _ChoicePickerSheet extends StatefulWidget {
  const _ChoicePickerSheet({required this.title, required this.options});
  final String title;
  final List<String> options;

  @override
  State<_ChoicePickerSheet> createState() => _ChoicePickerSheetState();
}

class _ChoicePickerSheetState extends State<_ChoicePickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.text.trim().toLowerCase();
    final options = widget.options
        .where((option) => option.toLowerCase().contains(normalizedQuery))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '输入名称搜索',
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: options.isEmpty
                    ? const _EmptyState(
                        icon: Icons.search_off_outlined,
                        title: '没有匹配项',
                        message: '换一个关键词试试。',
                      )
                    : ListView.separated(
                        itemCount: options.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => ListTile(
                          title: Text(options[index]),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, options[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            const SizedBox(height: 16),
            _GrowthArchive(colony: colony, records: detail.records),
            const SizedBox(height: 22),
            Text('养蚁日记', style: Theme.of(context).textTheme.titleLarge),
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

class _GrowthArchive extends StatelessWidget {
  const _GrowthArchive({required this.colony, required this.records});
  final Colony colony;
  final List<CareRecord> records;

  @override
  Widget build(BuildContext context) {
    final latest = records.cast<CareRecord?>().firstWhere(
      (record) =>
          record!.eggCount != null ||
          record.larvaCount != null ||
          record.pupaCount != null ||
          record.workerCount != null,
      orElse: () => null,
    );
    final latestDate = latest == null ? null : _date(latest.occurredAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up_outlined),
                const SizedBox(width: 8),
                Text('成长档案', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              latestDate == null ? '记录一次数量，成长变化会显示在这里。' : '最近数量记录：$latestDate',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _GrowthMetric(
                  label: '工蚁',
                  initial: colony.initialWorkerCount,
                  latest: latest?.workerCount,
                ),
                _GrowthMetric(
                  label: '卵',
                  initial: colony.initialEggCount,
                  latest: latest?.eggCount,
                ),
                _GrowthMetric(label: '幼虫', latest: latest?.larvaCount),
                _GrowthMetric(
                  label: '蛹',
                  initial: colony.initialCocoonCount,
                  latest: latest?.pupaCount,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GrowthMetric extends StatelessWidget {
  const _GrowthMetric({required this.label, this.initial, this.latest});
  final String label;
  final int? initial;
  final int? latest;

  @override
  Widget build(BuildContext context) {
    final value = latest ?? initial;
    final delta = initial != null && latest != null ? latest! - initial! : null;
    final deltaLabel = switch (delta) {
      null || 0 => '',
      > 0 => '（+$delta）',
      _ => '（$delta）',
    };
    return Chip(label: Text('$label ${value ?? '未记录'}$deltaLabel'));
  }
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
          if (colony.scale != null) ...[
            Chip(
              avatar: Icon(
                colony.scale == ColonyScale.newQueen
                    ? Icons.workspace_premium_outlined
                    : Icons.groups_outlined,
                size: 18,
              ),
              label: Text(colony.scale!.label),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (colony.queenCount != null)
                Chip(label: Text('${colony.queenCount} 只蚁后')),
              if (colony.initialWorkerCount != null)
                Chip(label: Text('${colony.initialWorkerCount} 只工蚁')),
              if (colony.initialEggCount != null)
                Chip(label: Text('卵 ${colony.initialEggCount}')),
              if (colony.initialCocoonCount != null)
                Chip(label: Text('茧 ${colony.initialCocoonCount}')),
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
                child: FutureBuilder<Uint8List>(
                  future: _photos[index].readAsBytes(),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.memory(
                          snapshot.data!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        )
                      : const SizedBox(width: 80, height: 80),
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
    // Keep the selection stable while an in-flight content refresh completes.
    final templates = onlineController.content.templates
        .where((t) => t.enabled)
        .toList();
    final nameController = TextEditingController();
    final shelfLifeController = TextEditingController(text: '3');
    var expiryType = InventoryExpiryType.none;
    DateTime? expiresAt;
    final item = await showDialog<_NewInventoryItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新增物品'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ItemTemplate>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '从模板预填（可选）'),
                  items: templates
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text('${t.name} · ${t.category} / ${t.unit}'),
                        ),
                      )
                      .toList(),
                  onChanged: (template) {
                    if (template == null) return;
                    setDialogState(() {
                      nameController.text = template.name;
                      expiryType = template.months == null
                          ? InventoryExpiryType.none
                          : InventoryExpiryType.shelfLife;
                      shelfLifeController.text = '${template.months ?? 3}';
                      expiresAt = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '物品名称'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InventoryExpiryType>(
                  key: ValueKey(expiryType),
                  initialValue: expiryType,
                  decoration: const InputDecoration(labelText: '有效期类型'),
                  items: InventoryExpiryType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: (type) => setDialogState(
                    () => expiryType = type ?? InventoryExpiryType.none,
                  ),
                ),
                if (expiryType == InventoryExpiryType.shelfLife) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: shelfLifeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '保质期（月）'),
                  ),
                ],
                if (expiryType == InventoryExpiryType.fixedDate) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      expiresAt == null ? '选择到期日' : '到期日：${_date(expiresAt!)}',
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: expiresAt ?? DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => expiresAt = picked);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty ||
                    (expiryType == InventoryExpiryType.fixedDate &&
                        expiresAt == null)) {
                  return;
                }
                Navigator.pop(
                  context,
                  _NewInventoryItem(
                    name: name,
                    expiryType: expiryType,
                    shelfLifeMonths: expiryType == InventoryExpiryType.shelfLife
                        ? int.tryParse(shelfLifeController.text) ?? 3
                        : null,
                    expiresAt: expiresAt,
                  ),
                );
              },
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    shelfLifeController.dispose();
    if (item == null) return;
    try {
      await AppDatabase.instance.saveInventoryItem(
        InventoryItem(
          id: const Uuid().v4(),
          name: item.name,
          purchased: false,
          createdAt: DateTime.now(),
          expiryType: item.expiryType,
          shelfLifeMonths: item.shelfLifeMonths,
          expiresAt: item.expiresAt,
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
    body: DefaultTabController(
      length: 2,
      child: FutureBuilder<List<InventoryItem>>(
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
          return Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: '推荐 (${needed.length})'),
                  Tab(text: '已购 (${purchased.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _itemList(needed, '暂时没有推荐的物品。'),
                    _itemList(purchased, '还没有已购的物品。'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _itemList(List<InventoryItem> items, String emptyMessage) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
    children: [if (items.isEmpty) Text(emptyMessage), ...items.map(_itemTile)],
  );

  Widget _itemTile(InventoryItem item) {
    final expired = item.isExpired();
    final expiry = item.effectiveExpiryDate();
    final expiryText = switch (item.expiryType) {
      InventoryExpiryType.none => null,
      InventoryExpiryType.shelfLife when item.purchasedAt == null =>
        '有效期：购入后 ${item.shelfLifeMonths ?? 3} 个月（勾选已购买后开始计时）',
      InventoryExpiryType.shelfLife when expiry == null => '有效期：未设置保质期',
      InventoryExpiryType.shelfLife =>
        expired ? '已过期：${_date(expiry!)}' : '有效期至：${_date(expiry!)}',
      InventoryExpiryType.fixedDate when expiry == null => '有效期：未设置到期日',
      InventoryExpiryType.fixedDate =>
        expired ? '已过期：${_date(expiry!)}' : '有效期至：${_date(expiry!)}',
    };
    return Card(
      child: CheckboxListTile(
        title: Row(
          children: [
            Expanded(child: Text(item.name)),
            if (expired)
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 20,
              ),
          ],
        ),
        subtitle: expiryText == null
            ? null
            : Text(
                expiryText,
                style: expired
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      )
                    : null,
              ),
        value: item.purchased,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (value) async {
          await AppDatabase.instance.setInventoryPurchased(
            item,
            value ?? false,
          );
          if (mounted) setState(_reload);
        },
      ),
    );
  }
}

class _NewInventoryItem {
  const _NewInventoryItem({
    required this.name,
    required this.expiryType,
    this.shelfLifeMonths,
    this.expiresAt,
  });

  final String name;
  final InventoryExpiryType expiryType;
  final int? shelfLifeMonths;
  final DateTime? expiresAt;
}

class DlcPage extends StatefulWidget {
  const DlcPage({super.key});

  @override
  State<DlcPage> createState() => _DlcPageState();
}

class _DlcPageState extends State<DlcPage> {
  late Map<FeederType, Future<FeederRecord?>> _counts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _counts = {
    for (final feeder in FeederType.values)
      feeder: AppDatabase.instance.latestFeederCountRecord(feeder),
  };

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('活体饲料养殖记录', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('每类饲料独立记录，数据只保存在本机。'),
      const SizedBox(height: 16),
      ...FeederType.values.map(
        (feeder) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_feederIcon(feeder))),
              title: Text(feeder.label),
              trailing: FutureBuilder<FeederRecord?>(
                future: _counts[feeder],
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _FeederSummary(text: '读取中…');
                  }
                  if (snapshot.hasError) {
                    return const _FeederSummary(text: '读取失败');
                  }
                  final record = snapshot.data;
                  if (record == null) return const _FeederSummary(text: '暂未记录');
                  final juveniles = record.juvenileCount;
                  final adults = record.adultCount;
                  return _FeederSummary(
                    time: _dateTime(record.occurredAt),
                    count: juveniles != null && adults != null
                        ? '${juveniles + adults} 只'
                        : '部分未记录',
                  );
                },
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FeederDetailPage(feeder: feeder),
                  ),
                );
                if (mounted) setState(_reload);
              },
            ),
          ),
        ),
      ),
    ],
  );
}

class _FeederSummary extends StatelessWidget {
  const _FeederSummary({this.time, this.count, this.text});

  final String? time;
  final String? count;
  final String? text;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: text == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(time!, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      count!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Text(
                  text!,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

class FeederDetailPage extends StatefulWidget {
  const FeederDetailPage({super.key, required this.feeder});
  final FeederType feeder;

  @override
  State<FeederDetailPage> createState() => _FeederDetailPageState();
}

class _FeederDetailPageState extends State<FeederDetailPage> {
  late Future<List<FeederRecord>> _records;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      _records = AppDatabase.instance.listFeederRecords(widget.feeder);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.feeder.label)),
    floatingActionButton: FloatingActionButton.extended(
      icon: const Icon(Icons.add),
      label: const Text('添加记录'),
      onPressed: () async {
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => FeederRecordFormPage(feeder: widget.feeder),
          ),
        );
        if (saved == true && mounted) setState(_reload);
      },
    ),
    body: FutureBuilder<List<FeederRecord>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState('读取养殖记录失败：${snapshot.error}');
        }
        final records = snapshot.data!;
        if (records.isEmpty) {
          return _EmptyState(
            icon: _feederIcon(widget.feeder),
            title: '还没有${widget.feeder.label}记录',
            message: '从一次投喂、清洁或观察开始。',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) =>
                _FeederRecordCard(record: records[index]),
          ),
        );
      },
    ),
  );
}

class FeederRecordFormPage extends StatefulWidget {
  const FeederRecordFormPage({super.key, required this.feeder});
  final FeederType feeder;

  @override
  State<FeederRecordFormPage> createState() => _FeederRecordFormPageState();
}

class _FeederRecordFormPageState extends State<FeederRecordFormPage> {
  final _note = TextEditingController();
  final _temperature = TextEditingController();
  final _humidity = TextEditingController();
  final _juveniles = TextEditingController();
  final _adults = TextEditingController();
  final _mortality = TextEditingController();
  var _type = FeederRecordType.observation;
  var _occurredAt = DateTime.now();
  var _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _note,
      _temperature,
      _humidity,
      _juveniles,
      _adults,
      _mortality,
    ]) {
      controller.dispose();
    }
    super.dispose();
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.saveFeederRecord(
        FeederRecord(
          id: const Uuid().v4(),
          feeder: widget.feeder,
          type: _type,
          occurredAt: _occurredAt,
          note: _textOrNull(_note.text),
          temperature: double.tryParse(_temperature.text),
          humidity: double.tryParse(_humidity.text),
          juvenileCount: int.tryParse(_juveniles.text),
          adultCount: int.tryParse(_adults.text),
          mortalityCount: int.tryParse(_mortality.text),
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('记录${widget.feeder.label}')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('记录类型', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: FeederRecordType.values
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
            hintText: '例如：更换食物，活动正常',
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
                controller: _juveniles,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '幼体/若虫数量'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _adults,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '成体数量'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mortality,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '死亡数量'),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存记录'),
        ),
      ],
    ),
  );
}

class _FeederRecordCard extends StatelessWidget {
  const _FeederRecordCard({required this.record});
  final FeederRecord record;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[
      if (record.temperature != null) '${record.temperature}°C',
      if (record.humidity != null) '${record.humidity}%',
      if (record.juvenileCount != null) '幼体/若虫 ${record.juvenileCount}',
      if (record.adultCount != null) '成体 ${record.adultCount}',
      if (record.mortalityCount != null) '死亡 ${record.mortalityCount}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_feederRecordIcon(record.type)),
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
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => _buildSettings(context),
  );

  Widget _buildSettings(BuildContext context) => ListView(
    children: [
      OnlineSettings(
        preferences: themeController,
        controller: onlineController,
      ),
      ListTile(
        leading: Icon(
          themeController.edition == AppEdition.offline
              ? Icons.phonelink_lock_outlined
              : Icons.cloud_download_outlined,
        ),
        title: Text(themeController.edition.label),
        subtitle: Text(
          themeController.edition == AppEdition.offline
              ? '使用 App 内置资料；蚁群、记录和照片仅保存在本设备。'
              : '养殖记录和照片仍仅保存在本设备；可获取后台发布的最新资料和配置。',
        ),
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.palette_outlined),
        title: Text('主题色'),
        subtitle: Text('选择喜欢的颜色，保存在本机'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ThemeColorPicker(
          selected: themeController.themeColor,
          onChanged: (color) async {
            try {
              await themeController.setThemeColor(color);
            } catch (error) {
              if (context.mounted) _showError(context, error);
            }
          },
        ),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.lightbulb_outline),
        title: const Text('新手注意事项'),
        subtitle: const Text('在蚁群首页显示养蚁新手注意事项'),
        value: themeController.beginner,
        onChanged: (enabled) async {
          try {
            await themeController.setBeginner(enabled);
          } catch (error) {
            if (context.mounted) _showError(context, error);
          }
        },
      ),
      const ListTile(
        leading: Icon(Icons.dark_mode_outlined),
        title: Text('外观模式'),
        subtitle: Text('跟随系统，或固定使用浅色、深色界面'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ThemeModePicker(
          selected: themeController.themeMode,
          onChanged: (mode) async {
            try {
              await themeController.setThemeMode(mode);
            } catch (error) {
              if (context.mounted) _showError(context, error);
            }
          },
        ),
      ),
      const Divider(),
      SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('本地养护提醒'),
        subtitle: Text(
          themeController.careRemindersEnabled
              ? '每天 ${_timeOfDay(themeController.careReminderMinuteOfDay)} 提醒；不上传任何数据'
              : '关闭；开启后仅向系统申请通知权限',
        ),
        value: themeController.careRemindersEnabled,
        onChanged: (enabled) async {
          try {
            if (enabled) {
              final granted = await LocalNotificationService.instance
                  .requestPermission();
              if (!granted) {
                if (context.mounted) _showInfo(context, '未获得通知权限，提醒没有开启。');
                return;
              }
              await LocalNotificationService.instance.scheduleDailyCareReminder(
                themeController.careReminderMinuteOfDay,
              );
            } else {
              await LocalNotificationService.instance.cancelDailyCareReminder();
            }
            await themeController.setCareReminder(
              enabled: enabled,
              minuteOfDay: themeController.careReminderMinuteOfDay,
            );
          } catch (error) {
            if (context.mounted) _showError(context, error);
          }
        },
      ),
      ListTile(
        enabled: themeController.careRemindersEnabled,
        leading: const Icon(Icons.schedule_outlined),
        title: const Text('提醒时间'),
        subtitle: Text(
          '每天 ${_timeOfDay(themeController.careReminderMinuteOfDay)}',
        ),
        onTap: !themeController.careRemindersEnabled
            ? null
            : () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: themeController.careReminderMinuteOfDay ~/ 60,
                    minute: themeController.careReminderMinuteOfDay % 60,
                  ),
                );
                if (picked == null || !context.mounted) return;
                final minuteOfDay = picked.hour * 60 + picked.minute;
                try {
                  await LocalNotificationService.instance
                      .scheduleDailyCareReminder(minuteOfDay);
                  await themeController.setCareReminder(
                    enabled: true,
                    minuteOfDay: minuteOfDay,
                  );
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
            final exported = await BackupService(
              AppDatabase.instance,
              LocalMediaStore.instance,
            ).exportBackup();
            if (exported && context.mounted) _showInfo(context, '已完成备份导出。');
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
            final restored = await BackupService(
              AppDatabase.instance,
              LocalMediaStore.instance,
            ).restoreBackup();
            if (restored && context.mounted) {
              _showInfo(context, '已恢复备份；可在设置中撤销上一次恢复。');
            }
          } catch (error) {
            if (context.mounted) _showError(context, error);
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.undo_outlined),
        title: const Text('撤销上一次恢复'),
        subtitle: const Text('恢复覆盖前自动保留的本地回退副本'),
        onTap: () async {
          final service = BackupService(
            AppDatabase.instance,
            LocalMediaStore.instance,
          );
          final hasRollback = await service.hasRollback();
          if (!context.mounted) return;
          if (!hasRollback) {
            _showInfo(context, '没有可撤销的恢复操作。');
            return;
          }
          final approved = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('撤销上一次恢复？'),
              content: const Text('当前数据会被恢复前自动保存的本地副本替换。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('撤销恢复'),
                ),
              ],
            ),
          );
          if (approved != true || !context.mounted) return;
          try {
            await service.undoLastRestore();
            if (context.mounted) _showInfo(context, '已撤销上一次恢复。');
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
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: LocalMediaStore.instance.readImage(relativePath),
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
        child: Image.memory(
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

IconData _feederIcon(FeederType feeder) => switch (feeder) {
  FeederType.dubia => Icons.bug_report_outlined,
  FeederType.cherryRoach => Icons.pest_control_outlined,
  FeederType.mealworm => Icons.grass_outlined,
  FeederType.cricket => Icons.music_note_outlined,
};

IconData _feederRecordIcon(FeederRecordType type) => switch (type) {
  FeederRecordType.observation => Icons.visibility_outlined,
  FeederRecordType.feeding => Icons.restaurant_outlined,
  FeederRecordType.cleaning => Icons.cleaning_services_outlined,
  FeederRecordType.breeding => Icons.egg_outlined,
  FeederRecordType.mortality => Icons.remove_circle_outline,
};

String? _textOrNull(String value) => value.trim().isEmpty ? null : value.trim();
String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _dateTime(DateTime value) =>
    '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _timeOfDay(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';
void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作未完成：$error')));
void _showInfo(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
