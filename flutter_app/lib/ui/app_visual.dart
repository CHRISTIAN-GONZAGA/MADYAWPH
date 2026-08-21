import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'design_tokens.dart';

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

  final double dimHover;
  final double pressScale;

  final List<BoxShadow> cardShadow;
  final List<BoxShadow> elevatedShadow;

  final double iconInsetMuted;
  final double gradientAccentMix;

  static AppVisual forScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return AppVisual(
      radiusXs: BorderRadius.circular(8),
      radiusSm: BorderRadius.circular(12),
      radiusMd: BorderRadius.circular(16),
      radiusLg: BorderRadius.circular(22),
      radiusHero: BorderRadius.circular(32),
      dimHover: dark ? 0.08 : 0.05,
      pressScale: 0.982,
      cardShadow: [
        BoxShadow(
          color: (dark ? Colors.black : UiTokens.luxuryNavy)
              .withValues(alpha: dark ? 0.42 : 0.07),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: UiTokens.luxuryGold.withValues(alpha: dark ? 0.04 : 0.06),
          blurRadius: 28,
          offset: const Offset(0, 4),
        ),
      ],
      elevatedShadow: [
        BoxShadow(
          color: (dark ? Colors.black : UiTokens.luxuryNavy)
              .withValues(alpha: dark ? 0.5 : 0.1),
          blurRadius: 36,
          offset: const Offset(0, 16),
        ),
      ],
      iconInsetMuted: dark ? 0.16 : 0.1,
      gradientAccentMix: dark ? 0.28 : 0.22,
    );
  }

  /// Kept for existing call sites.
  static AppVisual light(ColorScheme scheme) => forScheme(scheme);

  LinearGradient scaffoldGradient(ColorScheme scheme) {
    final glow = Color.lerp(
      scheme.surface,
      scheme.primaryContainer,
      gradientAccentMix,
    )!;
    final linen = Color.lerp(
      scheme.surface,
      scheme.brightness == Brightness.dark
          ? scheme.surfaceContainerLowest
          : const Color(0xFFF1EBE3),
      0.55,
    )!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        scheme.surface,
        Color.lerp(scheme.surface, glow, 0.42)!,
        linen,
      ],
      stops: const [0.0, 0.42, 1.0],
    );
  }

  LinearGradient subtleGlassHighlight(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          scheme.surfaceContainerHigh.withValues(alpha: 0.72),
          scheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
