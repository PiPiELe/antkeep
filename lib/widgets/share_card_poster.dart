import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/share_card_data.dart';

class ShareCardPoster extends StatelessWidget {
  const ShareCardPoster({
    super.key,
    required this.colony,
    required this.records,
    required this.kind,
    required this.now,
    required this.from,
    required this.to,
    required this.month,
    this.diary,
    this.photos = const [],
    this.caption = '',
    this.dark = false,
    this.showCounts = true,
    this.showDates = true,
    this.showDuration = true,
    this.showEnvironment = true,
    this.showNote = true,
    this.photoAlignment = Alignment.center,
  });
  final Colony colony;
  final List<CareRecord> records;
  final ShareCardKind kind;
  final DateTime now, from, to, month;
  final CareRecord? diary;
  final List<Uint8List?> photos;
  final String caption;
  final bool dark,
      showCounts,
      showDates,
      showDuration,
      showEnvironment,
      showNote;
  final Alignment photoAlignment;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xfff4efe4) : const Color(0xff293b31);
    final accent = dark ? const Color(0xffcbd4a9) : const Color(0xff5b7145);
    final stats = shareSnapshot(colony, records, now);
    final report = ShareMonth(colony, records, month, now);
    final days = colony.husbandryDays(now);
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: ink, fontSize: 14, height: 1.6);
    Widget label(String text) =>
        Text(text, style: TextStyle(color: accent, fontSize: 12));
    Widget headline(String text) => Text(
      text,
      style: TextStyle(
        fontSize: 25,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    );
    Widget counts(ShareSnapshot snapshot) => Wrap(
      spacing: 14,
      runSpacing: 8,
      children: snapshot.quantities.entries
          .where((e) => e.value.value != null)
          .map((e) => Text('${e.key} ${e.value.text}'))
          .toList(),
    );
    Widget photo(int index, {double ratio = 1.25}) {
      final bytes = index < photos.length ? photos[index] : null;
      return AspectRatio(
        aspectRatio: ratio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: bytes == null
              ? ColoredBox(
                  color: accent.withValues(alpha: .10),
                  child: Center(
                    child: Icon(Icons.spa_outlined, size: 44, color: accent),
                  ),
                )
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  alignment: photoAlignment,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('照片无法显示')),
                ),
        ),
      );
    }

    Widget comparisonSide(DateTime date, int index) {
      final cutoff = shareDayEnd(date).isAfter(now) ? now : shareDayEnd(date);
      final snapshot = shareSnapshot(colony, records, cutoff);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            photo(index, ratio: .85),
            const SizedBox(height: 10),
            if (showDates) label(shareDate(date)),
            if (showCounts)
              Text(
                '工蚁 ${snapshot.workers.text}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
          ],
        ),
      );
    }

    final firstSnapshot = shareSnapshot(
      colony,
      records,
      shareDayEnd(from).isAfter(now) ? now : shareDayEnd(from),
    );
    final lastSnapshot = shareSnapshot(
      colony,
      records,
      shareDayEnd(to).isAfter(now) ? now : shareDayEnd(to),
    );
    return ColoredBox(
      color: dark ? const Color(0xff202b26) : const Color(0xfff7f3e9),
      child: DefaultTextStyle(
        style: style,
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('ANTKEEP  /  ${kind.label}'),
              const SizedBox(height: 16),
              headline(colony.name),
              if (colony.species?.isNotEmpty ?? false) label(colony.species!),
              const SizedBox(height: 22),
              if (kind == ShareCardKind.colony) ...[
                if (photos.isNotEmpty) ...[
                  photo(0),
                  const SizedBox(height: 22),
                ],
                if (showDuration && days != null) ...[
                  headline('已陪伴 $days 天'),
                  const SizedBox(height: 14),
                ],
                if (showCounts) counts(stats),
                if (showDates) ...[
                  const SizedBox(height: 12),
                  label('截至 ${shareDate(now)} · 最近已知记录'),
                ],
              ],
              if (kind == ShareCardKind.diary && diary != null) ...[
                headline(diary!.type.label),
                if (showDates) label(shareDate(diary!.occurredAt)),
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  photo(0),
                ],
                if (showNote && caption.trim().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(caption.trim()),
                ],
                if (showCounts) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      for (final entry in {
                        '工蚁': diary!.workerCount,
                        '卵': diary!.eggCount,
                        '幼虫': diary!.larvaCount,
                        '茧': diary!.pupaCount,
                      }.entries)
                        if (entry.value != null)
                          Text(
                            '${entry.key} ${entry.value}${isEstimatedRecord(diary!) ? '（估算）' : ''}',
                          ),
                    ],
                  ),
                ],
                if (showEnvironment &&
                    (diary!.temperature != null ||
                        diary!.humidity != null)) ...[
                  const SizedBox(height: 12),
                  label(
                    [
                      if (diary!.temperature != null) '${diary!.temperature} ℃',
                      if (diary!.humidity != null) '${diary!.humidity}% RH',
                    ].join('  ·  '),
                  ),
                ],
              ],
              if (kind == ShareCardKind.comparison) ...[
                if (showDuration) ...[
                  headline(
                    '${DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays} 天的变化',
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    comparisonSide(from, 0),
                    const SizedBox(width: 14),
                    comparisonSide(to, 1),
                  ],
                ),
                if (showCounts) ...[
                  const SizedBox(height: 20),
                  Text(
                    shareWorkerChange(
                      firstSnapshot.workers,
                      lastSnapshot.workers,
                    ),
                  ),
                  label('数量取截至所选日期的最近已知记录'),
                ],
              ],
              if (kind == ShareCardKind.monthly) ...[
                headline('${month.year} 年 ${month.month} 月'),
                if (showDates)
                  label(
                    '${shareDate(report.start)} — ${shareDate(report.end)}',
                  ),
                const SizedBox(height: 16),
                Text(
                  '${report.diaryCount} 篇日记  ·  ${report.activeDays} 天留下记录',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (report.estimateCount > 0)
                  label('另有 ${report.estimateCount} 条自动估算记录'),
                if (showCounts) ...[
                  const SizedBox(height: 12),
                  Text(report.change),
                  if (report.records.isNotEmpty)
                    label(
                      '月初（或入手时）${report.before.workers.text} → 月末截至 ${report.after.workers.text}',
                    ),
                  if (report.workerRecords.length >= 2) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 70,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _TrendPainter(report.workerRecords, accent),
                      ),
                    ),
                    label(
                      '工蚁记录趋势${report.workerRecords.any(isEstimatedRecord) ? ' · 含估算' : ''}',
                    ),
                  ],
                ],
                if (report.records.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('这个月还没有留下养护记录。'),
                ],
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  for (var i = 0; i < photos.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(child: photo(i, ratio: 1)),
                          if (i + 1 < photos.length) ...[
                            const SizedBox(width: 10),
                            Expanded(child: photo(i + 1, ratio: 1)),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
              if (kind != ShareCardKind.diary &&
                  showNote &&
                  caption.trim().isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(caption.trim()),
              ],
              const SizedBox(height: 28),
              Divider(color: accent.withValues(alpha: .25)),
              const SizedBox(height: 8),
              label('蚁记 AntKeep  ·  记录微小生命的成长'),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.records, this.color);
  final List<CareRecord> records;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final values = records.map((r) => r.workerCount!.toDouble()).toList();
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final first = records.first.occurredAt.microsecondsSinceEpoch;
    final duration = math.max(
      1,
      records.last.occurredAt.microsecondsSinceEpoch - first,
    );
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x =
          4 +
          (size.width - 8) *
              (records[i].occurredAt.microsecondsSinceEpoch - first) /
              duration;
      final y = high == low
          ? size.height / 2
          : size.height -
                4 -
                (size.height - 8) * (values[i] - low) / (high - low);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.records != records || old.color != color;
}
