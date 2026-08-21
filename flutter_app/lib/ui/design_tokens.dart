import 'package:flutter/material.dart';

/// Luxury hotel design tokens — 8px rhythm with refined motion.
class UiTokens {
  UiTokens._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;

  static const Duration dFast = Duration(milliseconds: 160);
  static const Duration dStd = Duration(milliseconds: 280);
  static const Duration dSlow = Duration(milliseconds: 420);
  static const Curve easeOperational = Cubic(0.22, 1, 0.36, 1);
  static const Curve easeEnter = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeExit = Cubic(0.4, 0, 1, 1);

  static const Color lightBorder = Color(0xFFE6E0D6);
  static const Color darkBorder = Color(0xFF2C3340);

  /// Warm ivory — hotel linen, not stark white.
  static const Color lightBase = Color(0xFFF7F4EF);
  static const Color lightElevated = Color(0xFFFFFCF8);
  static const Color darkBase = Color(0xFF0E1520);
  static const Color darkElevated = Color(0xFF161E2B);

  static const Color luxuryGold = Color(0xFFC6A15B);
  static const Color luxuryNavy = Color(0xFF152238);
}
