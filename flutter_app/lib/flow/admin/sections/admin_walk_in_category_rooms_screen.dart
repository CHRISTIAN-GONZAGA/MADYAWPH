import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_dashboard_models.dart';
import '../widgets/admin_room_navigation.dart';

/// Simple walk-in room picker: name/number only, color-coded by status.
class AdminWalkInCategoryRoomsScreen extends StatelessWidget {
  const AdminWalkInCategoryRoomsScreen({
    super.key,
    required this.categoryName,
    required this.rooms,
    required this.onBooked,
  });

  final String categoryName;
  final List<Map<String, dynamic>> rooms;
  final Future<void> Function() onBooked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
      ),
      body: rooms.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No rooms found in this category.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _WalkInStatusLegend(scheme: scheme),
                const SizedBox(height: 16),
                ...rooms.map((room) => _WalkInRoomTile(
                      room: room,
                      onBooked: onBooked,
                    )),
              ],
            ),
    );
  }
}

class _WalkInStatusLegend extends StatelessWidget {
  const _WalkInStatusLegend({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _legendDot(
              AdminDashboardModels.walkInTileColor('available'),
              'Available',
            ),
            _legendDot(
              AdminDashboardModels.walkInTileColor('reserved'),
              'Reserved',
            ),
            _legendDot(
              AdminDashboardModels.walkInTileColor('occupied'),
              'Occupied',
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _WalkInRoomTile extends StatelessWidget {
  const _WalkInRoomTile({
    required this.room,
    required this.onBooked,
  });

  final Map<String, dynamic> room;
  final Future<void> Function() onBooked;

  @override
  Widget build(BuildContext context) {
    final walkInStatus = AdminDashboardModels.walkInTileStatus(room);
    final color = AdminDashboardModels.walkInTileColor(walkInStatus);
    final bookable = walkInStatus == 'available' &&
        AdminDashboardModels.isWalkInBookable(room);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _onTap(context, walkInStatus, bookable),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AdminDashboardModels.roomListTitle(room),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  AdminDashboardModels.walkInTileStatusLabel(walkInStatus),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    String walkInStatus,
    bool bookable,
  ) async {
    HapticFeedback.selectionClick();
    if (bookable) {
      await AdminRoomNavigation.openWalkInBooking(
        context,
        room: room,
        onSuccess: onBooked,
      );
      return;
    }

    final label = AdminDashboardModels.walkInTileStatusLabel(walkInStatus);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          walkInStatus == 'reserved'
              ? '${AdminDashboardModels.roomListTitle(room)} is reserved and cannot be booked for walk-in.'
              : '${AdminDashboardModels.roomListTitle(room)} is $label.',
        ),
      ),
    );
  }
}
