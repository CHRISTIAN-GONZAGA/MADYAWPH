import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/room_status_label.dart';
import '../admin_dashboard_models.dart';
import '../widgets/booking_overview_cards.dart';
import '../widgets/manual_booking_dialog.dart';
import '../../admin_rooms.dart';

class RoomSummarySection extends StatelessWidget {
  const RoomSummarySection({
    super.key,
    required this.rooms,
    required this.tasks,
    required this.hotelName,
    required this.localBookingsTotal,
    required this.onlineBookingsTotal,
    required this.recentBookings24h,
    required this.pendingReservations,
    required this.onOpenLocalBookings,
    required this.onOpenOnlineBookings,
    required this.onOpenBookingsAlert,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> rooms;
  final List<dynamic> tasks;
  final String hotelName;
  final int localBookingsTotal;
  final int onlineBookingsTotal;
  final int recentBookings24h;
  final int pendingReservations;
  final VoidCallback onOpenLocalBookings;
  final VoidCallback onOpenOnlineBookings;
  final VoidCallback onOpenBookingsAlert;
  final Future<void> Function() onRefresh;

  List<Map<String, dynamic>> _filterByStatuses(Set<String> statuses) {
    return rooms
        .where((r) => statuses.contains(AdminDashboardModels.statusOf(r)))
        .toList();
  }

  List<Map<String, dynamic>> _maintenanceRooms() {
    return _filterByStatuses({'maintenance'});
  }

  List<_IssueRoom> _issueRoomsFromTasks(String keyword) {
    final out = <_IssueRoom>[];
    for (final t in tasks) {
      if (t is! Map<String, dynamic>) continue;
      final title =
          (t['title'] ?? t['description'] ?? '').toString().toLowerCase();
      if (!title.contains(keyword)) continue;
      final desc = (t['description'] ?? t['title'] ?? '').toString();
      final roomMatch =
          RegExp(r'room\s*(\d+)', caseSensitive: false).firstMatch(desc);
      final no = roomMatch?.group(1) ?? '—';
      out.add(_IssueRoom(roomNumber: no, issue: desc));
    }
    return out;
  }

  void _openRooms(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> list,
    String? subtitle,
  }) {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No rooms in "$title".')),
      );
      return;
    }
    HapticFeedback.selectionClick();
    _showCategoryRooms(
      context,
      title,
      list,
      subtitle: subtitle ?? '${list.length} room(s)',
    );
  }

  void _showCategoryRooms(
    BuildContext context,
    String label,
    List<Map<String, dynamic>> list, {
    String? subtitle,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final reservedSoon = list.where((r) {
          return AdminDashboardModels.isStayArrivingSoon(r);
        }).toList();
        final others = list.where((r) => !reservedSoon.contains(r)).toList();
        final sheetHeight = MediaQuery.sizeOf(ctx).height * 0.78;

        return SizedBox(
          height: sheetHeight,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(label, style: Theme.of(ctx).textTheme.headlineSmall),
              Text(
                subtitle ?? '${list.length} room(s) in this category',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (reservedSoon.isNotEmpty) ...[
                Text(
                  'Arriving (today–2 days)',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                ...reservedSoon.map(
                  (r) => _roomTile(ctx, context, r, highlight: true),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'All rooms',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ...others.map((r) => _roomTile(ctx, context, r)),
              if (list.isEmpty) const Text('No rooms in this category.'),
            ],
          ),
        );
      },
    );
  }

  Widget _roomTile(
    BuildContext sheetContext,
    BuildContext hostContext,
    Map<String, dynamic> r, {
    bool highlight = false,
  }) {
    final status = AdminDashboardModels.displayStatusForRoom(r);
    final guest = AdminDashboardModels.guestName(r);
    final range = AdminDashboardModels.formatStayRange(r);
    return Card(
      color: highlight ? Colors.orange.shade50 : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.hotel_outlined,
          color: highlight ? Colors.orange.shade800 : roomStatusColor(status),
        ),
        title: Text('Room ${r['room_number']} · ${roomStatusLabel(status)}'),
        subtitle: Text(
          guest == '—'
              ? 'No guest'
              : 'Guest: $guest\nStay: $range',
        ),
        isThreeLine: true,
        trailing: AdminDashboardModels.isWalkInBookable(r)
            ? const Icon(Icons.person_add_outlined)
            : const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!hostContext.mounted) return;
            if (AdminDashboardModels.isWalkInBookable(r)) {
              await handleAdminWalkInRoomTap(
                hostContext,
                room: r,
                onSuccess: onRefresh,
              );
              return;
            }
            final roomId = AdminDashboardModels.roomIdOf(r);
            if (roomId.isEmpty) {
              ScaffoldMessenger.of(hostContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Room ID missing. Pull to refresh the dashboard.',
                  ),
                ),
              );
              return;
            }
            await Navigator.of(hostContext).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AdminRoomDetailScreen(roomId: roomId),
              ),
            );
          });
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
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final maint =
            useMaintenanceRooms ? _maintenanceRooms() : const <Map<String, dynamic>>[];
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
                    leading: Icon(Icons.hotel_outlined,
                        color: roomStatusColor('maintenance')),
                    title: Text('Room ${r['room_number']}'),
                    subtitle:
                        Text((r['display_name'] ?? 'Maintenance').toString()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      final roomId = AdminDashboardModels.roomIdOf(r);
                      if (roomId.isEmpty) return;
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => AdminRoomDetailScreen(roomId: roomId),
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
    final occupiedRooms =
        _filterByStatuses({'checked_in', 'booked', 'reserved'});
    final vacantRooms = rooms.where(AdminDashboardModels.isWalkInBookable).toList();
    final maintenanceRooms = _maintenanceRooms();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        BookingOverviewCards(
          localTotal: localBookingsTotal,
          onlineTotal: onlineBookingsTotal,
          recentBookings24h: recentBookings24h,
          pendingReservations: pendingReservations,
          onLocalTap: onOpenLocalBookings,
          onOnlineTap: onOpenOnlineBookings,
          onAlertTap: onOpenBookingsAlert,
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
              onTap: () => _openRooms(
                context,
                title: label,
                list: list,
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.analytics_outlined, color: scheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Hotel totals',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Tap any stat to view the room list',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            _TotalStatCard(
              label: 'Total rooms',
              value: '${totals['total']}',
              icon: Icons.apartment_rounded,
              color: scheme.primary,
              onTap: () => _openRooms(
                context,
                title: 'All hotel rooms',
                list: rooms,
                subtitle: '${rooms.length} rooms in property',
              ),
            ),
            _TotalStatCard(
              label: 'Occupied',
              value: '${totals['occupied']}',
              icon: Icons.person_pin_circle_outlined,
              color: Colors.green.shade700,
              onTap: () => _openRooms(
                context,
                title: 'Occupied rooms',
                list: occupiedRooms,
                subtitle: 'Checked in, booked, or reserved',
              ),
            ),
            _TotalStatCard(
              label: 'Vacant',
              value: '${totals['vacant']}',
              icon: Icons.meeting_room_outlined,
              color: Colors.teal.shade700,
              onTap: () => _openRooms(
                context,
                title: 'Vacant rooms',
                list: vacantRooms,
                subtitle: 'Available for booking',
              ),
            ),
            _TotalStatCard(
              label: 'Cleaning',
              value: '${totals['cleaning']}',
              icon: Icons.cleaning_services_outlined,
              color: Colors.orange.shade800,
              onTap: () => _showRoomList(
                context,
                title: 'Rooms in cleaning',
                items: cleaningIssues,
                useMaintenanceRooms: true,
              ),
            ),
            _TotalStatCard(
              label: 'Maintenance',
              value: '${totals['maintenance']}',
              icon: Icons.handyman_outlined,
              color: Colors.red.shade700,
              onTap: () {
                if (maintenanceRooms.isNotEmpty) {
                  _openRooms(
                    context,
                    title: 'Maintenance rooms',
                    list: maintenanceRooms,
                  );
                } else {
                  _showRoomList(
                    context,
                    title: 'Maintenance issues',
                    items: maintIssues,
                    useMaintenanceRooms: true,
                  );
                }
              },
            ),
            _TotalStatCard(
              label: 'Booked / reserved',
              value: '${AdminDashboardModels.bookedRoomCount(rooms)}',
              icon: Icons.event_available_outlined,
              color: Colors.blue.shade700,
              onTap: () => _openRooms(
                context,
                title: 'Booked / reserved',
                list: rooms
                    .where(AdminDashboardModels.isAwaitingCheckIn)
                    .toList(),
                subtitle: 'Awaiting guest check-in',
              ),
            ),
          ],
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
              Text('Occupied: ${stats['checked_in']}'),
              Text('Booked / reserved: ${stats['awaiting_check_in']}'),
              Text(
                'Arriving (today–2 days): ${stats['reserved_soon']}',
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

class _TotalStatCard extends StatelessWidget {
  const _TotalStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.08),
                scheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const Spacer(),
                    Icon(Icons.touch_app_outlined,
                        size: 16, color: scheme.outline),
                  ],
                ),
                const Spacer(),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
