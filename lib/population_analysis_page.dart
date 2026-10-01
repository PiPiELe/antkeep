import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'date_display.dart';
import 'domain/models.dart';
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
  bool _showSpending = false;
  bool _showForecast = false;
  ForecastHorizon _forecastHorizon = ForecastHorizon.month;

  String? get _forecastUnavailableReason => _colony == null
      ? 'DLC 暂无自动扩充规则'
      : _colony!.growth == null
      ? '请先在群落自动扩充中设置增长规则'
      : _metric == PopulationMetric.larvae
      ? '自动扩充规则不包含幼虫，暂不预测此指标'
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

  Future<_PopulationSeries> _loadPoints() async {
    final colony = _colony;
    final feeder = _feeder;
    final metric = _metric;
    final predict = _showForecast && _forecastUnavailableReason == null;
    final horizon = _forecastHorizon;
    if (colony != null) {
      final records =
          await (widget.loadRecords ?? AppDatabase.instance.listRecords)(
            colony.id,
          );
      final now = DateTime.now();
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
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('分析'),
        bottom: TabBar(
          onTap: (index) => setState(() => _showSpending = index == 1),
          tabs: const [
            Tab(text: '数量分析'),
            Tab(text: '消费占比'),
          ],
        ),
      ),
      body: _showSpending
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
                      key: const ValueKey('analysis-subject'),
                      initialValue: _selectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '选择蚁群或 DLC 养殖',
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
                    if (_selectedId == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Text(
                          '选择一窝蚁群或一种 DLC 养殖，查看数量变化。',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else ...[
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
                        onEnabledChanged: (value) => setState(() {
                          _showForecast = value;
                          _reloadPoints();
                        }),
                        onHorizonChanged: (value) => setState(() {
                          _forecastHorizon = value;
                          _reloadPoints();
                        }),
                      ),
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
                              child: const Text('数量读取失败，点击重试'),
                            );
                          }
                          return _PopulationResult(
                            points: snapshot.data!.history,
                            forecast: snapshot.data!.forecast,
                            metric: _metric,
                          );
                        },
                      ),
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
                );
              },
            ),
    ),
  );
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
