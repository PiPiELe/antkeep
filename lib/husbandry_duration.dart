import 'dart:async';

import 'package:flutter/material.dart';

import 'domain/models.dart';

class HusbandryDuration extends StatefulWidget {
  const HusbandryDuration({
    super.key,
    required this.colony,
    this.expanded = false,
  });

  final Colony colony;
  final bool expanded;

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
    return Container(
      width: widget.expanded ? double.infinity : null,
      padding: EdgeInsets.all(widget.expanded ? 16 : 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
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
              '入手日期：${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
