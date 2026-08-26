import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_visual.dart';
import 'design_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light(Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: UiTokens.lightBase,
    );
    return _build(scheme);
  }

  static ThemeData dark(Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: UiTokens.darkBase,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final visual = AppVisual.forScheme(scheme);
    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: text,
      primaryTextTheme: text,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: scheme.brightness == Brightness.light
            ? UiTokens.lightElevated
            : scheme.surfaceContainerLow,
        margin: const EdgeInsets.all(UiTokens.s8),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: visual.radiusMd,
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
            width: 0.7,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        barrierColor: scheme.scrim.withValues(alpha: 0.46),
        shape: RoundedRectangleBorder(borderRadius: visual.radiusLg),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline.withValues(alpha: 0.45),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(UiTokens.r20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: visual.radiusSm),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
        systemOverlayStyle: scheme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(
        thickness: 0.6,
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        space: UiTokens.s16,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s16,
          vertical: 16,
        ),
        filled: true,
        fillColor: scheme.brightness == Brightness.light
            ? UiTokens.lightElevated
            : scheme.surfaceContainerHighest,
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: visual.radiusSm,
          borderSide: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: visual.radiusSm,
          borderSide: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: visual.radiusSm,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: visual.radiusSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: visual.radiusSm),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s16,
          vertical: UiTokens.s4,
        ),
        minLeadingWidth: 24,
        iconColor: scheme.primary,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r12),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
        side: BorderSide(color: scheme.outlineVariant, width: 0.8),
        labelStyle: text.labelMedium,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
        ),
      ),
      extensions: [visual],
    );
  }

  /// Hotel typography: one family, Noto Sans. It reads as a real property
  /// system (and covers Korean, Japanese, and Chinese) instead of a display
  /// serif paired with a rounded UI sans.
  static TextTheme _textTheme(ColorScheme scheme) {
    final body = GoogleFonts.notoSansTextTheme();
    final on = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    const figures = <FontFeature>[
      FontFeature.tabularFigures(),
    ];

    return body.copyWith(
      displayLarge: body.displayLarge?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.15,
        color: on,
      ),
      displayMedium: body.displayMedium?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.18,
        color: on,
      ),
      displaySmall: body.displaySmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
        color: on,
      ),
      headlineLarge: body.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.22,
        color: on,
      ),
      headlineMedium: body.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        height: 1.25,
        color: on,
      ),
      headlineSmall: body.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.28,
        color: on,
      ),
      titleLarge: body.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.3,
        color: on,
        fontFeatures: figures,
      ),
      titleMedium: body.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.35,
        color: on,
        fontFeatures: figures,
      ),
      titleSmall: body.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.35,
        color: on,
        fontFeatures: figures,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0,
        color: on,
        fontFeatures: figures,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
        letterSpacing: 0,
        color: on,
        fontFeatures: figures,
      ),
      bodySmall: body.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.4,
        letterSpacing: 0,
        color: muted,
        fontFeatures: figures,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: on,
        fontFeatures: figures,
      ),
      labelMedium: body.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
        color: muted,
        fontFeatures: figures,
      ),
      labelSmall: body.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: muted,
        fontFeatures: figures,
      ),
    );
  }
}
