import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../branding/madyaw_logo_widget.dart';

/// Splash with vector-drawn Madyaw logo and staged motion.
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _main;
  late final AnimationController _pulse;
  bool _ended = false;

  static const _navy = MadyawLogoWidget.navy;
  static const _mist = Color(0xFFE8EEF5);

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _main.forward();
    _main.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finish();
      }
    });
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    HapticFeedback.lightImpact();
    if (_main.isAnimating) _main.stop();
    widget.onFinished();
  }

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draw = CurvedAnimation(
      parent: _main,
      curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
    );
    final textIn = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.42, 0.72, curve: Curves.easeOut),
    );
    final cardIn = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.08, 0.5, curve: Curves.easeOutBack),
    );
    final tagline = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.62, 0.88, curve: Curves.easeOut),
    );
    final shimmer = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.5, 1, curve: Curves.easeInOut),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(Colors.white, _mist, 0.2)!,
              _mist,
              Color.lerp(_mist, const Color(0xFFB8D4F5), 0.5)!,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_main, _pulse]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _IntroAmbientPainter(
                    phase: _main.value,
                    pulse: _pulse.value,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
            Center(
              child: AnimatedBuilder(
                animation: _main,
                builder: (context, child) {
                  final scale = 0.82 + 0.18 * cardIn.value;
                  final y = 24 * (1 - cardIn.value);
                  return Transform.translate(
                    offset: Offset(0, y),
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: cardIn.value.clamp(0, 1),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _main,
                      builder: (context, _) {
                        final glow = 0.35 +
                            0.65 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          shimmer.value * math.pi * 2,
                                        ));
                        return Material(
                          elevation: 8 + 10 * cardIn.value,
                          shadowColor: MadyawLogoWidget.brightBlue
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 28,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: MadyawLogoWidget.brightBlue
                                    .withValues(alpha: 0.12),
                              ),
                            ),
                            child: MadyawLogoWidget(
                              size: math.min(
                                260,
                                MediaQuery.sizeOf(context).width * 0.68,
                              ),
                              drawProgress: draw.value,
                              textOpacity: textIn.value,
                              glowStrength: glow,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: tagline,
                      child: Column(
                        children: [
                          Text(
                            'Hotel operations, simplified',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              color: _navy.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tap to continue',
                            style: TextStyle(
                              fontSize: 12,
                              color: _navy.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroAmbientPainter extends CustomPainter {
  _IntroAmbientPainter({required this.phase, required this.pulse});

  final double phase;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.4;

    for (var i = 0; i < 3; i++) {
      final t = (phase + i * 0.15) % 1;
      final r = 80 + i * 40 + 25 * math.sin(t * math.pi * 2);
      final paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36)
        ..color = Color.lerp(
          MadyawLogoWidget.brightBlue,
          Colors.white,
          0.5 + i * 0.15,
        )!
            .withValues(alpha: (0.06 + 0.04 * pulse) * (1 - t * 0.5));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = MadyawLogoWidget.brightBlue
          .withValues(alpha: 0.08 * (0.5 + 0.5 * pulse));
    canvas.drawCircle(
      Offset(cx, cy),
      100 + 20 * phase,
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _IntroAmbientPainter old) =>
      old.phase != phase || old.pulse != pulse;
}
