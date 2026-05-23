import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Splash using the official logo asset; tap to skip.
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _ended = false;

  static const _navy = Color(0xFF1A3150);
  static const _mist = Color(0xFFE8EEF5);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finish();
      }
    });
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    if (_controller.isAnimating) {
      _controller.stop();
    }
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    final fade = Tween<double>(begin: 0, end: 1).animate(curved);
    final scale = Tween<double>(begin: 0.92, end: 1).animate(curved);
    final drift = Tween<double>(begin: 6, end: 0).animate(curved);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(Colors.white, _mist, 0.35)!,
              _mist,
              Color.lerp(_mist, const Color(0xFFD4E4FA), 0.45)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SoftGlowPainter(progress: _controller.value),
                  child: const SizedBox.expand(),
                );
              },
            ),
            Center(
              child: FadeTransition(
                opacity: fade,
                child: Transform.translate(
                  offset: Offset(0, drift.value),
                  child: ScaleTransition(
                    scale: scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          elevation: 12,
                          shadowColor: Colors.black26,
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 20,
                            ),
                            child: Image.asset(
                              'assets/branding/madyaw_logo.png',
                              width: math.min(280, MediaQuery.sizeOf(context).width * 0.72),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Tap anywhere to continue',
                          style: TextStyle(
                            fontSize: 13,
                            color: _navy.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftGlowPainter extends CustomPainter {
  _SoftGlowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.42;
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40)
      ..color = Color.lerp(
            const Color(0xFF64B5F6),
            Colors.white,
            0.65,
          )!
          .withValues(alpha: 0.14 * (0.5 + 0.5 * math.sin(progress * math.pi * 2)));
    canvas.drawCircle(Offset(cx, cy), 120 + 30 * math.sin(progress * math.pi * 2), paint);
  }

  @override
  bool shouldRepaint(covariant _SoftGlowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
