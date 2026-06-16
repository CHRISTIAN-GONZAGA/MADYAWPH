import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/room_status_label.dart';
import '../admin_dashboard_models.dart';
import '../widgets/booking_overview_cards.dart';
import '../widgets/admin_room_navigation.dart';
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
    final occupiedRooms = _filterByStatuses({'checked_in'});
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
                      'Tap a category to open reserved, occupied, and vacant lists',
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
                list: rooms
                    .where(AdminDashboardModels.isAwaitingCheckIn)
                    .toList(),
                subtitle: 'Check-in today or later',
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return _CategoryBreakdownSheet(
          label: label,
          rooms: rooms,
          stats: stats,
          onOpenSection: (sectionTitle, filtered, subtitle) {
            Navigator.of(ctx).pop();
            _openRooms(
              context,
              title: '$label · $sectionTitle',
              list: filtered,
              subtitle: subtitle,
            );
          },
        );
      },
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

List<Map<String, dynamic>> _sortRoomsByNumber(List<Map<String, dynamic>> rooms) {
  final copy = List<Map<String, dynamic>>.from(rooms);
  copy.sort((a, b) {
    final an = (a['room_number'] ?? '').toString();
    final bn = (b['room_number'] ?? '').toString();
    return an.compareTo(bn);
  });
  return copy;
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
    final sorted = _sortRoomsByNumber(widget.rooms);
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
    final scheme = Theme.of(context).colorScheme;
    final status = AdminDashboardModels.displayStatusForRoom(room);
    final statusColor = highlight
        ? Colors.orange.shade800
        : roomStatusColor(status);
    final guest = AdminDashboardModels.guestName(room);
    final range = AdminDashboardModels.formatStayRange(room);
    final roomNo = (room['room_number'] ?? '—').toString();
    final name = (room['display_name'] ?? '').toString().trim();

    return Material(
      color: highlight
          ? Colors.orange.shade50
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          AdminRoomNavigation.openRoom(
            hostContext,
            room: room,
            onSuccess: onRefresh,
            sheetContext: sheetContext,
            mode: AdminRoomOpenMode.manageOnly,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      roomNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Text(
                    roomStatusLabel(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                        ),
                  ),
                ],
              ),
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
              Text(
                guest == '—' ? 'No guest' : guest,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                        label,
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
                Text(
                  '${stats['total']} rooms',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.primary,
                        height: 1,
                      ),
                ),
                const SizedBox(height: 8),
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

class _CategoryBreakdownSheet extends StatelessWidget {
  const _CategoryBreakdownSheet({
    required this.label,
    required this.rooms,
    required this.stats,
    required this.onOpenSection,
  });

  final String label;
  final List<Map<String, dynamic>> rooms;
  final Map<String, dynamic> stats;
  final void Function(
    String sectionTitle,
    List<Map<String, dynamic>> rooms,
    String subtitle,
  ) onOpenSection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reservedSoon =
        AdminDashboardModels.categoryReservedSoonRooms(rooms, withinDays: 1);
    final occupied = AdminDashboardModels.categoryOccupiedRooms(rooms);
    final vacant = AdminDashboardModels.categoryVacantRooms(rooms);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.king_bed_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      '${stats['total']} rooms in this category',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Tap a section to view rooms',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 10),
          _CategorySectionTile(
            icon: Icons.schedule_rounded,
            label: 'Reserved (0–1 day)',
            subtitle: 'Check-in today or tomorrow',
            count: reservedSoon.length,
            color: Colors.orange.shade800,
            onTap: reservedSoon.isEmpty
                ? null
                : () => onOpenSection(
                      'Reserved (0–1 day)',
                      reservedSoon,
                      '${reservedSoon.length} room(s)',
                    ),
          ),
          const SizedBox(height: 8),
          _CategorySectionTile(
            icon: Icons.person_pin_circle_outlined,
            label: 'Occupied',
            subtitle: 'Guests currently checked in',
            count: occupied.length,
            color: Colors.green.shade700,
            onTap: occupied.isEmpty
                ? null
                : () => onOpenSection(
                      'Occupied',
                      occupied,
                      '${occupied.length} room(s)',
                    ),
          ),
          const SizedBox(height: 8),
          _CategorySectionTile(
            icon: Icons.meeting_room_outlined,
            label: 'Vacant',
            subtitle: 'Available for walk-in booking',
            count: vacant.length,
            color: Colors.teal.shade700,
            onTap: vacant.isEmpty
                ? null
                : () => onOpenSection(
                      'Vacant',
                      vacant,
                      '${vacant.length} room(s)',
                    ),
          ),
        ],
      ),
    );
  }
}

class _CategorySectionTile extends StatelessWidget {
  const _CategorySectionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null && count > 0;

    return Material(
      color: enabled
          ? color.withValues(alpha: 0.08)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: enabled
                      ? color.withValues(alpha: 0.15)
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: enabled ? color : scheme.outline,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: enabled ? null : scheme.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '$count',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: enabled ? color : scheme.outline,
                    ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: enabled ? color : scheme.outline,
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
