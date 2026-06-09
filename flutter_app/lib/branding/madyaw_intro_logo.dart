import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'madyaw_logo_paths.dart';

/// Programmatic animated MADYAW mark for the premium intro sequence.
class MadyawIntroLogo extends StatelessWidget {
  const MadyawIntroLogo({
    super.key,
    required this.size,
    required this.drawProgress,
    this.shineProgress = 0,
    this.glowStrength = 0,
    this.breathe = 0,
    this.reduceMotion = false,
  });

  final double size;
  final double drawProgress;
  final double shineProgress;
  final double glowStrength;
  final double breathe;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.92,
      child: CustomPaint(
        painter: _PremiumLogoPainter(
          drawProgress: drawProgress.clamp(0, 1),
          shineProgress: shineProgress.clamp(0, 1),
          glowStrength: glowStrength.clamp(0, 1),
          breathe: breathe,
          reduceMotion: reduceMotion,
        ),
      ),
    );
  }
}

class _PremiumLogoPainter extends CustomPainter {
  _PremiumLogoPainter({
    required this.drawProgress,
    required this.shineProgress,
    required this.glowStrength,
    required this.breathe,
    required this.reduceMotion,
  });

  final double drawProgress;
  final double shineProgress;
  final double glowStrength;
  final double breathe;
  final bool reduceMotion;

  static const _markHeight = 120.0;

  bool _isWaveLayer(String id) =>
      id == 'wave_back' || id == 'wave_mid' || id == 'wave_front';

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final scale = (h * 0.72) / _markHeight;
    final floatY = reduceMotion ? 0.0 : math.sin(breathe * math.pi * 2) * 1.2;

    if (glowStrength > 0.01) {
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32)
        ..color = MadyawBrand.brightBlue.withValues(alpha: 0.16 * glowStrength);
      canvas.drawCircle(Offset(cx, h * 0.38 + floatY), 52 * scale, glow);
    }

    canvas.save();
    canvas.translate(cx, h * 0.14 + floatY);
    canvas.scale(scale);

    final layers = MadyawBrand.layers();
    final layerCount = layers.length;
    final waveBob = reduceMotion ? 0.0 : math.sin(breathe * math.pi * 2) * 0.8;

    for (var i = 0; i < layerCount; i++) {
      final layer = layers[i];
      final slice = 1 / layerCount;
      final start = i * slice;
      final local = ((drawProgress - start) / slice).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final eased = Curves.easeOutCubic.transform(local);
      final parallaxX = reduceMotion
          ? 0.0
          : layer.parallax * 14 * (1 - eased) * (i.isEven ? -1 : 1);
      final layerScale = 0.93 + 0.07 * eased;
      final waveY = _isWaveLayer(layer.id) && drawProgress > 0.7 ? waveBob : 0.0;

      canvas.save();
      canvas.translate(parallaxX, waveY);
      canvas.scale(layerScale, layerScale);
      _paintFilledLayer(canvas, layer.path, layer.color, eased);
      canvas.restore();
    }

    canvas.restore();

    if (shineProgress > 0.01 && !reduceMotion) {
      _paintShine(canvas, Rect.fromLTWH(0, h * 0.05, w, h * 0.75));
    }
  }

  /// Opacity + scale reveal — avoids partial-path line artifacts.
  void _paintFilledLayer(Canvas canvas, Path path, Color color, double t) {
    final paint = Paint()
      ..color = color.withValues(alpha: t.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  void _paintShine(Canvas canvas, Rect bounds) {
    final sweepW = bounds.width * 0.5;
    final x = ui.lerpDouble(
      bounds.left - sweepW,
      bounds.right + sweepW,
      shineProgress,
    )!;

    canvas.saveLayer(bounds, Paint());
    final shine = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          MadyawBrand.brightBlue.withValues(alpha: 0.0),
          MadyawBrand.brightBlue.withValues(alpha: 0.22),
          MadyawBrand.brightBlue.withValues(alpha: 0.0),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 0.5, 0.62, 1.0],
      ).createShader(Rect.fromLTWH(x, bounds.top, sweepW, bounds.height));
    canvas.drawRect(bounds, shine);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PremiumLogoPainter old) =>
      old.drawProgress != drawProgress ||
      old.shineProgress != shineProgress ||
      old.glowStrength != glowStrength ||
      old.breathe != breathe;
}

/// Staggered MADYAW wordmark reveal beneath the mark.
class MadyawIntroWordmark extends StatelessWidget {
  const MadyawIntroWordmark({
    super.key,
    required this.progress,
    this.fontSize = 28,
    this.lightOnDark = false,
  });

  final double progress;
  final double fontSize;
  final bool lightOnDark;

  @override
  Widget build(BuildContext context) {
    final letters = MadyawBrand.wordmark.split('');
    final baseColor = lightOnDark ? Colors.white : MadyawBrand.navy;
    final spacing = math.min(fontSize * 0.14, 6.0);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(letters.length, (i) {
          final slice = 1 / letters.length;
          final start = i * slice;
          final local = ((progress - start) / slice).clamp(0.0, 1.0);
          final eased = Curves.easeOutCubic.transform(local);
          final y = 12 * (1 - Curves.easeOutBack.transform(local));

          return Transform.translate(
            offset: Offset(0, y),
            child: Opacity(
              opacity: eased,
              child: Text(
                letters[i],
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: spacing,
                  color: baseColor.withValues(alpha: 0.94 * eased),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
