import 'package:flutter/material.dart';

import 'admin_dashboard_models.dart';
import 'widgets/admin_opaque_scaffold.dart';
import 'widgets/admin_room_navigation.dart';

/// Full-screen room list; tap a row to open [AdminRoomDetailScreen] (vacant/occupied).
class AdminRoomSummaryDetailScreen extends StatelessWidget {
  const AdminRoomSummaryDetailScreen({
    super.key,
    required this.title,
    required this.rooms,
    required this.showGuest,
  });

  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool showGuest;

  @override
  Widget build(BuildContext context) {
    return AdminOpaqueScaffold(
      appBar: AppBar(title: Text(title)),
      body: rooms.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No rooms in this category.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rooms.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final room = rooms[i];
                final roomId = AdminDashboardModels.roomIdOf(room);
                final roomNo = (room['room_number'] ?? '-').toString();
                final guest =
                    (room['current_guest_name'] ?? '').toString().trim();
                final category =
                    (room['category_name'] ?? '').toString().trim();
                final status = (room['status'] ?? '').toString();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.meeting_room_outlined),
                    title: Text('Room $roomNo'),
                    subtitle: Text(
                      [
                        if (category.isNotEmpty) 'Category: $category',
                        'Status: $status',
                        if (showGuest && guest.isNotEmpty) 'Guest: $guest',
                        if (showGuest && guest.isEmpty) 'Guest: —',
                      ].join('\n'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: roomId.isEmpty
                        ? null
                        : () => AdminRoomNavigation.openDetailById(roomId),
                  ),
                );
              },
            ),
    );
  }
}
