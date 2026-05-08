import 'package:flutter/material.dart';

/// Functional Minimalist design tokens (8px rhythm).
class UiTokens {
  UiTokens._();

  // Spacing (strict 8px grid + intentional half-step)
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;

  // Radius
  static const double r8 = 8;
  static const double r12 = 12;

  // Motion
  static const Duration dFast = Duration(milliseconds: 140);
  static const Duration dStd = Duration(milliseconds: 200);
  static const Curve easeOperational = Cubic(0.05, 0.7, 0.1, 1.0);

  // Border tones
  static const Color lightBorder = Color(0xFFE7E7E7);
  static const Color darkBorder = Color(0xFF2A2A2A);

  // Tonal surfaces
  static const Color lightBase = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFF7F7F7);
  static const Color darkBase = Color(0xFF121212);
  static const Color darkElevated = Color(0xFF1A1A1A);
}
