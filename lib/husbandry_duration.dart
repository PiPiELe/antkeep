import 'dart:async';

import 'package:flutter/material.dart';

import 'domain/models.dart';
import 'date_display.dart';
import 'widgets/justified_label.dart';

class HusbandryDuration extends StatefulWidget {
  const HusbandryDuration({
    super.key,
    required this.colony,
    this.expanded = false,
    this.showAcquiredDate = false,
    this.labelWidth,
    this.compactStacked = false,
    this.onTap,
  });

  final Colony colony;
  final bool expanded;
  final bool showAcquiredDate;
  final double? labelWidth;
  final bool compactStacked;
  final VoidCallback? onTap;

  @override
  State<HusbandryDuration> createState() => _HusbandryDurationState();
}

class _HusbandryDurationState extends State<HusbandryDuration>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(midnight.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleRefresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _scheduleRefresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = widget.colony.husbandryDays(DateTime.now());
    final start = widget.colony.acquiredOn;
    if (!widget.expanded) {
      if (days == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .6),
            ),
            const SizedBox(height: 6),
            Text(
              '入手日期待补充',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      }
      Widget duration = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text.rich(
          TextSpan(
            children: [
              if (widget.labelWidth == null) const TextSpan(text: '已养殖 '),
              TextSpan(
                text: '$days',
                style: TextStyle(
                  fontSize: widget.compactStacked ? 42 : 72,
                  height: 1,
                  letterSpacing: widget.compactStacked ? -1 : -3,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const TextSpan(text: ' 天'),
            ],
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
      if (widget.labelWidth != null) {
        duration = Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            JustifiedLabel(
              text: '已养殖',
              width: widget.labelWidth!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Expanded(child: duration),
          ],
        );
      }
      if (!widget.showAcquiredDate || start == null) return duration;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          duration,
          const SizedBox(height: 4),
          Text(
            '入手日期：${dottedDate(start)}',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: widget.expanded ? double.infinity : null,
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(widget.expanded ? 16 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: days == null
                        ? [const TextSpan(text: '补充入手日期后显示养殖天数')]
                        : [
                            const TextSpan(text: '已养殖 '),
                            TextSpan(
                              text: '$days',
                              style: TextStyle(
                                fontSize: widget.expanded ? 36 : 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: ' 天'),
                          ],
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                if (widget.expanded && start != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '入手日期：${dottedDate(start)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
