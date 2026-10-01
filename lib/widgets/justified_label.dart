import 'package:flutter/material.dart';

class JustifiedLabel extends StatelessWidget {
  const JustifiedLabel({
    super.key,
    required this.text,
    required this.width,
    this.style,
  });

  final String text;
  final double width;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    excludeSemantics: true,
    child: SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final character in text.characters)
            Text(character, style: style),
        ],
      ),
    ),
  );
}
