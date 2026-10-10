import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'app_preferences.dart';
import 'diary_preferences.dart';
import 'diary_settings_page.dart';
import 'colony_growth_page.dart';
import 'care_tasks_section.dart';
import 'memorial_page.dart';
import 'widgets/skull_icon.dart';
import 'share_cards_page.dart';
import 'share_content_page.dart';
import 'community_groups_page.dart';
import 'date_display.dart';
import 'husbandry_duration.dart';
import 'account_controller.dart';
import 'lottery_page.dart';
import 'species_encyclopedia_page.dart';
import 'population_analysis_page.dart';
import 'population_forecast_controls.dart';
import 'domain/population_forecast.dart';
import 'online/runtime.dart';
import 'online/inventory_push_page.dart';
import 'online/app_update.dart';
import 'online/online_widgets.dart';
import 'online/update_release_notes.dart';
import 'onboarding.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/local_media_store.dart';
import 'data/local_notification_service.dart';
import 'domain/models.dart';
import 'domain/care_task.dart';
import 'domain/mortality_analysis.dart';
import 'domain/colony_growth.dart';
import 'domain/population_analysis.dart';
import 'domain/purchase_price.dart';
import 'domain/beginner_care_notice.dart';
import 'domain/species_profile.dart';
import 'domain/imported_species_catalog.dart';
import 'widgets/diary_record_actions.dart';
import 'widgets/justified_label.dart';

const _builtInSpeciesOptions = <String, List<String>>{
  '收获蚁': [
    '工匠收获蚁',
    '野蛮收获蚁（原生收获蚁）',
    '红胸收获蚁',
    '大头收获蚁',
    '强壮收获蚁',
    '针毛收获蚁',
    '无颚齿收获蚁',
    '勤劳收获蚁',
    '白刺收获蚁',
    '东方收获蚁',
    '巨首收获蚁（肯尼亚收获蚁）',
    '希伯来收获蚁',
  ],
  '弓背蚁': [
    '费氏弓背蚁',
    '大头弓背蚁',
    '尼科巴弓背蚁',
    '巴瑞弓背蚁',
    '拟光腹弓背蚁',
    '全黄土耳其弓背蚁',
    '日本弓背蚁',
    '广布弓背蚁',
    '窄颈弓背蚁（窄径）',
    '红头弓背蚁',
    '沃斯曼弓背蚁',
    '神圣弓背蚁',
    '统领弓背蚁（统领蚁）',
    '白纵斑弓背蚁（白纵斑蚁）',
  ],
  '猛蚁': [
    '横纹猛蚁',
    '横纹齿猛蚁',
    '聚纹双刺猛蚁',
    '大齿猛蚁',
    '扁头猛蚁',
    '红足穴猛蚁',
    '山大齿猛蚁',
    '双色曲颊猛蚁',
    '中华细猛蚁',
    '条纹细猛蚁',
    '金属皱突蚁（金属蚁）',
  ],
  '蜜罐蚁': ['墨西哥蜜罐蚁', '大平眼蜜罐蚁'],
  '孔蚁': ['巨人孔蚁'],
  '子弹蚁': ['子弹蚁'],
  '铺道蚁': ['双隆骨铺道蚁', '草地铺道蚁'],
  '多刺蚁': ['拟弓多刺蚁', '拟黑多刺蚁', '双齿多刺蚁', '梅氏多刺蚁'],
  '大头蚁': ['中华大头蚁', '皮氏大头蚁', '伊大头蚁', '宽结大头蚁', '史氏大头蚁'],
  '毛蚁': ['玉米毛蚁', '黑毛蚁', '黄墩蚁', '亮毛蚁'],
  '细长蚁': ['红黑细长蚁', '黑细长蚁', '宾氏细长蚁'],
  '巨首蚁': ['全异巨首蚁', '近缘巨首蚁'],
  '虹臭蚁': ['扁平虹臭蚁', '紫彩虹臭蚁'],
  '盾胸切叶蚁': ['二色盾胸切叶蚁'],
  '原蚁': ['蒙古原蚁'],
  '举腹蚁': ['大阪举腹蚁', '黑褐举腹蚁'],
  '林蚁': ['日本黑褐蚁', '丝光蚁', '红须蚁'],
  '织叶蚁': ['黄猄蚁'],
  '须蚁': ['红胡须蚁（巴巴特斯）'],
  '箭蚁': ['银丝箭蚁（银丝蚁）'],
};

// Retain recognition of saved names and common input variants without duplicate
// picker entries. Existing colony records are not rewritten.
const _builtInSpeciesAliases = <String, String>{
  '全黄弓背蚁': '全黄土耳其弓背蚁',
  '无恶齿收获蚁': '无颚齿收获蚁',
  '铺道蚁': '草地铺道蚁',
  '全蚁巨首蚁': '全异巨首蚁',
  '拟广腹弓背蚁': '拟光腹弓背蚁',
  '费氏弓背蚁（黑金弓背蚁）': '费氏弓背蚁',
  '费事弓背蚁': '费氏弓背蚁',
  '黑金弓背蚁': '费氏弓背蚁',
  '野蛮收获蚁': '野蛮收获蚁（原生收获蚁）',
  '原生收获蚁': '野蛮收获蚁（原生收获蚁）',
  '巨首收获蚁': '巨首收获蚁（肯尼亚收获蚁）',
  '肯尼亚收获蚁': '巨首收获蚁（肯尼亚收获蚁）',
  '希伯来': '希伯来收获蚁',
  '统领弓背蚁': '统领弓背蚁（统领蚁）',
  '统领蚁': '统领弓背蚁（统领蚁）',
  '白纵斑弓背蚁': '白纵斑弓背蚁（白纵斑蚁）',
  '白纵斑蚁': '白纵斑弓背蚁（白纵斑蚁）',
  '金属皱突蚁': '金属皱突蚁（金属蚁）',
  '金属皱猛蚁': '金属皱突蚁（金属蚁）',
  '金属蚁': '金属皱突蚁（金属蚁）',
  '红胡须蚁': '红胡须蚁（巴巴特斯）',
  '巴巴特斯': '红胡须蚁（巴巴特斯）',
  '巴巴斯特': '红胡须蚁（巴巴特斯）',
  '银丝箭蚁': '银丝箭蚁（银丝蚁）',
  '银丝蚁': '银丝箭蚁（银丝蚁）',
  '紫菜蚁': '紫彩虹臭蚁',
  '紫菜虹臭蚁': '紫彩虹臭蚁',
};

final _speciesOptions = <String, List<String>>{
  for (final category in {
    ..._builtInSpeciesOptions.keys,
    ...importedSpeciesOptions.keys,
  })
    category: [
      ...?_builtInSpeciesOptions[category],
      ...?importedSpeciesOptions[category],
    ],
};

final _speciesAliases = <String, String>{
  ...importedSpeciesAliases,
  ..._builtInSpeciesAliases,
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
  '酱料杯',
  '自制巢',
  '饭盒',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalMediaStore.instance.initialize();
    await AppDatabase.instance.open();
    await themeController.load();
    AppEdition? appliedEdition;
    void updateOnlineMode() {
      final edition = themeController.edition;
      if (appliedEdition == edition) return;
      appliedEdition = edition;
      unawaited(setOnlineMode(edition == AppEdition.online));
    }

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
final accountController = AccountController(preferences: themeController);

class AntKeepApp extends StatefulWidget {
  const AntKeepApp({super.key});

  @override
  State<AntKeepApp> createState() => _AntKeepAppState();
}

class _AntKeepAppState extends State<AntKeepApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  int? _shownRequiredPolicy;
  bool _updateDialogOpen = false;
  bool _announcementDialogOpen = false;

  @override
  void initState() {
    super.initState();
    onlineController.addListener(_showAnnouncementIfNeeded);
  }

  @override
  void dispose() {
    onlineController.removeListener(_showAnnouncementIfNeeded);
    super.dispose();
  }

  void _showAnnouncementIfNeeded() {
    final announcement = onlineController.pendingAnnouncement;
    if (!mounted ||
        !themeController.onboardingCompleted ||
        _updateDialogOpen ||
        _announcementDialogOpen ||
        announcement == null) {
      return;
    }
    _announcementDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dialogContext = _navigatorKey.currentContext;
      if (!mounted ||
          dialogContext == null ||
          onlineController.pendingAnnouncement?.id != announcement.id) {
        _announcementDialogOpen = false;
        return;
      }
      await showDialog<void>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(announcement.title),
          content: Text(announcement.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      try {
        await onlineController.acknowledgeAnnouncement(announcement.id);
      } catch (_) {
        // A storage failure allows the announcement to appear next launch.
      }
      _announcementDialogOpen = false;
      _showAnnouncementIfNeeded();
    });
  }

  void _showUpdatePromptIfNeeded() {
    final policy = appUpdateController.policy;
    if (policy == null) {
      return;
    }
    final required =
        appUpdateController.availability == AppUpdateAvailability.required;
    final optional =
        appUpdateController.availability == AppUpdateAvailability.optional &&
        appUpdateController.takeOptionalPrompt();
    if ((!required && !optional) ||
        (required && _shownRequiredPolicy == policy.version)) {
      return;
    }
    if (required) {
      _shownRequiredPolicy = policy.version;
    }
    _updateDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dialogContext = _navigatorKey.currentContext;
      if (!mounted || dialogContext == null) {
        _updateDialogOpen = false;
        return;
      }
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: !required,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(required ? '在线版需要更新' : '发现新版本 ${policy.latestVersion}'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (required) ...[
                Text(
                  '请更新至 ${policy.minimumVersion} 后继续使用在线版。蚁群、记录、照片和备份仍可在离线版正常使用。',
                ),
                const SizedBox(height: 16),
              ],
              if (policy.apk case final apk?) ...[
                Text('安装包', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(apk.filename),
                Text('文件大小：${apk.formattedSize}'),
                const SizedBox(height: 16),
              ],
              Text('更新说明', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              UpdateReleaseNotes(notes: policy.releaseNotes),
            ],
          ),
          actions: [
            if (required)
              TextButton(
                onPressed: () async {
                  await themeController.setEdition(AppEdition.offline);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('使用离线版'),
              )
            else
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('稍后更新'),
              ),
            FilledButton(
              onPressed: () async {
                await appUpdateController.openDownload();
              },
              child: const Text('立即更新'),
            ),
          ],
        ),
      );
      _updateDialogOpen = false;
      _showAnnouncementIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([themeController, appUpdateController]),
    builder: (context, _) {
      _showUpdatePromptIfNeeded();
      _showAnnouncementIfNeeded();
      return MaterialApp(
        navigatorKey: _navigatorKey,
        title: '蚁记',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        theme: antKeepTheme(
          themeController.themeColor,
          fontColor: themeController.fontColor,
        ),
        darkTheme: antKeepTheme(
          themeController.themeColor,
          dark: true,
          fontColor: themeController.fontColor,
        ),
        themeMode: themeController.themeMode,
        home: themeController.onboardingCompleted
            ? const HomePage()
            : OnboardingPage(preferences: themeController),
      );
    },
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
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

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  var _index = 0;
  late final TabController _colonyTabs;
  late BeginnerCareNotice _beginnerCareNotice;
  late List<BeginnerCareNotice> _careNotices;

  void _updateCareNotices() {
    final notices = onlineController.content.beginnerCareNotices;
    if (identical(notices, _careNotices)) return;
    setState(() {
      _careNotices = notices;
      _beginnerCareNotice = randomBeginnerCareNotice(
        notices: notices,
        previous: _beginnerCareNotice,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _colonyTabs = TabController(length: 2, vsync: this);
    _careNotices = onlineController.content.beginnerCareNotices;
    _beginnerCareNotice = randomBeginnerCareNotice(notices: _careNotices);
    onlineController.addListener(_updateCareNotices);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _colonyTabs.dispose();
    onlineController.removeListener(_updateCareNotices);
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
    const titles = ['我的蚁群', '物品', 'DLC 养殖', '发现', '设置'];
    final visiblePages = themeController.simpleMode ? [0, 4] : [0, 1, 2, 3, 4];
    final pageIndex = visiblePages.contains(_index) ? _index : 0;
    final pages = [
      IndexedStack(
        index: _colonyTabs.index,
        children: [
          const ColoniesPage(),
          MemorialPage(
            onOpenColony: (context, id) async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ColonyDetailPage(colonyId: id),
                ),
              );
            },
          ),
        ],
      ),
      const InventoryPage(),
      const DlcPage(),
      const DiscoverPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: pageIndex == 0
            ? TabBar(
                controller: _colonyTabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                // Keep the colony switcher visually separate from page content;
                // the selected-tab indicator alone was too easy to miss.
                dividerColor: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: .55),
                dividerHeight: 1,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                labelStyle: Theme.of(context).textTheme.titleMedium,
                onTap: (_) => setState(() {}),
                tabs: [
                  for (final tab in ColonyTab.values)
                    Tab(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () => _renameColonyTab(context, tab),
                        child: Text(themeController.colonyTabName(tab)),
                      ),
                    ),
                ],
              )
            : Text(titles[pageIndex]),
        actions: [
          if (!themeController.simpleMode)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PopulationAnalysisPage(),
                ),
              ),
              icon: const Icon(Icons.show_chart),
              label: const Text('分析'),
            ),
          IconButton(
            tooltip: '分享',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ShareContentPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (pageIndex == 0 &&
              _colonyTabs.index == 0 &&
              themeController.beginner)
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
          Expanded(child: pages[pageIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: visiblePages.indexOf(pageIndex),
        onDestinationSelected: (index) => setState(() {
          final value = visiblePages[index];
          if (value == 0 && _index != 0) {
            _beginnerCareNotice = randomBeginnerCareNotice(
              previous: _beginnerCareNotice,
              notices: _careNotices,
            );
          }
          _index = value;
        }),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.hive_outlined),
            selectedIcon: Icon(Icons.hive),
            label: '蚁群',
          ),
          if (!themeController.simpleMode) ...[
            const NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: '物品',
            ),
            const NavigationDestination(
              icon: Icon(Icons.pets_outlined),
              selectedIcon: Icon(Icons.pets),
              label: 'DLC',
            ),
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: '发现',
            ),
          ],
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

Future<bool> _editColonyAcquiredOn(BuildContext context, Colony colony) async {
  if (colony.acquiredOn != null) return false;
  try {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = DateTime(2000);
    final initialDate = colony.acquiredOn ?? today;
    final date = await showDatePicker(
      context: context,
      helpText: '填写入手日期',
      confirmText: '保存',
      cancelText: '取消',
      initialEntryMode: DatePickerEntryMode.input,
      firstDate: firstDate,
      lastDate: today,
      initialDate: initialDate.isBefore(firstDate)
          ? firstDate
          : initialDate.isAfter(today)
          ? today
          : initialDate,
    );
    if (date == null || !context.mounted) return false;
    await AppDatabase.instance.saveColony(
      Colony.fromMap({
        ...colony.toMap(),
        'acquired_on': date.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }),
    );
    return true;
  } catch (error) {
    if (context.mounted) _showError(context, error);
    return false;
  }
}

class ColoniesPage extends StatefulWidget {
  const ColoniesPage({super.key});
  @override
  State<ColoniesPage> createState() => _ColoniesPageState();
}

typedef _ColonyListEntry = ({
  Colony colony,
  GrowthPopulation population,
  int? workers,
  List<CareTask> dueTasks,
});

class _ColoniesPageState extends State<ColoniesPage> {
  late Future<List<_ColonyListEntry>> _colonies;
  bool _editingAcquiredOn = false;
  bool _savingOrder = false;
  bool _dragging = false;

  StreamSubscription<void>? _memorialChanges;
  Timer? _growthTimer;
  AppLifecycleListener? _growthLifecycle;

  void _refreshGrowth() {
    if (mounted && !_savingOrder && !_dragging) setState(_reload);
  }

  @override
  void dispose() {
    _memorialChanges?.cancel();
    _growthTimer?.cancel();
    _growthLifecycle?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _memorialChanges = AppDatabase.instance.memorialChanges.listen(
      (_) => _refreshGrowth(),
    );
    _growthTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshGrowth(),
    );
    _growthLifecycle = AppLifecycleListener(onResume: _refreshGrowth);
  }

  void _reload() {
    _colonies = _loadColonies();
  }

  Future<List<_ColonyListEntry>> _loadColonies() async {
    final loaded = await AppDatabase.instance.listColonies();
    final tasks = await AppDatabase.instance.listCareTasks();
    final remaining = {for (final colony in loaded) colony.id: colony};
    final colonies = <Colony>[
      for (final id in themeController.colonyOrder)
        if (remaining.containsKey(id)) remaining.remove(id)!,
      ...remaining.values,
    ];
    return Future.wait(
      colonies.map((colony) async {
        final records = await AppDatabase.instance.listRecords(colony.id);
        final population = colony.currentPopulation(records);
        return (
          colony: colony,
          population: population,
          workers: population.workers,
          dueTasks: tasks
              .where(
                (task) =>
                    task.colonyId == colony.id && task.isDue(DateTime.now()),
              )
              .toList(),
        );
      }),
    );
  }

  Future<void> _reorderColonies(
    List<_ColonyListEntry> colonies,
    int oldIndex,
    int newIndex,
  ) async {
    if (_savingOrder) return;
    if (newIndex == oldIndex) return;
    final previous = List<_ColonyListEntry>.of(colonies);
    setState(() {
      _savingOrder = true;
      colonies.insert(newIndex, colonies.removeAt(oldIndex));
    });
    try {
      await themeController.setColonyOrder(
        colonies.map((entry) => entry.colony.id),
      );
    } catch (_) {
      colonies
        ..clear()
        ..addAll(previous);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存顺序失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Future<void> _editAcquiredOn(Colony colony) async {
    if (_editingAcquiredOn) return;
    _editingAcquiredOn = true;
    try {
      final saved = await _editColonyAcquiredOn(context, colony);
      if (saved && mounted) setState(_reload);
    } finally {
      _editingAcquiredOn = false;
    }
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
      label: const Text('蚁群'),
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
        return AbsorbPointer(
          absorbing: _savingOrder,
          child: RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _colonies;
            },
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              buildDefaultDragHandles: false,
              header: colonies.length > 1
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '长按蚁群卡片可上下拖动排序',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : null,
              itemCount: colonies.length,
              onReorderStart: (_) => _dragging = true,
              onReorderEnd: (_) => _dragging = false,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorderColonies(colonies, oldIndex, newIndex),
              itemBuilder: (context, index) =>
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(colonies[index].colony.id),
                    index: index,
                    enabled: colonies.length > 1 && !_savingOrder,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: index == colonies.length - 1 ? 0 : 10,
                      ),
                      child: _ColonyCard(
                        colony: colonies[index].colony,
                        population: colonies[index].population,
                        workers: colonies[index].workers,
                        dueTasks: colonies[index].dueTasks,
                        onDurationTap: () =>
                            _editAcquiredOn(colonies[index].colony),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ColonyDetailPage(
                                colonyId: colonies[index].colony.id,
                              ),
                            ),
                          );
                          if (mounted) setState(_reload);
                        },
                      ),
                    ),
                  ),
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
    required this.population,
    required this.workers,
    required this.dueTasks,
    required this.onTap,
    required this.onDurationTap,
  });
  final Colony colony;
  final GrowthPopulation population;
  final int? workers;
  final List<CareTask> dueTasks;
  final VoidCallback onTap;
  final VoidCallback onDurationTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numberStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );
    TextSpan quantity(int count, String label) => TextSpan(
      children: [
        TextSpan(text: '$count', style: numberStyle),
        TextSpan(text: ' $label'),
      ],
    );
    final details = <InlineSpan>[
      if (colony.queenCount != null) quantity(colony.queenCount!, '蚁后'),
      if (colony.showSpecialized && colony.specializedCount != null)
        quantity(colony.specializedCount!, '特化'),
      if (workers != null) quantity(workers!, '工蚁'),
      if (population.eggs != null) quantity(population.eggs!, '卵'),
      if (population.larvae != null) quantity(population.larvae!, '幼虫'),
      if (population.cocoons != null) quantity(population.cocoons!, '茧'),
    ];
    final description = [
      colony.species,
      colony.nestType,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final hasTags =
        colony.isNewQueenColony ||
        workers != null ||
        colony.nestType?.isNotEmpty == true;
    final dueText = dueTasks.isEmpty
        ? null
        : '今日待办：${dueTasks.map((task) => task.type.label).join('、')}';
    final lowerMetadata = <Widget>[
      if (hasTags) ...[
        const SizedBox(height: 6),
        _ColonyTags(colony: colony, workers: workers),
      ],
      const SizedBox(height: 10),
      if (dueText != null) ...[
        Text(
          dueText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
      ],
    ];
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            colony.coverPhotoPath == null
                ? CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: .12,
                    ),
                    child: Icon(
                      Icons.hive_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : _StoredImage(
                    relativePath: colony.coverPhotoPath!,
                    width: 32,
                    height: 32,
                    borderRadius: 16,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final baseStyle = theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  );
                  var fontSize = 18.0;
                  while (fontSize > 14) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: colony.name,
                        style: baseStyle?.copyWith(fontSize: fontSize),
                      ),
                      maxLines: 1,
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout(maxWidth: constraints.maxWidth);
                    final fits = !painter.didExceedMaxLines;
                    painter.dispose();
                    if (fits) break;
                    fontSize -= 1;
                  }
                  return Text(
                    colony.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: baseStyle?.copyWith(fontSize: fontSize),
                  );
                },
              ),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final durationWidth = (constraints.maxWidth * .43).clamp(
                    120.0,
                    160.0,
                  );
                  final tallDurationWidth = (constraints.maxWidth * .39).clamp(
                    120.0,
                    150.0,
                  );
                  final leftWidth =
                      constraints.maxWidth - tallDurationWidth - 21;
                  double textWidth(String value, TextStyle? style) {
                    final painter = TextPainter(
                      text: TextSpan(text: value, style: style),
                      maxLines: 1,
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout();
                    final width = painter.width;
                    painter.dispose();
                    return width;
                  }

                  final scale = ColonyScale.fromWorkerCount(workers);
                  final tagLabels = <String>[
                    if (colony.isNewQueenColony) '新后群',
                    if (scale != null) scale.label,
                    if (colony.nestType?.isNotEmpty == true) colony.nestType!,
                  ];
                  final tagWidth =
                      tagLabels.fold<double>(
                        0,
                        (width, label) =>
                            width +
                            textWidth(
                              label,
                              theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ) +
                            16,
                      ) +
                      (colony.isNewQueenColony ? 20 : 0) +
                      (tagLabels.isEmpty ? 0 : tagLabels.length - 1) * 8;
                  final canFillSpace =
                      constraints.maxWidth >= 280 &&
                      MediaQuery.textScalerOf(context).scale(12) <= 18 &&
                      colony.acquiredOn != null &&
                      dueText != null &&
                      (hasTags || description.isNotEmpty) &&
                      tagWidth <= leftWidth &&
                      textWidth(
                            dueText,
                            theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ) <=
                          leftWidth;
                  final duration = InkWell(
                    onTap: colony.acquiredOn == null ? onDurationTap : null,
                    borderRadius: BorderRadius.circular(8),
                    child: HusbandryDuration(
                      colony: colony,
                      tall: canFillSpace,
                    ),
                  );
                  if (constraints.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(12) > 18) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        const SizedBox(height: 10),
                        duration,
                        ...lowerMetadata,
                      ],
                    );
                  }
                  if (canFillSpace) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [identity, ...lowerMetadata],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 62,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: .3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(width: tallDurationWidth, child: duration),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            height: 62,
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: .3,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(width: durationWidth, child: duration),
                        ],
                      ),
                      ...lowerMetadata,
                    ],
                  );
                },
              ),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: .3),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 6,
                      children: [
                        for (final detail
                            in details.isEmpty
                                ? [const TextSpan(text: '尚未补充数量')]
                                : details)
                          Text.rich(
                            detail,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: .7,
                    ),
                  ),
                ],
              ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return Row(
      children: [
        if (colony.isNewQueenColony) badge('新后群', scheme.primary, crown: true),
        if (colony.isNewQueenColony &&
            (scale != null || colony.nestType?.isNotEmpty == true))
          const SizedBox(width: 8),
        if (scale != null) badge(scale.label, color),
        if (scale != null && colony.nestType?.isNotEmpty == true)
          const SizedBox(width: 8),
        if (colony.nestType?.isNotEmpty == true)
          Flexible(child: badge(colony.nestType!, scheme.onSurfaceVariant)),
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
  String? _sourceType;
  String? _originalSourceType;
  String _originalSourceDetail = '';
  final _purchasePrice = TextEditingController();
  final _queens = TextEditingController();
  final _specialized = TextEditingController(text: '0');
  var _showSpecialized = false;
  final _workers = TextEditingController();
  final _eggs = TextEditingController();
  final _cocoons = TextEditingController();
  final _larvae = TextEditingController();
  var _developmentPath = GrowthPath.eggToCocoonToWorker;
  final _targetTemperatureLower = TextEditingController();
  final _targetTemperature = TextEditingController();
  final _targetHumidityLower = TextEditingController();
  final _targetHumidity = TextEditingController();
  String? _speciesFamily;
  String? _selectedSpecies;
  String? _selectedNest;
  DateTime? _acquiredOn;
  XFile? _cover;
  Future<Uint8List?>? _coverPreview;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final colony = widget.colony;
    if (colony == null) return;
    _name.text = colony.name;
    _source.text = colony.source ?? '';
    final sourceMatch = RegExp(
      r'^(野采|网购|蚁友赠送)(?:（(.*)）|\((.*)\)|\s+(.+))?$',
      dotAll: true,
    ).firstMatch(_source.text.trim());
    if (sourceMatch != null) {
      _sourceType = sourceMatch.group(1);
      _source.text =
          sourceMatch.group(2) ??
          sourceMatch.group(3) ??
          sourceMatch.group(4) ??
          '';
    }
    _originalSourceType = _sourceType;
    _originalSourceDetail = _source.text;
    if (colony.coverPhotoPath != null) {
      _coverPreview = LocalMediaStore.instance
          .readImage(colony.coverPhotoPath!)
          .then<Uint8List?>((bytes) => bytes, onError: (Object _) => null);
    }
    _purchasePrice.text = colony.purchasePriceText ?? '';
    _queens.text = colony.queenCount?.toString() ?? '';
    _specialized.text = colony.specializedCount?.toString() ?? '0';
    _showSpecialized = colony.showSpecialized;
    _workers.text = colony.initialWorkerCount?.toString() ?? '';
    _eggs.text = colony.initialEggCount?.toString() ?? '';
    _developmentPath = colony.developmentPath;
    _larvae.text = colony.initialLarvaCount?.toString() ?? '';
    _cocoons.text = colony.initialCocoonCount?.toString() ?? '';
    _targetTemperatureLower.text =
        colony.targetTemperatureLower?.toString() ?? '';
    _targetTemperature.text = colony.targetTemperature?.toString() ?? '';
    _targetHumidityLower.text = colony.targetHumidityLower?.toString() ?? '';
    _targetHumidity.text = colony.targetHumidity?.toString() ?? '';
    _selectedSpecies = colony.species;
    for (final entry in _speciesOptions.entries) {
      if (entry.value.contains(
        _speciesAliases[colony.species] ?? colony.species,
      )) {
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
      _larvae,
      _targetTemperatureLower,
      _targetTemperature,
      _targetHumidityLower,
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

  String? _validateRequiredCount(String? value) =>
      value == null || value.trim().isEmpty ? '请填写数量' : _validateCount(value);

  String? _validateAlertLimit(
    String? value,
    TextEditingController counterpart, {
    required bool isLower,
  }) {
    if (value == null || value.trim().isEmpty) return null;
    final number = double.tryParse(value.trim());
    if (number == null) return '请输入有效数值';
    final other = double.tryParse(counterpart.text.trim());
    if (other == null) return null;
    if (isLower && number > other) return '下限不能高于上限';
    if (!isLower && number < other) return '上限不能低于下限';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final colonyId = widget.colony?.id ?? const Uuid().v4();
      await AppDatabase.instance.saveColony(
        Colony(
          id: colonyId,
          name: _name.text.trim(),
          species: _selectedSpecies,
          acquiredOn: _acquiredOn,
          source: _sourceValue,
          purchasePriceCents: parsePurchasePrice(_purchasePrice.text),
          queenCount: int.tryParse(_queens.text),
          specializedCount: int.tryParse(_specialized.text.trim()),
          showSpecialized: _showSpecialized,
          initialWorkerCount: int.tryParse(_workers.text),
          initialEggCount: int.tryParse(_eggs.text),
          initialLarvaCount: int.tryParse(_larvae.text),
          developmentPath: _developmentPath,
          initialCocoonCount: int.tryParse(_cocoons.text),
          nestType: _selectedNest,
          targetTemperatureLower: double.tryParse(_targetTemperatureLower.text),
          targetTemperature: double.tryParse(_targetTemperature.text),
          targetHumidityLower: double.tryParse(_targetHumidityLower.text),
          targetHumidity: double.tryParse(_targetHumidity.text),
          coverPhotoPath: _cover == null
              ? widget.colony?.coverPhotoPath
              : await LocalMediaStore.instance.copyImage(_cover!),
          archived: widget.colony?.archived ?? false,
          createdAt: widget.colony?.createdAt ?? now,
          updatedAt: now,
        ),
      );
      if (widget.colony == null && !themeController.simpleMode && mounted) {
        final colony = await AppDatabase.instance.findColony(colonyId);
        if (colony != null && mounted) {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => ColonyGrowthPage(colony: colony)),
          );
        }
      }
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
      _speciesFamily = null;
      for (final entry in _speciesOptions.entries) {
        if (entry.value.contains(_speciesAliases[species] ?? species)) {
          _speciesFamily = entry.key;
          break;
        }
      }
      _name.text = _speciesNickname(species);
    });
  }

  String _speciesNickname(String species) {
    final displayName = species.contains('（')
        ? species
        : _speciesAliases[species] ?? species;
    final match = RegExp(r'（([^（）]+)）').firstMatch(displayName);
    if (match == null) return displayName;

    final parenthetical = match.group(1) ?? displayName;
    if (!RegExp(r'[A-Za-z]').hasMatch(parenthetical)) return parenthetical;

    return displayName.substring(0, match.start);
  }

  String? get _sourceValue {
    if (_sourceType == _originalSourceType &&
        _source.text == _originalSourceDetail) {
      return widget.colony?.source;
    }
    final detail = _source.text.trim();
    if (_sourceType == null) return _textOrNull(detail);
    return detail.isEmpty ? _sourceType : '$_sourceType（$detail）';
  }

  Future<void> _selectFamily(String family) async {
    if (!mounted) return;
    setState(() {
      _speciesFamily = family;
      _selectedSpecies = null;
    });
    final species =
        await showModalBottomSheet<({String value, bool isSearchResult})>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ChoicePickerSheet(
            title: '细分品种',
            options: _speciesOptions[family] ?? const [],
          ),
        );
    if (species != null && mounted) _selectSpecies(species.value);
  }

  Future<void> _enterCustomSpecies() async {
    final selectedName = _selectedSpecies ?? '';
    // Keep the keeper's saved common name when editing an existing record.
    final currentName = selectedName.contains('（')
        ? selectedName
        : _speciesAliases[selectedName] ?? selectedName;
    final names = RegExp(r'^(.*?)（([^（）]+)）$').firstMatch(currentName);
    var speciesName = names?.group(1) ?? currentName;
    var commonName =
        names?.group(2) ??
        (findSpeciesProfile(selectedName)?.aliases.contains(selectedName) ==
                true
            ? selectedName
            : '');
    final formKey = GlobalKey<FormState>();
    final species = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动填写品种'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: speciesName,
                  onChanged: (value) => speciesName = value,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '学名 / 正式名',
                    hintText: '例如：费氏弓背蚁',
                    helperText: '可填写中文正式名或拉丁学名',
                  ),
                  validator: (_) =>
                      speciesName.trim().isEmpty && commonName.trim().isEmpty
                      ? '请至少填写一个名称'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: commonName,
                  onChanged: (value) => commonName = value,
                  decoration: const InputDecoration(
                    labelText: '通用名（可选）',
                    hintText: '例如：黑金弓背蚁',
                  ),
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
              if (!formKey.currentState!.validate()) return;
              final formal = speciesName.trim();
              final common = commonName.trim();
              final value = formal.isEmpty
                  ? common
                  : common.isEmpty || common == formal
                  ? formal
                  : '$formal（$common）';
              Navigator.pop(context, value);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (species?.isNotEmpty == true && mounted) {
      _selectSpecies(species!);
    }
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.colony == null ? '新入手蚁群' : '编辑蚁群')),
    bottomNavigationBar: SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存蚁群'),
        ),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            icon: Icons.pest_control_outlined,
            title: '品种',
            children: [
              _SearchableChoiceField(
                label: '品种分类/细分种类',
                hintText: '点击选择或搜索品种',
                value: [?_speciesFamily, ?_selectedSpecies].join(' / '),
                options: _speciesOptions.keys.toList(),
                searchOptions: {
                  for (final entry in _speciesOptions.entries)
                    for (final species in entry.value) species: entry.key,
                },
                onSelected: _selectFamily,
                onSearchSelected: _selectSpecies,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _enterCustomSpecies,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text(
                    '未收录？手动填写品种',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.edit_outlined,
            title: '蚁群昵称 *',
            children: [
              TextFormField(
                key: const ValueKey('colony-name'),
                controller: _name,
                decoration: const InputDecoration(hintText: '例如：红土一号'),
                validator: (value) =>
                    _textOrNull(value ?? '') == null ? '请填写一个昵称' : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.bar_chart_outlined,
            title: '数量',
            children: [
              DropdownButtonFormField<GrowthPath>(
                isExpanded: true,
                initialValue: _developmentPath,
                decoration: const InputDecoration(labelText: '发育模式'),
                items: [
                  for (final path in GrowthPath.values)
                    DropdownMenuItem(value: path, child: Text(path.label)),
                ],
                onChanged: (path) => setState(() => _developmentPath = path!),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _queens,
                      validator: _validateRequiredCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '蚁后 *'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _workers,
                      validator: _validateRequiredCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '工蚁 *'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _eggs,
                      validator: _validateCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '卵',
                        hintText: '可选',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _cocoons,
                      validator: _validateCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '茧',
                        hintText: '可选',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _larvae,
                validator: _validateCount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '幼虫',
                  hintText: '可选，暂无请填 0',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '工蚁填 0 表示从新后开始养',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _showSpecialized,
                    onChanged: (value) =>
                        setState(() => _showSpecialized = value ?? false),
                  ),
                  const Text('特化'),
                  if (_showSpecialized) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _specialized,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入特化数量'
                            : _validateCount(value),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '特化数量'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.home_outlined,
            title: '巢体',
            children: [
              _SearchableChoiceField(
                label: '巢体类型（可选）',
                hintText: '点击搜索或选择巢体类型',
                value: _selectedNest,
                options: _nestTypeOptions,
                onSelected: (nest) => setState(() => _selectedNest = nest),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.thermostat_outlined,
            title: '环境预警（可选）',
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _targetTemperatureLower,
                      validator: (value) => _validateAlertLimit(
                        value,
                        _targetTemperature,
                        isLower: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '温度下限 °C',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _targetTemperature,
                      validator: (value) => _validateAlertLimit(
                        value,
                        _targetTemperatureLower,
                        isLower: false,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '温度上限 °C',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _targetHumidityLower,
                      validator: (value) => _validateAlertLimit(
                        value,
                        _targetHumidity,
                        isLower: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '湿度下限 %',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _targetHumidity,
                      validator: (value) => _validateAlertLimit(
                        value,
                        _targetHumidityLower,
                        isLower: false,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '湿度上限 %',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('超出范围时提醒', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.receipt_long_outlined,
            title: '来源与补充信息',
            children: [
              TextFormField(
                controller: _source,
                decoration: InputDecoration(
                  labelText: '来源（可选）',
                  hintText: '商户 / 地点 / 赠送人',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 24,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '选择来源',
                        initialValue: _sourceType ?? '',
                        onSelected: (source) =>
                            setState(() => _sourceType = _textOrNull(source)),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: '野采', child: Text('野采')),
                          PopupMenuItem(value: '网购', child: Text('网购')),
                          PopupMenuItem(value: '蚁友赠送', child: Text('蚁友赠送')),
                          PopupMenuItem(value: '', child: Text('不选择')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_sourceType ?? '选择'),
                                const Icon(Icons.arrow_drop_down, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
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
                onPressed: _saving ? null : _pickCover,
              ),
              if (_coverPreview != null) ...[
                const SizedBox(height: 12),
                _CoverPhotoPreview(image: _coverPreview!),
              ],
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _pickCover() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 86,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _cover = image;
        _coverPreview = Future.value(bytes);
      });
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }
}

class _CoverPhotoPreview extends StatelessWidget {
  const _CoverPhotoPreview({required this.image});
  final Future<Uint8List?> image;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: image,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      const error = SizedBox(
        height: 180,
        child: Center(child: Text('封面无法预览，请重新选择照片')),
      );
      final bytes = snapshot.data;
      if (snapshot.hasError || bytes == null) return error;
      return Column(
        children: [
          InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('封面预览'),
                    leading: const CloseButton(),
                  ),
                  body: Center(
                    child: InteractiveViewer(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => error,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: Image.memory(
              bytes,
              semanticLabel: '封面照片预览',
              width: double.infinity,
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => error,
            ),
          ),
          const SizedBox(height: 4),
          Text('点击照片放大预览', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    },
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
    required this.label,
    required this.hintText,
    required this.value,
    required this.options,
    required this.onSelected,
    this.searchOptions = const {},
    this.onSearchSelected,
  });

  final String label;
  final String hintText;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final Map<String, String> searchOptions;
  final ValueChanged<String>? onSearchSelected;

  Future<void> _openPicker(BuildContext context) async {
    final picked =
        await showModalBottomSheet<({String value, bool isSearchResult})>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ChoicePickerSheet(
            title: label,
            options: options,
            searchOptions: searchOptions,
          ),
        );
    if (picked == null || !context.mounted) return;
    if (picked.isSearchResult) {
      onSearchSelected?.call(picked.value);
    } else {
      onSelected(picked.value);
    }
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('$label-$value'),
    initialValue: value ?? '',
    readOnly: true,
    onTap: () => _openPicker(context),
    decoration: InputDecoration(
      labelText: label,
      hintText: hintText,
      suffixIcon: const Icon(Icons.search),
    ),
  );
}

class _ChoicePickerSheet extends StatefulWidget {
  const _ChoicePickerSheet({
    required this.title,
    required this.options,
    this.searchOptions = const {},
  });
  final String title;
  final List<String> options;
  final Map<String, String> searchOptions;

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
    final options =
        <({String value, String? category})>[
              for (final option in widget.options)
                (value: option, category: null),
              if (normalizedQuery.isNotEmpty)
                for (final entry in widget.searchOptions.entries)
                  (value: entry.key, category: entry.value),
            ]
            .where(
              (option) =>
                  option.value.toLowerCase().contains(normalizedQuery) ||
                  _speciesAliases.entries.any(
                    (alias) =>
                        alias.value == option.value &&
                        alias.key.toLowerCase().contains(normalizedQuery),
                  ) ||
                  importedSpeciesSearchAliases.entries.any(
                    (alias) =>
                        alias.value.contains(option.value) &&
                        alias.key.toLowerCase().contains(normalizedQuery),
                  ),
            )
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
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: widget.searchOptions.isEmpty
                      ? '输入名称搜索'
                      : '搜索分类或细分品种',
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
                          title: Text(options[index].value),
                          subtitle:
                              options[index].category != null ||
                                  importedSpeciesDisambiguation.containsKey(
                                    options[index].value,
                                  )
                              ? Text(
                                  [
                                    ?options[index].category,
                                    ?importedSpeciesDisambiguation[options[index]
                                        .value],
                                  ].join(' · '),
                                )
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, (
                            value: options[index].value,
                            isSearchResult: options[index].category != null,
                          )),
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

Future<Colony?> _openDiarySettings(
  BuildContext context,
  Colony colony, {
  bool? recordIncremental,
  ValueChanged<bool>? onRecordIncrementalChanged,
  bool editingRecord = false,
  bool specificTime = false,
  Future<bool> Function(bool)? onSpecificTimeChanged,
}) async {
  var current = colony;
  Future<Colony?> edit(bool growth) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => growth
            ? ColonyGrowthPage(colony: current)
            : ColonyFormPage(colony: current),
      ),
    );
    current = await AppDatabase.instance.findColony(colony.id) ?? current;
    return current;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => DiarySettingsPage(
        preferences: themeController,
        colony: current,
        onSetSpecialized: colony.archived
            ? null
            : (enabled, count) async {
                current = await AppDatabase.instance.updateColonyDiaryRules(
                  colony.id,
                  showSpecialized: enabled,
                  specializedCount: count,
                );
                return current;
              },
        onSetDevelopmentPath: colony.archived
            ? null
            : (path) async {
                current = await AppDatabase.instance.updateColonyDiaryRules(
                  colony.id,
                  developmentPath: path,
                );
                return current;
              },
        onConfigureGrowth: colony.archived ? null : () => edit(true),
        recordIncremental: recordIncremental,
        onRecordIncrementalChanged: onRecordIncrementalChanged,
        editingRecord: editingRecord,
        specificTime: specificTime,
        onSpecificTimeChanged: onSpecificTimeChanged,
      ),
    ),
  );
  return current;
}

class ColonyDetailPage extends StatefulWidget {
  const ColonyDetailPage({super.key, required this.colonyId});
  final String colonyId;
  @override
  State<ColonyDetailPage> createState() => _ColonyDetailPageState();
}

class _ColonyDetailPageState extends State<ColonyDetailPage> {
  late Future<_Detail> _detail;
  bool _deleting = false;
  bool _editingAcquiredOn = false;
  DiaryDisplay get _display => themeController.diary.display;
  bool get _includeBrood => _display.includeBrood;
  bool get _populationExpanded => _display.populationExpanded;
  bool get _mortalityExpanded => _display.mortalityExpanded;
  bool get _showForecast => _display.forecast;
  ForecastHorizon get _forecastHorizon => _display.horizon;

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _updateDisplay(DiaryDisplay value) async {
    try {
      await themeController.setDiary(themeController.diary.customize(value));
    } catch (_) {
      if (mounted) _showError(context, '设置保存失败，请重试');
    }
  }

  Future<void> _settings(Colony colony) async {
    await _openDiarySettings(context, colony);
    if (mounted) setState(_reload);
  }

  Timer? _growthTimer;
  AppLifecycleListener? _growthLifecycle;

  void _refreshGrowth() {
    if (mounted) setState(_reload);
  }

  @override
  void dispose() {
    themeController.removeListener(_preferencesChanged);
    _growthTimer?.cancel();
    _growthLifecycle?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    themeController.addListener(_preferencesChanged);
    _reload();
    _growthTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshGrowth(),
    );
    _growthLifecycle = AppLifecycleListener(onResume: _refreshGrowth);
  }

  void _reload() {
    _detail = _load();
  }

  Future<_Detail> _load() async => _Detail(
    await AppDatabase.instance.findColony(widget.colonyId),
    await AppDatabase.instance.listRecords(widget.colonyId),
  );

  Future<void> _deleteColony(Colony colony) async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除蚁群？'),
          content: Text('确定删除「${colony.name}」吗？该蚁群及全部养护记录将被删除，此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await AppDatabase.instance.deleteColony(colony.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _editAcquiredOn(Colony colony) async {
    if (_editingAcquiredOn) return;
    _editingAcquiredOn = true;
    try {
      final saved = await _editColonyAcquiredOn(context, colony);
      if (saved && mounted) setState(_reload);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      _editingAcquiredOn = false;
    }
  }

  Future<void> _editRecord(Colony colony, CareRecord record) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordFormPage(colony: colony, record: record),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _deleteRecord(CareRecord record) async {
    final globalUpdate = await AppDatabase.instance
        .needsGlobalGrowthRecalculation(record.colonyId, [record.occurredAt]);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日记？'),
        content: Text(
          '确定删除 ${_dateTime(record.occurredAt)} 的${record.type.label}记录吗？此操作无法撤销。'
          '${globalUpdate ? '\n\n这条记录早于 30 天界碑，确认后将全局重算相关自动扩充日记，可能需要一些时间。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      Future<void> action() => AppDatabase.instance.deleteRecord(
        record,
        recalculateAllGrowth: globalUpdate,
      );
      if (globalUpdate) {
        await _runBusyTask(context, action, message: '正在全局更新日记与种群数量，请稍候…');
      } else {
        await action();
      }
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

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
      final compactAppBar = MediaQuery.sizeOf(context).width < 400;
      Future<void> addRecord() async {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => RecordFormPage(colony: colony)),
        );
        if (mounted) setState(_reload);
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(colony.name),
          actions: [
            IconButton(
              tooltip: '生成分享图',
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ShareCardsPage(colony: colony, records: detail.records),
                ),
              ),
            ),
            if (!colony.archived && !compactAppBar)
              IconButton(
                tooltip: '移入英灵殿',
                icon: const SkullIcon(),
                onPressed: _deleting
                    ? null
                    : () async {
                        final saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => MemorialFormPage(
                              wholeColony: true,
                              colony: colony,
                            ),
                          ),
                        );
                        if (saved == true && context.mounted) {
                          Navigator.of(context).pop(true);
                        }
                      },
              ),
            if (!colony.archived)
              IconButton(
                tooltip: '编辑蚁群',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _deleting
                    ? null
                    : () async {
                        final saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ColonyFormPage(colony: colony),
                          ),
                        );
                        if (saved == true && mounted) setState(_reload);
                      },
              ),
            if (!colony.archived && !compactAppBar)
              IconButton(
                tooltip: '删除蚁群',
                icon: const Icon(Icons.delete_outline),
                color: Theme.of(context).colorScheme.error,
                onPressed: _deleting ? null : () => _deleteColony(colony),
              ),
            if (!colony.archived && compactAppBar)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                enabled: !_deleting,
                onSelected: (action) async {
                  if (action == 'delete') {
                    await _deleteColony(colony);
                    return;
                  }
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          MemorialFormPage(wholeColony: true, colony: colony),
                    ),
                  );
                  if (saved == true && context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'memorial', child: Text('移入英灵殿')),
                  PopupMenuItem(value: 'delete', child: Text('删除蚁群')),
                ],
              ),
          ],
        ),
        bottomNavigationBar: colony.archived
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton.icon(
                    onPressed: _deleting ? null : addRecord,
                    icon: const Icon(Icons.add),
                    label: const Text('添加记录'),
                  ),
                ),
              ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ColonyProfileSummary(
              colony: colony,
              workers: colony.currentWorkerCount(detail.records),
              records: detail.records,
              onDurationTap: colony.archived
                  ? null
                  : () => _editAcquiredOn(colony),
            ),
            if (colony.targetTemperatureLower != null ||
                colony.targetTemperature != null ||
                colony.targetHumidityLower != null ||
                colony.targetHumidity != null) ...[
              const SizedBox(height: 4),
              _ColonySummary(colony: colony),
            ],
            const SizedBox(height: 4),
            CareTasksSection(
              colony: colony,
              onRecord: (task) async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => RecordFormPage(colony: colony, task: task),
                  ),
                );
                if (saved == true && mounted) setState(_reload);
                return saved == true;
              },
            ),
            const SizedBox(height: 4),
            _PopulationTimeline(
              colony: colony,
              records: detail.records,
              includeBrood: _includeBrood,
              expanded: _populationExpanded,
              showForecast: _showForecast,
              forecastHorizon: _forecastHorizon,
              onConfigureGrowth: themeController.simpleMode || colony.archived
                  ? null
                  : () async {
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ColonyGrowthPage(colony: colony),
                        ),
                      );
                      if (saved == true && mounted) {
                        await _updateDisplay(_display.copyWith(forecast: true));
                        if (mounted) setState(_reload);
                      }
                    },
              onOpenSettings: () => _settings(colony),
              onAdjustBoundary: colony.archived
                  ? null
                  : (record) => _editRecord(colony, record),
              onExpandedChanged: (value) =>
                  _updateDisplay(_display.copyWith(populationExpanded: value)),
            ),
            const SizedBox(height: 4),
            WorkerMortalityAnalysisCard(
              key: const ValueKey('colony-mortality-analysis'),
              expanded: _mortalityExpanded,
              onExpandedChanged: (value) =>
                  _updateDisplay(_display.copyWith(mortalityExpanded: value)),
              points: dailyWorkerMortality(
                colony.id,
                detail.records,
                now: DateTime.now(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_stories_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '养蚁日记',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      MenuAnchor(
                        builder: (context, controller, child) =>
                            TextButton.icon(
                              key: const ValueKey('diary-settings-menu'),
                              onPressed: () => controller.isOpen
                                  ? controller.close()
                                  : controller.open(),
                              icon: const Icon(Icons.tune, size: 18),
                              label: Text(themeController.diary.preset.label),
                            ),
                        menuChildren: [
                          for (final preset in DiaryPreset.values)
                            MenuItemButton(
                              onPressed: () async {
                                try {
                                  await themeController.setDiary(
                                    themeController.diary.select(preset),
                                  );
                                } catch (_) {
                                  if (context.mounted) {
                                    _showError(context, '设置保存失败，请重试');
                                  }
                                }
                              },
                              leadingIcon:
                                  themeController.diary.preset == preset
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              child: Text(preset.label),
                            ),
                          MenuItemButton(
                            onPressed: () => _settings(colony),
                            leadingIcon: const Icon(
                              Icons.settings_outlined,
                              size: 18,
                            ),
                            child: const Text('日记设置'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (detail.records.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      colony.archived
                          ? '${detail.records.length} 条记录'
                          : '${detail.records.length} 条记录 · 轻点编辑 · 左滑删除',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (detail.records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: _EmptyState(
                  icon: Icons.article_outlined,
                  title: '还没有记录',
                  message: '从一次投喂或观察开始。',
                ),
              ),
            ...detail.records.map((record) {
              final card = _RecordCard(
                record: record,
                colony: colony,
                remainingPopulation:
                    record.type == CareRecordType.mortality &&
                        record.workerMortalityCount != null
                    ? colony.currentPopulation(
                        detail.records.where(
                          (candidate) =>
                              CareRecord.comparePopulationOrder(
                                candidate,
                                record,
                              ) <=
                              0,
                        ),
                      )
                    : null,
                display: _display,
                onShare: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShareCardsPage(
                      colony: colony,
                      records: detail.records,
                      initialRecord: record,
                    ),
                  ),
                ),
              );
              return colony.archived
                  ? card
                  : DiaryRecordActions(
                      key: ValueKey(record.id),
                      onEdit: () => _editRecord(colony, record),
                      onDelete: () => _deleteRecord(record),
                      child: card,
                    );
            }),
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

class _ColonyProfileSummary extends StatelessWidget {
  const _ColonyProfileSummary({
    required this.colony,
    required this.workers,
    required this.records,
    required this.onDurationTap,
  });
  final Colony colony;
  final int? workers;
  final List<CareRecord> records;
  final VoidCallback? onDurationTap;

  String get _sourceLabel => (colony.source ?? '').trim().replaceFirstMapped(
    RegExp(r'^(野采|网购|蚁友赠送)(?:（(.*)）|\((.*)\)|\s+(.+))$', dotAll: true),
    (match) {
      final detail = (match.group(2) ?? match.group(3) ?? match.group(4)!)
          .trim();
      return detail.isEmpty ? match.group(1)! : '${match.group(1)}-$detail';
    },
  );

  @override
  Widget build(BuildContext context) {
    final population = colony.currentPopulation(records);
    final quantities = <String>[
      if (colony.queenCount != null) '${colony.queenCount} 蚁后',
      if (colony.showSpecialized && colony.specializedCount != null)
        '${colony.specializedCount} 特化',
      if (workers != null) '$workers 工蚁',
      if (population.eggs != null) '${population.eggs} 卵',
      if (population.larvae != null) '${population.larvae} 幼虫',
      if (population.cocoons != null) '${population.cocoons} 茧',
    ];
    final scheme = Theme.of(context).colorScheme;
    final metadataStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    double metadataLabelWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: metadataStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width + 1;
      painter.dispose();
      return width;
    }

    Widget metadataRow(
      String label,
      String value, {
      VoidCallback? onTap,
      TextStyle? valueStyle,
    }) {
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JustifiedLabel(
            text: label,
            width: metadataLabelWidth(label),
            style: metadataStyle,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: valueStyle ?? metadataStyle)),
        ],
      );
      return onTap == null
          ? row
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: row,
            );
    }

    final defaultCover = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/images/default-ant-cover.png',
        width: double.infinity,
        height: 92,
        fit: BoxFit.cover,
        semanticLabel: '默认蚂蚁封面',
      ),
    );
    final cover = colony.coverPhotoPath == null
        ? defaultCover
        : _StoredImage(
            relativePath: colony.coverPhotoPath!,
            width: double.infinity,
            height: 92,
            borderRadius: 8,
            fallback: defaultCover,
          );
    final duration = colony.archived
        ? const Text('遗失的文明 · 养殖已结束')
        : InkWell(
            onTap: onDurationTap,
            borderRadius: BorderRadius.circular(8),
            child: HusbandryDuration(colony: colony, compact: true),
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '蚂蚁品种：${colony.species ?? '未填写品种'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (!themeController.simpleMode &&
                    colony.species?.trim().isNotEmpty == true)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                    icon: const Icon(Icons.menu_book_outlined, size: 16),
                    label: const Text('百科'),
                    onPressed: () {
                      final species = colony.species!.trim();
                      final query = _speciesAliases[species] ?? species;
                      final profile = findSpeciesProfile(query);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => profile == null
                              ? SpeciesEncyclopediaPage(initialQuery: query)
                              : SpeciesDetailPage(profile: profile),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 250 ||
                    MediaQuery.textScalerOf(context).scale(12) > 18) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cover, const SizedBox(height: 8), duration],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 4, child: cover),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: duration),
                  ],
                );
              },
            ),
            if (colony.isNewQueenColony ||
                workers != null ||
                colony.nestType?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              _ColonyTags(colony: colony, workers: workers),
            ],
            if (colony.acquiredOn != null ||
                colony.source?.trim().isNotEmpty == true ||
                colony.purchasePriceCents != null) ...[
              const SizedBox(height: 10),
              if (colony.acquiredOn != null)
                metadataRow(
                  '入手日期',
                  dottedDate(colony.acquiredOn!),
                  onTap: onDurationTap,
                ),
              if (colony.source?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 4),
                metadataRow('来源', _sourceLabel),
              ],
              if (colony.purchasePriceCents != null) ...[
                const SizedBox(height: 4),
                metadataRow('购入价', '¥${colony.purchasePriceText}'),
              ],
            ],
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .3),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final quantity
                    in quantities.isEmpty ? ['尚未补充数量'] : quantities)
                  Text(
                    quantity,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PopulationTimeline extends StatelessWidget {
  const _PopulationTimeline({
    required this.colony,
    required this.records,
    required this.includeBrood,
    required this.expanded,
    required this.onExpandedChanged,
    required this.showForecast,
    required this.onOpenSettings,
    required this.forecastHorizon,
    this.onAdjustBoundary,
    this.onConfigureGrowth,
  });
  final Colony colony;
  final List<CareRecord> records;
  final VoidCallback onOpenSettings;
  final bool includeBrood;
  final bool expanded;
  final bool showForecast;
  final ForecastHorizon forecastHorizon;
  final VoidCallback? onConfigureGrowth;
  final ValueChanged<CareRecord>? onAdjustBoundary;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final boundaryCandidates =
        records
            .where(
              (record) =>
                  record.id.startsWith('growth:') &&
                  record.occurredAt.isBefore(
                    AppDatabase.growthReplayBoundary(now),
                  ),
            )
            .toList()
          ..sort(CareRecord.comparePopulationOrder);
    final boundary = boundaryCandidates.lastOrNull;
    final points = colonyPopulationTotal(
      colony,
      showForecast && colony.growth != null
          ? records.where((r) => !r.occurredAt.isAfter(now)).toList()
          : records,
      includeBrood: includeBrood,
    );
    final forecast = showForecast
        ? colonyPopulationForecast(
            colony,
            records,
            now: now,
            horizon: forecastHorizon,
            metric: PopulationMetric.total,
            includeBrood: includeBrood,
          )
        : <PopulationPoint>[];
    final description = includeBrood ? '蚁后、特化、工蚁与卵幼茧' : '蚁后、特化与工蚁';
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: expanded ? 16 : 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '种群数量',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onConfigureGrowth != null)
                  Tooltip(
                    message: '设置群落自动扩充',
                    child: TextButton(
                      onPressed: onConfigureGrowth,
                      child: const Text('自动扩充'),
                    ),
                  ),
                IconButton(
                  tooltip: expanded ? '折叠种群数量' : '展开种群数量',
                  onPressed: () => onExpandedChanged(!expanded),
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
              if (boundary != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '30 天界碑 ${_date(boundary.occurredAt)} · 工蚁 ${boundary.workerCount?.toString() ?? '未知'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (onAdjustBoundary != null)
                      TextButton(
                        onPressed: () => onAdjustBoundary!(boundary),
                        child: const Text('调整界碑'),
                      ),
                  ],
                ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('统计设置'),
                ),
              ),
              const SizedBox(height: 10),
              if (points.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('暂无有效数量，添加记录后会显示变化。'),
                )
              else ...[
                Text('最近 ${points.last.count} · ${points.length} 个时间点'),
                const SizedBox(height: 8),
                Semantics(
                  label: '种群数量时间折线图，$description。',
                  child: SizedBox(
                    key: const ValueKey('colony-population-chart'),
                    height: 160,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _ColonyPopulationChartPainter(
                        points,
                        Theme.of(context).colorScheme,
                        forecast: forecast,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_date(points.first.time)} — ${_date(forecast.isEmpty ? points.last.time : forecast.last.time)}',
                ),
              ],
              if (forecast.isNotEmpty)
                Text(
                  '预测至 ${_date(forecast.last.time)} · ${forecast.last.count} 只（估算）',
                  key: const ValueKey('population-forecast-summary'),
                ),
              const SizedBox(height: 8),
              Text(
                '未填写的数量不会按 0 计算；两次记录之间沿用最近一次已填写的数量。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColonyPopulationChartPainter extends CustomPainter {
  _ColonyPopulationChartPainter(
    List<PopulationPoint> history,
    this.colors, {
    List<PopulationPoint> forecast = const [],
  }) : points = [...history, ...forecast],
       historyCount = history.length;
  final int historyCount;
  final List<PopulationPoint> points;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final maximum = points.fold<int>(
      1,
      (value, point) => math.max(value, point.count),
    );
    TextPainter label(String text) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final left = math.min(label('$maximum').width + 10, size.width / 3);
    final plot = Rect.fromLTRB(left, 10, size.width - 6, size.height - 26);
    final grid = Paint()..color = colors.outlineVariant;
    final ticks = <int>{0, maximum ~/ 2, maximum};
    for (final tick in ticks) {
      final y = plot.bottom - plot.height * tick / maximum;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final text = label('$tick');
      text.paint(canvas, Offset(0, y - text.height / 2));
    }
    final duration = points.last.time
        .difference(points.first.time)
        .inMicroseconds;
    final locations = [
      for (final point in points)
        Offset(
          duration == 0
              ? plot.center.dx
              : plot.left +
                    plot.width *
                        point.time
                            .difference(points.first.time)
                            .inMicroseconds /
                        duration,
          plot.bottom - plot.height * point.count / maximum,
        ),
    ];
    drawPopulationSeries(canvas, locations, historyCount, colors);
    final start = label(
      chineseDate(points.first.time.toLocal(), includeYear: false),
    );
    start.paint(canvas, Offset(plot.left, plot.bottom + 8));
    if (points.length > 1) {
      final end = label(
        chineseDate(points.last.time.toLocal(), includeYear: false),
      );
      end.paint(canvas, Offset(plot.right - end.width, plot.bottom + 8));
    }
  }

  @override
  bool shouldRepaint(_ColonyPopulationChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.colors != colors;
}

class _ColonySummary extends StatelessWidget {
  const _ColonySummary({required this.colony});
  final Colony colony;
  @override
  Widget build(BuildContext context) {
    String? alertRange(
      String label,
      double? lower,
      double? upper,
      String unit,
    ) {
      if (lower == null && upper == null) return null;
      if (lower != null && upper != null) return '$label $lower–$upper$unit';
      return lower != null ? '$label ≥ $lower$unit' : '$label ≤ $upper$unit';
    }

    final temperatureRange = alertRange(
      '温度',
      colony.targetTemperatureLower,
      colony.targetTemperature,
      '°C',
    );
    final humidityRange = alertRange(
      '湿度',
      colony.targetHumidityLower,
      colony.targetHumidity,
      '%',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (temperatureRange != null)
                  Chip(label: Text(temperatureRange)),
                if (humidityRange != null) Chip(label: Text(humidityRange)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RecordFormPage extends StatefulWidget {
  const RecordFormPage({
    super.key,
    required this.colony,
    this.record,
    this.task,
  });
  final Colony colony;
  final CareRecord? record;
  final CareTask? task;
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
  final _workerMortality = TextEditingController();
  final _feedingFood = TextEditingController();
  final _feedingAmount = TextEditingController();
  final _photos = <XFile>[];
  var _type = CareRecordType.observation;
  FeedingResponse? _feedingResponse;
  bool? _feedingLeftovers;
  var _occurredAt = DateUtils.dateOnly(DateTime.now());
  var _hasSpecificTime = false;
  var _saving = false;
  var _incremental = true;
  late Colony _colony = widget.colony;

  Future<void> _settings() async {
    final updated = await _openDiarySettings(
      context,
      _colony,
      recordIncremental: _incremental,
      onRecordIncrementalChanged: (value) {
        if (mounted) setState(() => _incremental = value);
      },
      editingRecord: widget.record != null,
      specificTime: _hasSpecificTime,
      onSpecificTimeChanged: (value) async {
        await _setSpecificTime(value);
        return _hasSpecificTime;
      },
    );
    if (mounted && updated != null) setState(() => _colony = updated);
  }

  @override
  void initState() {
    super.initState();
    _incremental = themeController.diary.incremental;
    final record = widget.record;
    if (record == null) {
      if (widget.task != null) _type = widget.task!.type.recordType;
      return;
    }
    _type = record.type;
    _occurredAt = record.occurredAt;
    _hasSpecificTime =
        record.occurredAt.hour != 0 || record.occurredAt.minute != 0;
    _note.text = record.note ?? '';
    _temperature.text = record.temperature?.toString() ?? '';
    _humidity.text = record.humidity?.toString() ?? '';
    _eggs.text = record.eggCount?.toString() ?? '';
    _larvae.text = record.larvaCount?.toString() ?? '';
    _pupae.text = record.pupaCount?.toString() ?? '';
    _workers.text = record.workerCount?.toString() ?? '';
    _workerMortality.text = record.workerMortalityCount?.toString() ?? '';
    _feedingFood.text = record.feedingFood ?? '';
    _feedingAmount.text = record.feedingAmount ?? '';
    _feedingResponse = record.feedingResponse;
    _feedingLeftovers = record.feedingLeftovers;
    // Stored counts are snapshots, even if originally entered as increments.
    _incremental = false;
  }

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
      _workerMortality,
      _feedingFood,
      _feedingAmount,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_type == CareRecordType.feeding &&
        (_feedingFood.text.trim().length > 80 ||
            _feedingAmount.text.trim().length > 80)) {
      _showError(context, '食物和投喂量最多填写 80 个字符');
      return;
    }
    for (final controller in [
      _eggs,
      _larvae,
      _pupae,
      _workers,
      if (_type == CareRecordType.mortality) _workerMortality,
    ]) {
      final text = controller.text.trim();
      final n = int.tryParse(text);
      if (text.isNotEmpty && (n == null || n < 0 || n > 1000000)) {
        _showError(context, '数量请输入 0～1000000 的整数');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final globalUpdate = await AppDatabase.instance
          .needsGlobalGrowthRecalculation(_colony.id, [
            _occurredAt,
            if (widget.record case final existing?) existing.occurredAt,
          ]);
      if (!mounted) return;
      if (globalUpdate) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('需要全局更新'),
            content: const Text(
              '这条日记的时间早于 30 天界碑。保存后将从更早的记录重新计算自动扩充数量，并更新界碑及后续日记；人工填写的总数仍作为校正点。处理可能需要一些时间。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认并更新'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      Future<void> saveRecord() async {
        final photos = <String>[...?widget.record?.photos];
        for (final photo in _photos) {
          photos.add(await LocalMediaStore.instance.copyImage(photo));
        }
        final record = CareRecord(
          id: widget.record?.id ?? const Uuid().v4(),
          colonyId: _colony.id,
          type: _type,
          occurredAt: _occurredAt,
          note: _textOrNull(_note.text),
          temperature: double.tryParse(_temperature.text),
          humidity: double.tryParse(_humidity.text),
          eggCount: int.tryParse(_eggs.text),
          larvaCount: int.tryParse(_larvae.text),
          pupaCount:
              _incremental && _colony.developmentPath == GrowthPath.eggToWorker
              ? null
              : int.tryParse(_pupae.text),
          workerCount: int.tryParse(_workers.text),
          workerMortalityCount: _type == CareRecordType.mortality
              ? int.tryParse(_workerMortality.text.trim())
              : null,
          feedingFood: _type == CareRecordType.feeding
              ? _textOrNull(_feedingFood.text)
              : null,
          feedingAmount: _type == CareRecordType.feeding
              ? _textOrNull(_feedingAmount.text)
              : null,
          feedingResponse: _type == CareRecordType.feeding
              ? _feedingResponse
              : null,
          feedingLeftovers: _type == CareRecordType.feeding
              ? _feedingLeftovers
              : null,
          photos: photos,
          createdAt: widget.record?.createdAt ?? DateTime.now(),
        );
        if (widget.record == null) {
          await AppDatabase.instance.saveRecord(
            record,
            incremental: _incremental,
            recalculateAllGrowth: globalUpdate,
            completingTaskId: widget.task?.id,
          );
        } else {
          await AppDatabase.instance.updateRecord(
            record,
            recalculateAllGrowth: globalUpdate,
          );
        }
      }

      if (!mounted) return;
      if (globalUpdate) {
        await _runBusyTask(context, saveRecord, message: '正在全局更新日记与种群数量，请稍候…');
      } else {
        await saveRecord();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _occurredAt,
    );
    if (date == null || !mounted) return;
    setState(
      () => _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        _hasSpecificTime ? _occurredAt.hour : 0,
        _hasSpecificTime ? _occurredAt.minute : 0,
      ),
    );
  }

  Future<bool> _changeSpecificTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _hasSpecificTime
          ? TimeOfDay.fromDateTime(_occurredAt)
          : TimeOfDay.now(),
    );
    if (time != null && mounted) {
      setState(
        () => _occurredAt = DateTime(
          _occurredAt.year,
          _occurredAt.month,
          _occurredAt.day,
          time.hour,
          time.minute,
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> _setSpecificTime(bool enabled) async {
    if (!enabled) {
      setState(() {
        _hasSpecificTime = false;
        _occurredAt = DateUtils.dateOnly(_occurredAt);
      });
      return;
    }
    if (await _changeSpecificTime() && mounted) {
      setState(() => _hasSpecificTime = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.record == null ? '记录 ${_colony.name}' : '编辑日记'),
      actions: [
        IconButton(
          tooltip: '日记设置',
          onPressed: _saving ? null : _settings,
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: _saving ? '保存中…' : '保存记录',
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
        ),
      ],
    ),
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
                  onSelected: widget.task == null
                      ? (_) => setState(() => _type = type)
                      : null,
                ),
              )
              .toList(),
        ),
        if (_type == CareRecordType.feeding) ...[
          const SizedBox(height: 16),
          Text('投喂结果（可选）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _feedingFood,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '食物',
              hintText: '例如：面包虫',
            ),
          ),
          TextField(
            controller: _feedingAmount,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '投喂量',
              hintText: '例如：半只',
            ),
          ),
          DropdownButtonFormField<FeedingResponse>(
            initialValue: _feedingResponse,
            decoration: const InputDecoration(labelText: '进食情况'),
            items: [
              for (final response in FeedingResponse.values)
                DropdownMenuItem(value: response, child: Text(response.label)),
            ],
            onChanged: (value) => setState(() => _feedingResponse = value),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('是否有剩余食物'),
              for (final option in <(bool?, String)>[
                (null, '未知'),
                (false, '无'),
                (true, '有'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text(option.$2),
                    selected: _feedingLeftovers == option.$1,
                    onSelected: (_) =>
                        setState(() => _feedingLeftovers = option.$1),
                  ),
                ),
            ],
          ),
        ],
        if (_type == CareRecordType.mortality) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _workerMortality,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '工蚁死亡数量',
              helperMaxLines: 3,
              helperText: _incremental
                  ? '自动扣减工蚁数量，最低为 0；数量未知时仅记录死亡数'
                  : '工蚁总数留空时自动扣减，最低为 0；填写总数则以总数为准，未知时仅记录死亡数',
            ),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('发生日期：${_date(_occurredAt)}'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_hasSpecificTime ? '已记录具体时间' : '仅记录日期'),
          trailing: const Icon(Icons.tune, size: 18),
          onTap: _saving ? null : _settings,
        ),
        if (_hasSpecificTime)
          OutlinedButton.icon(
            onPressed: _saving ? null : _changeSpecificTime,
            icon: const Icon(Icons.schedule),
            label: Text(
              '具体时间：${_timeOfDay(_occurredAt.hour * 60 + _occurredAt.minute)}',
            ),
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            widget.record != null
                ? '编辑记录 · 总数'
                : _incremental
                ? '数量录入 · 增量'
                : '数量录入 · 总数',
          ),
          subtitle: Text(
            widget.record != null
                ? '填写该次记录的数量总数，留空表示该项未知。'
                : _incremental
                ? '填写增加值，自动扣减上一阶段；${_colony.developmentPath.label}。未知数量请先改为总数。'
                : '填写当前总数，留空不修改',
          ),
          trailing: const Icon(Icons.tune, size: 18),
          onTap: _saving ? null : _settings,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _eggs,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '卵数',
                  helperText: _incremental ? '增加数量' : '当前总数',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _larvae,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '幼虫数',
                  helperText: _incremental ? '增加数量' : '当前总数',
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
                controller: _pupae,
                enabled:
                    !_incremental ||
                    _colony.developmentPath == GrowthPath.eggToCocoonToWorker,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '茧数',
                  helperText: _incremental ? '增加数量' : '当前总数',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _workers,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '工蚁数量（可估计）',
                  helperText: _incremental ? '增加数量' : '当前总数',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.record?.photos.isNotEmpty == true) ...[
          const Text('已有照片'),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.record!.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _StoredImage(
                relativePath: widget.record!.photos[index],
                width: 80,
                height: 80,
                borderRadius: 8,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _photos.isEmpty ? '添加照片（可选）' : '已选择 ${_photos.length} 张照片',
          ),
          onPressed: _saving
              ? null
              : () async {
                  final images = await ImagePicker().pickMultiImage(
                    imageQuality: 86,
                  );
                  if (images.isNotEmpty && mounted) {
                    setState(() => _photos.addAll(images));
                  }
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
      ],
    ),
  );
}

class _RecordCard extends StatefulWidget {
  const _RecordCard({
    required this.record,
    this.colony,
    this.remainingPopulation,
    this.onShare,
    this.display = const DiaryDisplay(),
  });
  final DiaryDisplay display;
  final VoidCallback? onShare;
  final CareRecord record;
  final Colony? colony;
  final GrowthPopulation? remainingPopulation;
  @override
  State<_RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<_RecordCard> {
  bool _expanded = false;
  CareRecord get record => widget.record;
  Colony? get colony => widget.colony;
  VoidCallback? get onShare => widget.onShare;
  @override
  void didUpdateWidget(covariant _RecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.display != widget.display ||
        oldWidget.record.id != record.id) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _expanded ? const DiaryDisplay() : widget.display;
    final hasCounts =
        record.eggCount != null ||
        record.larvaCount != null ||
        record.pupaCount != null ||
        record.workerCount != null;
    final canExpand =
        (!widget.display.counts && hasCounts) ||
        (!widget.display.environment &&
            (record.temperature != null || record.humidity != null)) ||
        (!widget.display.photos && record.photos.isNotEmpty) ||
        (!widget.display.fullNotes && record.note?.isNotEmpty == true);
    final temperatureAbove =
        record.temperature != null &&
        colony?.targetTemperature != null &&
        record.temperature! > colony!.targetTemperature!;
    final temperatureBelow =
        record.temperature != null &&
        colony?.targetTemperatureLower != null &&
        record.temperature! < colony!.targetTemperatureLower!;
    final humidityAbove =
        record.humidity != null &&
        colony?.targetHumidity != null &&
        record.humidity! > colony!.targetHumidity!;
    final humidityBelow =
        record.humidity != null &&
        colony?.targetHumidityLower != null &&
        record.humidity! < colony!.targetHumidityLower!;
    final remaining = widget.remainingPopulation;
    final brood =
        remaining?.eggs != null &&
            remaining?.larvae != null &&
            remaining?.cocoons != null
        ? remaining!.eggs! + remaining.larvae! + remaining.cocoons!
        : null;
    final facts = <String>[
      if (record.type == CareRecordType.feeding && record.feedingFood != null)
        '食物 ${record.feedingFood}',
      if (record.type == CareRecordType.feeding && record.feedingAmount != null)
        '投喂 ${record.feedingAmount}',
      if (record.type == CareRecordType.feeding &&
          record.feedingResponse != null)
        record.feedingResponse!.label,
      if (record.type == CareRecordType.feeding &&
          record.feedingLeftovers != null)
        record.feedingLeftovers! ? '有剩余' : '无剩余',
      if (display.environment && record.temperature != null)
        '${record.temperature}°C',
      if (display.environment && record.humidity != null) '${record.humidity}%',
      if (display.counts && record.eggCount != null) '卵 ${record.eggCount}',
      if (display.counts && record.larvaCount != null)
        '幼虫 ${record.larvaCount}',
      if (display.counts && record.pupaCount != null) '茧 ${record.pupaCount}',
      if (display.counts && record.workerCount != null)
        '工蚁 ${record.workerCount}',
      if (record.workerMortalityCount != null)
        '工蚁死亡 ${record.workerMortalityCount}',
      if (remaining != null) ...[
        '剩余 蚁后 ${colony?.queenCount ?? '未知'}',
        '工蚁 ${remaining.workers ?? '未知'}',
        '卵幼茧子 ${brood ?? '未知'}',
      ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.type.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _dateTime(record.occurredAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onShare != null)
                  IconButton(
                    tooltip: '生成日记卡片',
                    icon: const Icon(Icons.ios_share_outlined, size: 20),
                    onPressed: onShare,
                  ),
              ],
            ),
            if (record.note?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                record.note!,
                maxLines: display.fullNotes ? null : 1,
                overflow: display.fullNotes ? null : TextOverflow.ellipsis,
              ),
            ],
            if (!display.counts &&
                hasCounts &&
                facts.isEmpty &&
                record.note?.isNotEmpty != true &&
                record.photos.isEmpty) ...[
              const SizedBox(height: 10),
              const Text('已记录种群数量'),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                facts.join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (temperatureAbove ||
                temperatureBelow ||
                humidityAbove ||
                humidityBelow) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (temperatureAbove)
                    '温度 ${record.temperature}°C 高于预设上限 ${colony!.targetTemperature}°C',
                  if (temperatureBelow)
                    '温度 ${record.temperature}°C 低于预设下限 ${colony!.targetTemperatureLower}°C',
                  if (humidityAbove)
                    '湿度 ${record.humidity}% 高于预设上限 ${colony!.targetHumidity}%',
                  if (humidityBelow)
                    '湿度 ${record.humidity}% 低于预设下限 ${colony!.targetHumidityLower}%',
                ].join('；'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (record.photos.isNotEmpty && !display.photos) ...[
              const SizedBox(height: 10),
              Text('${record.photos.length} 张照片'),
            ],
            if (canExpand)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起详情' : '查看详情'),
              ),
            if (record.photos.isNotEmpty && display.photos) ...[
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
      Text(
        '查阅物种资料，探索养蚁活动与实用工具。',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Icon(
            Icons.notifications_active_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('养护提醒'),
          subtitle: const Text('设置每天的本地养护提醒'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const SettingsPage(category: SettingsCategory.reminders),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Icon(
            Icons.menu_book_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('蚂蚁百科'),
          subtitle: const Text('基础分类、体型数据与饲养信息 · 离线可查'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SpeciesEncyclopediaPage(),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Icon(
            Icons.casino_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('数字抽奖'),
          subtitle: const Text('转盘随机抽取，或直接显示范围内数字'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const LotteryPage())),
        ),
      ),
      for (final entry in const [
        (
          icon: Icons.emoji_events_outlined,
          title: '蚁友比赛',
          subtitle: '分享养殖成果，参与主题挑战',
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
                  subtitle: const Text('一级名称下包含多个可单独添加的子物品'),
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
                    child: Text(_purchasing ? '正在添加…' : '查看购物车'),
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
    final expiry = item.purchased ? item.effectiveExpiryDate() : null;
    final expired = item.purchased && item.isExpired();
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.purchased
                  ? '已购入'
                  : _cart.contains(item.id)
                  ? '已加入购物车'
                  : '点击添加',
            ),
            if (expiry != null)
              Text(
                '有效期至：${_date(expiry)}${expired ? ' · 已过期' : ''}',
                style: expired
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
          ],
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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除已购物品？'),
        content: Text(
          '将从已购列表移除「${widget.item.fullName}」，并清除数量、购入价和购入日期。推荐项会保留，可随时重新添加。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context, (
      purchased: false,
      quantity: null,
      purchasePriceCents: null,
    ));
  }

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
          purchased: widget.item.purchased,
          onQuantityChanged: (value) => _quantity = value,
          onPriceChanged: (value) => _price = value,
        ),
      ),
    ),
    actions: [
      if (widget.item.purchased)
        TextButton(onPressed: _delete, child: const Text('删除')),
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
        child: Text(widget.item.purchased ? '保存' : '添加'),
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
    this.purchased = false,
  });

  final String quantity;
  final String price;
  final bool purchased;
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
        decoration: InputDecoration(
          labelText: '数量（选填）',
          helperText: purchased ? '有损耗时填写剩余数量；填 0 表示已用完。' : null,
          helperMaxLines: 2,
        ),
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
          helperText: '本次添加物品的总价（元）',
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
        child: const Text('添加'),
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
              title: Text(
                feeder.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (text == null)
        Column(
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
      else
        Text(
          text!,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      const SizedBox(width: 8),
      const Icon(Icons.chevron_right),
    ],
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
  var _occurredAt = DateUtils.dateOnly(DateTime.now());
  var _hasSpecificTime = false;
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

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _occurredAt,
    );
    if (date == null || !mounted) return;
    setState(
      () => _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        _hasSpecificTime ? _occurredAt.hour : 0,
        _hasSpecificTime ? _occurredAt.minute : 0,
      ),
    );
  }

  Future<bool> _changeSpecificTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _hasSpecificTime
          ? TimeOfDay.fromDateTime(_occurredAt)
          : TimeOfDay.now(),
    );
    if (time != null && mounted) {
      setState(
        () => _occurredAt = DateTime(
          _occurredAt.year,
          _occurredAt.month,
          _occurredAt.day,
          time.hour,
          time.minute,
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> _setSpecificTime(bool enabled) async {
    if (!enabled) {
      setState(() {
        _hasSpecificTime = false;
        _occurredAt = DateUtils.dateOnly(_occurredAt);
      });
      return;
    }
    if (await _changeSpecificTime() && mounted) {
      setState(() => _hasSpecificTime = true);
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
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('发生日期：${_date(_occurredAt)}'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _hasSpecificTime,
            onChanged: _saving
                ? null
                : (enabled) => _setSpecificTime(enabled ?? false),
            title: const Text('记录具体时间'),
            subtitle: const Text('默认仅保存年月日'),
          ),
          if (_hasSpecificTime)
            OutlinedButton.icon(
              onPressed: _saving ? null : _changeSpecificTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                '具体时间：${_timeOfDay(_occurredAt.hour * 60 + _occurredAt.minute)}',
              ),
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

Future<void> _renameColonyTab(BuildContext context, ColonyTab tab) async {
  final formKey = GlobalKey<FormState>();
  var name = themeController.colonyTabName(tab);
  var saving = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, updateDialog) {
        Future<void> save(String value) async {
          if (saving) return;
          updateDialog(() {
            saving = true;
            error = null;
          });
          try {
            await themeController.setColonyTabName(tab, value);
            if (context.mounted) Navigator.of(context).pop();
          } catch (_) {
            if (context.mounted) {
              updateDialog(() {
                saving = false;
                error = '保存失败，请重试';
              });
            }
          }
        }

        return PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('修改菜单名称'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: name,
                      autofocus: true,
                      enabled: !saving,
                      maxLength: 12,
                      decoration: const InputDecoration(labelText: '菜单名称'),
                      onChanged: (value) => name = value,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入菜单名称'
                          : null,
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => save(tab.defaultName),
                child: const Text('恢复默认'),
              ),
              TextButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () {
                        if (formKey.currentState!.validate()) save(name);
                      },
                child: Text(saving ? '保存中…' : '保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

enum SettingsCategory {
  appearance('外观与展示', Icons.palette_outlined),
  online('在线服务', Icons.cloud_outlined),
  reminders('养护提醒', Icons.notifications_active_outlined),
  data('数据管理', Icons.storage_outlined),
  help('帮助与反馈', Icons.help_outline),
  about('关于与更新', Icons.info_outline);

  const SettingsCategory(this.title, this.icon);
  final String title;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.category});
  final SettingsCategory? category;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _savingEdition = false;
  bool _savingSimpleMode = false;

  Future<void> _setSimpleMode(bool enabled) async {
    if (_savingSimpleMode) return;
    setState(() => _savingSimpleMode = true);
    try {
      await themeController.setSimpleMode(enabled);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _savingSimpleMode = false);
    }
  }

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
    animation: Listenable.merge([
      themeController,
      appUpdateController,
      onlineController,
    ]),
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

  Widget _settingsList(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: children,
      ),
    ),
  );

  Widget _categoryTile(BuildContext context, SettingsCategory category) {
    final subtitle = switch (category) {
      SettingsCategory.appearance =>
        '${themeController.themeColor.label} · ${themeController.simpleMode ? '简化模式' : '完整模式'}',
      SettingsCategory.online =>
        '${themeController.edition.label} · ${onlineController.user?.username ?? '账号与公共资料'}',
      SettingsCategory.reminders =>
        themeController.careRemindersEnabled
            ? '已开启 · 每天 ${_timeOfDay(themeController.careReminderMinuteOfDay)}'
            : '未开启 · 设置每日提醒',
      SettingsCategory.data => '数据推送、备份与恢复',
      SettingsCategory.help => '使用指南、交流群',
      SettingsCategory.about => switch (appUpdateController.availability) {
        AppUpdateAvailability.required => '在线服务需更新 · 点此查看',
        AppUpdateAvailability.optional =>
          '发现新版本 ${appUpdateController.policy?.latestVersion}',
        AppUpdateAvailability.none => '当前版本、检查更新',
      },
    };
    return ListTile(
      leading: Icon(category.icon),
      title: Text(category.title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsPage(category: category),
        ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context) {
    final category = widget.category;
    if (category != null) {
      return Scaffold(
        appBar: AppBar(title: Text(category.title)),
        body: _settingsList(_categoryContents(context, category)),
      );
    }
    return _settingsList([
      _section(context, '通用', [
        for (final category in [
          SettingsCategory.appearance,
          SettingsCategory.online,
          if (themeController.simpleMode) SettingsCategory.reminders,
        ])
          _categoryTile(context, category),
      ]),
      _section(context, '数据与支持', [
        for (final category in [
          SettingsCategory.data,
          SettingsCategory.help,
          SettingsCategory.about,
        ])
          _categoryTile(context, category),
      ]),
    ]);
  }

  List<Widget> _categoryContents(
    BuildContext context,
    SettingsCategory category,
  ) => switch (category) {
    SettingsCategory.appearance => [
      _section(context, '展示模式', [
        SwitchListTile(
          secondary: const Icon(Icons.view_agenda_outlined),
          title: const Text('简化模式'),
          subtitle: const Text('只展示蚁群、日常记录和设置；关闭后恢复全部功能入口，已有数据保留'),
          value: themeController.simpleMode,
          onChanged: _savingSimpleMode ? null : _setSimpleMode,
        ),
        for (final tab in ColonyTab.values)
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text('${tab.defaultName}菜单名称'),
            subtitle: Text(themeController.colonyTabName(tab)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _renameColonyTab(context, tab),
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
          leading: Icon(Icons.text_fields),
          title: Text('字体颜色'),
          subtitle: Text('独立于主题色，保存在本机；深色模式使用对应浅色'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FontColorPicker(
            selected: themeController.fontColor,
            onChanged: (color) async {
              try {
                await themeController.setFontColor(color);
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
    ],
    SettingsCategory.online => [
      _section(context, '资料模式与账号', [
        ListTile(
          leading: Icon(
            themeController.edition == AppEdition.offline
                ? Icons.phonelink_lock_outlined
                : Icons.cloud_download_outlined,
          ),
          title: const Text('资料模式'),
          subtitle: Text(
            themeController.edition == AppEdition.offline
                ? '使用内置资料，断网可用；启动时会联网检查 Android 更新。'
                : '在线版可获取公共资料，并会匿名检查 Android 更新。',
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
                      : (selected) {
                          if (!selected) return;
                          _setEdition(edition);
                        },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '蚁群、记录和照片都只保存在本设备。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        OnlineSettings(
          controller: onlineController,
          section: OnlineSettingsSection.account,
          updates: appUpdateController,
          useOffline: () => _setEdition(AppEdition.offline),
        ),
      ]),
    ],
    SettingsCategory.reminders => [
      _section(context, '养护提醒', [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('本地养护提醒'),
          subtitle: Text(
            themeController.careRemindersEnabled
                ? '每天 ${_timeOfDay(themeController.careReminderMinuteOfDay)} 提醒；不上传任何数据'
                : '关闭；开启后申请通知权限，Android 还会申请闹钟和提醒权限',
          ),
          value: themeController.careRemindersEnabled,
          onChanged: (enabled) async {
            try {
              var exact = true;
              if (enabled) {
                final granted = await LocalNotificationService.instance
                    .requestPermission();
                if (!granted) {
                  if (context.mounted) {
                    _showInfo(context, '未获得通知权限，提醒没有开启。');
                  }
                  return;
                }
                exact = await LocalNotificationService.instance
                    .scheduleDailyCareReminder(
                      themeController.careReminderMinuteOfDay,
                      requestExactPermission: true,
                    );
              } else {
                await LocalNotificationService.instance
                    .cancelDailyCareReminder();
              }
              await themeController.setCareReminder(
                enabled: enabled,
                minuteOfDay: themeController.careReminderMinuteOfDay,
              );
              if (!exact && context.mounted) {
                _showInfo(context, '未获得闹钟和提醒权限，已设置普通提醒，可能延迟。');
              }
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
                    final exact = await LocalNotificationService.instance
                        .scheduleDailyCareReminder(
                          minuteOfDay,
                          requestExactPermission: true,
                        );
                    await themeController.setCareReminder(
                      enabled: true,
                      minuteOfDay: minuteOfDay,
                    );
                    if (!exact && context.mounted) {
                      _showInfo(context, '未获得闹钟和提醒权限，已设置普通提醒，可能延迟。');
                    }
                  } catch (error) {
                    if (context.mounted) _showError(context, error);
                  }
                },
        ),
      ]),
    ],
    SettingsCategory.data => [
      _section(context, '数据管理', [
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('数据推送'),
          subtitle: const Text('选择物品栏数据推送到 B 端，每天一次'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => InventoryPushPage(
                controller: onlineController,
                loadItems: AppDatabase.instance.listInventory,
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('导出备份'),
          trailing: const Icon(Icons.chevron_right),
          subtitle: const Text('生成包含记录和照片的 .zip 文件'),
          onTap: () async {
            try {
              final exported = await _runBackupTask(
                context,
                () => BackupService(
                  AppDatabase.instance,
                  LocalMediaStore.instance,
                ).exportBackup(),
              );
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
          subtitle: const Text('可选择增量恢复或覆盖恢复'),
          onTap: () async {
            final mode = await showDialog<BackupRestoreMode>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('选择恢复方式'),
                scrollable: true,
                content: const Text(
                  '增量恢复：保留本机数据，只补入缺失的蚁群、记录、待办和物品。'
                  '相同 ID 的数据、同一蚁群同类型待办，以及同分组同名物品，保留本机内容。\n\n'
                  '覆盖恢复：用备份替换本机现有蚁群、记录和待办。'
                  '旧备份没有待办时，本机待办也会被清空。\n\n'
                  '两种方式都会在恢复前保存回退副本，可撤销上一次恢复。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, BackupRestoreMode.overwrite),
                    child: const Text('覆盖恢复'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, BackupRestoreMode.incremental),
                    child: const Text('增量恢复'),
                  ),
                ],
              ),
            );
            if (mode == null || !context.mounted) return;
            try {
              final restored = await _runBackupTask(
                context,
                () => BackupService(
                  AppDatabase.instance,
                  LocalMediaStore.instance,
                ).restoreBackup(mode: mode),
              );
              if (restored && context.mounted) {
                _showInfo(
                  context,
                  '${mode == BackupRestoreMode.incremental ? '增量' : '覆盖'}恢复完成；可在设置中撤销上一次恢复。',
                );
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
          subtitle: const Text('恢复操作前自动保留的本地回退副本'),
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
              await _runBackupTask(context, service.undoLastRestore);
              if (context.mounted) _showInfo(context, '已撤销上一次恢复。');
            } catch (error) {
              if (context.mounted) _showError(context, error);
            }
          },
        ),
      ]),
    ],
    SettingsCategory.help => [
      _section(context, '帮助与反馈', [
        OnlineSettings(
          controller: onlineController,
          section: OnlineSettingsSection.help,
          updates: appUpdateController,
          useOffline: () => _setEdition(AppEdition.offline),
        ),
        ListTile(
          leading: const Icon(Icons.qr_code_2_outlined),
          title: const Text('交流群二维码'),
          subtitle: const Text('微信、抖音交流群'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CommunityGroupsPage()),
          ),
        ),
      ]),
    ],
    SettingsCategory.about => [
      _section(context, '版本与更新', [
        OnlineSettings(
          controller: onlineController,
          section: OnlineSettingsSection.updates,
          updates: appUpdateController,
          useOffline: () => _setEdition(AppEdition.offline),
        ),
      ]),
    ],
  };
}

class _StoredImage extends StatelessWidget {
  const _StoredImage({
    required this.relativePath,
    required this.width,
    required this.height,
    required this.borderRadius,
    this.fallback,
  });

  final String relativePath;
  final double width;
  final double height;
  final double borderRadius;
  final Widget? fallback;

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
        return fallback ?? _missingImage(context);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.memory(
          snapshot.data!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stackTrace) =>
              fallback ?? _missingImage(context),
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
  CareRecordType.cleaning => Icons.cleaning_services_outlined,
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
String _date(DateTime value) => chineseDate(value);
String _dateTime(DateTime value) => value.hour == 0 && value.minute == 0
    ? _date(value)
    : '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _timeOfDay(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';
Future<T> _runBusyTask<T>(
  BuildContext context,
  Future<T> Function() action, {
  required String message,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  navigator.push(route);
  try {
    return await action();
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}

Future<T> _runBackupTask<T>(
  BuildContext context,
  Future<T> Function() action,
) => _runBusyTask(context, action, message: '正在处理备份，请稍候…');

void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作未完成：$error')));
void _showInfo(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
