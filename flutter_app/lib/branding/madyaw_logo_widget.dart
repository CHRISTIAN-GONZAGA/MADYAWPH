import 'package:flutter/material.dart';

/// Vector Madyaw sailboat mark + wordmark (no image asset).
class MadyawLogoWidget extends StatelessWidget {
  const MadyawLogoWidget({
    super.key,
    this.size = 200,
    this.drawProgress = 1,
    this.textOpacity = 1,
    this.glowStrength = 0,
    this.showWordmark = true,
  });

  final double size;
  /// 0–1 animates boat paths drawing in.
  final double drawProgress;
  final double textOpacity;
  final double glowStrength;
  final bool showWordmark;

  static const Color brightBlue = Color(0xFF0077C8);
  static const Color navy = Color(0xFF1A3150);

  @override
  Widget build(BuildContext context) {
    final markH = size * (showWordmark ? 0.62 : 1);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MadyawLogoPainter(
          drawProgress: drawProgress.clamp(0, 1),
          textOpacity: textOpacity.clamp(0, 1),
          glowStrength: glowStrength.clamp(0, 1),
          showWordmark: showWordmark,
          markHeight: markH,
        ),
      ),
    );
  }
}

class _MadyawLogoPainter extends CustomPainter {
  _MadyawLogoPainter({
    required this.drawProgress,
    required this.textOpacity,
    required this.glowStrength,
    required this.showWordmark,
    required this.markHeight,
  });

  final double drawProgress;
  final double textOpacity;
  final double glowStrength;
  final bool showWordmark;
  final double markHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final scale = markHeight / 120;

    if (glowStrength > 0.01) {
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28)
        ..color = MadyawLogoWidget.brightBlue
            .withValues(alpha: 0.22 * glowStrength);
      canvas.drawCircle(Offset(cx, markHeight * 0.38), 52 * scale, glow);
    }

    canvas.save();
    canvas.translate(cx, markHeight * 0.08);
    canvas.scale(scale);

    final layers = <_LogoLayer>[
      _LogoLayer(
        path: _leftSail(),
        color: MadyawLogoWidget.navy,
        order: 0,
      ),
      _LogoLayer(
        path: _mainSail(),
        color: MadyawLogoWidget.brightBlue,
        order: 1,
      ),
      _LogoLayer(
        path: _rightSail(),
        color: MadyawLogoWidget.brightBlue.withValues(alpha: 0.92),
        order: 2,
      ),
      _LogoLayer(
        path: _hull(),
        color: MadyawLogoWidget.navy,
        order: 3,
      ),
      _LogoLayer(
        path: _waveBack(),
        color: MadyawLogoWidget.brightBlue.withValues(alpha: 0.75),
        order: 4,
      ),
      _LogoLayer(
        path: _waveFront(),
        color: MadyawLogoWidget.brightBlue,
        order: 5,
      ),
    ];

    for (final layer in layers) {
      _drawTrimmedPath(canvas, layer.path, layer.color, drawProgress, layer.order, layers.length);
    }

    canvas.restore();

    if (showWordmark && textOpacity > 0.01) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'MADYAW',
          style: TextStyle(
            fontSize: w * 0.11,
            fontWeight: FontWeight.w800,
            letterSpacing: w * 0.018,
            color: MadyawLogoWidget.navy.withValues(alpha: textOpacity),
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);
      tp.paint(
        canvas,
        Offset((w - tp.width) / 2, markHeight + h * 0.04),
      );
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
      final extract = metric.extractPath(0, len);
      canvas.drawPath(extract, paint);
    }
  }

  Path _mainSail() {
    return Path()
      ..moveTo(-8, 78)
      ..quadraticBezierTo(2, 20, 18, 4)
      ..quadraticBezierTo(28, -2, 38, 8)
      ..quadraticBezierTo(42, 42, 28, 78)
      ..close();
  }

  Path _leftSail() {
    return Path()
      ..moveTo(-42, 76)
      ..quadraticBezierTo(-48, 38, -32, 18)
      ..quadraticBezierTo(-22, 8, -8, 78)
      ..close();
  }

  Path _rightSail() {
    return Path()
      ..moveTo(36, 76)
      ..quadraticBezierTo(52, 48, 48, 22)
      ..quadraticBezierTo(44, 10, 38, 8)
      ..lineTo(28, 78)
      ..close();
  }

  Path _hull() {
    return Path()
      ..moveTo(-44, 78)
      ..lineTo(44, 78)
      ..lineTo(52, 88)
      ..lineTo(-52, 88)
      ..close();
  }

  Path _waveBack() {
    return Path()
      ..moveTo(-58, 94)
      ..quadraticBezierTo(-20, 82, 20, 92)
      ..quadraticBezierTo(48, 100, 62, 96)
      ..lineTo(62, 104)
      ..quadraticBezierTo(40, 108, 10, 100)
      ..quadraticBezierTo(-30, 90, -58, 102)
      ..close();
  }

  Path _waveFront() {
    return Path()
      ..moveTo(-54, 100)
      ..quadraticBezierTo(-10, 88, 30, 98)
      ..quadraticBezierTo(56, 104, 66, 100)
      ..lineTo(66, 108)
      ..quadraticBezierTo(38, 114, 0, 106)
      ..quadraticBezierTo(-36, 98, -54, 110)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _MadyawLogoPainter old) =>
      old.drawProgress != drawProgress ||
      old.textOpacity != textOpacity ||
      old.glowStrength != glowStrength ||
      old.showWordmark != showWordmark;
}

class _LogoLayer {
  const _LogoLayer({
    required this.path,
    required this.color,
    required this.order,
  });

  final Path path;
  final Color color;
  final int order;
}
