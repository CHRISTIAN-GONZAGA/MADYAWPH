import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../branding/madyaw_logo_paths.dart';

/// Intro matching the official MADYAW logo asset (light grey canvas).
class MadyawIntroScreen extends StatefulWidget {
  const MadyawIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<MadyawIntroScreen> createState() => _MadyawIntroScreenState();
}

class _MadyawIntroScreenState extends State<MadyawIntroScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2800);
  static const _bg = Color(0xFFE8EAED);

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
    final logoSize = math.min(260.0, size.width * 0.62);
    final reduceMotion = _reduceMotion ||
        MediaQuery.maybeOf(context)?.disableAnimations == true;

    return Material(
      color: _bg,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: _timeline,
          builder: (context, _) {
            final logoIn = Curves.easeOutCubic.transform(_t(0.08, 0.45));
            final settle = Curves.easeOutBack.transform(_t(0.35, 0.7));
            final exitFade = Curves.easeInCubic.transform(_t(0.88, 1.0));
            final opacity = (1.0 - exitFade).clamp(0.0, 1.0);
            final scale = reduceMotion ? 1.0 : (0.92 + 0.08 * settle);
            final lift = reduceMotion ? 0.0 : 16 * (1 - logoIn);

            return Opacity(
              opacity: opacity,
              child: ColoredBox(
                color: _bg,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: logoIn.clamp(0.0, 1.0),
                        child: Image.asset(
                          'assets/branding/madyaw_logo.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Text(
                            MadyawBrand.wordmark,
                            style: TextStyle(
                              fontSize: logoSize * 0.18,
                              fontWeight: FontWeight.w800,
                              color: MadyawBrand.navy,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
