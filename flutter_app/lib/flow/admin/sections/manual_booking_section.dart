import 'package:flutter/material.dart';

import 'room_board_section.dart';

/// Walk-in / manual room booking — separate from the summary dashboard tab.
class ManualBookingSection extends StatelessWidget {
  const ManualBookingSection({
    super.key,
    required this.rooms,
    required this.hotelName,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> rooms;
  final String hotelName;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          'Walk-in booking',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'All rooms by category — tap a gray available room to book a local walk-in guest.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        RoomBoardSection(
          rooms: rooms,
          hotelName: hotelName,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
