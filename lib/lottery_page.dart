import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

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
}) => currentTurns.ceilToDouble() + 5 - (selectedIndex + 0.5) / itemCount;

class LotteryPage extends StatefulWidget {
  const LotteryPage({super.key});

  @override
  State<LotteryPage> createState() => _LotteryPageState();
}

class _LotteryPageState extends State<LotteryPage> {
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
  void dispose() {
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
    if (_wheelNumbers.isEmpty) {
      setState(() => _error = '请先生成转盘。');
      return;
    }

    final selectedIndex = _random.nextInt(_wheelNumbers.length);
    setState(() {
      _error = null;
      _result = null;
      _isSpinning = true;
      _wheelTurns = wheelTurnsForSelectedIndex(
        currentTurns: _wheelTurns,
        selectedIndex: selectedIndex,
        itemCount: _wheelNumbers.length,
      );
    });

    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    setState(() {
      _isSpinning = false;
      _result = _wheelNumbers[selectedIndex];
    });
  }

  void _drawDirect() {
    if (_isDrawing) return;
    final range = _validatedRange();
    if (range == null) return;

    setState(() {
      _error = null;
      _result = null;
      _isRolling = true;
      _rollingNumber = range.start + _random.nextInt(range.count);
    });
    _rollingTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      setState(() {
        _rollingNumber = range.start + _random.nextInt(range.count);
      });
    });
    if (_pauseMode == _PauseMode.automatic) {
      _pauseTimer = Timer(const Duration(seconds: 3), _pauseDirect);
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

  @override
  Widget build(BuildContext context) {
    final wheelDiameter = min(MediaQuery.sizeOf(context).width - 32, 420.0);
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
                  ? '开始后数字持续随机跳动，3 秒后自动暂停。'
                  : '开始后数字持续随机跳动，点击暂停确定结果。',
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
                : _drawDirect,
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
                alignment: Alignment.topCenter,
                children: [
                  AnimatedRotation(
                    turns: _wheelTurns,
                    duration: const Duration(milliseconds: 2200),
                    curve: Curves.easeOutCubic,
                    child: CustomPaint(
                      size: Size.square(wheelDiameter),
                      painter: _LotteryWheelPainter(
                        numbers: _wheelNumbers,
                        colorScheme: Theme.of(context).colorScheme,
                        selectedNumber: _result,
                      ),
                    ),
                  ),
                  if (_result != null)
                    Positioned(
                      top: wheelDiameter * 0.11 - 24,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.3, end: 1),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: Container(
                          constraints: BoxConstraints(
                            minWidth: 48,
                            maxWidth: wheelDiameter * 0.8,
                          ),
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(24),
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
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$_result',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: -8,
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
                onPressed: _isSpinning ? null : _spinWheel,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_isSpinning ? '转盘转动中…' : '转动转盘'),
              ),
            ],
          ],
          if (_result != null || _isRolling) ...[
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
    this.selectedNumber,
  });

  final List<int> numbers;
  final ColorScheme colorScheme;
  final int? selectedNumber;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
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
      if (numbers[index] == selectedNumber) continue;
      final labelAngle = startAngle + sweep / 2;
      final labelCenter =
          center + Offset(cos(labelAngle), sin(labelAngle)) * (radius * 0.78);
      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(labelAngle + pi / 2);
      _paintText(
        canvas,
        '${numbers[index]}',
        Offset.zero,
        Colors.white,
        min(26, max(8, 180 / numbers.length)),
      );
      canvas.restore();
    }
    fill.color = colorScheme.surface;
    canvas.drawCircle(center, radius * 0.16, fill);
    canvas.drawCircle(center, radius * 0.16, border);
  }

  Color _segmentColor(int index, int count) {
    final hue = (index * 360 / count + 330) % 360;
    return HSLColor.fromAHSL(1, hue, 0.67, 0.52).toColor();
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - painter.size.center(Offset.zero));
  }

  @override
  bool shouldRepaint(_LotteryWheelPainter oldDelegate) =>
      oldDelegate.numbers != numbers ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.selectedNumber != selectedNumber;
}
