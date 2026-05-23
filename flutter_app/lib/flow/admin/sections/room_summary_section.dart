import 'package:flutter/material.dart';

import '../admin_dashboard_models.dart';
import '../widgets/booking_overview_cards.dart';
import '../../admin_rooms.dart';

class RoomSummarySection extends StatelessWidget {
  const RoomSummarySection({
    super.key,
    required this.rooms,
    required this.tasks,
    required this.localBookingsTotal,
    required this.onlineBookingsTotal,
    required this.onOpenLocalBookings,
    required this.onOpenOnlineBookings,
  });

  final List<Map<String, dynamic>> rooms;
  final List<dynamic> tasks;
  final int localBookingsTotal;
  final int onlineBookingsTotal;
  final VoidCallback onOpenLocalBookings;
  final VoidCallback onOpenOnlineBookings;

  List<Map<String, dynamic>> _maintenanceRooms() {
    return rooms
        .where((r) => AdminDashboardModels.statusOf(r) == 'maintenance')
        .toList();
  }

  List<_IssueRoom> _issueRoomsFromTasks(String keyword) {
    final out = <_IssueRoom>[];
    for (final t in tasks) {
      if (t is! Map<String, dynamic>) continue;
      final title = (t['title'] ?? t['description'] ?? '').toString().toLowerCase();
      if (!title.contains(keyword)) continue;
      final desc = (t['description'] ?? t['title'] ?? '').toString();
      final roomMatch = RegExp(r'room\s*(\d+)', caseSensitive: false).firstMatch(desc);
      final no = roomMatch?.group(1) ?? '—';
      out.add(_IssueRoom(roomNumber: no, issue: desc));
    }
    return out;
  }

  void _showCategoryRooms(BuildContext context, String label, List<Map<String, dynamic>> list) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final reservedSoon = list.where((r) {
          final s = AdminDashboardModels.statusOf(r);
          if (s != 'reserved' && s != 'booked') return false;
          return AdminDashboardModels.isStayEndingSoon(r);
        }).toList();
        final others = list.where((r) => !reservedSoon.contains(r)).toList();

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (_, scroll) => SafeArea(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Text(label, style: Theme.of(ctx).textTheme.headlineSmall),
                Text(
                  '${list.length} room(s) in this category',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (reservedSoon.isNotEmpty) ...[
                  Text(
                    'Departing within 1–2 days',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...reservedSoon.map((r) => _roomTile(context, r, highlight: true)),
                  const SizedBox(height: 16),
                ],
                Text(
                  'All rooms',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                ...others.map((r) => _roomTile(context, r)),
                if (list.isEmpty) const Text('No rooms in this category.'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _roomTile(BuildContext context, Map<String, dynamic> r, {bool highlight = false}) {
    final status = AdminDashboardModels.statusOf(r);
    final guest = AdminDashboardModels.guestName(r);
    final range = AdminDashboardModels.formatStayRange(r);
    return Card(
      color: highlight ? Colors.orange.shade50 : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.hotel_outlined,
          color: highlight ? Colors.orange.shade800 : null,
        ),
        title: Text('Room ${r['room_number']} · $status'),
        subtitle: Text(
          guest == '—' ? 'No guest' : 'Guest: $guest\nCheck-in → out: $range',
        ),
        isThreeLine: true,
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => AdminRoomDetailScreen(
                roomId: (r['id'] ?? '').toString(),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRoomList(
    BuildContext context, {
    required String title,
    required List<_IssueRoom> items,
    bool useMaintenanceRooms = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final maint = useMaintenanceRooms ? _maintenanceRooms() : const <Map<String, dynamic>>[];
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (items.isNotEmpty)
                ...items.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.build_circle_outlined),
                    title: Text('Room ${e.roomNumber}'),
                    subtitle: Text(e.issue),
                  ),
                ),
              if (maint.isNotEmpty)
                ...maint.map(
                  (r) => ListTile(
                    leading: const Icon(Icons.hotel_outlined),
                    title: Text('Room ${r['room_number']}'),
                    subtitle: Text((r['display_name'] ?? 'Maintenance').toString()),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => AdminRoomDetailScreen(
                            roomId: (r['id'] ?? '').toString(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (items.isEmpty && maint.isEmpty)
                const Text('No rooms in this list.'),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = AdminDashboardModels.groupByCategory(rooms);
    final keys = grouped.keys.toList()..sort();
    final totals = AdminDashboardModels.statusCounts(rooms);
    final scheme = Theme.of(context).colorScheme;
    final cleaningIssues = _issueRoomsFromTasks('clean');
    final maintIssues = _issueRoomsFromTasks('maintenance');

    return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          BookingOverviewCards(
            localTotal: localBookingsTotal,
            onlineTotal: onlineBookingsTotal,
            onLocalTap: onOpenLocalBookings,
            onOnlineTap: onOpenOnlineBookings,
          ),
          const SizedBox(height: 20),
          Text(
            'Room summary by category',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemCount: keys.length,
            itemBuilder: (context, i) {
              final label = keys[i];
              final list = grouped[label]!;
              final stats = AdminDashboardModels.categoryStats(label, list);
              return _CategoryCard(
                stats: stats,
                onTap: () => _showCategoryRooms(context, label, list),
              );
            },
          ),
          const SizedBox(height: 20),
          Text('Hotel totals', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _TotalTile(
            label: 'TOTAL ROOMS IN HOTEL',
            value: '${totals['total']}',
            color: scheme.primary,
          ),
          _TotalTile(
            label: 'TOTAL OCCUPIED',
            value: '${totals['occupied']}',
            color: scheme.tertiary,
            onTap: null,
          ),
          _TotalTile(
            label: 'TOTAL VACANT',
            value: '${totals['vacant']}',
            color: scheme.secondary,
          ),
          _TotalTile(
            label: 'TOTAL CLEANING',
            value: '${totals['cleaning']}',
            color: Colors.orange.shade800,
            onTap: () => _showRoomList(
              context,
              title: 'Rooms in cleaning',
              items: cleaningIssues,
              useMaintenanceRooms: true,
            ),
          ),
          _TotalTile(
            label: 'TOTAL MAINTENANCE',
            value: '${totals['maintenance']}',
            color: Colors.red.shade700,
            onTap: () => _showRoomList(
              context,
              title: 'Maintenance issues',
              items: maintIssues,
              useMaintenanceRooms: true,
            ),
          ),
        ],
    );
  }
}

class _IssueRoom {
  _IssueRoom({required this.roomNumber, required this.issue});
  final String roomNumber;
  final String issue;
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.stats, required this.onTap});
  final Map<String, dynamic> stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.king_bed_outlined,
                        color: scheme.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${stats['label']}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text('Total: ${stats['total']}'),
              Text('Vacant: ${stats['vacant']}'),
              Text('Checked in: ${stats['checked_in']}'),
              Text(
                'Reserved (1–2 days): ${stats['reserved_soon']}',
                style: TextStyle(
                  color: (stats['reserved_soon'] as int) > 0
                      ? Colors.orange.shade800
                      : null,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${stats['occupancy']}% occupancy',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(label, style: Theme.of(context).textTheme.labelMedium),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
