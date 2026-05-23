import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdminNavItem {
  const AdminNavItem({
    required this.label,
    required this.icon,
    this.shortLabel,
  });

  final String label;
  final String? shortLabel;
  final IconData icon;
}

/// Floating bottom nav with wave notch, scroll support, and elevated active icon.
class AdminCurvedNavBar extends StatefulWidget {
  const AdminCurvedNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.activeColor = const Color(0xFF6C4DFF),
  });

  final List<AdminNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color activeColor;

  @override
  State<AdminCurvedNavBar> createState() => _AdminCurvedNavBarState();
}

class _AdminCurvedNavBarState extends State<AdminCurvedNavBar> {
  final ScrollController _scroll = ScrollController();
  double _scrollOffset = 0;

  static const _itemWidth = 76.0;
  static const _barHeight = 68.0;
  static const _bumpRadius = 30.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      setState(() => _scrollOffset = _scroll.offset);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AdminCurvedNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive() {
    if (!_scroll.hasClients) return;
    final target = (widget.currentIndex * _itemWidth) -
        (MediaQuery.sizeOf(context).width / 2) +
        (_itemWidth / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  double _activeCenterX(double viewportWidth) {
    final x =
        (widget.currentIndex * _itemWidth) + (_itemWidth / 2) - _scrollOffset;
    return x.clamp(_bumpRadius + 4, viewportWidth - _bumpRadius - 4);
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.items.length * _itemWidth;
    final viewportWidth = MediaQuery.sizeOf(context).width - 24;
    final barWidth = math.max(totalWidth, viewportWidth);

    return Container(
      height: 88,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _barHeight + 12,
            child: CustomPaint(
              painter: _WaveNavPainter(
                activeCenterX: _activeCenterX(viewportWidth),
                barHeight: _barHeight,
                bumpRadius: _bumpRadius,
                color: Colors.white,
                shadowColor: Colors.black.withValues(alpha: 0.1),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            height: _barHeight,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: barWidth,
                child: Row(
                  children: List.generate(widget.items.length, (i) {
                    final active = i == widget.currentIndex;
                    final item = widget.items[i];
                    return SizedBox(
                      width: _itemWidth,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onTap(i);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              width: active ? 52 : 40,
                              height: active ? 52 : 40,
                              decoration: BoxDecoration(
                                color: active
                                    ? Colors.white
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                boxShadow: active
                                    ? [
                                        BoxShadow(
                                          color: widget.activeColor
                                              .withValues(alpha: 0.4),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                item.icon,
                                size: active ? 26 : 22,
                                color: active
                                    ? widget.activeColor
                                    : Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: active ? 10 : 9,
                                fontWeight: active
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: active
                                    ? widget.activeColor
                                    : Colors.grey.shade600,
                                letterSpacing: active ? 0.2 : 0,
                              ),
                              child: Text(
                                item.shortLabel ?? item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveNavPainter extends CustomPainter {
  _WaveNavPainter({
    required this.activeCenterX,
    required this.barHeight,
    required this.bumpRadius,
    required this.color,
    required this.shadowColor,
  });

  final double activeCenterX;
  final double barHeight;
  final double bumpRadius;
  final Color color;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final top = size.height - barHeight;
    final r = 32.0;
    final w = size.width;

    Path buildPath() {
      final path = Path();
      path.moveTo(r, top);
      path.lineTo(activeCenterX - bumpRadius - 12, top);

      path.quadraticBezierTo(
        activeCenterX - bumpRadius,
        top,
        activeCenterX - bumpRadius * 0.55,
        top - bumpRadius * 0.85,
      );
      path.arcToPoint(
        Offset(activeCenterX + bumpRadius * 0.55, top - bumpRadius * 0.85),
        radius: Radius.circular(bumpRadius),
        clockwise: false,
      );
      path.quadraticBezierTo(
        activeCenterX + bumpRadius,
        top,
        activeCenterX + bumpRadius + 12,
        top,
      );

      path.lineTo(w - r, top);
      path.arcToPoint(Offset(w, top + r), radius: Radius.circular(r));
      path.lineTo(w, size.height - 4);
      path.arcToPoint(Offset(w - r, size.height), radius: const Radius.circular(4));
      path.lineTo(r, size.height);
      path.arcToPoint(Offset(0, size.height - 4), radius: const Radius.circular(4));
      path.lineTo(0, top + r);
      path.arcToPoint(Offset(r, top), radius: Radius.circular(r));
      path.close();
      return path;
    }

    final path = buildPath();
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveNavPainter old) =>
      old.activeCenterX != activeCenterX ||
      old.barHeight != barHeight;
}
