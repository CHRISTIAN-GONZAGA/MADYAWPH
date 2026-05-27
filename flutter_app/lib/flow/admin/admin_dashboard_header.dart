import 'package:flutter/material.dart';

import '../../widgets/admin_live_clock.dart';
import '../../widgets/admin_notification_badge.dart';
import 'widgets/admin_chat_header_button.dart';

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
    this.isSuperAdmin = false,
  });

  final String hotelName;
  final String adminName;
  final bool isSuperAdmin;
  final AdminChatBadgeInfo chatBadge;
  final VoidCallback onOpenChat;
  final VoidCallback onRefresh;
  final VoidCallback? onSignOut;

  String _displayHotelName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Hotel';
    // Normalize spacing; keep casing from API.
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = _displayHotelName(hotelName);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (isSuperAdmin) ...[
                      Icon(Icons.shield_outlined,
                          size: 16, color: scheme.tertiary),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        isSuperAdmin
                            ? 'Super admin · $adminName'
                            : 'Admin · $adminName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: isSuperAdmin
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const AdminLiveClock(align: TextAlign.end, compact: true),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh dashboard',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
              if (onSignOut != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Sign out',
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                ),
              AdminChatHeaderButton(
                badge: chatBadge,
                onPressed: onOpenChat,
              ),
            ],
          ),
          if (chatBadge.totalUnread > 0) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (chatBadge.guestUnread > 0)
                  _chatLegendChip(
                    context,
                    color: AdminChatColors.guest,
                    label: '${chatBadge.guestUnread} guest',
                  ),
                if (chatBadge.staffUnread > 0)
                  _chatLegendChip(
                    context,
                    color: AdminChatColors.staff,
                    label: '${chatBadge.staffUnread} staff',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chatLegendChip(
    BuildContext context, {
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
