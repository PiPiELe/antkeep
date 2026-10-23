import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps forms and long rows readable without changing phone layouts.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 760});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

EdgeInsets readablePagePadding(
  BuildContext context, {
  double maxWidth = 760,
  double minHorizontal = 16,
  double top = 16,
  double bottom = 16,
}) {
  final horizontal = math.max(
    minHorizontal,
    (MediaQuery.sizeOf(context).width - maxWidth) / 2,
  );
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}
