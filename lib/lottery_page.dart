import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _LotteryMode { wheel, direct }

enum _PauseMode { automatic, manual }

/// Returns every integer in the inclusive range in a non-sequential order.
///
/// A wheel with more than one option must never look like an ordered number
/// line, even when the random shuffle happens to retain the original order.
List<int> shuffledLotteryRange(int start, int end, {Random? random}) {
  if (start > end) {
    throw ArgumentError.value(end, 'end', 'must not be smaller than start');
  }

  final numbers = List<int>.generate(end - start + 1, (index) => start + index);
  numbers.shuffle(random);
  if (numbers.length > 1 &&
      numbers.every((number) => number == start + numbers.indexOf(number))) {
    return numbers.reversed.toList();
  }
  return numbers;
}

/// Calculates a forward rotation that leaves [selectedIndex] under the
/// fixed, top-mounted pointer.
double wheelTurnsForSelectedIndex({
  required double currentTurns,
  required int selectedIndex,
  required int itemCount,
  double rotationTurns = 3,
}) {
  final selectedCenter = (selectedIndex + 0.5) / itemCount;
  return (currentTurns + rotationTurns + selectedCenter).roundToDouble() -
      selectedCenter;
}

class LotteryPage extends StatefulWidget {
  const LotteryPage({super.key});

  @override
  State<LotteryPage> createState() => _LotteryPageState();
}

class _LotteryPageState extends State<LotteryPage>
    with SingleTickerProviderStateMixin {
  static const _durationOptions = [4, 6, 8, 10];
  static const _durationKey = 'lottery_wheel_seconds';
  static const _speedKey = 'lottery_wheel_speed';
  static const _directDurationKey = 'lottery_direct_seconds';
  static const _directSpeedKey = 'lottery_direct_speed';
  static const _rollingIntervals = {1: 200, 2: 100, 3: 40};
  static const _speedOptions = {1: '慢速', 2: '中速', 3: '快速'};
  // Match the previous 3 turns / 6 seconds and original 5 turns / 2.2 seconds.
  static const _turnsPerSecond = {1: 0.25, 2: 0.5, 3: 5 / 2.2};
  late final AnimationController _spinController;
  Animation<double> _rotation = const AlwaysStoppedAnimation(0);
  SharedPreferences? _preferences;
  var _spinSeconds = 6;
  var _spinSpeed = 2;
  var _directSeconds = 6;
  var _directSpeed = 2;
  var _settingsReady = false;
  var _savingSettings = false;
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final _random = Random();
  var _mode = _LotteryMode.wheel;
  var _wheelNumbers = const <int>[];
  var _wheelTurns = 0.0;
  var _isSpinning = false;
  var _pauseMode = _PauseMode.automatic;
  var _isRolling = false;
  Timer? _rollingTimer;
  Timer? _pauseTimer;
  int? _rollingNumber;
  int? _result;
  String? _error;

  bool get _isDrawing => _isSpinning || _isRolling;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    var seconds = 6;
    var speed = 2;
    var directSeconds = 6;
    var directSpeed = 2;
    try {
      _preferences = await SharedPreferences.getInstance();
      final saved = _preferences!.getInt(_durationKey);
      if (_durationOptions.contains(saved)) seconds = saved!;
      final savedSpeed = _preferences!.getInt(_speedKey);
      if (_speedOptions.containsKey(savedSpeed)) speed = savedSpeed!;
      final savedDirectSeconds = _preferences!.getInt(_directDurationKey);
      if (_durationOptions.contains(savedDirectSeconds)) {
        directSeconds = savedDirectSeconds!;
      }
      final savedDirectSpeed = _preferences!.getInt(_directSpeedKey);
      if (_speedOptions.containsKey(savedDirectSpeed)) {
        directSpeed = savedDirectSpeed!;
      }
    } catch (_) {
      // Keep defaults when local preferences cannot be read.
    }
    if (!mounted) return;
    setState(() {
      _spinSeconds = seconds;
      _spinSpeed = speed;
      _directSeconds = directSeconds;
      _directSpeed = directSpeed;
      _settingsReady = true;
    });
  }

  Future<void> _saveSetting(String key, int? value) async {
    if (value == null || _isDrawing || _savingSettings) return;
    setState(() => _savingSettings = true);
    try {
      final preferences = _preferences ?? await SharedPreferences.getInstance();
      if (!await preferences.setInt(key, value)) {
        throw StateError('Lottery setting was not saved');
      }
      if (!mounted) return;
      setState(() {
        if (key == _durationKey) _spinSeconds = value;
        if (key == _speedKey) _spinSpeed = value;
        if (key == _directDurationKey) _directSeconds = value;
        if (key == _directSpeedKey) _directSpeed = value;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('抽奖设置保存失败，请重试。')));
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _rollingTimer?.cancel();
    _pauseTimer?.cancel();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  ({int start, int count})? _validatedRange() {
    final start = int.tryParse(_startController.text.trim());
    final end = int.tryParse(_endController.text.trim());
    if (start == null || end == null || start > end) {
      setState(() {
        _error = '请输入有效的数字范围，且起始数字不能大于结束数字。';
        _result = null;
      });
      return null;
    }

    final count = end - start + 1;
    const maxRandomRange = 4294967296;
    if (count > maxRandomRange) {
      setState(() {
        _error = '数字范围过大，请输入不超过 42 亿个数字的范围。';
        _result = null;
      });
      return null;
    }
    if (_mode == _LotteryMode.wheel && (count < 2 || count > 100)) {
      setState(() {
        _error = '转盘抽奖请设置 2 到 100 个数字。';
        _result = null;
      });
      return null;
    }

    return (start: start, count: count);
  }

  void _generateWheel() {
    final range = _validatedRange();
    if (range == null) return;

    setState(() {
      _error = null;
      _result = null;
      _wheelNumbers = shuffledLotteryRange(
        range.start,
        range.start + range.count - 1,
        random: _random,
      );
    });
  }

  Future<void> _spinWheel() async {
    if (_isDrawing || !_settingsReady || _savingSettings) return;
    if (_wheelNumbers.isEmpty) {
      setState(() => _error = '请先生成转盘。');
      return;
    }

    final selectedIndex = _random.nextInt(_wheelNumbers.length);
    final targetTurns = wheelTurnsForSelectedIndex(
      currentTurns: _wheelTurns,
      selectedIndex: selectedIndex,
      itemCount: _wheelNumbers.length,
      rotationTurns: _spinSeconds * _turnsPerSecond[_spinSpeed]!,
    );
    _spinController.duration = Duration(seconds: _spinSeconds);
    _rotation = Tween<double>(
      begin: _wheelTurns,
      end: targetTurns,
    ).animate(_spinController.drive(CurveTween(curve: Curves.easeOutCubic)));
    setState(() {
      _error = null;
      _result = null;
      _isSpinning = true;
      _wheelTurns = targetTurns;
    });

    try {
      await _spinController.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSpinning = false;
      _result = _wheelNumbers[selectedIndex];
    });
  }

  void _drawDirect() {
    if (_isDrawing || !_settingsReady || _savingSettings) return;
    final range = _validatedRange();
    if (range == null) return;

    setState(() {
      _error = null;
      _result = null;
      _isRolling = true;
      _rollingNumber = range.start + _random.nextInt(range.count);
    });
    _rollingTimer = Timer.periodic(
      Duration(milliseconds: _rollingIntervals[_directSpeed]!),
      (_) {
        setState(() {
          _rollingNumber = range.start + _random.nextInt(range.count);
        });
      },
    );
    if (_pauseMode == _PauseMode.automatic) {
      _pauseTimer = Timer(Duration(seconds: _directSeconds), _pauseDirect);
    }
  }

  void _pauseDirect() {
    _rollingTimer?.cancel();
    _pauseTimer?.cancel();
    setState(() {
      _isRolling = false;
      _result = _rollingNumber;
    });
  }

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

  @override
  Widget build(BuildContext context) {
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
                    setState(() {
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
                  preferenceKey: isWheel ? _durationKey : _directDurationKey,
                  value: isWheel ? _spinSeconds : _directSeconds,
                  options: {
                    for (final seconds in _durationOptions)
                      seconds: '$seconds 秒',
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _lotterySettingDropdown(
                  label: isWheel ? '转速' : '跳动速度',
                  preferenceKey: isWheel ? _speedKey : _directSpeedKey,
                  value: isWheel ? _spinSpeed : _directSpeed,
                  options: _speedOptions,
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
                  : (selection) => setState(() {
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
                      painter: _LotteryWheelPainter(
                        numbers: _wheelNumbers,
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
              _wheelNumbers.isEmpty ? '输入范围后转动转盘。' : '转盘数字已随机打乱。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_wheelNumbers.isNotEmpty) ...[
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

class _LotteryWheelPainter extends CustomPainter {
  const _LotteryWheelPainter({
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
  bool shouldRepaint(_LotteryWheelPainter oldDelegate) =>
      oldDelegate.numbers != numbers ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.labelStyle != labelStyle;
}
