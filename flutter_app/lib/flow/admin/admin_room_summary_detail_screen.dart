import 'package:flutter/material.dart';

import 'widgets/admin_opaque_scaffold.dart';
import 'widgets/admin_room_detail_navigation.dart';
import 'widgets/admin_summary_room_tile.dart';

/// Full-screen room grid from Hotel totals; tap a tile for room details.
class AdminRoomSummaryDetailScreen extends StatelessWidget {
  const AdminRoomSummaryDetailScreen({
    super.key,
    required this.title,
    required this.rooms,
    required this.showGuest,
    this.subtitle,
  });

  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool showGuest;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columns = adminSummaryRoomGridColumns(context);

    return AdminOpaqueScaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    subtitle ??
                        '${rooms.length} room(s) · tap a tile for details',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.28,
                    ),
                    itemCount: rooms.length,
                    itemBuilder: (context, i) {
                      final room = rooms[i];
                      return AdminSummaryRoomGridTile(
                        room: room,
                        showGuest: showGuest,
                        onTap: () => AdminRoomDetailNavigation.pushDetailForRoom(
                          context: context,
                          room: room,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
