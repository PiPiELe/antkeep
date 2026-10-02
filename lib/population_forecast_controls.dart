import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain/population_forecast.dart';

class PopulationForecastControls extends StatelessWidget {
  const PopulationForecastControls({
    super.key,
    required this.enabled,
    required this.horizon,
    required this.onEnabledChanged,
    required this.onHorizonChanged,
    this.unavailableReason,
    this.onConfigureGrowth,
  });
  final bool enabled;
  final ForecastHorizon horizon;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<ForecastHorizon> onHorizonChanged;
  final String? unavailableReason;
  final VoidCallback? onConfigureGrowth;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (unavailableReason != null && onConfigureGrowth != null)
        ListTile(
          key: const ValueKey('population-forecast-setup'),
          contentPadding: EdgeInsets.zero,
          title: const Text('增长预测'),
          subtitle: Text(unavailableReason!),
          onTap: onConfigureGrowth,
          trailing: TextButton(
            onPressed: onConfigureGrowth,
            child: const Text('设置规则'),
          ),
        )
      else
        SwitchListTile.adaptive(
          key: const ValueKey('population-forecast-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('增长预测'),
          subtitle: Text(unavailableReason ?? '按自动扩充规则预测，最长 1 个月'),
          value: enabled && unavailableReason == null,
          onChanged: unavailableReason == null ? onEnabledChanged : null,
        ),
      if (enabled && unavailableReason == null) ...[
        Wrap(
          spacing: 8,
          children: [
            for (final value in ForecastHorizon.values)
              ChoiceChip(
                label: Text(value.label),
                selected: horizon == value,
                onSelected: (_) => onHorizonChanged(value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('实线：已有记录 · 虚线：增长预测（不写入记录）'),
      ],
    ],
  );
}

/// Both charts share the same forecast styling; the first forecast point is now.
void drawPopulationSeries(
  Canvas canvas,
  List<Offset> locations,
  int historyCount,
  ColorScheme colors,
) {
  for (var i = 1; i < locations.length; i++) {
    final forecast = i >= historyCount;
    final paint = Paint()
      ..color = forecast ? colors.tertiary : colors.primary
      ..strokeWidth = 2.5;
    final from = locations[i - 1];
    final to = locations[i];
    if (!forecast) {
      canvas.drawLine(from, to, paint);
      continue;
    }
    final distance = (to - from).distance;
    for (var step = 0.0; step < distance; step += 9) {
      canvas.drawLine(
        Offset.lerp(from, to, step / distance)!,
        Offset.lerp(from, to, math.min(step + 5, distance) / distance)!,
        paint,
      );
    }
  }
  for (var i = 0; i < locations.length; i++) {
    canvas.drawCircle(
      locations[i],
      i < historyCount ? 3.5 : 2.5,
      Paint()..color = i < historyCount ? colors.primary : colors.tertiary,
    );
  }
}
