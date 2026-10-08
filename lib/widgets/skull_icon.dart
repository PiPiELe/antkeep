import 'package:flutter/material.dart';

/// The upscaled skull extracted from the supplied reference image.
class SkullIcon extends StatelessWidget {
  const SkullIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '骷髅头',
      image: true,
      child: Image.asset(
        'assets/memorial/skull-hd-two-teeth.png',
        width: size,
        // Match the visible height of neighboring app-bar icons.
        height: size * 1.1,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
        color: theme.colorScheme.onSurfaceVariant,
        colorBlendMode: BlendMode.srcIn,
        excludeFromSemantics: true,
      ),
    );
  }
}
