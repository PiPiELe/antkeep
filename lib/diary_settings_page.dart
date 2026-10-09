import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'diary_preferences.dart';
import 'domain/colony_growth.dart';
import 'domain/models.dart';
import 'domain/population_forecast.dart';

/// Display preferences and the current colony's diary rules.
class DiarySettingsPage extends StatefulWidget {
  const DiarySettingsPage({
    super.key,
    required this.preferences,
    required this.colony,
    this.onSetSpecialized,
    this.onSetDevelopmentPath,
    this.onConfigureGrowth,
    this.recordIncremental,
    this.onRecordIncrementalChanged,
    this.editingRecord = false,
    this.specificTime = false,
    this.onSpecificTimeChanged,
  });
  final AppPreferences preferences;
  final Colony colony;
  final Future<Colony?> Function(bool enabled, int? count)? onSetSpecialized;
  final Future<Colony?> Function(GrowthPath path)? onSetDevelopmentPath;
  final Future<Colony?> Function()? onConfigureGrowth;
  final bool? recordIncremental;
  final ValueChanged<bool>? onRecordIncrementalChanged;
  final bool editingRecord, specificTime;
  final Future<bool> Function(bool)? onSpecificTimeChanged;

  @override
  State<DiarySettingsPage> createState() => _DiarySettingsPageState();
}

class _DiarySettingsPageState extends State<DiarySettingsPage> {
  late Colony _colony = widget.colony;
  late final TextEditingController _specializedCount = TextEditingController(
    text: widget.colony.specializedCount?.toString() ?? '0',
  );
  late bool _specificTime = widget.specificTime;
  late bool? _recordIncremental = widget.recordIncremental;
  bool _saving = false;

  @override
  void dispose() {
    _specializedCount.dispose();
    super.dispose();
  }

  Future<void> _save(DiaryPreferences value, {bool? incremental}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.preferences.setDiary(value);
      if (incremental != null) {
        _recordIncremental = incremental;
        widget.onRecordIncrementalChanged?.call(incremental);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(Future<Colony?> Function() action) async {
    try {
      final colony = await action();
      if (mounted && colony != null) setState(() => _colony = colony);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读取蚁群设置失败，请返回后重试')));
      }
    }
  }

  Future<void> _updateColony(Future<Colony?> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final colony = await action();
      if (mounted && colony != null) {
        setState(() => _colony = colony);
        _specializedCount.text = colony.specializedCount?.toString() ?? '0';
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('蚁群设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setSpecialized(bool enabled) async {
    final count = int.tryParse(_specializedCount.text.trim());
    if (enabled && (count == null || count < 0 || count > 1000000)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('特化数量须为 0～1000000 的整数')));
      return;
    }
    await _updateColony(
      () => widget.onSetSpecialized!(
        enabled,
        enabled ? count! : _colony.specializedCount,
      ),
    );
  }

  Future<void> _configureGrowth() async {
    final hadGrowth = _colony.growth != null;
    await _edit(widget.onConfigureGrowth!);
    if (mounted && !hadGrowth && _colony.growth != null) {
      await _save(
        widget.preferences.diary.customize(
          widget.preferences.diary.display.copyWith(forecast: true),
        ),
      );
    }
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _toggle(
    String title,
    bool value,
    DiaryDisplay Function(bool) change, {
    String? subtitle,
  }) => SwitchListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: _saving
        ? null
        : (next) => _save(widget.preferences.diary.customize(change(next))),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.preferences,
    builder: (context, _) {
      final settings = widget.preferences.diary;
      final display = settings.display;
      return Scaffold(
        appBar: AppBar(title: const Text('日记设置')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _heading('展示模式'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final preset in DiaryPreset.values)
                    ChoiceChip(
                      label: Text(preset.label),
                      selected: settings.preset == preset,
                      onSelected: _saving
                          ? null
                          : (_) => _save(settings.select(preset)),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '日常：隐藏数量明细；完整：保留全部内容；紧凑：只看摘要。预设默认折叠统计、不含卵幼和预测。仅改变展示，不改变增量、特化或自动扩充。',
              ),
            ),
            _heading('日记展示 · 本机所有蚁群'),
            _toggle(
              '显示种群数量',
              display.counts,
              (v) => display.copyWith(counts: v),
              subtitle: '顶部当前数量始终保留',
            ),
            _toggle(
              '显示温湿度',
              display.environment,
              (v) => display.copyWith(environment: v),
              subtitle: '异常提醒始终保留',
            ),
            _toggle(
              '显示照片缩略图',
              display.photos,
              (v) => display.copyWith(photos: v),
              subtitle: '关闭后显示照片张数',
            ),
            _toggle(
              '显示完整备注',
              display.fullNotes,
              (v) => display.copyWith(fullNotes: v),
              subtitle: '关闭后显示首行，可展开单条日记查看详情',
            ),
            _heading('记录方式'),
            SwitchListTile(
              title: const Text('增量'),
              value: widget.editingRecord
                  ? false
                  : (_recordIncremental ?? settings.incremental),
              subtitle: Text(
                widget.editingRecord
                    ? '编辑历史日记固定填写总数，避免重复累加'
                    : '新日记默认使用${(_recordIncremental ?? settings.incremental) ? '增加量，并按发育阶段扣减' : '当前总数'}；本机记忆${widget.recordIncremental == null ? '' : '，同时用于本次记录'}',
              ),
              onChanged: _saving || widget.editingRecord || _colony.archived
                  ? null
                  : (value) => _save(
                      settings.withIncremental(value),
                      incremental: value,
                    ),
            ),
            if (widget.onSpecificTimeChanged != null)
              CheckboxListTile(
                title: const Text('记录具体时间'),
                subtitle: const Text('仅本次日记；关闭后仅保存年月日'),
                value: _specificTime,
                onChanged: _saving
                    ? null
                    : (value) async {
                        setState(() => _saving = true);
                        try {
                          final enabled = await widget.onSpecificTimeChanged!(
                            value ?? false,
                          );
                          if (mounted) setState(() => _specificTime = enabled);
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
              )
            else
              const ListTile(
                title: Text('记录具体时间'),
                subtitle: Text('新增日记默认仅日期，可在录入时的日记设置中开启'),
              ),
            SwitchListTile(
              title: const Text('特化'),
              subtitle: const Text('仅当前蚁群'),
              value: _colony.showSpecialized,
              onChanged:
                  _saving || widget.onSetSpecialized == null || _colony.archived
                  ? null
                  : _setSpecialized,
            ),
            if (_colony.showSpecialized)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _specializedCount,
                  keyboardType: TextInputType.number,
                  enabled:
                      !_saving &&
                      !_colony.archived &&
                      widget.onSetSpecialized != null,
                  decoration: InputDecoration(
                    labelText: '特化数量',
                    helperText: '修改数量后点保存',
                    suffixIcon: IconButton(
                      tooltip: '保存特化数量',
                      onPressed:
                          _saving ||
                              _colony.archived ||
                              widget.onSetSpecialized == null
                          ? null
                          : () => _setSpecialized(true),
                      icon: const Icon(Icons.check),
                    ),
                  ),
                  onSubmitted: (_) => _setSpecialized(true),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '发育模式 · 仅当前蚁群'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<GrowthPath>(
                    isExpanded: true,
                    value: _colony.developmentPath,
                    items: [
                      for (final path in GrowthPath.values)
                        DropdownMenuItem(value: path, child: Text(path.label)),
                    ],
                    onChanged:
                        _saving ||
                            widget.onSetDevelopmentPath == null ||
                            _colony.archived
                        ? null
                        : (path) {
                            if (path != null &&
                                path != _colony.developmentPath) {
                              _updateColony(
                                () => widget.onSetDevelopmentPath!(path),
                              );
                            }
                          },
                  ),
                ),
              ),
            ),
            _heading('统计展示 · 本机所有蚁群'),
            _toggle(
              '展开种群数量',
              display.populationExpanded,
              (v) => display.copyWith(populationExpanded: v),
            ),
            _toggle(
              '展开死亡分析',
              display.mortalityExpanded,
              (v) => display.copyWith(mortalityExpanded: v),
            ),
            _toggle(
              '带卵幼',
              display.includeBrood,
              (v) => display.copyWith(includeBrood: v),
              subtitle: '数量图包含卵、幼虫和茧',
            ),
            _heading('增长 · 仅当前蚁群'),
            ListTile(
              key: _colony.growth == null
                  ? const ValueKey('population-forecast-setup')
                  : null,
              title: const Text('自动扩充与增长预测'),
              subtitle: Text(
                _colony.archived
                    ? '已归档，无法修改'
                    : _colony.growth == null
                    ? '未开启 · 设置周期与数量后可查看预测'
                    : '自动扩充已开启 · ${_colony.growth!.frequency.label} · 修改规则',
              ),
              trailing: TextButton(
                onPressed:
                    _saving ||
                        widget.onConfigureGrowth == null ||
                        _colony.archived
                    ? null
                    : _configureGrowth,
                child: Text(_colony.growth == null ? '设置规则' : '修改规则'),
              ),
              onTap:
                  _saving ||
                      widget.onConfigureGrowth == null ||
                      _colony.archived
                  ? null
                  : _configureGrowth,
            ),
            if (_colony.growth != null) ...[
              SwitchListTile(
                key: const ValueKey('population-forecast-toggle'),
                title: const Text('数量图显示增长预测'),
                subtitle: const Text('按自动扩充规则绘制虚线，不额外写入记录'),
                value: display.forecast,
                onChanged: _saving
                    ? null
                    : (value) => _save(
                        settings.customize(display.copyWith(forecast: value)),
                      ),
              ),
              if (display.forecast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final horizon in ForecastHorizon.values)
                        ChoiceChip(
                          label: Text(horizon.label),
                          selected: display.horizon == horizon,
                          onSelected: _saving
                              ? null
                              : (_) => _save(
                                  settings.customize(
                                    display.copyWith(horizon: horizon),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('自动扩充会生成估算记录；关闭图表预测不会停止自动扩充。'),
            ),
          ],
        ),
      );
    },
  );
}
