import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Cinematic splash: wave stroke, logo rise + scale, shimmer sweep, gentle bob, tap to skip.
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
  bool _ended = false;

  static const _navy = Color(0xFF1B2B4A);
  static const _sky = Color(0xFF4A90D9);
  static const _mist = Color(0xFFF0F4FA);

  @override
  void initState() {
    super.initState();
    _sequence = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addStatusListener(_onSequenceStatus);

    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

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
    widget.onFinished();
  }

  @override
  void dispose() {
    _sequence.removeStatusListener(_onSequenceStatus);
    _sequence.dispose();
    _bob.dispose();
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
        animation: Listenable.merge([_sequence, _bob]),
        builder: (context, _) {
          final v = _sequence.value;
          final wave = Curves.easeOutCubic.transform(_t(0.0, 0.38, v));
          final logoEnter = Curves.elasticOut.transform(_t(0.22, 0.72, v));
          final logoFade = Curves.easeOut.transform(_t(0.18, 0.45, v));
          final shimmer = _t(0.5, 0.92, v);
          final tagline = Curves.easeOut.transform(_t(0.58, 0.88, v));
          final bobY = math.sin(_bob.value * math.pi * 2) * 5.0 * logoEnter;

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(_mist, Colors.white, 0.35 + 0.08 * math.sin(v * math.pi * 2))!,
                  const Color(0xFFE8EEF7),
                  Color.lerp(const Color(0xFFD4E4FA), _mist, 0.4 + 0.15 * v)!,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
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
                        offset: Offset(0, 48 * (1 - logoEnter) + bobY),
                        child: Opacity(
                          opacity: logoFade,
                          child: Transform.scale(
                            scale: lerpDouble(0.45, 1.0, logoEnter)!,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0012)
                                ..rotateX((1 - logoEnter) * 0.35)
                                ..rotateY((1 - logoEnter) * -0.08),
                              child: _ShimmerLogoMask(
                                shimmerAmount: shimmer,
                                child: Image.asset(
                                  'assets/images/madyaw_logo.png',
                                  width: 260,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Opacity(
                        opacity: tagline,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - tagline)),
                          child: Column(
                            children: [
                              Text(
                                'MADYAW',
                                style: TextStyle(
                                  fontSize: 13,
                                  letterSpacing: 6,
                                  fontWeight: FontWeight.w600,
                                  color: _navy.withOpacity(0.55),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap anywhere to continue',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _sky.withOpacity(0.75),
                                ),
                              ),
                            ],
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

class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color.withOpacity(0.35 + 0.25 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    final baseY = size.height * 0.58;
    final path = Path();
    const step = 6.0;
    for (double x = 0; x <= size.width; x += step) {
      final w = math.sin((x / size.width) * math.pi * 2 + progress * 1.2) * 7 * progress;
      if (x == 0) {
        path.moveTo(x, baseY + w);
      } else {
        path.lineTo(x, baseY + w);
      }
    }

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final extract = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(extract, paint);
    }

    final glow = Paint()
      ..color = color.withOpacity(0.08 * progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(path, glow..style = PaintingStyle.stroke..strokeWidth = 10);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _ShimmerLogoMask extends StatelessWidget {
  const _ShimmerLogoMask({required this.shimmerAmount, required this.child});

  final double shimmerAmount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        final sweep = bounds.width * 2.2;
        final dx = (shimmerAmount * (bounds.width + sweep)) - sweep;
        return LinearGradient(
          colors: [
            Colors.white.withOpacity(0),
            Colors.white.withOpacity(0.55),
            Colors.white.withOpacity(0),
          ],
          stops: const [0.35, 0.5, 0.65],
          transform: GradientTranslation(dx, 0),
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

class GradientTranslation extends GradientTransform {
  const GradientTranslation(this.dx, this.dy);

  final double dx;
  final double dy;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, dy, 0);
  }
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
    final rnd = math.Random(4);
    for (var i = 0; i < 28; i++) {
      final x = (rnd.nextDouble()) * size.width;
      final baseY = rnd.nextDouble() * size.height;
      final speed = 0.4 + rnd.nextDouble() * 0.9;
      final y = (baseY - progress * size.height * speed * 1.4) % (size.height + 40) - 20;
      final r = 1.2 + rnd.nextDouble() * 2.2;
      final o = 0.04 + rnd.nextDouble() * 0.12;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = const Color(0xFF4A90D9).withOpacity(o * (0.5 + 0.5 * progress)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
