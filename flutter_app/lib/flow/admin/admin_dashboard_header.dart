import 'package:flutter/material.dart';

import '../../widgets/admin_live_clock.dart';

/// Unread counts from chat inbox (preferred) or dashboard guestMessages fallback.
AdminChatBadgeInfo adminChatBadgeFromData({
  Map<String, dynamic>? inbox,
  required List<dynamic> guestMessages,
}) {
  var guestUnread = 0;
  var staffUnread = 0;
  var preview = '';
  var kind = 'guest';

  void scanThreads(List<dynamic>? threads, {required bool staff}) {
    for (final raw in threads ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final u = (raw['unread_count'] as num?)?.toInt() ?? 0;
      if (staff) {
        staffUnread += u;
      } else {
        guestUnread += u;
      }
      if (u > 0 && preview.isEmpty) {
        preview = (raw['latest_message'] ?? '').toString();
        kind = staff ? 'staff' : 'guest';
      }
    }
  }

  if (inbox != null) {
    scanThreads(inbox['guest_threads'] as List?, staff: false);
    scanThreads(inbox['staff_threads'] as List?, staff: true);
    final threads = inbox['threads'] as List?;
    if (threads != null && guestUnread == 0 && staffUnread == 0) {
      for (final raw in threads) {
        if (raw is! Map<String, dynamic>) continue;
        final roomId = (raw['room_id'] ?? '').toString();
        final isStaff = roomId.startsWith('STAFF-ADMIN:');
        final u = (raw['unread_count'] as num?)?.toInt() ?? 0;
        if (isStaff) {
          staffUnread += u;
        } else {
          guestUnread += u;
        }
        if (u > 0 && preview.isEmpty) {
          preview = (raw['latest_message'] ?? '').toString();
          kind = isStaff ? 'staff' : 'guest';
        }
      }
    }
  }

  if (guestUnread == 0) {
    for (final raw in guestMessages) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['is_read'] == true) continue;
      guestUnread++;
      if (preview.isEmpty) {
        preview = (raw['message'] ?? raw['body'] ?? '').toString();
      }
      if (raw['priority'] == 'urgent' || raw['is_urgent'] == true) {
        kind = 'urgent';
      }
    }
  }

  return AdminChatBadgeInfo(
    totalUnread: guestUnread + staffUnread,
    guestUnread: guestUnread,
    staffUnread: staffUnread,
    latestPreview: preview,
    latestKind: kind,
  );
}

class AdminChatBadgeInfo {
  const AdminChatBadgeInfo({
    required this.totalUnread,
    required this.guestUnread,
    required this.staffUnread,
    this.latestPreview = '',
    this.latestKind = 'guest',
  });

  final int totalUnread;
  final int guestUnread;
  final int staffUnread;
  final String latestPreview;
  final String latestKind; // guest | staff | urgent
}

class AdminDashboardHeader extends StatelessWidget {
  const AdminDashboardHeader({
    super.key,
    required this.hotelName,
    required this.adminName,
    required this.chatBadge,
    required this.onOpenChat,
    required this.onRefresh,
    this.onSignOut,
  });

  final String hotelName;
  final String adminName;
  final AdminChatBadgeInfo chatBadge;
  final VoidCallback onOpenChat;
  final VoidCallback onRefresh;
  final VoidCallback? onSignOut;

  Color _badgeColor() {
    if (chatBadge.latestKind == 'urgent') return Colors.red;
    if (chatBadge.latestKind == 'staff') return Colors.green.shade700;
    return Colors.blue.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.55),
            scheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hotelName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Admin: $adminName',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const AdminLiveClock(align: TextAlign.end),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          if (onSignOut != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
          Tooltip(
            message: chatBadge.latestPreview.isEmpty
                ? 'Open chatroom'
                : chatBadge.latestPreview,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Chatroom',
                  onPressed: onOpenChat,
                  icon: const Icon(Icons.forum_outlined),
                ),
                if (chatBadge.totalUnread > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _badgeColor(),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        chatBadge.totalUnread > 99
                            ? '99+'
                            : '${chatBadge.totalUnread}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
