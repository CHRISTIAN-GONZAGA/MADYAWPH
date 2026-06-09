import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../branding/madyaw_intro_logo.dart';
import '../branding/madyaw_logo_paths.dart';

/// Premium programmatic intro — light branded canvas, staged logo reveal.
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 3400);

  late final AnimationController _timeline;
  bool _ended = false;
  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = SchedulerBinding.instance.platformDispatcher
        .accessibilityFeatures
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

    return Material(
      color: MadyawBrand.introBgTop,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: _timeline,
          builder: (context, _) {
            final t = _timeline.value;

            final bgIn = Curves.easeOutCubic.transform(_t(0, 0.14));
            final ambient = Curves.easeOut.transform(_t(0.06, 0.38));
            final logoDraw = Curves.easeInOutCubic.transform(_t(0.1, 0.55));
            final logoSettle = Curves.easeOutExpo.transform(_t(0.44, 0.62));
            final shine = Curves.easeInOut.transform(_t(0.56, 0.74));
            final glow = Curves.easeOut.transform(_t(0.4, 0.68));
            final wordmark = Curves.easeOutCubic.transform(_t(0.64, 0.84));
            final subtitle = Curves.easeOut.transform(_t(0.74, 0.9));
            final tagline = Curves.easeOut.transform(_t(0.8, 0.94));
            final exitFade = Curves.easeInCubic.transform(_t(0.94, 1.0));
            final screenOpacity = 1.0 - exitFade;

            final logoScale =
                reduceMotion ? 1.0 : lerpDouble(0.9, 1.0, logoSettle)!;
            final logoLift = reduceMotion ? 0.0 : 18 * (1 - logoSettle);
            final breathe = reduceMotion ? 0.0 : t * 0.35;

            return Opacity(
              opacity: screenOpacity.clamp(0, 1),
              child: ColoredBox(
                color: MadyawBrand.introBgTop,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(
                              MadyawBrand.introBgTop,
                              MadyawBrand.introAccent,
                              bgIn,
                            )!,
                            Color.lerp(
                              MadyawBrand.introBgBottom,
                              Colors.white,
                              bgIn * 0.35,
                            )!,
                          ],
                        ),
                      ),
                    ),

                    if (!reduceMotion)
                      CustomPaint(
                        painter: _AmbientPainter(
                          strength: ambient,
                          pulse: t,
                        ),
                        child: const SizedBox.expand(),
                      ),

                    Center(
                      child: Transform.translate(
                        offset: Offset(0, logoLift),
                        child: Transform.scale(
                          scale: logoScale,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                    offset: Offset(0, 6 * (1 - subtitle)),
                                    child: _PhBadge(reveal: subtitle),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

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
                                  foregroundColor: MadyawBrand.navy
                                      .withValues(alpha: 0.55),
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
                              offset: Offset(0, 10 * (1 - tagline)),
                              child: Column(
                                children: [
                                  Text(
                                    'Hotel operations, refined',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5,
                                      color: MadyawBrand.navy
                                          .withValues(alpha: 0.72),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Rooms · Bookings · Wallet · Staff',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0.35,
                                      color: MadyawBrand.navy
                                          .withValues(alpha: 0.42),
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
      scale: 0.92 + 0.08 * Curves.easeOutBack.transform(reveal),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: MadyawBrand.brightBlue.withValues(alpha: 0.5 * reveal),
          ),
          color: MadyawBrand.brightBlue.withValues(alpha: 0.1 * reveal),
        ),
        child: Text(
          'PH',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: MadyawBrand.navy.withValues(alpha: 0.88 * reveal),
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
    final cy = size.height * 0.36;
    final breathe = 1 + math.sin(pulse * math.pi * 2) * 0.03;

    final orb = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9 * breathe,
        colors: [
          MadyawBrand.brightBlue.withValues(alpha: 0.12 * strength),
          MadyawBrand.brightBlue.withValues(alpha: 0.03 * strength),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(cx, cy),
        radius: size.width * 0.5,
      ));
    canvas.drawRect(Offset.zero & size, orb);

    final edge = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.05,
        colors: [
          Colors.transparent,
          MadyawBrand.navy.withValues(alpha: 0.06 * strength),
        ],
        stops: const [0.7, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, edge);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) =>
      old.strength != strength || old.pulse != pulse;
}
