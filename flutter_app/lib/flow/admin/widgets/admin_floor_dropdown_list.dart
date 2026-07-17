import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/room_status_label.dart';
import '../admin_dashboard_models.dart';

/// Dropdown-style floor list: each floor is a full-width row with a count
/// badge; tapping it expands inline to reveal the rooms on that floor as a
/// compact 4-per-row box grid.
///
/// When [badgeNoun] is null the badge shows the vacant count ("3 vacant").
/// Otherwise it shows the number of rooms on the floor with that noun
/// (e.g. "3 occupied") — useful for pre-filtered lists.
class AdminFloorDropdownList extends StatefulWidget {
  const AdminFloorDropdownList({
    super.key,
    required this.rooms,
    required this.onRoomTap,
    this.scrollController,
    this.badgeNoun,
  });

  final List<Map<String, dynamic>> rooms;
  final void Function(Map<String, dynamic> room) onRoomTap;
  final ScrollController? scrollController;
  final String? badgeNoun;

  @override
  State<AdminFloorDropdownList> createState() => _AdminFloorDropdownListState();
}

class _AdminFloorDropdownListState extends State<AdminFloorDropdownList> {
  int? _expandedFloor;

  static String ordinalFloorLabel(int floor) {
    final mod100 = floor % 100;
    final mod10 = floor % 10;
    String suffix;
    if (mod100 >= 11 && mod100 <= 13) {
      suffix = 'th';
    } else if (mod10 == 1) {
      suffix = 'st';
    } else if (mod10 == 2) {
      suffix = 'nd';
    } else if (mod10 == 3) {
      suffix = 'rd';
    } else {
      suffix = 'th';
    }
    return '$floor$suffix Floor';
  }

  @override
  Widget build(BuildContext context) {
    final floors = AdminDashboardModels.distinctFloors(widget.rooms);
    if (floors.isEmpty) {
      return Center(
        child: Text(
          'No floors with rooms yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: floors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final floor = floors[i];
        final onFloor = AdminDashboardModels.sortRoomsByNumber(
          AdminDashboardModels.roomsOnFloor(widget.rooms, floor),
        );
        final noun = widget.badgeNoun;
        final badgeCount = noun == null
            ? AdminDashboardModels.categoryVacantRooms(onFloor).length
            : onFloor.length;
        final expanded = _expandedFloor == floor;
        return _FloorDropdownTile(
          label: ordinalFloorLabel(floor),
          roomCount: onFloor.length,
          badgeCount: badgeCount,
          badgeNoun: noun ?? 'vacant',
          expanded: expanded,
          onToggle: () {
            HapticFeedback.selectionClick();
            setState(() => _expandedFloor = expanded ? null : floor);
          },
          rooms: onFloor,
          onRoomTap: widget.onRoomTap,
        );
      },
    );
  }
}

class _FloorDropdownTile extends StatelessWidget {
  const _FloorDropdownTile({
    required this.label,
    required this.roomCount,
    required this.badgeCount,
    required this.badgeNoun,
    required this.expanded,
    required this.onToggle,
    required this.rooms,
    required this.onRoomTap,
  });

  final String label;
  final int roomCount;
  final int badgeCount;
  final String badgeNoun;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Map<String, dynamic>> rooms;
  final void Function(Map<String, dynamic> room) onRoomTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeColor =
        badgeCount > 0 ? Colors.green.shade700 : scheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: expanded ? scheme.surfaceContainerLow : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          '$roomCount room(s)',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badgeCount $badgeNoun',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: badgeColor,
                          ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              child: rooms.isEmpty
                  ? Text(
                      'No rooms on this floor.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.92,
                      ),
                      itemCount: rooms.length,
                      itemBuilder: (context, i) => AdminCompactRoomBox(
                        room: rooms[i],
                        onTap: () => onRoomTap(rooms[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small box-grid tile (4 per row) showing the room number and status.
class AdminCompactRoomBox extends StatelessWidget {
  const AdminCompactRoomBox({
    super.key,
    required this.room,
    required this.onTap,
  });

  final Map<String, dynamic> room;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = AdminDashboardModels.displayStatusForRoom(room);
    final color = roomStatusColor(status);
    final roomNo = (room['room_number'] ?? '—').toString();

    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    roomNo,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          height: 1,
                        ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  roomStatusLabel(status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: 9.5,
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
