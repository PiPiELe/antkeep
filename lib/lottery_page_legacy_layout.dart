part of 'lottery_page.dart';

extension _LegacyLotteryLayout on _LotteryPageState {
  Widget _lotterySettingDropdown({
    required String label,
    required String preferenceKey,
    required int value,
    required Map<int, String> options,
    bool available = true,
  }) {
    final enabled =
        available && !_isDrawing && _settingsReady && !_savingSettings;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        enabled: enabled,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: ValueKey(preferenceKey),
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (final option in options.entries)
              DropdownMenuItem(value: option.key, child: Text(option.value)),
          ],
          onChanged: enabled
              ? (value) => _saveSetting(preferenceKey, value)
              : null,
        ),
      ),
    );
  }

  Widget _buildLegacyLotteryPage(BuildContext context) {
    final isWheel = _mode == _LotteryMode.wheel;
    final wheelDiameter = min(MediaQuery.sizeOf(context).width - 32, 420.0);
    final resultDiameter =
        wheelDiameter *
        (0.30 + max(0, (_result?.toString().length ?? 0) - 3) * 0.025).clamp(
          0.30,
          0.46,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('数字抽奖')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '选定一个数字范围，随机抽出幸运数字。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          SegmentedButton<_LotteryMode>(
            segments: const [
              ButtonSegment(
                value: _LotteryMode.wheel,
                icon: Icon(Icons.casino_outlined),
                label: Text('转盘抽奖'),
              ),
              ButtonSegment(
                value: _LotteryMode.direct,
                icon: Icon(Icons.numbers_outlined),
                label: Text('数字跳动'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _isDrawing
                ? null
                : (selection) {
                    _refreshLegacy(() {
                      _mode = selection.first;
                      _error = null;
                      _result = null;
                    });
                  },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _lotterySettingDropdown(
                  label: isWheel ? '旋转时长' : '跳动时长',
                  available: isWheel || _pauseMode == _PauseMode.automatic,
                  preferenceKey: isWheel
                      ? _LotteryPageState._durationKey
                      : _LotteryPageState._directDurationKey,
                  value: isWheel ? _spinSeconds : _directSeconds,
                  options: {
                    for (final seconds in _LotteryPageState._durationOptions)
                      seconds: '$seconds 秒',
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _lotterySettingDropdown(
                  label: isWheel ? '转速' : '跳动速度',
                  preferenceKey: isWheel
                      ? _LotteryPageState._speedKey
                      : _LotteryPageState._directSpeedKey,
                  value: isWheel ? _spinSpeed : _directSpeed,
                  options: _LotteryPageState._speedOptions,
                ),
              ),
            ],
          ),
          if (_mode == _LotteryMode.direct) ...[
            const SizedBox(height: 16),
            SegmentedButton<_PauseMode>(
              segments: const [
                ButtonSegment(value: _PauseMode.automatic, label: Text('自动暂停')),
                ButtonSegment(value: _PauseMode.manual, label: Text('手动暂停')),
              ],
              selected: {_pauseMode},
              onSelectionChanged: _isRolling
                  ? null
                  : (selection) => _refreshLegacy(() {
                      _pauseMode = selection.first;
                    }),
            ),
            const SizedBox(height: 8),
            Text(
              _pauseMode == _PauseMode.automatic
                  ? '开始后数字持续随机跳动，$_directSeconds 秒后自动暂停。'
                  : '手动模式不限制时长，点击暂停确定结果。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startController,
                  enabled: !_isDrawing,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '起始数字',
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('至'),
              ),
              Expanded(
                child: TextField(
                  controller: _endController,
                  enabled: !_isDrawing,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '结束数字',
                  ),
                ),
              ),
            ],
          ),
          if (_mode == _LotteryMode.wheel) ...[
            const SizedBox(height: 10),
            Text(
              '转盘支持 2–100 个数字；每次都会随机打乱数字位置。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _mode == _LotteryMode.wheel
                ? (_isSpinning ? null : _generateWheel)
                : _isRolling
                ? (_pauseMode == _PauseMode.manual ? _pauseDirect : null)
                : (_settingsReady && !_savingSettings ? _drawDirect : null),
            icon: Icon(
              _mode == _LotteryMode.wheel
                  ? Icons.cached_rounded
                  : _isRolling
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            label: Text(
              _mode == _LotteryMode.wheel
                  ? '生成转盘'
                  : _isRolling
                  ? (_pauseMode == _PauseMode.manual ? '暂停' : '数字跳动中…')
                  : '开始抽奖',
            ),
          ),
          if (_mode == _LotteryMode.wheel) ...[
            const SizedBox(height: 28),
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  RotationTransition(
                    key: const ValueKey('lottery-rotation'),
                    turns: _rotation,
                    child: CustomPaint(
                      key: const ValueKey('lottery-wheel'),
                      size: Size.square(wheelDiameter),
                      painter: _LegacyLotteryWheelPainter(
                        numbers: _wheelGenerated ? _wheelNumbers : const [],
                        colorScheme: Theme.of(context).colorScheme,
                        labelStyle: Theme.of(context).textTheme.bodySmall!,
                      ),
                    ),
                  ),
                  if (_result != null)
                    SizedBox.square(
                      dimension: resultDiameter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.3, end: 1),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: Container(
                          key: const ValueKey('lottery-wheel-result'),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '抽中数字',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$_result',
                                    key: const ValueKey('lottery-number'),
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: -22,
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 44,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              !_wheelGenerated ? '输入范围后转动转盘。' : '转盘数字已随机打乱。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_wheelGenerated) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSpinning || !_settingsReady || _savingSettings
                    ? null
                    : _spinWheel,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_isSpinning ? '转盘转动中…' : '转动转盘'),
              ),
            ],
          ],
          if (_mode == _LotteryMode.direct &&
              (_result != null || _isRolling)) ...[
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      _isRolling ? '随机跳动中' : '抽中数字',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.65, end: 1),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Text(
                        '${_isRolling ? _rollingNumber : _result}',
                        key: const ValueKey('lottery-number'),
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 76,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegacyLotteryWheelPainter extends CustomPainter {
  const _LegacyLotteryWheelPainter({
    required this.numbers,
    required this.colorScheme,
    required this.labelStyle,
  });

  final List<int> numbers;
  final ColorScheme colorScheme;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = numbers.length > 20 ? 0.6 : 2
      ..color = colorScheme.outlineVariant;

    if (numbers.isEmpty) {
      fill.color = colorScheme.surfaceContainerHighest;
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, border);
      _paintText(canvas, '等待抽奖', center, colorScheme.onSurfaceVariant, 20);
      return;
    }

    final sweep = 2 * pi / numbers.length;
    for (var index = 0; index < numbers.length; index++) {
      final startAngle = -pi / 2 + index * sweep;
      fill.color = _segmentColor(index, numbers.length);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        true,
        fill,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        true,
        border,
      );
      final labelAngle = startAngle + sweep / 2;
      if (numbers.length > 20) {
        _paintRadialLabel(canvas, center, radius, labelAngle, sweep, index);
      } else {
        final labelCenter =
            center + Offset(cos(labelAngle), sin(labelAngle)) * (radius * 0.78);
        canvas.save();
        canvas.translate(labelCenter.dx, labelCenter.dy);
        canvas.rotate(labelAngle + pi / 2);
        _paintText(
          canvas,
          '${numbers[index]}',
          Offset.zero,
          _labelColor(index),
          min(26, max(8, 180 / numbers.length)),
          maxWidth: radius * min(0.8, sweep * 0.62),
          maxHeight: radius * 0.25,
        );
        canvas.restore();
      }
    }
    fill.color = colorScheme.surface;
    canvas.drawCircle(center, radius * 0.16, fill);
    canvas.drawCircle(center, radius * 0.16, border);
  }

  void _paintRadialLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    double sweep,
    int index,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: '${numbers[index]}',
        style: labelStyle.copyWith(
          color: _labelColor(index),
          fontSize: 14,
          height: 1,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Fit the full label inside the wedge, including at its narrow inner end.
    final halfSweep = tan(sweep / 2) * 0.85;
    final outerRadius = radius * 0.93;
    final scale = min(
      1.0,
      min(
        radius * 0.42 / painter.width,
        2 *
            outerRadius *
            halfSweep /
            (painter.height + 2 * painter.width * halfSweep),
      ),
    );
    final labelRadius = outerRadius - painter.width * scale / 2;
    final labelCenter = center + Offset(cos(angle), sin(angle)) * labelRadius;
    canvas.save();
    canvas.translate(labelCenter.dx, labelCenter.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    painter.paint(canvas, -painter.size.center(Offset.zero));
    canvas.restore();
    painter.dispose();
  }

  Color _labelColor(int index) =>
      _segmentColor(index, numbers.length).computeLuminance() > 0.4
      ? Colors.black87
      : Colors.white;

  Color _segmentColor(int index, int count) {
    final hue = (index * 360 / count + 330) % 360;
    return HSLColor.fromAHSL(1, hue, 0.67, 0.52).toColor();
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size, {
    double maxWidth = double.infinity,
    double maxHeight = double.infinity,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final scale = min(
      1.0,
      min(maxWidth / painter.width, maxHeight / painter.height),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    painter.paint(canvas, -painter.size.center(Offset.zero));
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(_LegacyLotteryWheelPainter oldDelegate) =>
      oldDelegate.numbers != numbers ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.labelStyle != labelStyle;
}
