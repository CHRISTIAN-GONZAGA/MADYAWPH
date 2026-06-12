import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/room_status_label.dart';
import '../admin_dashboard_models.dart';
import '../widgets/manual_booking_dialog.dart';
import '../../admin_rooms.dart';

/// Visual room board grouped by category — tap a room to book or manage.
class RoomBoardSection extends StatelessWidget {
  const RoomBoardSection({
    super.key,
    required this.rooms,
    required this.hotelName,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> rooms;
  final String hotelName;
  final Future<void> Function() onChanged;

  static const _tileStatusesAvailable = {'available'};

  Color _tileColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'available':
        return const Color(0xFFB0BEC5);
      case 'checked_in':
        return Colors.green.shade600;
      case 'booked':
      case 'reserved':
        return Colors.blue.shade600;
      case 'maintenance':
        return Colors.red.shade400;
      default:
        return scheme.surfaceContainerHighest;
    }
  }

  Future<void> _onRoomTap(BuildContext context, Map<String, dynamic> room) async {
    HapticFeedback.selectionClick();
    final status = AdminDashboardModels.statusOf(room);
    final roomId = (room['id'] ?? '').toString();

    if (_tileStatusesAvailable.contains(status)) {
      final booked = await showAdminManualBookingDialog(
        context: context,
        room: room,
        onSuccess: onChanged,
      );
      if (booked && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Room ${room['room_number']} booked successfully.',
            ),
          ),
        );
      }
      return;
    }

    if (roomId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminRoomDetailScreen(roomId: roomId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = AdminDashboardModels.groupByCategory(rooms);
    final keys = grouped.keys.toList()..sort();
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final dateLabel =
        '${_month(now.month)} ${now.day}, ${now.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          hotelName.toUpperCase(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: scheme.primary,
              ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF37474F),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            dateLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap an available room to book · occupied rooms open details',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        ...keys.map((label) {
          final list = grouped[label]!;
          list.sort((a, b) => (a['room_number'] ?? '')
              .toString()
              .compareTo((b['room_number'] ?? '').toString()));
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              elevation: 2,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final r = list[i];
                        final status = AdminDashboardModels.statusOf(r);
                        final no = (r['room_number'] ?? '—').toString();
                        final guest = AdminDashboardModels.guestName(r);
                        final hasGuest = guest != '—';

                        return Material(
                          color: _tileColor(status, scheme),
                          borderRadius: BorderRadius.circular(10),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _onRoomTap(context, r),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasGuest
                                          ? Colors.white
                                          : Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      no,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${list.length} rooms · ${roomStatusLabel(statusOfCategory(list))}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  String statusOfCategory(List<Map<String, dynamic>> list) {
    final vacant =
        list.where((r) => AdminDashboardModels.statusOf(r) == 'available').length;
    if (vacant == list.length) return 'all available';
    if (vacant == 0) return 'no vacancies';
    return '$vacant available';
  }

  String _month(int m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[m - 1];
  }
}
