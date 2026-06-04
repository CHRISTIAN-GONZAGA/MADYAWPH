import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../branding/madyaw_logo_widget.dart';

/// Cinematic splash — vector logo, ocean waves, particles, staged reveal.
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _timeline;
  late final AnimationController _waves;
  late final AnimationController _particles;
  late final AnimationController _burst;
  bool _ended = false;

  static const _deepNavy = Color(0xFF0D1B2A);
  static const _ocean = Color(0xFF1B4965);
  static const _sky = Color(0xFFCAE9FF);

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _waves = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _particles = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _timeline.forward();
    _timeline.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    HapticFeedback.mediumImpact();
    _timeline.stop();
    widget.onFinished();
  }

  void _skip() {
    _burst.forward(from: 0);
    _finish();
  }

  @override
  void dispose() {
    _timeline.dispose();
    _waves.dispose();
    _particles.dispose();
    _burst.dispose();
    super.dispose();
  }

  double _interval(double start, double end) {
    final t = _timeline.value;
    if (t <= start) return 0;
    if (t >= end) return 1;
    return ((t - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoSize = math.min(300.0, size.width * 0.78);

    final bgReveal = Curves.easeOutCubic.transform(_interval(0, 0.25));
    final logoDraw = Curves.easeInOutCubic.transform(_interval(0.08, 0.45));
    final logoPop = Curves.elasticOut.transform(_interval(0.38, 0.58));
    final letters = Curves.easeOutCubic.transform(_interval(0.42, 0.72));
    final tagline = Curves.easeOut.transform(_interval(0.68, 0.88));
    final cta = Curves.easeOut.transform(_interval(0.82, 0.95));
    final sway = math.sin(_timeline.value * math.pi * 3) * 2.5 * logoDraw;
    final wavePhase = _waves.value;
    final glow = 0.4 + 0.6 * math.sin(_timeline.value * math.pi * 2).abs();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _timeline,
          _waves,
          _particles,
          _burst,
        ]),
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(Colors.white, _sky, bgReveal)!,
                  Color.lerp(_sky, _ocean, bgReveal * 0.6)!,
                  Color.lerp(_ocean, _deepNavy, bgReveal * 0.35)!,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _SunRaysPainter(
                    progress: _interval(0.1, 0.6),
                    pulse: _particles.value,
                  ),
                  child: const SizedBox.expand(),
                ),
                CustomPaint(
                  painter: _ParticleFieldPainter(
                    phase: _particles.value,
                    count: 24,
                  ),
                  child: const SizedBox.expand(),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: CustomPaint(
                    size: Size(size.width, size.height * 0.42),
                    painter: _OceanWavesPainter(
                      phase: wavePhase,
                      depth: bgReveal,
                    ),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - logoPop) + sway),
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * logoPop,
                      child: Opacity(
                        opacity: logoDraw.clamp(0, 1),
                        child: _LogoStage(
                          logoSize: logoSize,
                          drawProgress: logoDraw,
                          letterReveal: letters,
                          glowStrength: glow,
                          wavePhase: wavePhase,
                          swayAngle: sway,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_burst.value > 0)
                  CustomPaint(
                    painter: _BurstPainter(
                      progress: Curves.easeOut.transform(_burst.value),
                      center: Offset(size.width / 2, size.height * 0.42),
                    ),
                    child: const SizedBox.expand(),
                  ),
                SafeArea(
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextButton(
                            onPressed: _skip,
                            style: TextButton.styleFrom(
                              foregroundColor: MadyawLogoWidget.navy
                                  .withValues(alpha: 0.7),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.65),
                            ),
                            child: const Text('Skip'),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Opacity(
                        opacity: tagline,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - tagline)),
                          child: Column(
                            children: [
                              Text(
                                'Hotel operations, simplified',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: MadyawLogoWidget.navy
                                      .withValues(alpha: 0.9),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Rooms · Bookings · Guests · Staff',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: MadyawLogoWidget.navy
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Opacity(
                        opacity: cta,
                        child: Column(
                          children: [
                            SizedBox(
                              width: 120,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _timeline.value,
                                  minHeight: 3,
                                  backgroundColor: MadyawLogoWidget.navy
                                      .withValues(alpha: 0.12),
                                  color: MadyawLogoWidget.brightBlue,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Tap anywhere to continue',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: MadyawLogoWidget.navy
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: size.height * 0.14),
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

class _LogoStage extends StatelessWidget {
  const _LogoStage({
    required this.logoSize,
    required this.drawProgress,
    required this.letterReveal,
    required this.glowStrength,
    required this.wavePhase,
    required this.swayAngle,
  });

  final double logoSize;
  final double drawProgress;
  final double letterReveal;
  final double glowStrength;
  final double wavePhase;
  final double swayAngle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: MadyawLogoWidget.brightBlue.withValues(alpha: 0.25),
            blurRadius: 32,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: MadyawLogoWidget.brightBlue.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: MadyawLogoWidget(
        size: logoSize,
        drawProgress: drawProgress,
        textOpacity: letterReveal,
        letterReveal: letterReveal,
        useStaggeredWordmark: true,
        glowStrength: glowStrength,
        wavePhase: wavePhase,
        swayAngle: swayAngle,
      ),
    );
  }
}

class _ParticleFieldPainter extends CustomPainter {
  _ParticleFieldPainter({required this.phase, required this.count});

  final double phase;
  final int count;
  final _rng = math.Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < count; i++) {
      final bx = _rng.nextDouble();
      final by = _rng.nextDouble();
      final speed = 0.3 + _rng.nextDouble() * 0.7;
      final x = (bx + phase * speed) % 1.0 * size.width;
      final y = (by + phase * speed * 0.4) % 1.0 * size.height * 0.85;
      final r = 1.5 + _rng.nextDouble() * 2.5;
      final alpha = 0.08 + _rng.nextDouble() * 0.2;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleFieldPainter old) =>
      old.phase != phase;
}

class _SunRaysPainter extends CustomPainter {
  _SunRaysPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final cx = size.width * 0.5;
    final cy = size.height * 0.32;
    final rayCount = 12;
    for (var i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * math.pi * 2 + pulse * math.pi * 2;
      final len = size.width * 0.55 * progress;
      final path = Path()
        ..moveTo(cx, cy)
        ..lineTo(
          cx + math.cos(angle) * len,
          cy + math.sin(angle) * len,
        );
      final rayPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..strokeCap = StrokeCap.round
        ..color =
            MadyawLogoWidget.brightBlue.withValues(alpha: 0.04 * progress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawPath(path, rayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SunRaysPainter old) =>
      old.progress != progress || old.pulse != pulse;
}

class _OceanWavesPainter extends CustomPainter {
  _OceanWavesPainter({required this.phase, required this.depth});

  final double phase;
  final double depth;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;

    void drawWave(double yOff, Color color, double amp, double speed) {
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += 6) {
        final y = yOff +
            amp * math.sin((x / w) * math.pi * 4 + phase * math.pi * 2 * speed);
        path.lineTo(x, y);
      }
      path.lineTo(w, h);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    final base = h * (0.55 - 0.15 * depth);
    drawWave(
      base,
      MadyawLogoWidget.brightBlue.withValues(alpha: 0.35),
      14,
      1,
    );
    drawWave(
      base + 18,
      MadyawLogoWidget.navy.withValues(alpha: 0.5),
      10,
      1.3,
    );
    drawWave(
      base + 36,
      const Color(0xFF0D1B2A).withValues(alpha: 0.75),
      8,
      0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _OceanWavesPainter old) =>
      old.phase != phase || old.depth != depth;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.center});

  final double progress;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final radius = size.width * 0.8 * progress;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          MadyawLogoWidget.brightBlue.withValues(alpha: 0.2 * (1 - progress)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.progress != progress;
}
