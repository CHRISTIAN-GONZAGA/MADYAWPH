import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_dashboard_models.dart';
import '../widgets/admin_floor_picker_grid.dart';
import '../widgets/admin_hotel_totals_room_panel.dart';
import '../widgets/booking_overview_cards.dart';
import '../widgets/admin_room_navigation.dart';
import '../widgets/admin_summary_room_tile.dart';

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
    bool showGuest = true,
  }) {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No rooms in "$title".')),
      );
      return;
    }
    HapticFeedback.selectionClick();
    openHotelTotalsRoomList(
      context,
      title: title,
      rooms: list,
      showGuest: showGuest,
      subtitle: subtitle,
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
      useRootNavigator: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            return _SummaryRoomListSheet(
              label: label,
              subtitle: subtitle ?? '${list.length} room(s)',
              rooms: list,
              hostContext: context,
              scrollController: scrollController,
              onRefresh: onRefresh,
            );
          },
        );
      },
    );
  }

  void _showRoomList(
    BuildContext context, {
    required String title,
    required List<_IssueRoom> items,
    bool useMaintenanceRooms = false,
  }) {
    HapticFeedback.selectionClick();
    final maint =
        useMaintenanceRooms ? _maintenanceRooms() : const <Map<String, dynamic>>[];
    if (items.isEmpty && maint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No rooms in "$title".')),
      );
      return;
    }
    if (maint.isNotEmpty) {
      _showCategoryRooms(context, title, maint);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (ctx, scrollController) {
            return _SummaryIssueListSheet(
              title: title,
              items: items,
              scrollController: scrollController,
            );
          },
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
        rooms.where(AdminDashboardModels.isSummaryOccupied).toList();
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
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.category_outlined, color: scheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Room summary by category',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      'Tap a category to browse floors, then rooms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CategorySummaryGrid(
          grouped: grouped,
          keys: keys,
          onCategoryTap: (ctx, label, list, stats) => _showCategoryBreakdown(
            ctx,
            label: label,
            rooms: list,
            stats: stats,
          ),
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
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.35,
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
              label: 'Booked / reserved',
              value: '${totals['booked_reserved'] ?? AdminDashboardModels.bookedRoomCount(rooms)}',
              icon: Icons.event_available_outlined,
              color: Colors.blue.shade700,
              onTap: () => _openRooms(
                context,
                title: 'Booked / reserved',
                list: AdminDashboardModels.categoryBookedReservedRooms(rooms),
                subtitle: 'Check-in today or tomorrow',
                showGuest: true,
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
                subtitle: 'Guests checked in',
                showGuest: true,
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
                showGuest: false,
              ),
            ),
            _TotalStatCard(
              label: 'Cleaning',
              value: '${totals['cleaning']}',
              icon: Icons.cleaning_services_outlined,
              color: Colors.orange.shade800,
              onTap: () {
                if (maintenanceRooms.isNotEmpty) {
                  _openRooms(
                    context,
                    title: 'Rooms in cleaning',
                    list: maintenanceRooms,
                    subtitle: 'Turnover / housekeeping',
                    showGuest: false,
                  );
                  return;
                }
                if (cleaningIssues.isNotEmpty) {
                  _showRoomList(
                    context,
                    title: 'Cleaning tasks',
                    items: cleaningIssues,
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No rooms in cleaning.')),
                );
              },
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
          ],
        ),
      ],
    );
  }

  void _showCategoryBreakdown(
    BuildContext context, {
    required String label,
    required List<Map<String, dynamic>> rooms,
    required Map<String, dynamic> stats,
  }) {
    HapticFeedback.selectionClick();
    if (!AdminDashboardModels.needsFloorDrilldown(rooms)) {
      _openRooms(
        context,
        title: label,
        list: AdminDashboardModels.sortRoomsByNumber(rooms),
        subtitle: '${rooms.length} room(s)',
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          builder: (ctx, scrollController) {
            return Material(
              color: Theme.of(ctx).colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      label,
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Text(
                    '${stats['total']} rooms · ${AdminDashboardModels.distinctFloors(rooms).length} floors',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: AdminFloorPickerGrid(
                      rooms: rooms,
                      onFloorTap: (floor) {
                        Navigator.of(ctx).pop();
                        final onFloor = AdminDashboardModels.roomsOnFloor(
                          rooms,
                          floor,
                        );
                        _showFloorStatusBreakdown(
                          context,
                          categoryLabel: label,
                          floor: floor,
                          floorRooms: onFloor,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFloorStatusBreakdown(
    BuildContext context, {
    required String categoryLabel,
    required int floor,
    required List<Map<String, dynamic>> floorRooms,
  }) {
    HapticFeedback.selectionClick();
    final floorLabel = AdminDashboardModels.floorLabel(floor);
    final title = '$categoryLabel · $floorLabel';
    final reserved = AdminDashboardModels.sortRoomsByNumber(
      AdminDashboardModels.categoryReservedSoonRooms(floorRooms, withinDays: 1),
    );
    final occupied = AdminDashboardModels.sortRoomsByNumber(
      AdminDashboardModels.categoryOccupiedRooms(floorRooms),
    );
    final vacant = AdminDashboardModels.sortRoomsByNumber(
      AdminDashboardModels.categoryVacantRooms(floorRooms),
    );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${floorRooms.length} room(s) · choose status',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              _FloorStatusOption(
                label: 'Reserved',
                count: reserved.length,
                color: Colors.orange.shade800,
                icon: Icons.event_available_outlined,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openRooms(
                    context,
                    title: '$title · Reserved',
                    list: reserved,
                    subtitle: 'Check-in today or tomorrow',
                    showGuest: true,
                  );
                },
              ),
              const SizedBox(height: 8),
              _FloorStatusOption(
                label: 'Occupied',
                count: occupied.length,
                color: Colors.green.shade700,
                icon: Icons.person_pin_circle_outlined,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openRooms(
                    context,
                    title: '$title · Occupied',
                    list: occupied,
                    subtitle: 'Guests checked in',
                    showGuest: true,
                  );
                },
              ),
              const SizedBox(height: 8),
              _FloorStatusOption(
                label: 'Vacant',
                count: vacant.length,
                color: Colors.teal.shade700,
                icon: Icons.meeting_room_outlined,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openRooms(
                    context,
                    title: '$title · Vacant',
                    list: vacant,
                    subtitle: 'Available for booking',
                    showGuest: false,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FloorStatusOption extends StatelessWidget {
  const _FloorStatusOption({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '$count',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IssueRoom {
  _IssueRoom({required this.roomNumber, required this.issue});
  final String roomNumber;
  final String issue;
}

int _summaryGridColumns(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  return 2;
}

class _SummaryRoomListSheet extends StatefulWidget {
  const _SummaryRoomListSheet({
    required this.label,
    required this.subtitle,
    required this.rooms,
    required this.hostContext,
    required this.scrollController,
    required this.onRefresh,
  });

  final String label;
  final String subtitle;
  final List<Map<String, dynamic>> rooms;
  final BuildContext hostContext;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;

  @override
  State<_SummaryRoomListSheet> createState() => _SummaryRoomListSheetState();
}

class _SummaryRoomListSheetState extends State<_SummaryRoomListSheet> {
  String _query = '';

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final sorted = AdminDashboardModels.sortRoomsByNumber(widget.rooms);
    if (q.isEmpty) return sorted;
    return sorted.where((r) {
      final parts = [
        (r['room_number'] ?? '').toString(),
        (r['display_name'] ?? '').toString(),
        AdminDashboardModels.guestName(r),
        AdminDashboardModels.categoryLabel(r),
        AdminDashboardModels.displayStatusForRoom(r),
      ];
      return parts.any((p) => p.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final arrivingSoon = filtered
        .where(AdminDashboardModels.isStayArrivingSoon)
        .toList();
    final others = filtered
        .where((r) => !arrivingSoon.contains(r))
        .toList();
    final columns = _summaryGridColumns(context);

    return Material(
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  widget.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search room, guest, or status…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => setState(() => _query = ''),
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 6),
                Text(
                  '${filtered.length} shown · tap a room for details',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No rooms in this list.'
                          : 'No rooms match "$_query".',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (arrivingSoon.isNotEmpty) ...[
                        Text(
                          'Arriving (today–2 days)',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _SummaryRoomGrid(
                          rooms: arrivingSoon,
                          columns: columns,
                          highlight: true,
                          hostContext: widget.hostContext,
                          sheetContext: context,
                          onRefresh: widget.onRefresh,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (others.isNotEmpty) ...[
                        if (arrivingSoon.isNotEmpty)
                          Text(
                            'All rooms',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        if (arrivingSoon.isNotEmpty) const SizedBox(height: 8),
                        _SummaryRoomGrid(
                          rooms: others,
                          columns: columns,
                          hostContext: widget.hostContext,
                          sheetContext: context,
                          onRefresh: widget.onRefresh,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRoomGrid extends StatelessWidget {
  const _SummaryRoomGrid({
    required this.rooms,
    required this.columns,
    required this.hostContext,
    required this.sheetContext,
    required this.onRefresh,
    this.highlight = false,
  });

  final List<Map<String, dynamic>> rooms;
  final int columns;
  final BuildContext hostContext;
  final BuildContext sheetContext;
  final Future<void> Function() onRefresh;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.45,
      ),
      itemCount: rooms.length,
      itemBuilder: (context, i) => _SummaryRoomGridTile(
        room: rooms[i],
        highlight: highlight,
        hostContext: hostContext,
        sheetContext: sheetContext,
        onRefresh: onRefresh,
      ),
    );
  }
}

class _SummaryRoomGridTile extends StatelessWidget {
  const _SummaryRoomGridTile({
    required this.room,
    required this.hostContext,
    required this.sheetContext,
    required this.onRefresh,
    this.highlight = false,
  });

  final Map<String, dynamic> room;
  final BuildContext hostContext;
  final BuildContext sheetContext;
  final Future<void> Function() onRefresh;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return AdminSummaryRoomGridTile(
      room: room,
      highlight: highlight,
      onTap: () async {
        if (Navigator.of(sheetContext).canPop()) {
          Navigator.of(sheetContext).pop();
        }
        await adminRoomAfterFrame(() async {
          if (!hostContext.mounted) return;
          await AdminSummaryRoomActions.openRoomDetail(hostContext, room);
        });
      },
    );
  }
}

class _SummaryIssueListSheet extends StatelessWidget {
  const _SummaryIssueListSheet({
    required this.title,
    required this.items,
    required this.scrollController,
  });

  final String title;
  final List<_IssueRoom> items;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columns = _summaryGridColumns(context);

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  '${items.length} issue(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.2,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                return Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.build_circle_outlined,
                                size: 16, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Room ${e.roomNumber}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            e.issue,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
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

class _CategorySummaryGrid extends StatelessWidget {
  const _CategorySummaryGrid({
    required this.grouped,
    required this.keys,
    required this.onCategoryTap,
  });

  final Map<String, List<Map<String, dynamic>>> grouped;
  final List<String> keys;
  final void Function(
    BuildContext context,
    String label,
    List<Map<String, dynamic>> rooms,
    Map<String, dynamic> stats,
  ) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final label = keys[i];
        final list = grouped[label]!;
        final stats = AdminDashboardModels.categoryStats(label, list);
        final reservedSoon =
            AdminDashboardModels.categoryReservedSoonRooms(list, withinDays: 1);
        final occupied = AdminDashboardModels.categoryOccupiedRooms(list);
        final vacant = AdminDashboardModels.categoryVacantRooms(list);
        return _CategoryCard(
          stats: stats,
          reservedCount: reservedSoon.length,
          occupiedCount: occupied.length,
          vacantCount: vacant.length,
          onTap: () => onCategoryTap(context, label, list, stats),
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.stats,
    required this.reservedCount,
    required this.occupiedCount,
    required this.vacantCount,
    required this.onTap,
  });

  final Map<String, dynamic> stats;
  final int reservedCount;
  final int occupiedCount;
  final int vacantCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = '${stats['label']}';
    final total = stats['total'];
    final title = '$label $total';

    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        Icons.king_bed_outlined,
                        color: scheme.onPrimaryContainer,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                      ),
                    ),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _CategoryMiniStat(
                        label: 'Rsv',
                        count: reservedCount,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _CategoryMiniStat(
                        label: 'Occ',
                        count: occupiedCount,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _CategoryMiniStat(
                        label: 'Vac',
                        count: vacantCount,
                        color: Colors.teal.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryMiniStat extends StatelessWidget {
  const _CategoryMiniStat({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.07),
                scheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                      ),
                    ],
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
