import 'package:flutter/material.dart';

class AdminNavItem {
  const AdminNavItem({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

/// Bottom navigation inspired by floating pill + elevated active icon.
class AdminCurvedNavBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final itemW = w / items.length;
        final left = (currentIndex * itemW) + (itemW / 2) - 28;

        return Container(
          height: 78,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: List.generate(items.length, (i) {
                    final active = i == currentIndex;
                    return Expanded(
                      child: InkWell(
                        onTap: () => onTap(i),
                        borderRadius: BorderRadius.circular(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const SizedBox(height: 18),
                            Icon(
                              items[i].icon,
                              size: 22,
                              color: active
                                  ? Colors.transparent
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              items[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w500,
                                color: active
                                    ? activeColor
                                    : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: left.clamp(8.0, w - 56),
                top: 0,
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        items[currentIndex].icon,
                        color: activeColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
