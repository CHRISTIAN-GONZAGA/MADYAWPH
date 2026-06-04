import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_notification_badge.dart';

class AdminNavItem {
  const AdminNavItem({
    required this.label,
    required this.icon,
    this.shortLabel,
    this.badgeCount = 0,
    this.badgeColor,
  });

  final String label;
  final String? shortLabel;
  final IconData icon;
  final int badgeCount;
  final Color? badgeColor;
}

/// Floating bottom nav with animated wave notch and spring tab transitions.
class AdminCurvedNavBar extends StatefulWidget {
  const AdminCurvedNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.canSelectTab,
    this.onBlockedTabTap,
    this.activeColor = const Color(0xFF6C4DFF),
  });

  final List<AdminNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool Function(int index)? canSelectTab;
  final VoidCallback? onBlockedTabTap;
  final Color activeColor;

  @override
  State<AdminCurvedNavBar> createState() => _AdminCurvedNavBarState();
}

class _AdminCurvedNavBarState extends State<AdminCurvedNavBar>
    with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  double _scrollOffset = 0;
  late AnimationController _bump;
  late AnimationController _iconPop;
  late Animation<double> _bumpCurve;
  double _displayedCenterX = 0;
  int _fromIndex = 0;

  static const _itemWidth = 76.0;
  static const _barHeight = 68.0;
  static const _bumpRadius = 30.0;

  @override
  void initState() {
    super.initState();
    _bump = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _iconPop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _bumpCurve = CurvedAnimation(parent: _bump, curve: Curves.easeOutCubic);
    _scroll.addListener(() {
      setState(() => _scrollOffset = _scroll.offset);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _displayedCenterX = _targetCenterX(MediaQuery.sizeOf(context).width - 24);
      _scrollToActive();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _bump.dispose();
    _iconPop.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AdminCurvedNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _fromIndex = oldWidget.currentIndex;
      _bump.forward(from: 0);
      _iconPop.forward(from: 0);
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
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  double _targetCenterX(double viewportWidth) {
    final x = (widget.currentIndex * _itemWidth) +
        (_itemWidth / 2) -
        _scrollOffset;
    return x.clamp(_bumpRadius + 4, viewportWidth - _bumpRadius - 4);
  }

  double _activeCenterX(double viewportWidth) {
    final target = _targetCenterX(viewportWidth);
    if (!_bump.isAnimating && _bump.value == 0) {
      _displayedCenterX = target;
      return target;
    }
    final from = ( _fromIndex * _itemWidth) + (_itemWidth / 2) - _scrollOffset;
    final clampedFrom =
        from.clamp(_bumpRadius + 4, viewportWidth - _bumpRadius - 4);
    _displayedCenterX = uiLerp(clampedFrom, target, _bumpCurve.value);
    return _displayedCenterX;
  }

  double uiLerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.items.length * _itemWidth;
    final viewportWidth = MediaQuery.sizeOf(context).width - 24;
    final barWidth = math.max(totalWidth, viewportWidth);

    final scheme = Theme.of(context).colorScheme;
    final activeColor = widget.activeColor == const Color(0xFF6C4DFF)
        ? scheme.primary
        : widget.activeColor;

    return Container(
      height: 92,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_bump, _scroll]),
            builder: (context, _) {
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _barHeight + 14,
                child: CustomPaint(
                  painter: _WaveNavPainter(
                    activeCenterX: _activeCenterX(viewportWidth),
                    barHeight: _barHeight,
                    bumpRadius: _bumpRadius + 2 * _bumpCurve.value,
                    color: scheme.surface,
                    accentColor: activeColor,
                    shadowColor: scheme.shadow.withValues(alpha: 0.14),
                    lift: 4 * _bumpCurve.value,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
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
                    final enabled =
                        widget.canSelectTab?.call(i) ?? true;
                    final item = widget.items[i];
                    final popScale = active
                        ? 1.0 + 0.12 * Curves.elasticOut.transform(_iconPop.value)
                        : 1.0;
                    return SizedBox(
                      width: _itemWidth,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: enabled
                              ? () {
                                  if (i == widget.currentIndex) return;
                                  HapticFeedback.mediumImpact();
                                  widget.onTap(i);
                                }
                              : () {
                                  widget.onBlockedTabTap?.call();
                                },
                          borderRadius: BorderRadius.circular(20),
                          splashColor: activeColor.withValues(alpha: 0.12),
                          highlightColor: activeColor.withValues(alpha: 0.06),
                          child: Opacity(
                            opacity: enabled ? 1 : 0.35,
                            child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Transform.scale(
                                scale: popScale,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 320),
                                  curve: Curves.easeOutCubic,
                                  width: active ? 54 : 40,
                                  height: active ? 54 : 40,
                                  decoration: BoxDecoration(
                                    gradient: active
                                        ? LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              activeColor.withValues(alpha: 0.15),
                                              scheme.surface,
                                            ],
                                          )
                                        : null,
                                    color: active ? null : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: active
                                        ? Border.all(
                                            color: activeColor.withValues(alpha: 0.25),
                                            width: 1.5,
                                          )
                                        : null,
                                    boxShadow: active
                                        ? [
                                            BoxShadow(
                                              color: activeColor
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 18,
                                              spreadRadius: -2,
                                              offset: const Offset(0, 6),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 220),
                                        transitionBuilder: (child, anim) =>
                                            ScaleTransition(scale: anim, child: child),
                                        child: Icon(
                                          item.icon,
                                          key: ValueKey('$i-$active'),
                                          size: active ? 26 : 22,
                                          color: active
                                              ? activeColor
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (item.badgeCount > 0)
                                        Positioned(
                                          right: -4,
                                          top: -2,
                                          child: AdminNotificationBadge(
                                            count: item.badgeCount,
                                            color: item.badgeColor ??
                                                const Color(0xFF6C4DFF),
                                            size: 16,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: active ? 1 : 0.85,
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  style: TextStyle(
                                    fontSize: active ? 10.5 : 9,
                                    fontWeight: active
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: active
                                        ? activeColor
                                        : scheme.onSurfaceVariant,
                                    letterSpacing: active ? 0.25 : 0,
                                  ),
                                  child: Text(
                                    item.shortLabel ?? item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                margin: const EdgeInsets.only(top: 4, bottom: 6),
                                width: active ? 18 : 0,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: activeColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                          ),
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
    required this.accentColor,
    required this.shadowColor,
    required this.lift,
  });

  final double activeCenterX;
  final double barHeight;
  final double bumpRadius;
  final Color color;
  final Color accentColor;
  final Color shadowColor;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height - barHeight - lift * 0.5;
    final r = 32.0;
    final w = size.width;

    Path buildPath() {
      final path = Path();
      path.moveTo(r, top);
      path.lineTo(activeCenterX - bumpRadius - 14, top);

      path.cubicTo(
        activeCenterX - bumpRadius * 0.7,
        top,
        activeCenterX - bumpRadius * 0.35,
        top - bumpRadius * 0.95 - lift,
        activeCenterX,
        top - bumpRadius * 1.05 - lift,
      );
      path.cubicTo(
        activeCenterX + bumpRadius * 0.35,
        top - bumpRadius * 0.95 - lift,
        activeCenterX + bumpRadius * 0.7,
        top,
        activeCenterX + bumpRadius + 14,
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

    canvas.drawPath(
      path,
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color,
            Color.lerp(color, accentColor.withValues(alpha: 0.06), 0.35)!,
          ],
        ).createShader(Rect.fromLTWH(0, top, w, size.height - top)),
    );
  }

  @override
  bool shouldRepaint(covariant _WaveNavPainter old) =>
      old.activeCenterX != activeCenterX ||
      old.bumpRadius != bumpRadius ||
      old.lift != lift;
}
