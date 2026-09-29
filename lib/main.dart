import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'app_preferences.dart';
import 'account_controller.dart';
import 'personal_center_page.dart';
import 'population_analysis_page.dart';
import 'onboarding.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/local_media_store.dart';
import 'data/local_notification_service.dart';
import 'domain/models.dart';
import 'domain/purchase_price.dart';
import 'domain/beginner_care_notice.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalMediaStore.instance.initialize();
    await AppDatabase.instance.open();
    await themeController.load();
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
final accountController = AccountController(preferences: themeController);

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

class _HomePageState extends State<HomePage> {
  var _index = 0;
  late BeginnerCareNotice _beginnerCareNotice;

  @override
  void initState() {
    super.initState();
    _beginnerCareNotice = randomBeginnerCareNotice();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    const titles = ['我的蚁群', '物品', 'DLC 养殖', '发现', '设置'];
    final pages = [
      const ColoniesPage(),
      const InventoryPage(),
      const DlcPage(),
      const DiscoverPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PopulationAnalysisPage()),
            ),
            icon: const Icon(Icons.show_chart),
            label: const Text('分析'),
          ),
        ],
      ),
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
                onTap: () {
                  final notice = _beginnerCareNotice;
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => SingleChildScrollView(
                      padding: EdgeInsets.all(24),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lightbulb_outline),
                        title: Text(notice.title),
                        subtitle: Text(notice.description),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(child: pages[_index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() {
          if (value == 0 && _index != 0) {
            _beginnerCareNotice = randomBeginnerCareNotice(
              previous: _beginnerCareNotice,
            );
          }
          _index = value;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.hive_outlined),
            selectedIcon: Icon(Icons.hive),
            label: '蚁群',
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
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
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

typedef _ColonyListEntry = ({
  Colony colony,
  CareRecord? latestPopulation,
  int? workers,
});

class _ColoniesPageState extends State<ColoniesPage> {
  late Future<List<_ColonyListEntry>> _colonies;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _colonies = _loadColonies();
  }

  Future<List<_ColonyListEntry>> _loadColonies() async {
    final colonies = await AppDatabase.instance.listColonies();
    return Future.wait(
      colonies.map((colony) async {
        final records = await AppDatabase.instance.listRecords(colony.id);
        final latestPopulation = records.cast<CareRecord?>().firstWhere(
          (record) =>
              record!.eggCount != null ||
              record.larvaCount != null ||
              record.pupaCount != null ||
              record.workerCount != null,
          orElse: () => null,
        );
        return (
          colony: colony,
          latestPopulation: latestPopulation,
          workers: colony.currentWorkerCount(records),
        );
      }),
    );
  }

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
    body: FutureBuilder<List<_ColonyListEntry>>(
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
              colony: colonies[index].colony,
              latestPopulation: colonies[index].latestPopulation,
              workers: colonies[index].workers,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ColonyDetailPage(colonyId: colonies[index].colony.id),
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
  const _ColonyCard({
    required this.colony,
    required this.latestPopulation,
    required this.workers,
    required this.onTap,
  });
  final Colony colony;
  final CareRecord? latestPopulation;
  final int? workers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final broodCounts = [
      latestPopulation?.eggCount ?? colony.initialEggCount,
      latestPopulation?.larvaCount,
      latestPopulation?.pupaCount ?? colony.initialCocoonCount,
    ].whereType<int>();
    final brood = broodCounts.isEmpty
        ? null
        : broodCounts.fold<int>(0, (sum, count) => sum + count);
    final theme = Theme.of(context);
    final numberStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );
    TextSpan quantity(int count, String label) => TextSpan(
      children: [
        TextSpan(text: '$count', style: numberStyle),
        TextSpan(text: ' 只$label'),
      ],
    );
    final details = <InlineSpan>[
      if (colony.queenCount != null) quantity(colony.queenCount!, '蚁后'),
      if (colony.showSpecialized && colony.specializedCount != null)
        quantity(colony.specializedCount!, '特化'),
      if (workers != null) quantity(workers!, '工蚁'),
      if (brood != null) quantity(brood, '卵幼茧'),
    ];
    final description = [
      colony.species,
      colony.nestType,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  colony.coverPhotoPath == null
                      ? const CircleAvatar(
                          radius: 24,
                          child: Icon(Icons.hive_outlined),
                        )
                      : _StoredImage(
                          relativePath: colony.coverPhotoPath!,
                          width: 48,
                          height: 48,
                          borderRadius: 24,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              colony.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            _ColonyTags(colony: colony, workers: workers),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (details.isNotEmpty || description.isEmpty) ...[
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    children: details.isEmpty
                        ? [const TextSpan(text: '尚未补充档案')]
                        : [
                            for (var i = 0; i < details.length; i++) ...[
                              if (i > 0) const TextSpan(text: ' · '),
                              details[i],
                            ],
                          ],
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ColonyTags extends StatelessWidget {
  const _ColonyTags({required this.colony, required this.workers});
  final Colony colony;
  final int? workers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = ColonyScale.fromWorkerCount(workers);
    final color = switch (scale) {
      ColonyScale.small => scheme.secondary,
      ColonyScale.medium => scheme.tertiary,
      ColonyScale.large => scheme.primary,
      ColonyScale.superLarge => scheme.error,
      null => scheme.onSurfaceVariant,
    };
    Widget badge(String label, Color color, {bool crown = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (crown) ...[
            const Text('👑', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (colony.isNewQueenColony) badge('新后群', scheme.primary, crown: true),
        if (scale != null) badge(scale.label, color),
      ],
    );
  }
}

class ColonyFormPage extends StatefulWidget {
  const ColonyFormPage({super.key, this.colony});
  final Colony? colony;
  @override
  State<ColonyFormPage> createState() => _ColonyFormPageState();
}

class _ColonyFormPageState extends State<ColonyFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _source = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _queens = TextEditingController();
  final _specialized = TextEditingController(text: '0');
  var _showSpecialized = false;
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
  void initState() {
    super.initState();
    final colony = widget.colony;
    if (colony == null) return;
    _name.text = colony.name;
    _source.text = colony.source ?? '';
    _purchasePrice.text = colony.purchasePriceText ?? '';
    _queens.text = colony.queenCount?.toString() ?? '';
    _specialized.text = colony.specializedCount?.toString() ?? '0';
    _showSpecialized = colony.showSpecialized;
    _workers.text = colony.initialWorkerCount?.toString() ?? '';
    _eggs.text = colony.initialEggCount?.toString() ?? '';
    _cocoons.text = colony.initialCocoonCount?.toString() ?? '';
    _targetTemperature.text = colony.targetTemperature?.toString() ?? '';
    _targetHumidity.text = colony.targetHumidity?.toString() ?? '';
    _selectedSpecies = colony.species;
    for (final entry in _speciesOptions.entries) {
      if (entry.value.contains(colony.species)) {
        _speciesFamily = entry.key;
        break;
      }
    }
    _selectedNest = colony.nestType;
    _acquiredOn = colony.acquiredOn;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _source,
      _purchasePrice,
      _queens,
      _specialized,
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

  String? _validateCount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final count = int.tryParse(value.trim());
    return count == null || count < 0 ? '请输入非负整数，未知可留空' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await AppDatabase.instance.saveColony(
        Colony(
          id: widget.colony?.id ?? const Uuid().v4(),
          name: _name.text.trim(),
          species: _selectedSpecies,
          acquiredOn: _acquiredOn,
          source: _textOrNull(_source.text),
          purchasePriceCents: parsePurchasePrice(_purchasePrice.text),
          queenCount: int.tryParse(_queens.text),
          specializedCount: int.tryParse(_specialized.text.trim()),
          showSpecialized: _showSpecialized,
          initialWorkerCount: int.tryParse(_workers.text),
          initialEggCount: int.tryParse(_eggs.text),
          initialCocoonCount: int.tryParse(_cocoons.text),
          nestType: _selectedNest,
          targetTemperature: double.tryParse(_targetTemperature.text),
          targetHumidity: double.tryParse(_targetHumidity.text),
          coverPhotoPath: _cover == null
              ? widget.colony?.coverPhotoPath
              : await LocalMediaStore.instance.copyImage(_cover!),
          archived: widget.colony?.archived ?? false,
          createdAt: widget.colony?.createdAt ?? now,
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

  void _selectSpecies(String species) {
    setState(() {
      _selectedSpecies = species;
      if (_name.text.trim().isEmpty) _name.text = species;
    });
  }

  Future<void> _selectFamily(String family) async {
    if (!mounted) return;
    setState(() {
      _speciesFamily = family;
      _selectedSpecies = null;
    });
    final species = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChoicePickerSheet(
        title: '细分品种',
        options: _speciesOptions[family] ?? const [],
      ),
    );
    if (species != null && mounted) _selectSpecies(species);
  }

  Future<void> _enterCustomSpecies() async {
    var speciesName = '';
    final species = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动填写品种'),
        content: TextField(
          onChanged: (value) => speciesName = value,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：其他弓背蚁'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, speciesName.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (species?.isNotEmpty == true && mounted) {
      _selectSpecies(species!);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.colony == null ? '新入手蚁群' : '编辑蚁群')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SearchableChoiceField(
            label: '品种分类',
            hintText: '点击选择分类',
            value: _speciesFamily,
            options: _speciesOptions.keys.toList(),
            onSelected: _selectFamily,
          ),
          const SizedBox(height: 12),
          _SearchableChoiceField(
            key: ValueKey(_speciesFamily),
            enabled: _speciesFamily != null,
            label: '细分品种',
            hintText: _speciesFamily == null ? '请先选择品种分类' : '点击搜索或选择品种',
            value: _selectedSpecies,
            options: _speciesOptions[_speciesFamily] ?? const [],
            onSelected: _selectSpecies,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _enterCustomSpecies,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('未收录？手动填写品种'),
            ),
          ),
          const SizedBox(height: 12),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _queens,
                  validator: _validateCount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '蚁后数量'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _workers,
                  validator: _validateCount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '初始工蚁数量',
                    helperText: '初始工蚁为 0 表示从新后开始养；群规模随数量记录更新',
                    helperMaxLines: 3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('显示特化'),
            value: _showSpecialized,
            onChanged: (value) =>
                setState(() => _showSpecialized = value ?? false),
          ),
          if (_showSpecialized) ...[
            TextFormField(
              controller: _specialized,
              validator: (value) => value == null || value.trim().isEmpty
                  ? '请输入特化数量'
                  : _validateCount(value),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '特化数量'),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _eggs,
                  validator: _validateCount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '卵数量（可选）'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _cocoons,
                  validator: _validateCount,
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
          _PurchasePriceField(controller: _purchasePrice),
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
            label: Text(
              _cover != null
                  ? '已选择封面照片'
                  : widget.colony?.coverPhotoPath != null
                  ? '更换封面照片'
                  : '添加封面照片（可选）',
            ),
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

class _PurchasePriceField extends StatelessWidget {
  const _PurchasePriceField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: const InputDecoration(
      labelText: '购入价（可选）',
      prefixText: '¥ ',
      suffixText: '元',
    ),
    validator: (value) => value == null || value.trim().isEmpty
        ? null
        : parsePurchasePrice(value) == null
        ? '请输入有效的非负金额，最多两位小数'
        : null,
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

  void _reload() {
    _detail = _load();
  }

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
        appBar: AppBar(
          title: Text(colony.name),
          actions: [
            IconButton(
              tooltip: '编辑蚁群',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ColonyFormPage(colony: colony),
                  ),
                );
                if (saved == true && mounted) setState(_reload);
              },
            ),
          ],
        ),
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
            _ColonyScaleSummary(
              colony: colony,
              workers: colony.currentWorkerCount(detail.records),
            ),
            const SizedBox(height: 12),
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

class _ColonyScaleSummary extends StatelessWidget {
  const _ColonyScaleSummary({required this.colony, required this.workers});
  final Colony colony;
  final int? workers;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('群规模', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _ColonyTags(colony: colony, workers: workers),
          if (workers == null) const Text('待填写工蚁数量'),
        ],
      ),
    ),
  );
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
              if (colony.showSpecialized && colony.specializedCount != null)
                Chip(label: Text('${colony.specializedCount} 只特化')),
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
              if (colony.purchasePriceCents != null)
                Chip(label: Text('购入价 ¥${colony.purchasePriceText}')),
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

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('发现养蚁的更多乐趣', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text('活动与实用工具将在这里陆续开放。', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 24),
      for (final entry in const [
        (
          icon: Icons.emoji_events_outlined,
          title: '蚁友比赛',
          subtitle: '分享养殖成果，参与主题挑战',
        ),
        (
          icon: Icons.card_giftcard_outlined,
          title: '抽奖活动',
          subtitle: '发现活动，收获养蚁小惊喜',
        ),
        (icon: Icons.handyman_outlined, title: '养殖工具', subtitle: '让日常养护更方便'),
      ])
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Icon(
              entry.icon,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(entry.title),
            subtitle: Text(entry.subtitle),
            trailing: Text(
              '敬请期待',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
    ],
  );
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late Future<List<InventoryItem>> _items;
  var _purchasing = false;
  final _cart = <String>{};
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = AppDatabase.instance.listInventory();
  }

  Future<void> _checkout() async {
    final items = (await _items)
        .where((item) => !item.purchased && _cart.contains(item.id))
        .toList();
    if (!mounted || items.isEmpty || _purchasing) return;
    final details =
        await showDialog<
          Map<String, ({int? quantity, int? purchasePriceCents})>
        >(
          context: context,
          builder: (context) => _InventoryCartDialog(
            items: items,
            onRemove: (id) => setState(() => _cart.remove(id)),
          ),
        );
    if (details == null || details.isEmpty || !mounted) return;
    setState(() => _purchasing = true);
    try {
      await AppDatabase.instance.purchaseInventoryItems(
        details.keys,
        details: details,
      );
      if (mounted) {
        setState(() {
          _cart.removeAll(details.keys);
          _reload();
        });
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _addItem() async {
    var itemName = '';
    var isGroup = false;
    var childNames = '';
    String? validationError;
    var shelfLifeMonths = '3';
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('聚合物品'),
                  subtitle: const Text('一级名称下包含多个可单独购买的子物品'),
                  value: isGroup,
                  onChanged: (value) => setDialogState(() {
                    isGroup = value;
                    validationError = null;
                  }),
                ),
                TextField(
                  onChanged: (value) => itemName = value,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: isGroup ? '一级物品名称' : '物品名称',
                  ),
                ),
                if (isGroup) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: childNames,
                    onChanged: (value) => childNames = value,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '子物品（每行一个）',
                      hintText: '干巢\n湿巢\n中活动区',
                    ),
                  ),
                  const Text('有效期设置应用于各子物品；同名一级物品可继续追加子物品。'),
                ],
                if (validationError != null)
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
                  TextFormField(
                    initialValue: shelfLifeMonths,
                    onChanged: (value) => shelfLifeMonths = value,
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
                final name = itemName.trim();
                final children = isGroup
                    ? childNames
                          .split('\n')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toList()
                    : <String>[];
                if (name.isEmpty ||
                    (isGroup && children.isEmpty) ||
                    children.toSet().length != children.length) {
                  setDialogState(
                    () => validationError = name.isEmpty
                        ? '请填写物品名称'
                        : children.isEmpty
                        ? '请至少填写一个子物品'
                        : '子物品名称不能重复',
                  );
                  return;
                }
                if (name.isEmpty ||
                    (expiryType == InventoryExpiryType.fixedDate &&
                        expiresAt == null)) {
                  return;
                }
                Navigator.pop(
                  context,
                  _NewInventoryItem(
                    name: name,
                    children: children,
                    expiryType: expiryType,
                    shelfLifeMonths: expiryType == InventoryExpiryType.shelfLife
                        ? int.tryParse(shelfLifeMonths) ?? 3
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
    if (item == null) return;
    try {
      InventoryItem createItem(String name) => InventoryItem(
        id: const Uuid().v4(),
        name: name,
        groupName: item.children.isEmpty ? null : item.name,
        purchased: false,
        createdAt: DateTime.now(),
        expiryType: item.expiryType,
        shelfLifeMonths: item.shelfLifeMonths,
        expiresAt: item.expiresAt,
      );
      if (item.children.isEmpty) {
        await AppDatabase.instance.saveInventoryItem(createItem(item.name));
      } else {
        await AppDatabase.instance.saveInventoryGroup(
          item.children.map(createItem).toList(),
        );
      }
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
    bottomNavigationBar: _cart.isEmpty
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('已选 ${_cart.length} 件物品')),
                  FilledButton(
                    onPressed: _purchasing ? null : _checkout,
                    child: Text(_purchasing ? '正在购买…' : '查看购物车'),
                  ),
                ],
              ),
            ),
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
                  Tab(text: '推荐 (${_groupItems(items).length})'),
                  Tab(text: '已购 (${_groupItems(purchased).length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _itemList(needed, '暂时没有推荐的物品。', purchasedItems: purchased),
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

  Map<String, List<InventoryItem>> _groupItems(List<InventoryItem> items) {
    final groups = <String, List<InventoryItem>>{};
    for (final item in items) {
      final name = item.groupLabel == null
          ? 'item:${item.id}'
          : 'group:${item.groupLabel}';
      groups.putIfAbsent(name, () => []).add(item);
    }
    return groups;
  }

  Widget _itemList(
    List<InventoryItem> items,
    String emptyMessage, {
    List<InventoryItem> purchasedItems = const [],
  }) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
    children: [
      if (items.isEmpty && purchasedItems.isEmpty) Text(emptyMessage),
      for (final section in [items, purchasedItems])
        for (final group in _groupItems(section).entries)
          if (group.value.first.groupLabel != null)
            Card(
              child: ExpansionTile(
                key: PageStorageKey(
                  '$emptyMessage-${group.value.first.purchased}-${group.key}',
                ),
                leading: SizedBox(
                  width: group.value.first.purchased ? 24 : 48,
                  child: const Icon(Icons.layers_outlined),
                ),
                title: Text(
                  group.value.first.purchased
                      ? '${group.value.first.groupLabel} · 已购入'
                      : group.value.first.groupLabel!,
                ),
                subtitle: Text(
                  group.value.map((item) => item.childLabel).join(' · '),
                ),
                children: group.value.map(_itemTile).toList(),
              ),
            )
          else
            _itemTile(group.value.single),
    ],
  );

  Future<void> _editItem(InventoryItem item) async {
    final result =
        await showDialog<
          ({bool purchased, int? quantity, int? purchasePriceCents})
        >(
          context: context,
          builder: (context) => _InventoryPurchaseDialog(item: item),
        );
    if (result == null || !mounted) return;
    setState(() => _purchasing = true);
    try {
      await AppDatabase.instance.setInventoryPurchased(
        item,
        result.purchased,
        quantity: result.quantity,
        purchasePriceCents: result.purchasePriceCents,
      );
      if (mounted) {
        setState(() {
          _cart.remove(item.id);
          _reload();
        });
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Widget _itemTile(InventoryItem item) {
    return Card(
      child: ListTile(
        leading: item.purchased
            ? const Icon(Icons.check_circle)
            : IconButton(
                tooltip: _cart.contains(item.id) ? '移出购物车' : '加入购物车',
                icon: Icon(
                  _cart.contains(item.id)
                      ? Icons.shopping_cart
                      : Icons.add_shopping_cart_outlined,
                ),
                color: _cart.contains(item.id)
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: _purchasing
                    ? null
                    : () => setState(() {
                        if (!_cart.add(item.id)) _cart.remove(item.id);
                      }),
              ),
        title: Text(item.name),
        subtitle: Text(
          item.purchased
              ? '已购入'
              : _cart.contains(item.id)
              ? '已加入购物车'
              : '点击购买',
        ),
        trailing: Icon(
          item.purchased ? Icons.edit_outlined : Icons.chevron_right,
        ),
        onTap: _purchasing ? null : () => _editItem(item),
      ),
    );
  }
}

class _InventoryPurchaseDialog extends StatefulWidget {
  const _InventoryPurchaseDialog({required this.item});
  final InventoryItem item;

  @override
  State<_InventoryPurchaseDialog> createState() =>
      _InventoryPurchaseDialogState();
}

class _InventoryPurchaseDialogState extends State<_InventoryPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _quantity;
  late String _price;

  @override
  void initState() {
    super.initState();
    _quantity = widget.item.quantity?.toString() ?? '';
    _price = widget.item.purchasePriceText ?? '';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item.fullName),
    content: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: _InventoryPurchaseFields(
          quantity: _quantity,
          price: _price,
          onQuantityChanged: (value) => _quantity = value,
          onPriceChanged: (value) => _price = value,
        ),
      ),
    ),
    actions: [
      if (widget.item.purchased)
        TextButton(
          onPressed: () => Navigator.pop(context, (
            purchased: false,
            quantity: null,
            purchasePriceCents: null,
          )),
          child: const Text('撤销购入'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, (
            purchased: true,
            quantity: int.tryParse(_quantity.trim()),
            purchasePriceCents: parsePurchasePrice(_price),
          ));
        },
        child: Text(widget.item.purchased ? '保存' : '购买'),
      ),
    ],
  );
}

class _InventoryPurchaseFields extends StatelessWidget {
  const _InventoryPurchaseFields({
    required this.quantity,
    required this.price,
    required this.onQuantityChanged,
    required this.onPriceChanged,
  });

  final String quantity;
  final String price;
  final ValueChanged<String> onQuantityChanged;
  final ValueChanged<String> onPriceChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextFormField(
        initialValue: quantity,
        onChanged: onQuantityChanged,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '数量（选填）'),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return null;
          final quantity = int.tryParse(text);
          return quantity == null || quantity < 0 ? '请输入非负整数' : null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: price,
        onChanged: onPriceChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: '购入价（选填）',
          prefixText: '¥ ',
          helperText: '本次购买总价（元）',
        ),
        validator: (value) =>
            (value?.trim().isEmpty ?? true) ||
                parsePurchasePrice(value!) != null
            ? null
            : '请输入非负金额，最多两位小数',
      ),
    ],
  );
}

class _InventoryCartDialog extends StatefulWidget {
  const _InventoryCartDialog({required this.items, required this.onRemove});
  final List<InventoryItem> items;
  final ValueChanged<String> onRemove;

  @override
  State<_InventoryCartDialog> createState() => _InventoryCartDialogState();
}

class _InventoryCartDialogState extends State<_InventoryCartDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<InventoryItem> _items = List.of(widget.items);
  final _quantities = <String, String>{};
  final _prices = <String, String>{};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('购物车 (${_items.length})'),
    content: SizedBox(
      width: double.maxFinite,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_items.isEmpty) const Text('购物车是空的，去添加心仪的物品吧。'),
              for (final item in _items)
                Padding(
                  key: ValueKey(item.id),
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.fullName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: '移除${item.name}',
                            onPressed: () {
                              widget.onRemove(item.id);
                              setState(() => _items.remove(item));
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      _InventoryPurchaseFields(
                        quantity: _quantities[item.id] ?? '',
                        price: _prices[item.id] ?? '',
                        onQuantityChanged: (value) =>
                            _quantities[item.id] = value,
                        onPriceChanged: (value) => _prices[item.id] = value,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _items.isEmpty
            ? null
            : () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(context, {
                  for (final item in _items)
                    item.id: (
                      quantity: int.tryParse(
                        (_quantities[item.id] ?? '').trim(),
                      ),
                      purchasePriceCents: parsePurchasePrice(
                        _prices[item.id] ?? '',
                      ),
                    ),
                });
              },
        child: const Text('购买'),
      ),
    ],
  );
}

class _NewInventoryItem {
  const _NewInventoryItem({
    required this.name,
    required this.expiryType,
    this.shelfLifeMonths,
    this.expiresAt,
    this.children = const [],
  });

  final String name;
  final InventoryExpiryType expiryType;
  final int? shelfLifeMonths;
  final DateTime? expiresAt;
  final List<String> children;
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
                    time: _date(record.occurredAt),
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

  void _reload() {
    _records = AppDatabase.instance.listFeederRecords(widget.feeder);
  }

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
  final _formKey = GlobalKey<FormState>();
  final _purchasePrice = TextEditingController();
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
      _purchasePrice,
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
    if (!_formKey.currentState!.validate()) return;
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
          purchasePriceCents: parsePurchasePrice(_purchasePrice.text),
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
    body: Form(
      key: _formKey,
      child: ListView(
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
          _PurchasePriceField(controller: _purchasePrice),
          const SizedBox(height: 16),
          Text('数量（不清楚可留空）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
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
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('环境（选填）'),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [
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
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存记录'),
          ),
        ],
      ),
    ),
  );
}

class _FeederRecordCard extends StatelessWidget {
  const _FeederRecordCard({required this.record});
  final FeederRecord record;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[
      if (record.purchasePriceCents != null) '购入价 ¥${record.purchasePriceText}',
      if (record.juvenileCount != null) '幼体/若虫 ${record.juvenileCount}',
      if (record.adultCount != null) '成体 ${record.adultCount}',
      if (record.mortalityCount != null) '死亡 ${record.mortalityCount}',
      if (record.temperature != null) '${record.temperature}°C',
      if (record.humidity != null) '${record.humidity}%',
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
  bool _savingEdition = false;

  Future<void> _setEdition(AppEdition edition) async {
    if (_savingEdition || themeController.edition == edition) return;
    setState(() => _savingEdition = true);
    try {
      await themeController.setEdition(edition);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _savingEdition = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => _buildSettings(context),
  );

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildSettings(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _section(context, '使用版本', [
            ListTile(
              leading: Icon(
                themeController.edition == AppEdition.offline
                    ? Icons.phonelink_lock_outlined
                    : Icons.cloud_download_outlined,
              ),
              title: const Text('资料模式'),
              subtitle: Text(
                themeController.edition == AppEdition.offline
                    ? '使用 App 内置资料，断网也能查看。'
                    : '已选择在线版，在线资料更新暂不可用。',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final edition in AppEdition.values)
                    ChoiceChip(
                      label: Text(edition.label),
                      selected: themeController.edition == edition,
                      onSelected: _savingEdition
                          ? null
                          : (_) => _setEdition(edition),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '两种模式下，蚁群、记录和照片都只保存在本设备。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ]),
          if (themeController.edition == AppEdition.online)
            _section(context, '个人中心', [
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('个人中心与签到'),
                subtitle: const Text('登录账号，查看每日签到记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PersonalCenterPage(controller: accountController),
                  ),
                ),
              ),
            ]),
          _section(context, '外观与偏好', [
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
            const Divider(height: 1),
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
          ]),
          _section(context, '养护提醒', [
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
                      if (context.mounted) {
                        _showInfo(context, '未获得通知权限，提醒没有开启。');
                      }
                      return;
                    }
                    await LocalNotificationService.instance
                        .scheduleDailyCareReminder(
                          themeController.careReminderMinuteOfDay,
                        );
                  } else {
                    await LocalNotificationService.instance
                        .cancelDailyCareReminder();
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
              trailing: const Icon(Icons.chevron_right),
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
          ]),
          _section(context, '数据与备份', [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('导出备份'),
              trailing: const Icon(Icons.chevron_right),
              subtitle: const Text('生成包含记录和照片的 .zip 文件'),
              onTap: () async {
                try {
                  final exported = await BackupService(
                    AppDatabase.instance,
                    LocalMediaStore.instance,
                  ).exportBackup();
                  if (exported && context.mounted) {
                    _showInfo(context, '已完成备份导出。');
                  }
                } catch (error) {
                  if (context.mounted) _showError(context, error);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('恢复备份'),
              trailing: const Icon(Icons.chevron_right),
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
              trailing: const Icon(Icons.chevron_right),
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
          ]),
        ],
      ),
    ),
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
