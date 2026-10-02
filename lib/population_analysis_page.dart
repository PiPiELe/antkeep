import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'colony_growth_page.dart';
import 'date_display.dart';
import 'domain/models.dart';
import 'domain/mortality_analysis.dart';
import 'domain/population_analysis.dart';
import 'domain/spending_analysis.dart';
import 'spending_analysis_view.dart';
import 'domain/population_forecast.dart';
import 'population_forecast_controls.dart';

typedef _PopulationSeries = ({
  List<PopulationPoint> history,
  List<PopulationPoint> forecast,
});

class PopulationAnalysisPage extends StatefulWidget {
  const PopulationAnalysisPage({
    super.key,
    this.loadColonies,
    this.loadRecords,
    this.loadFeederRecords,
    this.loadSpending,
  });

  final Future<SpendingSummary> Function()? loadSpending;
  final Future<List<Colony>> Function()? loadColonies;
  final Future<List<CareRecord>> Function(String)? loadRecords;
  final Future<List<FeederRecord>> Function(FeederType)? loadFeederRecords;

  @override
  State<PopulationAnalysisPage> createState() => _PopulationAnalysisPageState();
}

class _PopulationAnalysisPageState extends State<PopulationAnalysisPage> {
  late Future<List<Colony>> _colonies;
  Future<_PopulationSeries>? _points;
  Colony? _colony;
  FeederType? _feeder;
  PopulationMetric _metric = PopulationMetric.workers;
  String? _selectedId;
  int _tabIndex = 0;
  bool get _showMortality => _tabIndex == 2;
  bool _showForecast = false;
  ForecastHorizon _forecastHorizon = ForecastHorizon.month;

  String? get _forecastUnavailableReason => _colony == null
      ? 'DLC 暂无自动扩充规则'
      : _colony!.growth == null
      ? '请先在群落自动扩充中设置增长规则'
      : null;

  @override
  void initState() {
    super.initState();
    _reloadColonies();
  }

  void _reloadColonies() {
    _colonies = (widget.loadColonies ?? AppDatabase.instance.listColonies)();
    _colonies.ignore();
  }

  Future<void> _configureGrowth() async {
    final colony = _colony;
    if (colony == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ColonyGrowthPage(colony: colony)),
    );
    if (saved != true || !mounted) return;
    try {
      final colonies =
          await (widget.loadColonies ?? AppDatabase.instance.listColonies)();
      if (!mounted) return;
      setState(() {
        _colonies = Future.value(colonies);
        _colony = colonies.where((c) => c.id == colony.id).firstOrNull;
        if (_colony == null) {
          _selectedId = null;
          _points = null;
          _showForecast = false;
        } else {
          _showForecast = _colony!.growth != null;
          _reloadPoints();
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刷新增长规则失败，请重新进入分析页重试')),
      );
    }
  }

  Future<_PopulationSeries> _loadPoints() async {
    final colony = _colony;
    final feeder = _feeder;
    final metric = _metric;
    final mortality = _showMortality;
    final predict = _showForecast && _forecastUnavailableReason == null;
    final horizon = _forecastHorizon;
    if (colony != null) {
      final records =
          await (widget.loadRecords ?? AppDatabase.instance.listRecords)(
            colony.id,
          );
      final now = DateTime.now();
      if (mortality) {
        return (
          history: dailyWorkerMortality(colony.id, records, now: now),
          forecast: <PopulationPoint>[],
        );
      }
      return (
        history: colonyPopulation(
          colony,
          predict
              ? records.where((r) => !r.occurredAt.isAfter(now)).toList()
              : records,
          metric,
        ),
        forecast: predict
            ? colonyPopulationForecast(
                colony,
                records,
                now: now,
                horizon: horizon,
                metric: metric,
              )
            : <PopulationPoint>[],
      );
    }
    final records =
        await (widget.loadFeederRecords ??
            AppDatabase.instance.listFeederRecords)(feeder!);
    return (
      history: feederPopulation(feeder, records, metric),
      forecast: <PopulationPoint>[],
    );
  }

  void _reloadPoints() {
    _points = _loadPoints();
    // A read can fail before the next frame attaches FutureBuilder's listener.
    // Keep its error available to the builder without an unhandled async error.
    _points!.ignore();
  }

  void _select(String id, List<Colony> colonies) {
    setState(() {
      _selectedId = id;
      _showForecast = false;
      _colony = id.startsWith('colony:')
          ? colonies.firstWhere((c) => 'colony:${c.id}' == id)
          : null;
      _feeder = _colony == null
          ? FeederType.values.firstWhere((f) => 'feeder:${f.name}' == id)
          : null;
      _metric = _colony != null
          ? PopulationMetric.workers
          : PopulationMetric.total;
      _reloadPoints();
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('分析'),
        bottom: TabBar(
          onTap: (index) => setState(() {
            _tabIndex = index;
            if (index != 1 &&
                (_colony != null || (!_showMortality && _feeder != null))) {
              _reloadPoints();
            }
          }),
          tabs: const [
            Tab(text: '数量分析'),
            Tab(text: '消费占比'),
            Tab(text: '死亡分析'),
          ],
        ),
      ),
      body: _tabIndex == 1
          ? SpendingAnalysisView(loadSummary: widget.loadSpending)
          : FutureBuilder<List<Colony>>(
              future: _colonies,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(_reloadColonies),
                      child: const Text('读取失败，点击重试'),
                    ),
                  );
                }
                final colonies = snapshot.data!;
                final metrics = _colony != null
                    ? PopulationMetric.colonyMetrics
                    : PopulationMetric.feederMetrics;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        _showMortality
                            ? 'mortality-subject'
                            : 'analysis-subject',
                      ),
                      initialValue: _showMortality && _colony == null
                          ? null
                          : _selectedId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _showMortality ? '选择蚁群' : '选择蚁群或 DLC 养殖',
                      ),
                      items: [
                        for (final colony in colonies)
                          DropdownMenuItem(
                            value: 'colony:${colony.id}',
                            child: Text(
                              '蚁群 · ${colony.name}${colony.species == null ? "" : "（${colony.species}）"}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (!_showMortality)
                          for (final feeder in FeederType.values)
                            DropdownMenuItem(
                              value: 'feeder:${feeder.name}',
                              child: Text('DLC · ${feeder.label}'),
                            ),
                      ],
                      onChanged: (id) {
                        if (id != null) _select(id, colonies);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_selectedId == null ||
                        (_showMortality && _colony == null))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Text(
                          _showMortality
                              ? '选择一窝蚁群，查看工蚁死亡量变化。'
                              : '选择一窝蚁群或一种 DLC 养殖，查看数量变化。',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else ...[
                      if (!_showMortality) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final metric in metrics)
                              ChoiceChip(
                                label: Text(metric.label),
                                selected: _metric == metric,
                                onSelected: (_) => setState(() {
                                  _metric = metric;
                                  _reloadPoints();
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PopulationForecastControls(
                          enabled: _showForecast,
                          horizon: _forecastHorizon,
                          unavailableReason: _forecastUnavailableReason,
                          onConfigureGrowth:
                              _colony == null ? null : _configureGrowth,
                          onEnabledChanged: (value) => setState(() {
                            _showForecast = value;
                            _reloadPoints();
                          }),
                          onHorizonChanged: (value) => setState(() {
                            _forecastHorizon = value;
                            _reloadPoints();
                          }),
                        ),
                      ],
                      FutureBuilder<_PopulationSeries>(
                        future: _points,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return TextButton(
                              onPressed: () => setState(_reloadPoints),
                              child: Text(
                                _showMortality
                                    ? '死亡数量读取失败，点击重试'
                                    : '数量读取失败，点击重试',
                              ),
                            );
                          }
                          if (_showMortality) {
                            return WorkerMortalityAnalysisCard(
                              points: snapshot.data!.history,
                            );
                          }
                          return _PopulationResult(
                            points: snapshot.data!.history,
                            forecast: snapshot.data!.forecast,
                            metric: _metric,
                          );
                        },
                      ),
                      if (!_showMortality) ...[
                        const SizedBox(height: 16),
                        Text(
                          '按全部有效记录的实际发生时间展示；空白数量不计入，0 会保留。'
                          '${_colony != null ? "初始数量以入手日期（未填写时用建档时间）计入。" : "总数量仅使用同时填写幼体和成体的记录，不重复扣除死亡数量。"}'
                          '同一时刻的同一指标使用最后录入的有效值。连线仅连接记录点，不代表期间每天的数量。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '趋势规则：至少 3 个时间点；数量相同为平稳，只增不减为稳定上升，'
                          '只减不增为稳定下降，有升有降为数量波动。估计数量也会参与分析，结果仅描述已有记录。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ],
                );
              },
            ),
    ),
  );
}

class WorkerMortalityAnalysisCard extends StatelessWidget {
  const WorkerMortalityAnalysisCard({
    super.key,
    required this.points,
    this.expanded = true,
    this.onExpandedChanged,
  });
  final List<PopulationPoint> points;
  final bool expanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final comparison = MortalityComparison(points, now: DateTime.now());
    String period(DateTime start, DateTime end) =>
        '${_date(start)} — ${_date(DateTime(end.year, end.month, end.day - 1))}';
    final percent = comparison.percent;
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: expanded ? 16 : 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onExpandedChanged != null)
              Row(
                children: [
                  const Icon(Icons.monitor_heart_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '死亡分析',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: expanded ? '折叠死亡分析' : '展开死亡分析',
                    onPressed: () => onExpandedChanged!(!expanded),
                    icon: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ),
                ],
              ),
            if (expanded && points.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('暂无工蚁死亡数量记录\n请在日记中选择「死亡」，填写工蚁死亡数量。'),
              ),
            if (expanded && points.isNotEmpty) ...[
              Text(
                comparison.label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: comparison.comparable && comparison.delta > 0
                      ? colors.error
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '最近 7 日 · ${comparison.recentTotal} 只 · 已记录 ${comparison.recentDays}/7 天',
              ),
              Text(
                period(comparison.recentStart, comparison.end),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '前 7 日 · ${comparison.previousTotal} 只 · 已记录 ${comparison.previousDays}/7 天',
              ),
              Text(
                period(comparison.previousStart, comparison.recentStart),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (comparison.comparable) ...[
                const SizedBox(height: 8),
                Text(
                  '较前 7 日 ${comparison.delta > 0 ? "+" : ""}${comparison.delta} 只'
                  '${percent == null ? "（前期为 0，不计算百分比）" : "（${percent > 0 ? "+" : ""}${percent.toStringAsFixed(1)}%）"}',
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '比较截至昨日的两个完整 7 日周期，不含今天。仅比较已录入死亡数，记录频率不同可能影响结果；未记录日期不视为零死亡。',
              ),
              const SizedBox(height: 20),
              Text('每日工蚁死亡数量', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Semantics(
                label: '每日工蚁死亡数量折线图，详细数据见每日明细。',
                child: SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _PopulationChartPainter(points, colors),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('${_date(points.first.time)} — ${_date(points.last.time)}'),
              const Text('按实际发生日期汇总，同日多条相加；空白不计入，0 保留。连线仅连接记录日，今日数据可能尚未完整。'),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('每日明细'),
                children: [
                  for (final point in points.reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_date(point.time)),
                      trailing: Text('${point.count} 只'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PopulationResult extends StatelessWidget {
  const _PopulationResult({
    required this.points,
    required this.forecast,
    required this.metric,
  });
  final List<PopulationPoint> forecast;
  final List<PopulationPoint> points;
  final PopulationMetric metric;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无有效数量记录\n请先在该对象的记录中填写所选指标的数量。'),
        ),
      );
    }
    final trend = populationTrend(points);
    final delta = points.last.count - points.first.count;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trend.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${metric.label} · 最近 ${points.last.count} 只 · ${points.length} 个时间点',
            ),
            if (points.length > 1)
              Text('较首次数量 ${delta > 0 ? "+" : ""}$delta 只'),
            if (points.length < 3) const Text('至少需要 3 个不同时间点的有效数量，才能判断趋势。'),
            const SizedBox(height: 20),
            Semantics(
              label: '${metric.label}数量折线图，${trend.label}。详细数据见下方数量记录。',
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: CustomPaint(
                  painter: _PopulationChartPainter(
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
            if (forecast.isNotEmpty) ...[
              Text(
                '预测至 ${_date(forecast.last.time)} · ${forecast.last.count} 只（估算）',
                key: const ValueKey('population-forecast-summary'),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('预测数量（估算）'),
                children: [
                  for (final point in forecast.skip(1))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${_date(point.time)} ${_time(point.time)}'),
                      trailing: Text('${point.count} 只'),
                    ),
                ],
              ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('数量记录'),
              children: [
                for (final point in points.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_date(point.time)} ${_time(point.time)}'),
                    trailing: Text('${point.count} 只'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime time) {
  final local = time.toLocal();
  return chineseDate(local);
}

String _time(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, "0")}:${local.minute.toString().padLeft(2, "0")}:${local.second.toString().padLeft(2, "0")}';
}

class _PopulationChartPainter extends CustomPainter {
  _PopulationChartPainter(
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
    final maximum = points.fold<int>(1, (value, p) => math.max(value, p.count));
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
  bool shouldRepaint(_PopulationChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.colors != colors;
}
