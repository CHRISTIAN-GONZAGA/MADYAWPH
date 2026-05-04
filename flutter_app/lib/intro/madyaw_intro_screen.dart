import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Vector “Madyaw” mark: animated wave, sailboat build, shimmer, typography, tap to skip.
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _sequence;
  late final AnimationController _bob;
  late final AnimationController _ripple;
  bool _ended = false;

  static const _navy = Color(0xFF1B2B4A);
  static const _navyDeep = Color(0xFF152238);
  static const _sky = Color(0xFF4A90D9);
  static const _skyLight = Color(0xFF7AB8F0);
  static const _mist = Color(0xFFF0F4FA);

  @override
  void initState() {
    super.initState();
    _sequence = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..addStatusListener(_onSequenceStatus);

    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();

    _sequence.forward();
  }

  void _onSequenceStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _finish();
    }
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    if (_sequence.isAnimating) {
      _sequence.stop();
    }
    _bob.stop();
    _ripple.stop();
    widget.onFinished();
  }

  @override
  void dispose() {
    _sequence.removeStatusListener(_onSequenceStatus);
    _sequence.dispose();
    _bob.dispose();
    _ripple.dispose();
    super.dispose();
  }

  double _t(double start, double end, double v) {
    if (v <= start) return 0;
    if (v >= end) return 1;
    return (v - start) / (end - start);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: AnimatedBuilder(
        animation: Listenable.merge([_sequence, _bob, _ripple]),
        builder: (context, _) {
          final v = _sequence.value;
          final wave = Curves.easeOutCubic.transform(_t(0.0, 0.32, v));
          final boat = Curves.elasticOut.transform(_t(0.14, 0.62, v));
          final boatFade = Curves.easeOut.transform(_t(0.1, 0.35, v));
          final shimmer = _t(0.42, 0.95, v);
          final wordmark = Curves.easeOutCubic.transform(_t(0.48, 0.82, v));
          final subline = Curves.easeOut.transform(_t(0.62, 0.9, v));
          final bobY = math.sin(_bob.value * math.pi * 2) * 4.5 * boat;
          final ripplePhase = _ripple.value;

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(_mist, Colors.white, 0.32 + 0.06 * math.sin(v * math.pi * 2 + ripplePhase))!,
                  const Color(0xFFE8EEF7),
                  Color.lerp(const Color(0xFFD4E4FA), _mist, 0.38 + 0.12 * v)!,
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _AuroraRings(progress: v, phase: ripplePhase),
                _DriftParticles(progress: v),
                CustomPaint(
                  painter: _WavePainter(progress: wave, color: _navy),
                  child: const SizedBox.expand(),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(0, 36 * (1 - boat) + bobY),
                        child: Opacity(
                          opacity: boatFade,
                          child: Transform.scale(
                            scale: lerpDouble(0.55, 1.0, boat)!,
                            child: Transform(
                              alignment: Alignment.bottomCenter,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateX((1 - boat) * 0.42)
                                ..rotateZ((1 - boat) * -0.04),
                              child: ShaderMask(
                                blendMode: BlendMode.srcATop,
                                shaderCallback: (bounds) {
                                  final sweep = bounds.width * 2.4;
                                  final dx = (shimmer * (bounds.width + sweep)) - sweep * 0.6;
                                  return LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      _skyLight.withOpacity(0.35),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.38, 0.5, 0.62],
                                    transform: _GradientPan(dx),
                                  ).createShader(bounds);
                                },
                                child: CustomPaint(
                                  size: const Size(260, 150),
                                  painter: _BoatMarkPainter(
                                    progress: boat,
                                    shimmer: shimmer,
                                    navy: _navy,
                                    navyDeep: _navyDeep,
                                    accent: _sky,
                                    accentLight: _skyLight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: wordmark,
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - wordmark)),
                          child: Text(
                            'madyaw',
                            style: TextStyle(
                              fontSize: 38,
                              height: 1.05,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.8,
                              fontFamily: 'Georgia',
                              fontFamilyFallback: const ['serif'],
                              color: _sky,
                              shadows: [
                                Shadow(
                                  color: _skyLight.withOpacity(0.55),
                                  blurRadius: 18,
                                  offset: const Offset(0, 2),
                                ),
                                Shadow(
                                  color: _navy.withOpacity(0.2),
                                  blurRadius: 0.5,
                                  offset: const Offset(0, 1.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Opacity(
                        opacity: subline,
                        child: Transform.translate(
                          offset: Offset(0, 8 * (1 - subline)),
                          child: Text(
                            'BOOKING APP',
                            style: TextStyle(
                              fontSize: 11.5,
                              letterSpacing: 5.2,
                              fontWeight: FontWeight.w700,
                              color: _navy.withOpacity(0.88),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: subline,
                        child: Text(
                          'Tap anywhere to continue',
                          style: TextStyle(
                            fontSize: 12,
                            color: _sky.withOpacity(0.78),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GradientPan extends GradientTransform {
  const _GradientPan(this.dx);

  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/// Stylized sailboat: hull → mast → sails (trimmed paths) + water sheen.
class _BoatMarkPainter extends CustomPainter {
  _BoatMarkPainter({
    required this.progress,
    required this.shimmer,
    required this.navy,
    required this.navyDeep,
    required this.accent,
    required this.accentLight,
  });

  final double progress;
  final double shimmer;
  final Color navy;
  final Color navyDeep;
  final Color accent;
  final Color accentLight;

  Path _hullPath() {
    final p = Path();
    p.moveTo(-52, 18);
    p.quadraticBezierTo(-8, 26, 56, 14);
    p.lineTo(62, 4);
    p.quadraticBezierTo(28, -6, -48, 6);
    p.close();
    return p;
  }

  Path _mastPath() {
    final p = Path();
    p.moveTo(-6, 8);
    p.lineTo(-6, -72);
    p.lineTo(2, -72);
    p.lineTo(2, 8);
    p.close();
    return p;
  }

  Path _sailFrontPath() {
    final p = Path();
    p.moveTo(-2, -70);
    p.quadraticBezierTo(48, -58, 58, -88);
    p.quadraticBezierTo(32, -102, -2, -78);
    p.close();
    return p;
  }

  Path _sailRearPath() {
    final p = Path();
    p.moveTo(-10, -68);
    p.quadraticBezierTo(-46, -62, -52, -90);
    p.quadraticBezierTo(-36, -100, -10, -76);
    p.close();
    return p;
  }

  Path _reflectionPath() {
    final p = Path();
    p.addOval(Rect.fromCenter(center: const Offset(8, 34), width: 88, height: 10));
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.72);

    final hullT = Curves.easeOutCubic.transform((progress / 0.45).clamp(0.0, 1.0));
    final mastT = Curves.easeOut.transform(((progress - 0.12) / 0.4).clamp(0.0, 1.0));
    final sailT = Curves.easeOut.transform(((progress - 0.22) / 0.55).clamp(0.0, 1.0));

    void drawTrimmed(Path path, Paint paint, double t) {
      if (t <= 0) return;
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * t), paint);
      }
    }

    // Soft shadow under boat
    if (hullT > 0.05) {
      canvas.save();
      canvas.translate(4, 6);
      canvas.scale(1.0, 0.35);
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.14 * hullT)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(_hullPath(), shadowPaint);
      canvas.restore();
    }

    // Hull
    final hullPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [navy, navyDeep],
      ).createShader(Rect.fromLTWH(-70, -90, 140, 120));

    canvas.save();
    canvas.scale(lerpDouble(0.86, 1.0, hullT)!, lerpDouble(0.75, 1.0, hullT)!);
    canvas.translate(0, 18 * (1 - hullT));
    drawTrimmed(_hullPath(), hullPaint, hullT);
    canvas.restore();

    // Mast
    final mastPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = navyDeep;
    canvas.save();
    canvas.translate(0, 10 * (1 - mastT));
    drawTrimmed(_mastPath(), mastPaint, mastT);
    canvas.restore();

    // Sails (gradient + trim)
    final sailShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        navy,
        Color.lerp(navy, accentLight, 0.35 + 0.15 * math.sin(shimmer * math.pi * 2))!,
        navyDeep,
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromLTWH(-70, -110, 140, 100));

    final rearPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = sailShader;
    final frontPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = sailShader;

    canvas.save();
    canvas.translate(-2 * (1 - sailT), -4 * (1 - sailT));
    drawTrimmed(_sailRearPath(), rearPaint, sailT);
    canvas.restore();

    canvas.save();
    canvas.translate(3 * (1 - sailT), -2 * (1 - sailT));
    drawTrimmed(_sailFrontPath(), frontPaint, sailT);
    canvas.restore();

    // Highlight stroke on sails
    if (sailT > 0.4) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withOpacity(0.22 * sailT);
      drawTrimmed(_sailFrontPath(), stroke, 1);
      drawTrimmed(_sailRearPath(), stroke, 1);
    }

    // Water sheen under hull
    if (hullT > 0.5) {
      final sheen = Paint()
        ..style = PaintingStyle.fill
        ..color = accent.withOpacity(0.12 * hullT * (0.5 + 0.5 * math.sin(shimmer * math.pi * 2)));
      drawTrimmed(_reflectionPath(), sheen, Curves.easeOut.transform(((hullT - 0.5) / 0.5).clamp(0.0, 1.0)));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BoatMarkPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.shimmer != shimmer ||
        oldDelegate.navy != navy ||
        oldDelegate.accentLight != accentLight;
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color.withOpacity(0.28 + 0.22 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    final baseY = size.height * 0.58;
    final path = Path();
    const step = 5.0;
    for (double x = 0; x <= size.width; x += step) {
      final w = math.sin((x / size.width) * math.pi * 2 + progress * 1.15) * 8 * progress;
      if (x == 0) {
        path.moveTo(x, baseY + w);
      } else {
        path.lineTo(x, baseY + w);
      }
    }

    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }

    final glow = Paint()
      ..color = color.withOpacity(0.07 * progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawPath(path, glow);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _AuroraRings extends StatelessWidget {
  const _AuroraRings({required this.progress, required this.phase});

  final double progress;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AuroraPainter(progress: progress, phase: phase),
      child: const SizedBox.expand(),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.progress, required this.phase});

  final double progress;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.38;
    for (var i = 0; i < 3; i++) {
      final r = 80.0 + i * 55 + 20 * math.sin(phase * math.pi * 2 + i);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF4A90D9).withOpacity(0.04 * progress * (1 - i * 0.25));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.phase != phase;
}

class _DriftParticles extends StatelessWidget {
  const _DriftParticles({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ParticlesPainter(progress: progress),
      child: const SizedBox.expand(),
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (var i = 0; i < 32; i++) {
      final x = rnd.nextDouble() * size.width;
      final baseY = rnd.nextDouble() * size.height;
      final speed = 0.35 + rnd.nextDouble() * 0.95;
      final y = (baseY - progress * size.height * speed * 1.35) % (size.height + 36) - 18;
      final r = 1.0 + rnd.nextDouble() * 2.0;
      final o = 0.035 + rnd.nextDouble() * 0.1;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = const Color(0xFF4A90D9).withOpacity(o * (0.45 + 0.55 * progress)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
