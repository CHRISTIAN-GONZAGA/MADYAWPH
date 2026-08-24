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

/// Floating pill nav. Active tab uses a soft rounded highlight inside the bar
/// (no wave notch or pointed bump).
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

class _AdminCurvedNavBarState extends State<AdminCurvedNavBar> {
  final ScrollController _scroll = ScrollController();

  static const _itemWidth = 78.0;
  static const _barHeight = 68.0;

  @override
  void initState() {
    super.initState();
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
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.items.length * _itemWidth;
    final viewportWidth = MediaQuery.sizeOf(context).width - 24;
    final barWidth = math.max(totalWidth, viewportWidth);
    final scheme = Theme.of(context).colorScheme;
    final activeColor = widget.activeColor == const Color(0xFF6C4DFF)
        ? scheme.primary
        : widget.activeColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Material(
        color: scheme.surface,
        elevation: 10,
        shadowColor: scheme.shadow.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: _barHeight,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: barWidth,
              height: _barHeight,
              child: Row(
                children: List.generate(widget.items.length, (i) {
                  final active = i == widget.currentIndex;
                  final enabled = widget.canSelectTab?.call(i) ?? true;
                  final item = widget.items[i];
                  return SizedBox(
                    width: _itemWidth,
                    height: _barHeight,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: enabled
                            ? () {
                                if (i == widget.currentIndex) return;
                                HapticFeedback.selectionClick();
                                widget.onTap(i);
                              }
                            : () => widget.onBlockedTabTap?.call(),
                        borderRadius: BorderRadius.circular(22),
                        splashColor: activeColor.withValues(alpha: 0.12),
                        child: Opacity(
                          opacity: enabled ? 1 : 0.35,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                color: active
                                    ? activeColor.withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(
                                        item.icon,
                                        size: active ? 24 : 22,
                                        color: active
                                            ? activeColor
                                            : scheme.onSurfaceVariant,
                                      ),
                                      if (item.badgeCount > 0)
                                        Positioned(
                                          right: -10,
                                          top: -6,
                                          child: AdminNotificationBadge(
                                            count: item.badgeCount,
                                            color: item.badgeColor ??
                                                const Color(0xFF6C4DFF),
                                            size: 15,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.shortLabel ?? item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      height: 1.1,
                                      fontWeight: active
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: active
                                          ? activeColor
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
      ),
    );
  }
}
