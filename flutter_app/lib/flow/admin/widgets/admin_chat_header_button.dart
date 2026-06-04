import 'package:flutter/material.dart';

import '../../../widgets/admin_notification_badge.dart';
import '../admin_dashboard_header.dart';

/// Chat icon with dual color-coded unread badges (guest = red, staff = yellow).
class AdminChatHeaderButton extends StatelessWidget {
  const AdminChatHeaderButton({
    super.key,
    required this.badge,
    required this.onPressed,
  });

  final AdminChatBadgeInfo badge;
  final VoidCallback? onPressed;

  String get _tooltip {
    if (badge.totalUnread == 0) return 'Open chatroom';
    final parts = <String>[];
    if (badge.guestUnread > 0) {
      parts.add('${badge.guestUnread} guest');
    }
    if (badge.staffUnread > 0) {
      parts.add('${badge.staffUnread} staff');
    }
    final summary = parts.join(' · ');
    if (badge.latestPreview.isEmpty) return 'Unread: $summary';
    return '$summary\n${badge.latestPreview}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUnread = badge.totalUnread > 0;
    final hasUrgentGuest = badge.latestKind == 'urgent' && badge.guestUnread > 0;
    final ringColor = hasUrgentGuest
        ? AdminChatColors.urgent
        : badge.guestUnread > 0
            ? AdminChatColors.guest
            : badge.staffUnread > 0
                ? AdminChatColors.staff
                : scheme.primary;

    return Tooltip(
      message: _tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasUnread)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ringColor.withValues(alpha: 0.55),
                    width: 2,
                  ),
                ),
              ),
            ),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            tooltip: '',
            onPressed: onPressed,
            icon: Icon(
              hasUnread ? Icons.mark_chat_unread_outlined : Icons.forum_outlined,
            ),
          ),
          if (badge.guestUnread > 0)
            Positioned(
              right: 2,
              top: 2,
              child: AdminNotificationBadge(
                count: badge.guestUnread,
                color: hasUrgentGuest ? AdminChatColors.urgent : AdminChatColors.guest,
              ),
            ),
          if (badge.staffUnread > 0)
            Positioned(
              left: 2,
              bottom: 2,
              child: AdminNotificationBadge(
                count: badge.staffUnread,
                color: AdminChatColors.staff,
                size: 17,
              ),
            ),
        ],
      ),
    );
  }
}
