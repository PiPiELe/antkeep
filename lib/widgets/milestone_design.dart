import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/milestone.dart';
import '../date_display.dart';

/// The colors and surfaces used by the milestone screens in the supplied design.
abstract final class MilestoneDesign {
  static const background = Color(0xff0c1119);
  static const surface = Color(0xff151d28);
  static const border = Color(0xff35404a);
  static const gold = Color(0xffd6b584);
  static const parchment = Color(0xffe3c396);
  static const muted = Color(0xffa5a9ad);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    return ThemeData.dark().copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: parchment,
        onPrimary: background,
        surface: surface,
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
      ),
    );
  }

  static BoxDecoration panel({double radius = 10}) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
  );
}

class MilestoneArtworkTile extends StatelessWidget {
  const MilestoneArtworkTile({
    super.key,
    required this.artwork,
    required this.selected,
    required this.onTap,
    this.width = 86,
    this.height = 106,
  });

  final MilestoneArtwork artwork;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? MilestoneDesign.parchment
                      : MilestoneDesign.border,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x9988aee6), blurRadius: 8)]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.scale(
                      scale: 1.45,
                      alignment: Alignment.topCenter,
                      child: Image.asset(
                        artwork.assetPath,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                    if (selected)
                      const Positioned(
                        top: 4,
                        right: 4,
                        child: Icon(
                          Icons.check_circle,
                          size: 18,
                          color: MilestoneDesign.parchment,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            artwork.label,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class MilestoneListCard extends StatelessWidget {
  const MilestoneListCard({
    super.key,
    required this.milestone,
    required this.onTap,
  });

  final Milestone milestone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 102,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xff28241e), Color(0xff191c1e)],
          ),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xff746044)),
        ),
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                milestone.artwork.assetPath,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    milestone.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MilestoneDesign.parchment,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    chineseDate(milestone.occurredAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: MilestoneDesign.muted,
                    ),
                  ),
                  if (milestone.note?.isNotEmpty == true)
                    Text(
                      milestone.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: MilestoneDesign.muted,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    ),
  );
}

class MilestoneHero extends StatelessWidget {
  const MilestoneHero({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(18) / 18;
      return SizedBox(
        height: constraints.maxWidth / 1.12 + (scale - 1).clamp(0, 2) * 100,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fade the artwork itself so every edge meets the page surface.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0, .16, .78, 1],
              ).createShader(bounds),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0, .08, .92, 1],
                ).createShader(bounds),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Image.asset(
                        'assets/milestone/milestone-hero.png',
                        fit: BoxFit.cover,
                        color: const Color(0x99000000),
                        colorBlendMode: BlendMode.darken,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: constraints.maxWidth / 1.3,
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.white],
                          stops: [0, .22],
                        ).createShader(bounds),
                        child: Image.asset(
                          'assets/milestone/milestone-hero.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              top: 10,
              left: 20,
              right: 20,
              child: Text(
                '记录重要的时刻\n让每一个值得铭记的瞬间，都被永远铭刻',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xffd6cbc0),
                  height: 1.6,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, .15),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '微小的生命\n也能书写伟大的篇章',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'StoneSerif',
                        fontSize: 21,
                        color: Color(0xff352414),
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '— ANTKEEP —',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 2,
                        color: Color(0xff574027),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
