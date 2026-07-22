import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../branding/madyaw_logo_paths.dart';

/// Premium MADYAW intro — soft atmosphere + transparent mark (no PNG plate).
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 3400);

  late final AnimationController _timeline;
  late final AnimationController _breathe;
  bool _ended = false;
  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = SchedulerBinding.instance.platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _timeline = AnimationController(vsync: this, duration: _duration);
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (!_reduceMotion) {
      _breathe.repeat(reverse: true);
    }
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
    _breathe.dispose();
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
      color: MadyawBrand.introBgBottom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: Listenable.merge([_timeline, _breathe]),
          builder: (context, _) {
            final hazeIn = Curves.easeOut.transform(_t(0.0, 0.28));
            final glowIn = Curves.easeOutCubic.transform(_t(0.06, 0.42));
            final logoIn = Curves.easeOutCubic.transform(_t(0.1, 0.48));
            final settle = Curves.easeOutBack.transform(_t(0.32, 0.72));
            final waveIn = Curves.easeOutCubic.transform(_t(0.28, 0.62));
            final shine = Curves.easeInOut.transform(_t(0.52, 0.82));
            final exitFade = Curves.easeInCubic.transform(_t(0.88, 1.0));
            final opacity = (1.0 - exitFade).clamp(0.0, 1.0);

            final breath = reduceMotion ? 0.0 : _breathe.value;
            final floatY = reduceMotion ? 0.0 : math.sin(breath * math.pi) * 5;
            final scale = reduceMotion
                ? 1.0
                : (0.88 + 0.12 * settle) * (1 + 0.012 * math.sin(breath * math.pi));
            final lift = reduceMotion ? 0.0 : 28 * (1 - logoIn) + floatY;

            return Opacity(
              opacity: opacity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Soft brand atmosphere (not a flat grey card).
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(
                            MadyawBrand.introBgTop,
                            const Color(0xFFF5F7FB),
                            1 - hazeIn,
                          )!,
                          Color.lerp(
                            MadyawBrand.introBgBottom,
                            MadyawBrand.introAccent,
                            0.35 * hazeIn,
                          )!,
                        ],
                      ),
                    ),
                  ),
                  // Soft radial bloom behind the mark.
                  Center(
                    child: Opacity(
                      opacity: (0.55 + 0.45 * glowIn) * logoIn,
                      child: Transform.scale(
                        scale: 0.85 + 0.25 * glowIn,
                        child: Container(
                          width: logoSize * 1.35,
                          height: logoSize * 1.15,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                MadyawBrand.brightBlue
                                    .withValues(alpha: 0.18 * glowIn),
                                MadyawBrand.brightBlue
                                    .withValues(alpha: 0.06 * glowIn),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Ambient ripple rings.
                  if (!reduceMotion)
                    Center(
                      child: CustomPaint(
                        size: Size(logoSize * 1.6, logoSize * 1.2),
                        painter: _IntroRipplePainter(
                          progress: waveIn,
                          phase: breath,
                          color: MadyawBrand.brightBlue,
                        ),
                      ),
                    ),
                  // Logo + soft under-glow (hides hard PNG edges).
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, lift),
                      child: Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: logoIn.clamp(0.0, 1.0),
                          child: SizedBox(
                            width: logoSize,
                            height: logoSize,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Diffuse halo so the mark floats, not a cutout.
                                IgnorePointer(
                                  child: ImageFiltered(
                                    imageFilter: ui.ImageFilter.blur(
                                      sigmaX: 18,
                                      sigmaY: 18,
                                    ),
                                    child: Opacity(
                                      opacity: 0.22 * glowIn,
                                      child: Image.asset(
                                        'assets/branding/madyaw_logo.png',
                                        width: logoSize * 0.92,
                                        height: logoSize * 0.92,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                                Image.asset(
                                  'assets/branding/madyaw_logo.png',
                                  width: logoSize,
                                  height: logoSize,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) => Text(
                                    MadyawBrand.wordmark,
                                    style: TextStyle(
                                      fontSize: logoSize * 0.16,
                                      fontWeight: FontWeight.w800,
                                      color: MadyawBrand.navy,
                                      letterSpacing: 4,
                                    ),
                                  ),
                                ),
                                // Light sweep across the mark.
                                if (!reduceMotion && shine > 0.01)
                                  IgnorePointer(
                                    child: ClipRect(
                                      child: CustomPaint(
                                        size: Size(logoSize, logoSize),
                                        painter: _IntroShinePainter(
                                          progress: shine,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IntroRipplePainter extends CustomPainter {
  _IntroRipplePainter({
    required this.progress,
    required this.phase,
    required this.color,
  });

  final double progress;
  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01) return;
    final cx = size.width * 0.5;
    final cy = size.height * 0.58;
    final base = math.min(size.width, size.height);

    for (var i = 0; i < 3; i++) {
      final t = ((progress + phase * 0.15 + i * 0.18) % 1.0);
      final radius = base * (0.22 + 0.28 * t);
      final alpha = (1 - t) * 0.14 * progress;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 + (1 - t) * 1.2
        ..color = color.withValues(alpha: alpha)
        ..isAntiAlias = true;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: radius * 2.1,
          height: radius * 0.55,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IntroRipplePainter old) =>
      old.progress != progress || old.phase != phase;
}

class _IntroShinePainter extends CustomPainter {
  _IntroShinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final sweepW = size.width * 0.42;
    final x = ui.lerpDouble(-sweepW, size.width + sweepW, progress)!;
    final paint = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.0),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(x, 0, sweepW, size.height));
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _IntroShinePainter old) =>
      old.progress != progress;
}
