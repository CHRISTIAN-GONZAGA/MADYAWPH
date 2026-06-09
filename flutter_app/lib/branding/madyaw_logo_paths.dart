import 'package:flutter/material.dart';

/// Brand colors and vector paths for the MADYAW sailboat mark.
abstract final class MadyawBrand {
  static const Color brightBlue = Color(0xFF1E88E5);
  static const Color navy = Color(0xFF1A237E);
  static const Color introBgTop = Color(0xFFEEF2FA);
  static const Color introBgBottom = Color(0xFFE3EAF6);
  static const Color introAccent = Color(0xFFD6E4F7);
  static const String wordmark = 'MADYAW';

  /// Layer draw order for staged reveal animations.
  static List<MadyawLogoLayer> layers() => [
        MadyawLogoLayer(
          id: 'left_sail',
          path: _leftSail(),
          color: navy,
          parallax: 0.04,
        ),
        MadyawLogoLayer(
          id: 'main_sail',
          path: _mainSail(),
          color: brightBlue,
          parallax: 0.0,
        ),
        MadyawLogoLayer(
          id: 'right_sail',
          path: _rightSail(),
          color: brightBlue.withValues(alpha: 0.94),
          parallax: 0.06,
        ),
        MadyawLogoLayer(
          id: 'hull_upper',
          path: _hullUpper(),
          color: navy,
          parallax: 0.02,
        ),
        MadyawLogoLayer(
          id: 'hull_lower',
          path: _hullLower(),
          color: brightBlue,
          parallax: 0.03,
        ),
        MadyawLogoLayer(
          id: 'wave_back',
          path: _waveBack(),
          color: navy.withValues(alpha: 0.85),
          parallax: 0.08,
        ),
        MadyawLogoLayer(
          id: 'wave_mid',
          path: _waveMid(),
          color: brightBlue.withValues(alpha: 0.75),
          parallax: 0.1,
        ),
        MadyawLogoLayer(
          id: 'wave_front',
          path: _waveFront(),
          color: brightBlue,
          parallax: 0.12,
        ),
      ];

  static Path _mainSail() => Path()
    ..moveTo(-6, 78)
    ..quadraticBezierTo(4, 18, 20, 2)
    ..quadraticBezierTo(30, -4, 40, 10)
    ..quadraticBezierTo(44, 44, 30, 78)
    ..close();

  static Path _leftSail() => Path()
    ..moveTo(-44, 76)
    ..quadraticBezierTo(-50, 36, -34, 16)
    ..quadraticBezierTo(-24, 6, -10, 78)
    ..close();

  static Path _rightSail() => Path()
    ..moveTo(34, 76)
    ..quadraticBezierTo(50, 46, 46, 20)
    ..quadraticBezierTo(42, 8, 36, 10)
    ..lineTo(26, 78)
    ..close();

  static Path _hullUpper() => Path()
    ..moveTo(-46, 78)
    ..lineTo(46, 78)
    ..lineTo(54, 86)
    ..lineTo(-54, 86)
    ..close();

  static Path _hullLower() => Path()
    ..moveTo(-50, 86)
    ..lineTo(50, 86)
    ..lineTo(46, 90)
    ..lineTo(-46, 90)
    ..close();

  static Path _waveBack() => Path()
    ..moveTo(-60, 94)
    ..quadraticBezierTo(-22, 82, 18, 92)
    ..quadraticBezierTo(46, 100, 64, 96)
    ..lineTo(64, 102)
    ..quadraticBezierTo(42, 106, 12, 98)
    ..quadraticBezierTo(-28, 90, -60, 100)
    ..close();

  static Path _waveMid() => Path()
    ..moveTo(-56, 100)
    ..quadraticBezierTo(-12, 88, 28, 98)
    ..quadraticBezierTo(54, 104, 66, 100)
    ..lineTo(66, 106)
    ..quadraticBezierTo(38, 110, 0, 102)
    ..quadraticBezierTo(-34, 96, -56, 108)
    ..close();

  static Path _waveFront() => Path()
    ..moveTo(-52, 106)
    ..quadraticBezierTo(-8, 94, 32, 104)
    ..quadraticBezierTo(58, 110, 68, 106)
    ..lineTo(68, 112)
    ..quadraticBezierTo(40, 116, 2, 108)
    ..quadraticBezierTo(-32, 102, -52, 114)
    ..close();
}

class MadyawLogoLayer {
  const MadyawLogoLayer({
    required this.id,
    required this.path,
    required this.color,
    this.parallax = 0,
  });

  final String id;
  final Path path;
  final Color color;
  final double parallax;
}
