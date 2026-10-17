import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:shared_preferences/shared_preferences.dart';

import 'lottery_visuals.dart';

part 'lottery_page_layout.dart';

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
  final selectedCenter = selectedIndex / itemCount;
  return (currentTurns + rotationTurns + selectedCenter).roundToDouble() -
      selectedCenter;
}

class LotteryPage extends StatefulWidget {
  const LotteryPage({super.key});

  @override
  State<LotteryPage> createState() => _LotteryPageState();
}

class _LotteryPageState extends State<LotteryPage>
    with TickerProviderStateMixin {
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
  late final AnimationController _confettiController;
  Animation<double> _rotation = const AlwaysStoppedAnimation(0);
  SharedPreferences? _preferences;
  var _spinSeconds = 4;
  var _spinSpeed = 2;
  var _directSeconds = 4;
  var _directSpeed = 2;
  var _settingsReady = false;
  var _savingSettings = false;
  final _startController = TextEditingController(text: '1');
  final _endController = TextEditingController(text: '100');
  final _random = Random();
  var _mode = _LotteryMode.wheel;
  var _wheelNumbers = List<int>.generate(100, (index) => index + 1);
  var _wheelGenerated = false;
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
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    var seconds = 4;
    var speed = 2;
    var directSeconds = 4;
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
    _confettiController.dispose();
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
      _wheelGenerated = true;
      _wheelNumbers = shuffledLotteryRange(
        range.start,
        range.start + range.count - 1,
        random: _random,
      );
    });
  }

  Future<void> _spinWheel() async {
    if (_isDrawing || !_settingsReady || _savingSettings) return;
    final range = _validatedRange();
    if (range == null) return;
    if (_wheelNumbers.length != range.count ||
        _wheelNumbers.any(
          (number) =>
              number < range.start || number >= range.start + range.count,
        )) {
      _wheelNumbers = shuffledLotteryRange(
        range.start,
        range.start + range.count - 1,
        random: _random,
      );
      _wheelGenerated = true;
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
    _confettiController.forward(from: 0);
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

  void _selectMode(_LotteryMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _result = null;
    });
  }

  void _selectPauseMode(_PauseMode mode) {
    setState(() => _pauseMode = mode);
  }

  @override
  Widget build(BuildContext context) => _buildLotteryPage(context);
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
      ..strokeWidth = numbers.length > 20 ? 0.55 : 1.3
      ..color = const Color(0xFF142540);

    if (numbers.isEmpty) {
      fill.color = const Color(0xFF122747);
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, border);
      _paintText(canvas, '待抽奖', center, lotteryText, 20);
      return;
    }

    final sweep = 2 * pi / numbers.length;
    for (var index = 0; index < numbers.length; index++) {
      final startAngle = -pi / 2 - sweep / 2 + index * sweep;
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
    fill.color = const Color(0xFF071425);
    canvas.drawCircle(center, radius * 0.15, fill);
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
          fontSize: 13,
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

  Color _labelColor(int index) => Colors.white;

  Color _segmentColor(int index, int count) {
    final hue = (index * 360 / count + 350) % 360;
    return HSLColor.fromAHSL(1, hue, 0.88, 0.54).toColor();
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
