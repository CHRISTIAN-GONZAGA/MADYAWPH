import 'package:flutter/material.dart';

/// Small count pill for admin dashboard (chat, nav tabs, lists).
class AdminNotificationBadge extends StatelessWidget {
  const AdminNotificationBadge({
    super.key,
    required this.count,
    required this.color,
    this.max = 99,
    this.size = 18,
  });

  final int count;
  final Color color;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final label = count > max ? '$max+' : '$count';
    final fontSize = size < 17 ? 9.0 : 10.0;

    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: EdgeInsets.symmetric(
        horizontal: count > 9 ? 5 : 4,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// Admin chat unread colors: guests = red, staff = amber/yellow.
abstract final class AdminChatColors {
  static const guest = Color(0xFFD32F2F);
  static const staff = Color(0xFFF9A825);
  static const urgent = Color(0xFFB71C1C);
}
