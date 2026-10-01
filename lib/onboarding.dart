import 'dart:async';

import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'online/online_widgets.dart';
import 'online/runtime.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.preferences});
  final AppPreferences preferences;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  AppEdition? _edition;
  bool? _beginner;
  var _step = 0;
  var _saving = false;
  String? _error;
  late ThemeColor _color = widget.preferences.themeColor;
  late ThemeMode _mode = widget.preferences.themeMode;

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.preferences.completeOnboarding(
        edition: _edition!,
        beginner: _beginner!,
        color: _color,
        mode: _mode,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = '设置未能保存，请重试。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _back() => setState(() {
    _step--;
    _error = null;
  });

  @override
  Widget build(BuildContext context) => Theme(
    data: antKeepTheme(
      _color,
      dark:
          _mode == ThemeMode.dark ||
          (_mode == ThemeMode.system &&
              MediaQuery.platformBrightnessOf(context) == Brightness.dark),
    ),
    child: Builder(
      builder: (context) => PopScope(
        canPop: _step == 0 && !_saving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_saving && _step > 0) _back();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('欢迎使用蚁记'),
            leading: _step == 0
                ? null
                : BackButton(onPressed: _saving ? null : _back),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              key: ValueKey(_step),
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                24,
                                24,
                                16,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight > 40
                                      ? constraints.maxHeight - 40
                                      : 0,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (_step == 0) ...[
                                      Text(
                                        '选择使用版本',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        '离线版使用内置资料；在线版可获取后台发布的最新资料和配置。',
                                      ),
                                      const SizedBox(height: 24),
                                      _editionCard(
                                        context,
                                        AppEdition.offline,
                                        '使用 App 内封装好的资料；蚁群、记录和照片始终只保存在本机。',
                                        Icons.phonelink_lock_outlined,
                                      ),
                                      const SizedBox(height: 12),
                                      _editionCard(
                                        context,
                                        AppEdition.online,
                                        '保留本地养殖记录；联网时可获取后台发布的最新资料和配置。',
                                        Icons.cloud_download_outlined,
                                      ),
                                    ] else if (_step == 1) ...[
                                      Text(
                                        '选择你喜欢的主题色',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text('点选即可预览，以后可在设置中更换。'),
                                      const SizedBox(height: 24),
                                      ThemeColorPicker(
                                        selected: _color,
                                        onChanged: (color) =>
                                            setState(() => _color = color),
                                      ),
                                      const SizedBox(height: 24),
                                      const Text('外观模式'),
                                      const SizedBox(height: 8),
                                      ThemeModePicker(
                                        selected: _mode,
                                        onChanged: (mode) =>
                                            setState(() => _mode = mode),
                                      ),
                                      const SizedBox(height: 16),
                                      const Card(
                                        child: ListTile(
                                          leading: Icon(Icons.hive_outlined),
                                          title: Text('我的蚁群'),
                                          subtitle: Text('主题预览 · 记录每一次成长'),
                                          trailing: Icon(Icons.check_circle),
                                        ),
                                      ),
                                    ] else if (_step == 2) ...[
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              28,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.hive_outlined,
                                            size: 48,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        '你是养蚁新手，还是老玩家？',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '按你的经验提供提示，以后也能在设置中调整。',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              height: 1.5,
                                            ),
                                      ),
                                      const SizedBox(height: 24),
                                      _experienceCard(
                                        context,
                                        true,
                                        '我是新手',
                                        '从建立第一窝蚁群档案开始，带我了解记录方法。',
                                        Icons.eco_outlined,
                                      ),
                                      const SizedBox(height: 12),
                                      _experienceCard(
                                        context,
                                        false,
                                        '我是老玩家',
                                        '已经有养蚁经验，直接开始使用。',
                                        Icons.workspace_premium_outlined,
                                      ),
                                    ] else ...[
                                      Text(
                                        '从第一份记录开始',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall,
                                      ),
                                      const SizedBox(height: 16),
                                      const BeginnerTips(),
                                    ],
                                    if (_step == 3 ||
                                        (_step == 2 && _beginner == false)) ...[
                                      const SizedBox(height: 24),
                                      const Text('无需账号，记录和照片保存在本机。记得定期导出备份。'),
                                      if (_error != null) ...[
                                        const SizedBox(height: 16),
                                        Text(_error!, semanticsLabel: _error),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                        ),
                        onPressed:
                            _saving ||
                                (_step == 0 && _edition == null) ||
                                (_step == 2 && _beginner == null)
                            ? null
                            : () {
                                if (_step == 3 ||
                                    (_step == 2 && _beginner == false)) {
                                  _finish();
                                } else {
                                  setState(() => _step++);
                                }
                              },
                        child: Text(
                          _saving
                              ? '正在保存…'
                              : _step == 3 || (_step == 2 && _beginner == false)
                              ? '开始使用'
                              : '下一步',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _editionCard(
    BuildContext context,
    AppEdition edition,
    String subtitle,
    IconData icon,
  ) {
    final selected = _edition == edition;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _saving
              ? null
              : () => setState(() {
                  _edition = edition;
                  unawaited(setOnlineMode(edition == AppEdition.online));
                  _error = null;
                }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          edition.label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                height: 1.5,
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _experienceCard(
    BuildContext context,
    bool beginner,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final selected = _beginner == beginner;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _saving
              ? null
              : () => setState(() {
                  _beginner = beginner;
                  _error = null;
                }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                height: 1.5,
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThemeColorPicker extends StatelessWidget {
  const ThemeColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final ThemeColor selected;
  final ValueChanged<ThemeColor>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final color in ThemeColor.values)
        ChoiceChip(
          avatar: CircleAvatar(backgroundColor: color.color),
          label: Text(color.label),
          selected: selected == color,
          onSelected: onChanged == null ? null : (_) => onChanged!(color),
        ),
    ],
  );
}

class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final mode in ThemeMode.values)
        ChoiceChip(
          label: Text(switch (mode) {
            ThemeMode.system => '跟随系统',
            ThemeMode.light => '浅色',
            ThemeMode.dark => '深色',
          }),
          selected: selected == mode,
          onSelected: (_) => onChanged(mode),
        ),
    ],
  );
}

class BeginnerTips extends StatelessWidget {
  const BeginnerTips({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: onlineController,
    builder: (_, _) => HelpContent(content: onlineController.content),
  );
}
