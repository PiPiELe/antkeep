import 'package:flutter/material.dart';

/// Fades only the edges that have content outside the visible viewport.
class FadingHorizontalScroll extends StatefulWidget {
  const FadingHorizontalScroll({super.key, required this.child});

  final Widget child;

  @override
  State<FadingHorizontalScroll> createState() => _FadingHorizontalScrollState();
}

class _FadingHorizontalScrollState extends State<FadingHorizontalScroll> {
  final _controller = ScrollController();
  bool _hasMoreBefore = false;
  bool _hasMoreAfter = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateFade);
  }

  void _updateFade() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final before = position.extentBefore > .5;
    final after = position.extentAfter > .5;
    if (before != _hasMoreBefore || after != _hasMoreAfter) {
      setState(() {
        _hasMoreBefore = before;
        _hasMoreAfter = after;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _updateFade();
        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final fade = bounds.width > 0
              ? (20 / bounds.width).clamp(0.0, .5)
              : 0.0;
          return LinearGradient(
            colors: [
              (rtl ? _hasMoreAfter : _hasMoreBefore)
                  ? Colors.transparent
                  : Colors.white,
              Colors.white,
              Colors.white,
              (rtl ? _hasMoreBefore : _hasMoreAfter)
                  ? Colors.transparent
                  : Colors.white,
            ],
            stops: [0, fade, 1 - fade, 1],
          ).createShader(bounds);
        },
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
  }
}
