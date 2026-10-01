import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'domain/purchase_price.dart';
import 'domain/spending_analysis.dart';

class SpendingAnalysisView extends StatefulWidget {
  const SpendingAnalysisView({super.key, this.loadSummary});

  final Future<SpendingSummary> Function()? loadSummary;

  @override
  State<SpendingAnalysisView> createState() => _SpendingAnalysisViewState();
}

class _SpendingAnalysisViewState extends State<SpendingAnalysisView> {
  late Future<SpendingSummary> _summary;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _summary =
        (widget.loadSummary ?? AppDatabase.instance.loadSpendingSummary)();
    _summary.ignore();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SpendingSummary>(
    future: _summary,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(_reload),
            child: const Text('消费读取失败，点击重试'),
          ),
        );
      }
      final summary = snapshot.data!;
      final categories = summary.categories;
      const colors = [Color(0xFF287A62), Color(0xFFD58A25), Color(0xFF5B70BE)];
      return RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _summary.catchError((_) => summary);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('已记录购入总额'),
                    const SizedBox(height: 8),
                    Text(
                      '¥${formatPurchasePrice(summary.totalCents)}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    if (summary.totalCents > 0)
                      Center(
                        child: Semantics(
                          label: '购入消费金额占比饼图，分类金额和占比见下方',
                          image: true,
                          child: SizedBox.square(
                            dimension: 220,
                            child: CustomPaint(
                              key: const ValueKey('spending-pie'),
                              painter: _SpendingPiePainter(
                                amounts: categories
                                    .map((c) => c.cents)
                                    .toList(),
                                total: summary.totalCents,
                                colors: colors,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('暂无可展示的消费占比\n填写购入价后即可查看；总额为 0 时不生成饼图。'),
                      ),
                    const SizedBox(height: 24),
                    for (var i = 0; i < categories.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 12),
                              child: SizedBox.square(
                                dimension: 12,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors[i],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${categories[i].label}\n'
                                '¥${formatPurchasePrice(categories[i].cents)} · '
                                '${summary.totalCents == 0 ? '0.0' : (categories[i].cents / summary.totalCents * 100).toStringAsFixed(1)}%',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '统计当前保存的全部购入价：蚁群（含已归档）、已购物品及 DLC 养殖记录，'
              '不限日期。未填金额、未购物品不计入；0 元不占扇区。'
              '每笔录入金额计入一次，不再乘数量。百分比四舍五入至 1 位小数。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '消费前 5 笔',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '按单笔购入金额从高到低排列',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (summary.topEntries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text('暂无消费明细，填写大于 0 的购入价后即可查看。'),
                      ),
                    for (var i = 0; i < summary.topEntries.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _SpendingEntryRow(
                        rank: i + 1,
                        entry: summary.topEntries[i],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SpendingEntryRow extends StatelessWidget {
  const _SpendingEntryRow({required this.rank, required this.entry});

  final int rank;
  final SpendingEntry entry;

  @override
  Widget build(BuildContext context) {
    final date = entry.occurredAt;
    final subtitle = date == null
        ? entry.category
        : '${entry.category} · ${date.year}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  '¥${formatPurchasePrice(entry.cents)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendingPiePainter extends CustomPainter {
  const _SpendingPiePainter({
    required this.amounts,
    required this.total,
    required this.colors,
  });

  final List<int> amounts;
  final int total;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2,
    );
    var start = -math.pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      if (amounts[i] <= 0) continue;
      final sweep = amounts[i] / total * math.pi * 2;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = colors[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_SpendingPiePainter oldDelegate) =>
      total != oldDelegate.total ||
      !listEquals(amounts, oldDelegate.amounts) ||
      !listEquals(colors, oldDelegate.colors);
}
