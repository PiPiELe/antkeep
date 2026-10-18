import 'package:flutter/material.dart';

import '../domain/purchase_price.dart';

class ColonyPriceBadge extends StatelessWidget {
  const ColonyPriceBadge({super.key, required this.tier});

  final ColonyPriceTier tier;

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground, accent) = switch (tier) {
      ColonyPriceTier.tens => (
        const [Color(0xfff4f5f7), Color(0xfff4f5f7)],
        const [Color(0xffd8dde5), Color(0xffd8dde5)],
        const Color(0xff46505d),
        const Color(0xffa5adb9),
      ),
      ColonyPriceTier.hundreds => (
        const [Color(0xffffffff), Color(0xffe6ebf3), Color(0xffcdd5e1)],
        const [Color(0xffaab7c9), Color(0xffaab7c9)],
        const Color(0xff47566c),
        const Color(0xff67778d),
      ),
      ColonyPriceTier.thousands => (
        const [Color(0xfffff9e9), Color(0xffffe4a8), Color(0xffefc06b)],
        const [Color(0xffe6b759), Color(0xffe6b759)],
        const Color(0xff915c14),
        const Color(0xffb87819),
      ),
      ColonyPriceTier.tenThousands => (
        const [
          Color(0xfffbe1ef),
          Color(0xffe2e2ff),
          Color(0xffdaf5ff),
          Color(0xffdcf9e9),
        ],
        const [
          Color(0xffe879a8),
          Color(0xff9a82f5),
          Color(0xff65bceb),
          Color(0xff59cfa2),
        ],
        const Color(0xff7751a5),
        const Color(0xff9764cd),
      ),
    };
    final rainbow = tier == ColonyPriceTier.tenThousands;
    final stops = switch (tier) {
      ColonyPriceTier.tens => null,
      ColonyPriceTier.hundreds => const [0.0, .45, 1.0],
      ColonyPriceTier.thousands => const [0.0, .48, 1.0],
      ColonyPriceTier.tenThousands => const [0.0, .28, .60, 1.0],
    };
    return Semantics(
      label: '蚁群入手价档位：${tier.label}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(rainbow ? 1.2 : 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: border,
            stops: rainbow ? const [0, .35, .70, 1] : null,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: background,
              stops: stops,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tier == ColonyPriceTier.tens
                    ? Icons.circle
                    : rainbow
                    ? Icons.auto_awesome_outlined
                    : Icons.star_rounded,
                size: tier == ColonyPriceTier.tens ? 6 : 12,
                color: accent,
              ),
              const SizedBox(width: 4),
              Text(
                tier.label,
                maxLines: 1,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
