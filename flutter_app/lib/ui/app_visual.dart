import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Brand surfaces, radii, and shadows — never hardcode these in widgets.
@immutable
class AppVisual extends ThemeExtension<AppVisual> {
  const AppVisual({
    required this.radiusXs,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusHero,
    required this.dimHover,
    required this.pressScale,
    required this.cardShadow,
    required this.elevatedShadow,
    required this.iconInsetMuted,
    required this.gradientAccentMix,
  });

  final BorderRadius radiusXs;
  final BorderRadius radiusSm;
  final BorderRadius radiusMd;
  final BorderRadius radiusLg;
  final BorderRadius radiusHero;

  /// Press overlay for Ink/Material buttons (0–1 alpha applied to onSurface).
  final double dimHover;
  final double pressScale;

  final List<BoxShadow> cardShadow;
  final List<BoxShadow> elevatedShadow;

  /// Icon circle background alpha toward primary.
  final double iconInsetMuted;

  /// How much primaryContainer lerps into scaffold gradient bottom.
  final double gradientAccentMix;

  static AppVisual light(ColorScheme scheme) {
    final muted = scheme.brightness == Brightness.dark ? 0.14 : 0.12;
    return AppVisual(
      radiusXs: BorderRadius.circular(6),
      radiusSm: BorderRadius.circular(10),
      radiusMd: BorderRadius.circular(14),
      radiusLg: BorderRadius.circular(20),
      radiusHero: BorderRadius.circular(28),
      dimHover: 0.06,
      pressScale: 0.985,
      cardShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: scheme.brightness == Brightness.dark ? 0.35 : 0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
      elevatedShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: scheme.brightness == Brightness.dark ? 0.45 : 0.12),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
      iconInsetMuted: muted,
      gradientAccentMix: 0.38,
    );
  }

  LinearGradient scaffoldGradient(ColorScheme scheme) {
    final glow = Color.lerp(
      scheme.surface,
      scheme.primaryContainer,
      gradientAccentMix,
    )!;
    final depth = scheme.surfaceContainerLowest;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.surface,
        Color.lerp(scheme.surface, glow, 0.55)!,
        Color.lerp(depth, scheme.primaryContainer, 0.08)!,
      ],
      stops: const [0.0, 0.48, 1.0],
    );
  }

  LinearGradient subtleGlassHighlight(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          scheme.surfaceContainerHigh.withValues(alpha: 0.65),
          scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        ],
      );

  static AppVisual of(BuildContext context) =>
      Theme.of(context).extension<AppVisual>()!;

  @override
  AppVisual copyWith({
    BorderRadius? radiusXs,
    BorderRadius? radiusSm,
    BorderRadius? radiusMd,
    BorderRadius? radiusLg,
    BorderRadius? radiusHero,
    double? dimHover,
    double? pressScale,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? elevatedShadow,
    double? iconInsetMuted,
    double? gradientAccentMix,
  }) {
    return AppVisual(
      radiusXs: radiusXs ?? this.radiusXs,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusHero: radiusHero ?? this.radiusHero,
      dimHover: dimHover ?? this.dimHover,
      pressScale: pressScale ?? this.pressScale,
      cardShadow: cardShadow ?? this.cardShadow,
      elevatedShadow: elevatedShadow ?? this.elevatedShadow,
      iconInsetMuted: iconInsetMuted ?? this.iconInsetMuted,
      gradientAccentMix: gradientAccentMix ?? this.gradientAccentMix,
    );
  }

  @override
  AppVisual lerp(ThemeExtension<AppVisual>? other, double t) {
    if (other is! AppVisual) return this;
    return AppVisual(
      radiusXs: BorderRadius.lerp(radiusXs, other.radiusXs, t)!,
      radiusSm: BorderRadius.lerp(radiusSm, other.radiusSm, t)!,
      radiusMd: BorderRadius.lerp(radiusMd, other.radiusMd, t)!,
      radiusLg: BorderRadius.lerp(radiusLg, other.radiusLg, t)!,
      radiusHero: BorderRadius.lerp(radiusHero, other.radiusHero, t)!,
      dimHover: lerpDouble(dimHover, other.dimHover, t)!,
      pressScale: lerpDouble(pressScale, other.pressScale, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      elevatedShadow: t < 0.5 ? elevatedShadow : other.elevatedShadow,
      iconInsetMuted: lerpDouble(iconInsetMuted, other.iconInsetMuted, t)!,
      gradientAccentMix:
          lerpDouble(gradientAccentMix, other.gradientAccentMix, t)!,
    );
  }
}
