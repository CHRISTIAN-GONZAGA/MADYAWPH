import 'package:flutter/material.dart';

import '../../../widgets/room_status_label.dart';
import '../admin_dashboard_models.dart';
import '../admin_room_detail_screen.dart';

/// Opens room details with the same [Navigator.push] path used by Manage rooms.
abstract final class AdminSummaryRoomActions {
  static Future<void> openRoomDetail(
    BuildContext context,
    Map<String, dynamic> room,
  ) async {
    final id = AdminDashboardModels.roomIdOf(room);
    if (id.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Room ID missing. Pull to refresh the dashboard and try again.',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminRoomDetailScreen(roomId: id),
      ),
    );
  }
}

/// Grid tile for hotel-totals / summary room lists.
class AdminSummaryRoomGridTile extends StatelessWidget {
  const AdminSummaryRoomGridTile({
    super.key,
    required this.room,
    required this.onTap,
    this.highlight = false,
    this.showGuest = true,
  });

  final Map<String, dynamic> room;
  final VoidCallback onTap;
  final bool highlight;
  final bool showGuest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = AdminDashboardModels.displayStatusForRoom(room);
    final statusColor = highlight
        ? Colors.orange.shade800
        : roomStatusColor(status);
    final guest = AdminDashboardModels.guestName(room);
    final range = AdminDashboardModels.formatStayRange(room);
    final roomNo = (room['room_number'] ?? '—').toString();
    final name = (room['display_name'] ?? '').toString().trim();
    final category = (room['category_name'] ?? '').toString().trim();

    return Material(
      color: highlight
          ? Colors.orange.shade50
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      roomNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                roomStatusLabel(status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (category.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                ),
              ],
              if (name.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                ),
              ],
              const Spacer(),
              if (showGuest)
                Text(
                  guest == '—' ? 'No guest' : guest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                ),
              if (range != '—')
                Text(
                  range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

int adminSummaryRoomGridColumns(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  return 2;
}
