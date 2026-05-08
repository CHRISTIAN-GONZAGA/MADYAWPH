import 'package:flutter/material.dart';

import 'design_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light(Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: UiTokens.lightBase,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      scaffoldBackgroundColor: UiTokens.lightBase,
      cardTheme: CardThemeData(
        color: UiTokens.lightElevated,
        margin: const EdgeInsets.all(UiTokens.s8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r12),
          side: const BorderSide(color: UiTokens.lightBorder, width: 0.8),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: UiTokens.lightBase,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          letterSpacing: -0.1,
        ),
      ),
      dividerTheme: const DividerThemeData(
        thickness: 0.8,
        color: UiTokens.lightBorder,
        space: UiTokens.s16,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s12,
          vertical: UiTokens.s12,
        ),
        filled: true,
        fillColor: UiTokens.lightElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.r8),
          borderSide: const BorderSide(color: UiTokens.lightBorder, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.r8),
          borderSide: const BorderSide(color: UiTokens.lightBorder, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.r8),
          borderSide: BorderSide(color: scheme.primary, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: UiTokens.s12,
          vertical: UiTokens.s4,
        ),
        minLeadingWidth: 20,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r8),
          side: const BorderSide(color: UiTokens.lightBorder, width: 0.8),
        ),
        side: const BorderSide(color: UiTokens.lightBorder, width: 0.8),
      ),
      textTheme: _textTheme(Brightness.light),
    );
  }

  static ThemeData dark(Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: UiTokens.darkBase,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      scaffoldBackgroundColor: UiTokens.darkBase,
      cardTheme: CardThemeData(
        color: UiTokens.darkElevated,
        margin: const EdgeInsets.all(UiTokens.s8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r12),
          side: const BorderSide(color: UiTokens.darkBorder, width: 0.8),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: UiTokens.darkBase,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        thickness: 0.8,
        color: UiTokens.darkBorder,
        space: UiTokens.s16,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s12,
          vertical: UiTokens.s12,
        ),
        filled: true,
        fillColor: UiTokens.darkElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.r8),
          borderSide: const BorderSide(color: UiTokens.darkBorder, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.r8),
          borderSide: const BorderSide(color: UiTokens.darkBorder, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.r8),
          borderSide: BorderSide(color: scheme.primary, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: UiTokens.s12,
          vertical: UiTokens.s4,
        ),
      ),
      textTheme: _textTheme(Brightness.dark),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? const Color(0xFFF4F4F4) : const Color(0xFF111111);
    final secondary =
        isDark ? const Color(0xFFB8B8B8) : const Color(0xFF666666);
    return TextTheme(
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: primary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.3,
        color: secondary,
      ),
      labelMedium: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: secondary,
      ),
    );
  }
}
