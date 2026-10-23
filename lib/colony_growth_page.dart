import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'domain/colony_growth.dart';
import 'domain/models.dart';
import 'widgets/readable_width.dart';

class ColonyGrowthPage extends StatefulWidget {
  const ColonyGrowthPage({super.key, required this.colony});
  final Colony colony;

  @override
  State<ColonyGrowthPage> createState() => _ColonyGrowthPageState();
}

class _ColonyGrowthPageState extends State<ColonyGrowthPage> {
  final _form = GlobalKey<FormState>();
  final _eggs = TextEditingController();
  final _larvae = TextEditingController();
  final _cocoons = TextEditingController();
  final _workers = TextEditingController();
  late final Future<GrowthPopulation> _population = AppDatabase.instance
      .listRecords(widget.colony.id)
      .then(widget.colony.currentPopulation);
  var _enabled = false;
  var _saving = false;
  var _frequency = GrowthFrequency.daily;
  GrowthPath get _path => widget.colony.developmentPath;

  @override
  void initState() {
    super.initState();
    final growth = widget.colony.growth;
    _enabled = growth != null;
    if (growth != null) {
      _frequency = growth.frequency;
      _larvae.text = growth.larvae?.toString() ?? '';
      _eggs.text = growth.eggs?.toString() ?? '';
      _cocoons.text = growth.cocoons?.toString() ?? '';
      _workers.text = growth.workers?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _eggs.dispose();
    _larvae.dispose();
    _cocoons.dispose();
    _workers.dispose();
    super.dispose();
  }

  int? _count(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final eggs = _count(_eggs);
    final larvae = _count(_larvae);
    final cocoons = _path == GrowthPath.eggToCocoonToWorker
        ? _count(_cocoons)
        : null;
    final workers = _count(_workers);
    if (_enabled &&
        (eggs ?? 0) + (larvae ?? 0) + (cocoons ?? 0) + (workers ?? 0) == 0) {
      _error('请至少填写一项大于 0 的增长数量');
      return;
    }
    setState(() => _saving = true);
    try {
      final colony = await AppDatabase.instance.findColony(widget.colony.id);
      if (colony == null) throw StateError('蚁群已不存在');
      final records = await AppDatabase.instance.listRecords(colony.id);
      final population = colony.currentPopulation(records);
      if (_enabled &&
          (population.eggs == null ||
              population.larvae == null ||
              population.workers == null ||
              (_path == GrowthPath.eggToCocoonToWorker &&
                  population.cocoons == null))) {
        _error('请先在蚁群档案或养护记录中填写卵、幼虫、工的当前数量；经过茧的路径还需填写茧数量，暂无请填 0。');
        return;
      }
      final old = colony.growth;
      // Saving identical settings must not restart an existing period.
      final unchanged =
          old != null &&
          old.frequency == _frequency &&
          old.path == _path &&
          old.eggs == eggs &&
          old.larvae == larvae &&
          old.cocoons == cocoons &&
          old.workers == workers;
      final growth = !_enabled
          ? null
          : unchanged
          ? old
          : ColonyGrowth(
              frequency: _frequency,
              path: _path,
              startedAt: DateTime.now(),
              eggs: eggs,
              larvae: larvae,
              cocoons: cocoons,
              workers: workers,
            );
      await AppDatabase.instance.configureColonyGrowth(colony.id, growth);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _error('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _quantity(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: '$label净增长',
        suffixText: '只 / ${_frequency.label.substring(1)}',
        helperMaxLines: 3,
        helperText: label == '工' ? '留空或填 0 表示不增长' : '留空按路径扣减；填 0 表示数量保持不变',
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final n = int.tryParse(value.trim());
        return n == null || n < 0 || n > 1000000 ? '请输入 0～1000000 的整数' : null;
      },
    ),
  );

  Widget _preview() => FutureBuilder<GrowthPopulation>(
    future: _population,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('无法读取当前数量，请返回重试');
      if (!snapshot.hasData) return const Text('正在读取当前数量…');
      final before = snapshot.data!;
      if ([
        before.eggs,
        before.larvae,
        before.workers,
        if (_path == GrowthPath.eggToCocoonToWorker) before.cocoons,
      ].any((value) => value == null)) {
        return const Text('当前数量有未知项，请先补充总数后预览自动估算；暂无个体请填 0。');
      }
      for (final input in [_eggs, _larvae, _cocoons, _workers]) {
        if (input.text.trim().isNotEmpty &&
            (int.tryParse(input.text.trim()) == null ||
                int.parse(input.text.trim()) < 0 ||
                int.parse(input.text.trim()) > 1000000)) {
          return const Text('请先填写有效的每周期增长数量');
        }
      }
      final rule = ColonyGrowth(
        frequency: _frequency,
        path: _path,
        startedAt: DateTime.now(),
        eggs: _count(_eggs),
        larvae: _count(_larvae),
        cocoons: _path == GrowthPath.eggToCocoonToWorker
            ? _count(_cocoons)
            : null,
        workers: _count(_workers),
      );
      final after = rule.advance(before);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('下一周期数量预览 · 自动估算'),
              for (final entry in <(String, int?, int?)>[
                ('卵', before.eggs, after.eggs),
                ('幼虫', before.larvae, after.larvae),
                if (_path == GrowthPath.eggToCocoonToWorker)
                  ('茧', before.cocoons, after.cocoons),
                ('工蚁', before.workers, after.workers),
              ])
                Text('${entry.$1} ${entry.$2 ?? '—'} → ${entry.$3 ?? '—'}'),
              const Text('这是规则推算；请用实际观察记录校正。'),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('群落自动扩充')),
    body: ReadableWidth(
      maxWidth: 680,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.colony.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开启自动扩充'),
              subtitle: Text(
                _enabled ? '按设定周期估算卵、幼虫、茧、工数量' : '未开启 · 设置卵、幼虫、茧、工增长规则',
              ),
              value: _enabled,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _enabled = value),
            ),
            if (_enabled) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<GrowthFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: '族群扩展速度'),
                items: [
                  for (final value in GrowthFrequency.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) => setState(() => _frequency = value!),
              ),
              const SizedBox(height: 20),
              Text('发育模式：${_path.label}（在蚁群信息中修改）'),
              const SizedBox(height: 20),
              _quantity('卵', _eggs),
              _quantity('幼虫', _larvae),
              if (_path == GrowthPath.eggToCocoonToWorker)
                _quantity('茧', _cocoons),
              _quantity('工', _workers),
              _preview(),
              const Text(
                '填写的是每周期净增长。\n'
                '填幼虫时扣卵；填茧时扣幼虫；填工时根据蚁群发育模式扣茧或幼虫。\n'
                '明确填写的阶段按净增长处理，留空阶段按路径扣减。\n'
                '来源不足时只转化已有数量，不会扣成负数。',
              ),
              const SizedBox(height: 16),
              const Text(
                '启用或修改规则后，从保存时刻开始计算完整周期。每月按对应日期计算，月末不足则取当月最后一天。\n'
                '打开或返回应用时补算未处理的周期。数量会写入标注“自动扩充（估算）”的养护记录；可用实际观察记录校正。关闭后保留历史估算。',
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存设置'),
            ),
          ],
        ),
      ),
    ),
  );
}
