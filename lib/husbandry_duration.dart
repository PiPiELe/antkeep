import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain/models.dart';
import 'date_display.dart';
import 'widgets/justified_label.dart';

class HusbandryDuration extends StatefulWidget {
  const HusbandryDuration({
    super.key,
    required this.colony,
    this.expanded = false,
    this.compact = false,
    this.rightVerticalLabel = false,
    this.stackedLabel = false,
    this.showAcquiredDate = false,
    this.labelWidth,
    this.onTap,
  });

  final Colony colony;
  final bool expanded;
  final bool compact;
  final bool rightVerticalLabel;
  final bool stackedLabel;
  final bool showAcquiredDate;
  final double? labelWidth;
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
      if (widget.stackedLabel) {
        final numberStyle = TextStyle(
          fontSize: widget.compact ? 42 : 84,
          height: 1,
          letterSpacing: -3,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        );
        final unitStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        Size measureDuration(String number) {
          final painter = TextPainter(
            text: TextSpan(
              style: unitStyle,
              children: [
                TextSpan(text: number, style: numberStyle),
                const TextSpan(text: ' 天'),
              ],
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final size = painter.size;
          painter.dispose();
          return size;
        }

        // Use the requested three-digit appearance as a minimum width while
        // keeping longer or wider values on one line.
        final targetSize = measureDuration('167');
        final actualSize = measureDuration('$days');
        final referenceSize = Size(
          math.max(targetSize.width, actualSize.width),
          math.max(targetSize.height, actualSize.height),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '已养殖',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width: math.min(constraints.maxWidth, referenceSize.width),
                height: referenceSize.height,
                child: FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: referenceSize.width,
                    height: referenceSize.height,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$days', style: numberStyle),
                            const TextSpan(text: ' 天'),
                          ],
                        ),
                        style: unitStyle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      if (widget.rightVerticalLabel) {
        if ('$days'.length >= 4) {
          return LayoutBuilder(
            builder: (context, constraints) => Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '已养殖',
                      key: const ValueKey('duration-right-label'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(0, constraints.maxWidth - 8),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$days',
                                style: TextStyle(
                                  fontSize: 52,
                                  height: 1,
                                  letterSpacing: -2,
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : 92.0;
            final numberStyle = TextStyle(
              fontSize: 160,
              height: .9,
              letterSpacing: -2,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            );
            final labelStyle = theme.textTheme.bodySmall?.copyWith(
              fontSize: 14,
              height: 1,
              color: theme.colorScheme.onSurfaceVariant,
            );
            final unitStyle = theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            );
            TextPainter measure(String text, TextStyle? style) => TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final numberSize = measure('$days', numberStyle);
            final labelSize = measure('已\n养\n殖', labelStyle);
            final unitSize = measure('天', unitStyle);
            final sideWidth = math.max(labelSize.width, unitSize.width);
            final numberWidth = math.max(
              1.0,
              constraints.maxWidth - 20 - sideWidth,
            );
            final numberScale = math.min(
              1.0,
              math.min(
                numberWidth / numberSize.width,
                height / numberSize.height,
              ),
            );
            final numberHeight = numberSize.height * numberScale;
            final numberTop = (height - numberHeight) / 2;
            final unitTop = numberTop + numberHeight - unitSize.height - 10;
            final labelTop = math.max(
              0.0,
              math.min(numberTop + 12, unitTop - labelSize.height - 10),
            );
            final labelSpace = math.max(1.0, unitTop - labelTop - 10);
            numberSize.dispose();
            labelSize.dispose();
            unitSize.dispose();
            return SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text('$days', style: numberStyle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: sideWidth,
                    child: Stack(
                      children: [
                        Positioned(
                          top: labelTop,
                          left: 0,
                          right: 0,
                          height: labelSpace,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '已\n养\n殖',
                                key: const ValueKey('duration-right-label'),
                                semanticsLabel: '已养殖',
                                textAlign: TextAlign.center,
                                style: labelStyle,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: unitTop,
                          left: 0,
                          right: 0,
                          child: Text(
                            '天',
                            textAlign: TextAlign.center,
                            style: unitStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
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
                  fontSize: widget.compact ? 42 : 72,
                  height: 1,
                  letterSpacing: widget.compact ? -1 : -3,
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
