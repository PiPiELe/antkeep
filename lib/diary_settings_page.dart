import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'diary_preferences.dart';
import 'domain/models.dart';
import 'population_forecast_controls.dart';

/// All diary controls live here. Colony rules keep their existing editors.
class DiarySettingsPage extends StatefulWidget {
  const DiarySettingsPage({
    super.key,
    required this.preferences,
    required this.colony,
    this.onEditColony,
    this.onConfigureGrowth,
    this.recordIncremental,
    this.onRecordIncrementalChanged,
    this.editingRecord = false,
    this.specificTime = false,
    this.onSpecificTimeChanged,
  });
  final AppPreferences preferences;
  final Colony colony;
  final Future<Colony?> Function()? onEditColony, onConfigureGrowth;
  final bool? recordIncremental;
  final ValueChanged<bool>? onRecordIncrementalChanged;
  final bool editingRecord, specificTime;
  final Future<bool> Function(bool)? onSpecificTimeChanged;

  @override
  State<DiarySettingsPage> createState() => _DiarySettingsPageState();
}

class _DiarySettingsPageState extends State<DiarySettingsPage> {
  late Colony _colony = widget.colony;
  late bool _specificTime = widget.specificTime;
  late bool? _recordIncremental = widget.recordIncremental;
  bool _saving = false;

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
            ListTile(
              title: const Text('特化'),
              subtitle: Text(
                '${_colony.showSpecialized ? '已开启 · ${_colony.specializedCount ?? '未知'} 只' : '未开启'} · 仅当前蚁群',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving || widget.onEditColony == null
                  ? null
                  : () => _edit(widget.onEditColony!),
            ),
            ListTile(
              title: const Text('发育模式'),
              subtitle: Text('${_colony.developmentPath.label} · 仅当前蚁群'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving || widget.onEditColony == null
                  ? null
                  : () => _edit(widget.onEditColony!),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PopulationForecastControls(
                enabled: display.forecast,
                horizon: display.horizon,
                unavailableReason: _colony.growth == null
                    ? '当前蚁群未设置增长规则，预测暂不可用'
                    : null,
                onEnabledChanged: (value) {
                  if (!_saving) {
                    _save(
                      settings.customize(display.copyWith(forecast: value)),
                    );
                  }
                },
                onHorizonChanged: (value) {
                  if (!_saving) {
                    _save(settings.customize(display.copyWith(horizon: value)));
                  }
                },
                onConfigureGrowth: widget.onConfigureGrowth == null
                    ? null
                    : () async {
                        await _edit(widget.onConfigureGrowth!);
                        if (mounted && _colony.growth != null) {
                          await _save(
                            widget.preferences.diary.customize(
                              widget.preferences.diary.display.copyWith(
                                forecast: true,
                              ),
                            ),
                          );
                        }
                      },
              ),
            ),
            _heading('自动记录 · 仅当前蚁群'),
            ListTile(
              title: const Text('群落自动扩充'),
              subtitle: Text(
                _colony.archived
                    ? '已归档，无法修改'
                    : _colony.growth == null
                    ? '未开启 · 设置周期与数量'
                    : '已开启 · 修改周期与数量',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving || widget.onConfigureGrowth == null
                  ? null
                  : () => _edit(widget.onConfigureGrowth!),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('自动扩充会生成估算记录；展示模式不会替你启停。'),
            ),
          ],
        ),
      );
    },
  );
}
