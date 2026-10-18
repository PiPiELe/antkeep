import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/milestone.dart';
import '../date_display.dart';

/// Theme-aware surfaces around the original sandstone artwork.
abstract final class MilestoneDesign {
  static const background = Color(0xff0c1119);
  static const surface = Color(0xff151d28);
  static const border = Color(0xff35404a);
  static const gold = Color(0xffd6b584);
  static const parchment = Color(0xffe3c396);
  static const muted = Color(0xffa5a9ad);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundColor(BuildContext context) =>
      isDark(context) ? background : const Color(0xfffffcf7);
  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? surface : const Color(0xfffff8ed);
  static Color borderColor(BuildContext context) =>
      isDark(context) ? border : const Color(0xffd8c6ad);
  static Color textColor(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xff352b21);
  static Color mutedColor(BuildContext context) =>
      isDark(context) ? muted : const Color(0xff736657);
  static Color accentColor(BuildContext context) =>
      isDark(context) ? parchment : const Color(0xff805b2c);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    if (!isDark(context)) {
      final scheme = base.colorScheme.copyWith(
        primary: accentColor(context),
        onPrimary: Colors.white,
        primaryContainer: parchment,
        onPrimaryContainer: background,
        surface: backgroundColor(context),
        onSurface: textColor(context),
        onSurfaceVariant: mutedColor(context),
        outline: borderColor(context),
      );
      return base.copyWith(
        scaffoldBackgroundColor: backgroundColor(context),
        colorScheme: scheme,
        textTheme: base.textTheme.apply(
          bodyColor: textColor(context),
          displayColor: textColor(context),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: backgroundColor(context),
          foregroundColor: textColor(context),
          centerTitle: true,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceColor(context),
          labelStyle: TextStyle(color: mutedColor(context)),
          hintStyle: TextStyle(color: mutedColor(context)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor(context)),
          ),
        ),
      );
    }
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

  static BoxDecoration panel(BuildContext context, {double radius = 10}) =>
      BoxDecoration(
        color: surfaceColor(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor(context)),
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
                      ? MilestoneDesign.accentColor(context)
                      : MilestoneDesign.borderColor(context),
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
            style: TextStyle(
              color: MilestoneDesign.textColor(context),
              fontSize: 10,
            ),
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
          gradient: LinearGradient(
            colors: MilestoneDesign.isDark(context)
                ? const [Color(0xff28241e), Color(0xff191c1e)]
                : const [Color(0xfffff3df), Color(0xfffffdfa)],
          ),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: MilestoneDesign.isDark(context)
                ? const Color(0xff746044)
                : MilestoneDesign.borderColor(context),
          ),
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
                    style: TextStyle(
                      color: MilestoneDesign.accentColor(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    chineseDate(milestone.occurredAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: MilestoneDesign.mutedColor(context),
                    ),
                  ),
                  if (milestone.note?.isNotEmpty == true)
                    Text(
                      milestone.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: MilestoneDesign.mutedColor(context),
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
      final height =
          constraints.maxWidth / 1.12 + (scale - 1).clamp(0, 2) * 100;
      const introduction = '记录重要的时刻\n让每一个值得铭记的瞬间，都被永远铭刻';
      final introductionStyle = DefaultTextStyle.of(context).style.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: MilestoneDesign.isDark(context)
            ? const Color(0xffd6cbc0)
            : MilestoneDesign.textColor(context),
        height: 1.6,
        shadows: MilestoneDesign.isDark(context)
            ? const [Shadow(color: Colors.black87, blurRadius: 8)]
            : null,
      );
      final heading = TextPainter(
        text: TextSpan(text: introduction, style: introductionStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth - 40);
      final headingEnd = ((10 + heading.height) / height).clamp(0.0, .8);
      heading.dispose();
      return SizedBox(
        height: height,
        child: ClipRect(
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
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 12,
                          sigmaY: 12,
                        ),
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
              if (!MilestoneDesign.isDark(context))
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          MilestoneDesign.backgroundColor(context),
                          MilestoneDesign.backgroundColor(context)
                              .withValues(alpha: 0),
                        ],
                        stops: [headingEnd, (headingEnd + .18).clamp(0.0, 1.0)],
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 10,
                left: 20,
                right: 20,
                child: Text(introduction, style: introductionStyle),
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
        ),
      );
    },
  );
}
