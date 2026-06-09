import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'madyaw_logo_paths.dart';

/// Vector Madyaw sailboat mark + wordmark (no image asset).
class MadyawLogoWidget extends StatelessWidget {
  const MadyawLogoWidget({
    super.key,
    this.size = 200,
    this.drawProgress = 1,
    this.textOpacity = 1,
    this.glowStrength = 0,
    this.showWordmark = true,
    this.wavePhase = 0,
    this.swayAngle = 0,
    this.useStaggeredWordmark = false,
    this.letterReveal = 1,
    this.showBrandLine = false,
    this.brandReveal = 1,
  });

  final double size;
  final double drawProgress;
  final double textOpacity;
  final double glowStrength;
  final bool showWordmark;
  final double wavePhase;
  final double swayAngle;
  final bool useStaggeredWordmark;
  final double letterReveal;
  final bool showBrandLine;
  final double brandReveal;

  static const Color brightBlue = MadyawBrand.brightBlue;
  static const Color navy = MadyawBrand.navy;
  static const String wordmark = MadyawBrand.wordmark;

  @override
  Widget build(BuildContext context) {
    final markH = size * (showWordmark ? 0.58 : 1);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (glowStrength > 0.01)
            CustomPaint(
              size: Size(size, size),
              painter: _LogoGlowPainter(
                strength: glowStrength,
                markHeight: markH,
              ),
            ),
          Transform.rotate(
            angle: swayAngle * math.pi / 180,
            child: CustomPaint(
              size: Size(size, size),
              painter: _MadyawLogoPainter(
                drawProgress: drawProgress.clamp(0, 1),
                textOpacity: useStaggeredWordmark ? 0 : textOpacity.clamp(0, 1),
                showWordmark: showWordmark && !useStaggeredWordmark,
                markHeight: markH,
                wavePhase: wavePhase,
              ),
            ),
          ),
          if (showWordmark && useStaggeredWordmark)
            Positioned(
              left: 0,
              right: 0,
              bottom: size * 0.02,
              child: _StaggeredWordmark(
                progress: letterReveal.clamp(0, 1),
                opacity: textOpacity,
                fontSize: size * 0.11,
              ),
            ),
          if (showBrandLine)
            Positioned(
              left: 0,
              right: 0,
              bottom: -size * 0.02,
              child: _BrandLine(reveal: brandReveal.clamp(0, 1)),
            ),
        ],
      ),
    );
  }
}

class _BrandLine extends StatelessWidget {
  const _BrandLine({required this.reveal});

  final double reveal;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: reveal,
      child: Transform.scale(
        scale: 0.85 + 0.15 * reveal,
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [MadyawLogoWidget.brightBlue, MadyawLogoWidget.navy],
          ).createShader(bounds),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MADYAW',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: MadyawLogoWidget.brightBlue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PH',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaggeredWordmark extends StatelessWidget {
  const _StaggeredWordmark({
    required this.progress,
    required this.opacity,
    required this.fontSize,
  });

  final double progress;
  final double opacity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final letters = MadyawLogoWidget.wordmark.split('');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(letters.length, (i) {
        final slice = 1 / letters.length;
        final start = i * slice;
        final local = ((progress - start) / slice).clamp(0.0, 1.0);
        final y = 12 * (1 - Curves.easeOutBack.transform(local));
        return Transform.translate(
          offset: Offset(0, y),
          child: Opacity(
            opacity: (local * opacity).clamp(0, 1),
            child: Text(
              letters[i],
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: fontSize * 0.06,
                color: MadyawLogoWidget.navy,
                shadows: [
                  Shadow(
                    color: MadyawLogoWidget.brightBlue.withValues(alpha: 0.35 * local),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _LogoGlowPainter extends CustomPainter {
  _LogoGlowPainter({required this.strength, required this.markHeight});

  final double strength;
  final double markHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = markHeight * 0.42;
    for (var i = 0; i < 2; i++) {
      final paint = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 24 + i * 12)
        ..color = MadyawLogoWidget.brightBlue
            .withValues(alpha: (0.18 - i * 0.06) * strength);
      canvas.drawCircle(Offset(cx, cy), 48 + i * 18, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LogoGlowPainter old) =>
      old.strength != strength;
}

class _MadyawLogoPainter extends CustomPainter {
  _MadyawLogoPainter({
    required this.drawProgress,
    required this.textOpacity,
    required this.showWordmark,
    required this.markHeight,
    required this.wavePhase,
  });

  final double drawProgress;
  final double textOpacity;
  final bool showWordmark;
  final double markHeight;
  final double wavePhase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final scale = markHeight / 120;
    final waveY = math.sin(wavePhase * math.pi * 2) * 2;

    canvas.save();
    canvas.translate(cx, markHeight * 0.08 + waveY);
    canvas.scale(scale);

    final layers = MadyawBrand.layers();
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      _drawTrimmedPath(
        canvas,
        layer.path,
        layer.color,
        drawProgress,
        i,
        layers.length,
      );
    }

    canvas.restore();

    if (showWordmark && textOpacity > 0.01) {
      final tp = TextPainter(
        text: TextSpan(
          text: MadyawLogoWidget.wordmark,
          style: TextStyle(
            fontSize: w * 0.11,
            fontWeight: FontWeight.w800,
            letterSpacing: w * 0.018,
            color: MadyawLogoWidget.navy.withValues(alpha: textOpacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);
      tp.paint(canvas, Offset((w - tp.width) / 2, markHeight + h * 0.04));
    }
  }

  void _drawTrimmedPath(
    Canvas canvas,
    Path path,
    Color color,
    double progress,
    int index,
    int total,
  ) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final slice = 1 / total;
    final start = index * slice;
    final local = ((progress - start) / slice).clamp(0.0, 1.0);
    if (local <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final metric in metrics) {
      final len = metric.length * local;
      canvas.drawPath(metric.extractPath(0, len), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MadyawLogoPainter old) =>
      old.drawProgress != drawProgress ||
      old.textOpacity != textOpacity ||
      old.wavePhase != wavePhase;
}
