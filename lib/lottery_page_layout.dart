part of 'lottery_page.dart';

extension _LotteryPageLayout on _LotteryPageState {
  Widget _buildLotteryPage(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wheel = _mode == _LotteryMode.wheel;
        final wheelDiameter = min(constraints.maxWidth * .70, 420.0);
        return Scaffold(
          backgroundColor: lotteryBackground,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            toolbarHeight: 50,
            backgroundColor: Colors.transparent,
            foregroundColor: lotteryText,
            centerTitle: true,
            title: const Text(
              '数字抽奖',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 14),
                child: Center(
                  child: Text(
                    '小小数字\n也有大惊喜',
                    style: TextStyle(color: Color(0xFF5E769B), fontSize: 9),
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/lottery-night-background.png',
                  fit: BoxFit.fill,
                ),
              ),
              ListView(
                scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top + 58,
                  24,
                  24,
                ),
                children: [
                  const Text(
                    '选定一个数字范围，随机抽出幸运数字。',
                    style: TextStyle(color: lotteryText, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  _switch<_LotteryMode>(
                    selected: _mode,
                    enabled: !_isDrawing,
                    choices: const [
                      (_LotteryMode.wheel, '转盘抽奖', Icons.blur_circular_rounded),
                      (_LotteryMode.direct, '数字跳动', Icons.tag_rounded),
                    ],
                    onSelect: _selectMode,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                    decoration: BoxDecoration(
                      color: const Color(0xBC13253D),
                      border: Border.all(color: const Color(0xFF263E64)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _settingDropdown(
                                label: wheel ? '旋转时长' : '跳动时长',
                                icon: Icons.access_time_rounded,
                                preferenceKey: wheel
                                    ? _LotteryPageState._durationKey
                                    : _LotteryPageState._directDurationKey,
                                value: wheel ? _spinSeconds : _directSeconds,
                                options: {
                                  for (final seconds
                                      in _LotteryPageState._durationOptions)
                                    seconds: '$seconds 秒',
                                },
                                available:
                                    wheel || _pauseMode == _PauseMode.automatic,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _settingDropdown(
                                label: wheel ? '转速' : '跳动速度',
                                icon: Icons.speed_rounded,
                                preferenceKey: wheel
                                    ? _LotteryPageState._speedKey
                                    : _LotteryPageState._directSpeedKey,
                                value: wheel ? _spinSpeed : _directSpeed,
                                options: _LotteryPageState._speedOptions,
                              ),
                            ),
                          ],
                        ),
                        if (!wheel) ...[
                          const SizedBox(height: 10),
                          _switch<_PauseMode>(
                            selected: _pauseMode,
                            enabled: !_isRolling,
                            choices: const [
                              (
                                _PauseMode.automatic,
                                '自动暂停',
                                Icons.access_time_rounded,
                              ),
                              (
                                _PauseMode.manual,
                                '手动暂停',
                                Icons.pan_tool_alt_outlined,
                              ),
                            ],
                            onSelect: _selectPauseMode,
                          ),
                          const SizedBox(height: 6),
                          _info(
                            _pauseMode == _PauseMode.automatic
                                ? '开始后数字持续随机跳动，$_directSeconds 秒后自动暂停。'
                                : '手动模式不限制时长，点击暂停确定结果。',
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _rangeField(
                                '开始数字',
                                Icons.play_arrow_outlined,
                                _startController,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _rangeField(
                                '结束数字',
                                Icons.flag_outlined,
                                _endController,
                              ),
                            ),
                          ],
                        ),
                        if (wheel) ...[
                          const SizedBox(height: 8),
                          _info('支持 2–100 个数字，生成后会随机打乱数字顺序。'),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF9AA5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _actionButton(
                    label: wheel
                        ? '生成转盘'
                        : _isRolling
                        ? (_pauseMode == _PauseMode.manual ? '暂停' : '数字跳动中…')
                        : _result == null
                        ? '开始抽奖'
                        : '重新抽取',
                    icon: wheel || (_result != null && !_isRolling)
                        ? Icons.autorenew_rounded
                        : _isRolling
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    enabled: wheel
                        ? !_isSpinning
                        : !_isRolling || _pauseMode == _PauseMode.manual,
                    onPressed: wheel
                        ? _generateWheel
                        : _isRolling
                        ? _pauseDirect
                        : _drawDirect,
                  ),
                  if (wheel) ...[
                    const SizedBox(height: 10),
                    _wheelDisplay(wheelDiameter),
                    const SizedBox(height: 10),
                    _hint(_wheelGenerated ? '转盘数字已随机打乱。' : '点击开始后，转盘将按设定时长旋转。'),
                    const SizedBox(height: 10),
                    _actionButton(
                      label: _isSpinning
                          ? '转盘转动中…'
                          : _result == null
                          ? '开始转动'
                          : '再次转动',
                      icon: Icons.play_arrow_rounded,
                      enabled:
                          !_isSpinning && _settingsReady && !_savingSettings,
                      onPressed: _spinWheel,
                      tall: true,
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    _directResultCard(),
                    const SizedBox(height: 10),
                    _hint(
                      _isRolling
                          ? '数字正在随机跳动。'
                          : _result == null
                          ? '每一个数字，都是一份小小的期待。'
                          : '结果已生成，可重新抽取。',
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _switch<T>({
    required T selected,
    required bool enabled,
    required List<(T, String, IconData)> choices,
    required ValueChanged<T> onSelect,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF14243A),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFF405B88), width: 1.2),
      ),
      child: Row(
        children: [
          for (final choice in choices)
            Expanded(
              child: InkWell(
                onTap: enabled ? () => onSelect(choice.$1) : null,
                borderRadius: BorderRadius.circular(22),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: selected == choice.$1
                        ? const LinearGradient(
                            colors: [Color(0xFF75C3FF), Color(0xFF3265E7)],
                          )
                        : null,
                    boxShadow: selected == choice.$1
                        ? [
                            const BoxShadow(
                              color: Color(0x884E91FF),
                              blurRadius: 13,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        choice.$3,
                        size: 20,
                        color: selected == choice.$1
                            ? Colors.white
                            : lotteryMuted,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          choice.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected == choice.$1
                                ? Colors.white
                                : lotteryMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _settingDropdown({
    required String label,
    required IconData icon,
    required String preferenceKey,
    required int value,
    required Map<int, String> options,
    bool available = true,
  }) {
    final enabled =
        available && !_isDrawing && _settingsReady && !_savingSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, icon),
        const SizedBox(height: 4),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: _fieldDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: ValueKey(preferenceKey),
              value: value,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF162D4D),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: enabled ? lotteryText : lotteryMuted,
                fontSize: 15,
              ),
              iconEnabledColor: lotteryMuted,
              items: [
                for (final option in options.entries)
                  DropdownMenuItem(
                    value: option.key,
                    child: Text(option.value),
                  ),
              ],
              onChanged: enabled
                  ? (value) => _saveSetting(preferenceKey, value)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _rangeField(
    String label,
    IconData icon,
    TextEditingController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, icon),
        const SizedBox(height: 4),
        Container(
          height: 34,
          decoration: _fieldDecoration(),
          child: TextField(
            controller: controller,
            enabled: !_isDrawing,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            style: const TextStyle(color: lotteryText, fontSize: 16),
            cursorColor: lotteryBlue,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(11, 7, 8, 8),
              isDense: true,
              suffixIcon: Icon(
                Icons.arrow_drop_down_rounded,
                color: lotteryMuted,
              ),
              suffixIconConstraints: BoxConstraints(
                minWidth: 29,
                minHeight: 29,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label, IconData icon) => Row(
    children: [
      Icon(icon, size: 18, color: lotteryMuted),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(color: lotteryMuted, fontSize: 12),
        ),
      ),
    ],
  );

  BoxDecoration _fieldDecoration() => BoxDecoration(
    color: const Color(0xFF0D1B2E),
    borderRadius: BorderRadius.circular(7),
    border: Border.all(color: const Color(0xFF4A648C)),
  );

  Widget _info(String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.info_outline_rounded, size: 16, color: lotteryMuted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(color: lotteryMuted, fontSize: 11),
        ),
      ),
    ],
  );

  Widget _hint(String value) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(
        Icons.lightbulb_outline_rounded,
        color: lotteryMuted,
        size: 18,
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(color: lotteryMuted, fontSize: 12),
        ),
      ),
    ],
  );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
    bool tall = false,
  }) => SizedBox(
    height: tall ? 44 : 38,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: enabled
            ? const LinearGradient(
                colors: [Color(0xFF79C6FF), Color(0xFF3165EF)],
              )
            : const LinearGradient(
                colors: [Color(0xFF283C5A), Color(0xFF1B2F4E)],
              ),
        border: Border.all(
          color: enabled ? const Color(0xFF9DDBFF) : const Color(0xFF405575),
        ),
        boxShadow: enabled
            ? const [
                BoxShadow(
                  color: Color(0x664478FF),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: enabled ? onPressed : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _wheelDisplay(double diameter) {
    return Center(
      child: SizedBox(
        width: diameter + 16,
        height: diameter + 24,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: diameter + 8,
              height: diameter + 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF5798FF), width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0xAA3978EE), blurRadius: 18),
                ],
              ),
            ),
            SizedBox.square(
              dimension: diameter,
              child: RotationTransition(
                key: const ValueKey('lottery-rotation'),
                turns: _rotation,
                child: CustomPaint(
                  key: const ValueKey('lottery-wheel'),
                  size: Size.square(diameter),
                  painter: _LotteryWheelPainter(
                    numbers: _wheelNumbers,
                    colorScheme: Theme.of(context).colorScheme,
                    labelStyle: Theme.of(context).textTheme.bodySmall!,
                  ),
                ),
              ),
            ),
            Container(
              key: _result == null
                  ? null
                  : const ValueKey('lottery-wheel-result'),
              width: diameter * .30,
              height: diameter * .30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF1E3151), Color(0xFF071427)],
                ),
                border: Border.all(
                  color: _result == null
                      ? const Color(0xFF5B95F3)
                      : const Color(0xFFFFDC6E),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _result == null
                        ? const Color(0xFF4B8BFF)
                        : const Color(0xFFFFC74F),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LotteryAntEmblem(
                    size: diameter * .06,
                    color: const Color(0xFF34517F),
                  ),
                  Text(
                    _result == null ? '待抽奖' : '抽中数字',
                    style: const TextStyle(color: lotteryText, fontSize: 9),
                  ),
                  if (_result != null)
                    FittedBox(
                      child: Text(
                        '$_result',
                        key: const ValueKey('lottery-number'),
                        style: TextStyle(
                          color: Color(0xFFFFDF7A),
                          fontSize: min(28, diameter * .10),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: -1,
              child: Icon(
                Icons.arrow_drop_down_rounded,
                color: const Color(0xFFBDEBFF),
                size: 43,
                shadows: const [
                  Shadow(color: Color(0xFF4B91FF), blurRadius: 12),
                ],
              ),
            ),
            if (_result != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _confettiController,
                    builder: (context, child) => CustomPaint(
                      painter: LotteryConfettiPainter(
                        _confettiController.value,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _directResultCard() {
    final completed = _result != null && !_isRolling;
    return AspectRatio(
      aspectRatio: 1.55,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            completed
                ? 'assets/images/lottery-result-win.png'
                : 'assets/images/lottery-result-wait.png',
            fit: BoxFit.fill,
          ),
          Align(
            alignment: const Alignment(0, -0.62),
            child: Text(
              _isRolling
                  ? '随机跳动中'
                  : completed
                  ? '抽中数字'
                  : '等待开始',
              style: const TextStyle(
                color: lotteryText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.03),
            child: Text(
              _isRolling
                  ? '$_rollingNumber'
                  : completed
                  ? '$_result'
                  : '--',
              key: (_isRolling || completed)
                  ? const ValueKey('lottery-number')
                  : null,
              style: TextStyle(
                color: completed ? const Color(0xFFB8F5FF) : lotteryText,
                fontSize: completed ? 92 : 76,
                fontWeight: FontWeight.bold,
                shadows: const [
                  Shadow(color: Color(0xFF53B5FF), blurRadius: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
