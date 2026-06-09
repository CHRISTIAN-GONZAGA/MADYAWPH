import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../branding/madyaw_intro_logo.dart';
import '../branding/madyaw_logo_paths.dart';

/// Premium programmatic intro — Apple-style staged reveal, shine pass, seamless exit.
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 3200);

  late final AnimationController _timeline;
  bool _ended = false;
  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = SchedulerBinding.instance.platformDispatcher.accessibilityFeatures
        .disableAnimations;
    _timeline = AnimationController(vsync: this, duration: _duration);
    _timeline.forward();
    _timeline.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    HapticFeedback.lightImpact();
    widget.onFinished();
  }

  void _skip() {
    if (_ended) return;
    _timeline.stop();
    _finish();
  }

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  double _t(double start, double end) {
    final v = _timeline.value;
    if (v <= start) return 0;
    if (v >= end) return 1;
    return ((v - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoSize = math.min(280.0, size.width * 0.68);
    final reduceMotion = _reduceMotion ||
        MediaQuery.maybeOf(context)?.disableAnimations == true;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: _timeline,
        builder: (context, _) {
          final t = _timeline.value;

          // Timeline choreography (2.5–4s total feel)
          final bgIn = Curves.easeOutCubic.transform(_t(0, 0.12));
          final ambient = Curves.easeOut.transform(_t(0.05, 0.35));
          final logoDraw = Curves.easeInOutCubic.transform(_t(0.08, 0.52));
          final logoSettle = Curves.easeOutExpo.transform(_t(0.42, 0.58));
          final shine = Curves.easeInOut.transform(_t(0.54, 0.72));
          final glow = Curves.easeOut.transform(_t(0.38, 0.65));
          final wordmark = Curves.easeOutCubic.transform(_t(0.62, 0.82));
          final subtitle = Curves.easeOut.transform(_t(0.72, 0.88));
          final tagline = Curves.easeOut.transform(_t(0.78, 0.92));
          final exitFade = Curves.easeInCubic.transform(_t(0.93, 1.0));
          final screenOpacity = 1.0 - exitFade;

          final logoScale = reduceMotion
              ? 1.0
              : lerpDouble(0.88, 1.0, logoSettle)!;
          final logoLift = reduceMotion ? 0.0 : 24 * (1 - logoSettle);
          final breathe = reduceMotion ? 0.0 : t * 0.4;

          return Opacity(
            opacity: screenOpacity.clamp(0, 1),
            child: ColoredBox(
              color: MadyawBrand.introBgTop,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Branded gradient background
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(
                            MadyawBrand.introBgTop,
                            const Color(0xFF0E1524),
                            bgIn,
                          )!,
                          Color.lerp(
                            MadyawBrand.introBgBottom,
                            const Color(0xFF0A1020),
                            bgIn,
                          )!,
                        ],
                      ),
                    ),
                  ),

                  // Ambient orb + vignette
                  if (!reduceMotion)
                    CustomPaint(
                      painter: _AmbientPainter(
                        strength: ambient,
                        pulse: t,
                      ),
                      child: const SizedBox.expand(),
                    ),

                  // Subtle particles
                  if (!reduceMotion && ambient > 0.1)
                    CustomPaint(
                      painter: _ParticlePainter(phase: t, count: 18),
                      child: const SizedBox.expand(),
                    ),

                  // Logo + wordmark stack
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, logoLift),
                      child: Transform.scale(
                        scale: logoScale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MadyawIntroLogo(
                              size: logoSize,
                              drawProgress: logoDraw,
                              shineProgress: shine,
                              glowStrength: glow,
                              breathe: breathe,
                              reduceMotion: reduceMotion,
                            ),
                            SizedBox(height: logoSize * 0.1),
                            Opacity(
                              opacity: wordmark,
                              child: MadyawIntroWordmark(
                                progress: wordmark,
                                fontSize: logoSize * 0.11,
                              ),
                            ),
                            SizedBox(height: logoSize * 0.04),
                            Opacity(
                              opacity: subtitle,
                              child: Transform.translate(
                                offset: Offset(0, 8 * (1 - subtitle)),
                                child: _PhBadge(reveal: subtitle),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Tagline
                  SafeArea(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: TextButton(
                              onPressed: _skip,
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    Colors.white.withValues(alpha: 0.55),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Skip',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Opacity(
                          opacity: tagline,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - tagline)),
                            child: Column(
                              children: [
                                Text(
                                  'Hotel operations, refined',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.6,
                                    color: Colors.white.withValues(alpha: 0.72),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Rooms · Bookings · Wallet · Staff',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0.4,
                                    color: Colors.white.withValues(alpha: 0.38),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhBadge extends StatelessWidget {
  const _PhBadge({required this.reveal});

  final double reveal;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.9 + 0.1 * Curves.easeOutBack.transform(reveal),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: MadyawBrand.brightBlue.withValues(alpha: 0.45 * reveal),
          ),
          color: MadyawBrand.brightBlue.withValues(alpha: 0.12 * reveal),
        ),
        child: Text(
          'PH',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Colors.white.withValues(alpha: 0.85 * reveal),
          ),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({required this.strength, required this.pulse});

  final double strength;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;

    final cx = size.width * 0.5;
    final cy = size.height * 0.38;
    final breathe = 1 + math.sin(pulse * math.pi * 2) * 0.04;

    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.85 * breathe,
        colors: [
          MadyawBrand.brightBlue.withValues(alpha: 0.14 * strength),
          MadyawBrand.brightBlue.withValues(alpha: 0.04 * strength),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(cx, cy),
        radius: size.width * 0.55,
      ));

    canvas.drawRect(Offset.zero & size, paint);

    // Soft vignette
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.1,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.45 * strength),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) =>
      old.strength != strength || old.pulse != pulse;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.phase, this.count = 18});

  final double phase;
  final int count;
  final _rng = math.Random(7);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < count; i++) {
      final bx = _rng.nextDouble();
      final by = _rng.nextDouble();
      final speed = 0.15 + _rng.nextDouble() * 0.35;
      final x = (bx + phase * speed) % 1.0 * size.width;
      final y = (by + phase * speed * 0.25) % 1.0 * size.height;
      final r = 0.8 + _rng.nextDouble() * 1.2;
      final alpha = 0.04 + _rng.nextDouble() * 0.1;

      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.phase != phase;
}
